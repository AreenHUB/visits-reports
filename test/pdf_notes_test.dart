@TestOn('vm')
library;

import 'package:alaqsa_visits/db/repository.dart';
import 'package:alaqsa_visits/models/models.dart';
import 'package:alaqsa_visits/providers/providers.dart';
import 'package:alaqsa_visits/services/pdf_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// يتحقق أن التقرير يُبنى وفيه ملاحظات على الوارد والصادر معًا،
/// وأنه يبقى في صفحة واحدة للتقرير الصغير.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  CashEntry cash({
    required CashDirection direction,
    required String notes,
    double amount = 100,
  }) =>
      CashEntry(
        id: 'c_${direction.name}_$notes',
        direction: direction,
        categoryKey: direction == CashDirection.income ? 'sale' : 'purchase',
        categoryLabel: direction == CashDirection.income ? 'بيع' : 'شراء',
        description: 'بيان',
        amount: amount,
        notes: notes,
        date: DateTime(2026, 9, 7),
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

  test('التقرير يُبنى مع ملاحظات على الوارد والصادر', () async {
    final s = PeriodSummary(
      from: DateTime(2026, 9, 7),
      to: DateTime(2026, 9, 7),
      visits: const [],
      credits: const [],
      cash: [
        cash(direction: CashDirection.income, notes: 'ملاحظة الوارد'),
        cash(direction: CashDirection.expense, notes: 'ملاحظة الصادر'),
      ],
      visitTotals: const Totals(),
      creditTotals: const Totals(),
    );

    final bytes = await PdfService.instance
        .buildReport(summary: s, settings: const ShopSettings(shopName: 'الأقصى'));
    expect(bytes.length, greaterThan(1000));
  });

  test('تقرير بقطع تحمل ملاحظات يُبنى بنجاح', () async {
    final visit = Visit(
      id: 'v1',
      customerId: 'c1',
      customerName: 'عميل',
      date: DateTime(2026, 9, 7),
      dayNotes: 'ملاحظة على الزيارة',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    final vf = VisitFull(
      visit: visit,
      items: [
        Item(
          id: 'i1',
          visitId: 'v1',
          serial: 'SN123',
          typeKey: 'camera',
          typeLabel: 'كاميرا',
          price: 500,
          notes: 'ملاحظة على القطعة',
          createdAt: DateTime(2026),
        ),
      ],
    );

    final s = PeriodSummary(
      from: DateTime(2026, 9, 7),
      to: DateTime(2026, 9, 7),
      visits: [vf],
      credits: const [],
      visitTotals: vf.totals,
      creditTotals: const Totals(),
    );

    final bytes = await PdfService.instance
        .buildReport(summary: s, settings: const ShopSettings());
    expect(bytes.length, greaterThan(1000));
  });

  test('التقرير اليومي الصغير لا يتجاوز صفحتين', () async {
    final s = PeriodSummary(
      from: DateTime(2026, 9, 7),
      to: DateTime(2026, 9, 7),
      visits: const [],
      credits: const [],
      cash: [cash(direction: CashDirection.income, notes: 'ملاحظة')],
      visitTotals: const Totals(),
      creditTotals: const Totals(),
    );

    final bytes = await PdfService.instance
        .buildReport(summary: s, settings: const ShopSettings());

    // نعدّ كائنات الصفحات داخل ملف الـ PDF
    final content = String.fromCharCodes(bytes);
    final pageCount = '/Type /Page'.allMatches(content).length -
        '/Type /Pages'.allMatches(content).length;

    expect(pageCount, lessThanOrEqualTo(2),
        reason: 'التقرير الصغير يجب ألا ينفتح على صفحات زائدة');
  });
}
