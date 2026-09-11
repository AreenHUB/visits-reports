@TestOn('vm')
library;

import 'package:alaqsa_visits/db/repository.dart';
import 'package:alaqsa_visits/models/models.dart';
import 'package:alaqsa_visits/providers/providers.dart';
import 'package:alaqsa_visits/services/pdf_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// يقيس حجم ملف التقرير وزمن توليده مع ازدياد عدد الزيارات،
/// لاكتشاف الانفجار في الحجم أو البطء الذي يُسقط التطبيق على الجوال.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  VisitFull visit(int i) {
    final date = DateTime(2026, 9, 1).add(Duration(days: i % 30));
    final v = Visit(
      id: 'v$i',
      customerId: 'c$i',
      customerName: 'مؤسسة الاختبار للتجارة والمقاولات رقم $i',
      customerPhone: '+971 50 140 9543',
      customerAddress: 'دبا الفجيرة / المهلب - شارع طويل للاختبار',
      date: date,
      purpose: 'صيانة وتركيب كاميرات مراقبة وتمديد شبكات\n'
          'مع فحص الجهاز واستبدال القطع التالفة',
      dayNotes: 'ملاحظات مفصّلة عن هذه الزيارة\nبعدة أسطر\nلاختبار الحجم',
      createdAt: date,
      updatedAt: date,
    );

    return VisitFull(
      visit: v,
      items: List.generate(
        5,
        (k) => Item(
          id: 'i${i}_$k',
          visitId: v.id,
          serial: '210235XGHMF2610001$i$k',
          typeKey: 'camera',
          typeLabel: 'كاميرا',
          specs: const {
            'brand': 'Tiandy',
            'shape': 'Bullet بوليت',
            'mp': '2 ميغا',
            'tech': 'IP',
            'placement': 'خارجية',
          },
          price: 100.0 + k * 50,
          notes: 'ملاحظة على القطعة رقم $k',
          createdAt: date,
        ),
      ),
      payments: [
        Payment(id: 'p$i', visitId: v.id, amount: 500, date: date),
      ],
    );
  }

  PeriodSummary summaryOf(int count) {
    final visits = List.generate(count, visit);
    var totals = const Totals();
    for (final v in visits) {
      totals = totals + v.totals;
    }
    return PeriodSummary(
      from: DateTime(2026, 9, 1),
      to: DateTime(2026, 9, 30),
      visits: visits,
      credits: const [],
      visitTotals: totals,
      creditTotals: const Totals(),
    );
  }

  Future<({int bytes, int millis})> measure(int count) async {
    final sw = Stopwatch()..start();
    final out = await PdfService.instance.buildReport(
      summary: summaryOf(count),
      settings: const ShopSettings(shopName: 'الأقصى'),
    );
    sw.stop();
    return (bytes: out.length, millis: sw.elapsedMilliseconds);
  }

  test('قياس حجم التقرير وزمنه مع ازدياد الزيارات', () async {
    for (final n in [1, 5, 10, 20, 40]) {
      final r = await measure(n);
      // ignore: avoid_print
      print('زيارات: ${n.toString().padLeft(3)}  '
          'الحجم: ${(r.bytes / 1024).toStringAsFixed(0)} ك.ب  '
          'الزمن: ${r.millis} مللي');
    }
  });

  test('تقرير 40 زيارة يبقى ضمن حجم معقول', () async {
    final r = await measure(40);
    // الخط يُضمَّن مرة واحدة؛ إن تجاوز الملف 20 ميغا فهناك انفجار
    expect(r.bytes, lessThan(20 * 1024 * 1024),
        reason: 'حجم الملف ${(r.bytes / 1024 / 1024).toStringAsFixed(1)} ميغا');
  });

  test('توليد تقرير 40 زيارة لا يستغرق زمنًا مفرطًا', () async {
    final r = await measure(40);
    expect(r.millis, lessThan(30000),
        reason: 'استغرق ${r.millis} مللي ثانية');
  });
}
