@TestOn('vm')
library;

import 'package:alaqsa_visits/db/repository.dart';
import 'package:alaqsa_visits/models/models.dart';
import 'package:alaqsa_visits/providers/providers.dart';
import 'package:alaqsa_visits/services/pdf_service.dart';
import 'package:alaqsa_visits/services/share_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // إعدادات تحمل اسمي الفني والمدير: يجب ألا يظهرا في المخرجات
  const settings = ShopSettings(
    shopName: 'محل الأقصى',
    shopPhone: '0500000000',
    technicianName: 'اسم_الفني_للاختبار',
    managerName: 'اسم_المدير_للاختبار',
  );

  PeriodSummary summary() => PeriodSummary(
        from: DateTime(2026, 9, 6),
        to: DateTime(2026, 9, 6),
        visits: const [],
        credits: const [],
        visitTotals: const Totals(),
        creditTotals: const Totals(),
      );

  test('ملف الـ PDF يُبنى بنجاح', () async {
    final bytes = await PdfService.instance
        .buildReport(summary: summary(), settings: settings);
    expect(bytes.length, greaterThan(1000));
  });

  test('نص المشاركة لا يحتوي اسم الفني ولا المدير', () {
    final msg = ShareService.reportMessage(summary(), settings);
    expect(msg.contains('اسم_الفني_للاختبار'), isFalse);
    expect(msg.contains('اسم_المدير_للاختبار'), isFalse);
    expect(msg.contains('الفني'), isFalse);
    expect(msg.contains('المدير'), isFalse);
    // اسم المحل يبقى
    expect(msg.contains('محل الأقصى'), isTrue);
  });
}
