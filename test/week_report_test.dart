@TestOn('vm')
library;

import 'package:alaqsa_visits/db/repository.dart';
import 'package:alaqsa_visits/models/models.dart';
import 'package:alaqsa_visits/providers/providers.dart';
import 'package:alaqsa_visits/services/pdf_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// يعيد إنتاج تقرير أسبوع فيه زيارات وقطع وحركات مالية
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  VisitFull visit(int dayOffset, {int itemCount = 3}) {
    final date = DateTime(2026, 9, 1).add(Duration(days: dayOffset));
    final v = Visit(
      id: 'v$dayOffset',
      customerId: 'c$dayOffset',
      customerName: 'عميل رقم $dayOffset - مؤسسة الاختبار للتجارة',
      customerPhone: '05012345$dayOffset',
      customerAddress: 'دبي - شارع الاختبار - بناية رقم $dayOffset',
      date: date,
      purpose: 'تركيب كاميرات مراقبة وصيانة الشبكة في الموقع رقم $dayOffset',
      dayNotes: 'ملاحظات اليوم رقم $dayOffset',
      createdAt: date,
      updatedAt: date,
    );
    return VisitFull(
      visit: v,
      items: List.generate(
        itemCount,
        (i) => Item(
          id: 'i${dayOffset}_$i',
          visitId: v.id,
          serial: 'SN-$dayOffset-$i-ABCDEF123456',
          typeKey: 'camera',
          typeLabel: 'كاميرا',
          specs: const {'mp': '4 ميغا', 'placement': 'خارجية'},
          price: 450 + i * 25,
          notes: 'ملاحظة على القطعة $i',
          createdAt: date,
        ),
      ),
      payments: [
        Payment(id: 'p$dayOffset', visitId: v.id, amount: 500, date: date),
      ],
    );
  }

  test('تقرير أسبوع كامل يُبنى بنجاح', () async {
    final visits = List.generate(7, (d) => visit(d));
    var totals = const Totals();
    for (final v in visits) {
      totals = totals + v.totals;
    }

    final s = PeriodSummary(
      from: DateTime(2026, 9, 1),
      to: DateTime(2026, 9, 7),
      visits: visits,
      credits: const [],
      cash: [
        CashEntry(
          id: 'cash1',
          direction: CashDirection.income,
          categoryKey: 'sale',
          categoryLabel: 'بيع أغراض من المحل',
          description: 'بيع كاميرا',
          amount: 300,
          date: DateTime(2026, 9, 3),
          createdAt: DateTime(2026, 9, 3),
          updatedAt: DateTime(2026, 9, 3),
        ),
      ],
      dayNotes: List.generate(
        3,
        (i) => DayNote(
          day: DateTime(2026, 9, 1).add(Duration(days: i)),
          notes: 'ملاحظة اليوم $i',
        ),
      ),
      visitTotals: totals,
      creditTotals: const Totals(),
    );

    final bytes = await PdfService.instance
        .buildReport(summary: s, settings: const ShopSettings(shopName: 'الأقصى'));
    expect(bytes.length, greaterThan(1000));
  });

  test('تقرير شهر بحجم كبير يُبنى بنجاح', () async {
    final visits = List.generate(30, (d) => visit(d, itemCount: 5));
    var totals = const Totals();
    for (final v in visits) {
      totals = totals + v.totals;
    }

    final s = PeriodSummary(
      from: DateTime(2026, 9, 1),
      to: DateTime(2026, 9, 30),
      visits: visits,
      credits: const [],
      visitTotals: totals,
      creditTotals: const Totals(),
    );

    final bytes = await PdfService.instance
        .buildReport(summary: s, settings: const ShopSettings());
    expect(bytes.length, greaterThan(1000));
  });
}
