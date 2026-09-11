@TestOn('vm')
library;

import 'package:alaqsa_visits/db/repository.dart';
import 'package:alaqsa_visits/models/models.dart';
import 'package:alaqsa_visits/services/pdf_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// أسماء الملفات يجب أن تبقى لاتينية.
///
/// السبب: مزوّد الملفات في أندرويد (FileProvider) الذي تستخدمه المشاركة
/// والطباعة يفشل مع بعض الأحرف غير اللاتينية في اسم الملف. الفشل يقع في
/// الطبقة الأصلية فلا يلتقطه Dart، ويُسقط التطبيق بلا رسالة — وهذا ما كان
/// يحدث عند مشاركة تقرير أسبوع أو شهر.
void main() {
  PeriodSummary range(DateTime from, DateTime to) => PeriodSummary(
        from: from,
        to: to,
        visits: const [],
        credits: const [],
        visitTotals: const Totals(),
        creditTotals: const Totals(),
      );

  /// الأحرف المسموحة في اسم ملف للمشاركة
  final safe = RegExp(r'^[A-Za-z0-9_\-.]+$');

  test('اسم تقرير اليوم الواحد لاتيني', () {
    final name = PdfService.fileNameFor(
      range(DateTime(2026, 9, 10), DateTime(2026, 9, 10)),
    );
    expect(safe.hasMatch(name), isTrue, reason: name);
    expect(name.endsWith('.pdf'), isTrue);
  });

  test('اسم تقرير الأسبوع لاتيني — وهو ما كان يُسقط التطبيق', () {
    final name = PdfService.fileNameFor(
      range(DateTime(2026, 9, 5), DateTime(2026, 9, 11)),
    );
    expect(safe.hasMatch(name), isTrue, reason: name);
    // الاسم القديم كان يحتوي «إلى» العربية
    expect(name.contains('إلى'), isFalse);
  });

  test('اسم تقرير الشهر لاتيني', () {
    final name = PdfService.fileNameFor(
      range(DateTime(2026, 9, 1), DateTime(2026, 9, 30)),
    );
    expect(safe.hasMatch(name), isTrue, reason: name);
  });

  test('اسم تقرير ثلاثة أيام لاتيني', () {
    final name = PdfService.fileNameFor(
      range(DateTime(2026, 9, 8), DateTime(2026, 9, 10)),
    );
    expect(safe.hasMatch(name), isTrue, reason: name);
  });

  test('اسم مهمة الطباعة لاتيني بلا امتداد', () {
    final name = PdfService.printJobName(
      range(DateTime(2026, 9, 5), DateTime(2026, 9, 11)),
    );
    expect(safe.hasMatch(name), isTrue, reason: name);
    expect(name.contains('.pdf'), isFalse);
  });

  test('التواريخ تُنسّق بصفر بادئ فيبقى الطول ثابتًا', () {
    final name = PdfService.fileNameFor(
      range(DateTime(2026, 1, 5), DateTime(2026, 2, 9)),
    );
    expect(name, 'Report_2026-01-05_to_2026-02-09.pdf');
  });

  test('safeFileName ينظّف الرموز الممنوعة', () {
    expect(PdfService.safeFileName('a/b\\c:d*e?f"g<h>i|j'),
        'a_b_c_d_e_f_g_h_i_j');
    expect(PdfService.safeFileName('اسم به مسافات'), 'اسم_به_مسافات');
    expect(PdfService.safeFileName(''), 'file');
  });

  test('أسماء فترات مختلفة لا تتصادم', () {
    final a = PdfService.fileNameFor(
      range(DateTime(2026, 9, 5), DateTime(2026, 9, 11)),
    );
    final b = PdfService.fileNameFor(
      range(DateTime(2026, 9, 6), DateTime(2026, 9, 11)),
    );
    expect(a == b, isFalse);
  });
}
