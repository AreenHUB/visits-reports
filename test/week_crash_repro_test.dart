@TestOn('vm')
library;

import 'package:alaqsa_visits/db/repository.dart';
import 'package:alaqsa_visits/models/models.dart';
import 'package:alaqsa_visits/providers/providers.dart';
import 'package:alaqsa_visits/services/excel_service.dart';
import 'package:alaqsa_visits/services/pdf_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// يعيد إنتاج تقرير أسبوع بمعطيات واقعية شبيهة ببيانات المستخدم،
/// بما فيها الحقول الطويلة والملاحظات متعددة الأسطر التي كانت
/// تُسقط توليد التقرير.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  VisitFull realisticVisit(int i) {
    final date = DateTime(2026, 9, 5).add(Duration(days: i));
    final v = Visit(
      id: 'v$i',
      customerId: 'c$i',
      customerName: 'روضة طفولتي الممتعة $i',
      customerPhone: '+971 50 140 9543',
      customerAddress: 'دبا الفجيرة / المهلب - شارع الاختبار',
      date: date,
      purpose: 'الصيانة\nصاحب جهاز ال hikvision اللي ركبنالو هارد\n'
          'فصل الجهاز عندو\nطلع مضروب',
      // ملاحظات متعددة الأسطر مثل بيانات المستخدم الحقيقية
      dayNotes: 'تمت الزيارة والصيانة\n300 درهم الحساب (غير واصل)\n'
          'بكرة عادل بجيبهن من عندن\nسطر إضافي للاختبار',
      status: i % 3 == 0 ? VisitStatus.notDone : VisitStatus.done,
      notDoneReason: i % 3 == 0
          ? 'عندو البايبات مسكرة\nتم تأجيل العمل حتى يتم فتح البايبات المخصصة للكابلات'
          : '',
      createdAt: date,
      updatedAt: date,
    );

    return VisitFull(
      visit: v,
      items: List.generate(
        4,
        (k) => Item(
          id: 'i${i}_$k',
          visitId: v.id,
          serial: '210235XGHMF26100014$k',
          typeKey: k.isEven ? 'camera' : 'nvr',
          typeLabel: k.isEven ? 'كاميرا' : 'NVR / DVR',
          specs: k.isEven
              ? const {
                  'brand': 'Tiandy',
                  'shape': 'Bullet بوليت',
                  'mp': '2 ميغا',
                  'tech': 'IP',
                  'placement': 'خارجية',
                  'lens': '2.8mm',
                  'audio': 'صوت',
                }
              : const {
                  'brand': 'UNV',
                  'device': 'NVR',
                  'channels': '16 قناة',
                  'poe_ports': '0 بورت',
                  'hdd': 'بدون',
                },
          price: 100.0 + k * 50,
          notes: 'تم جلب القطعة عن طريق كوريا وتم بيعها مباشرة '
              'دون ادخالها على البيان ب طلب من منير',
          createdAt: date,
        ),
      ),
      payments: [
        Payment(
          id: 'p$i',
          visitId: v.id,
          amount: 640,
          date: date,
          method: i.isEven ? PayMethod.cash : PayMethod.card,
          notes: 'سعر القطعة 500 و أجور 140',
        ),
      ],
    );
  }

  PeriodSummary weekSummary({bool withEverything = true}) {
    final visits = List.generate(7, realisticVisit);
    var totals = const Totals();
    for (final v in visits) {
      totals = totals + v.totals;
    }

    return PeriodSummary(
      from: DateTime(2026, 9, 5),
      to: DateTime(2026, 9, 11),
      visits: visits,
      credits: const [],
      cash: withEverything
          ? List.generate(
              8,
              (i) => CashEntry(
                id: 'c$i',
                direction:
                    i.isEven ? CashDirection.income : CashDirection.expense,
                categoryKey: i.isEven ? 'sale' : 'purchase',
                categoryLabel: i.isEven ? 'بيع أغراض من المحل' : 'شراء بضاعة',
                description: 'حركة رقم $i بوصف طويل نسبيًا للاختبار',
                partyName: 'طرف $i',
                amount: 100.0 * (i + 1),
                method: i % 3 == 0 ? PayMethod.card : PayMethod.cash,
                date: DateTime(2026, 9, 5).add(Duration(days: i % 7)),
                notes: 'ملاحظة متعددة\nالأسطر على الحركة رقم $i',
                createdAt: DateTime(2026),
                updatedAt: DateTime(2026),
              ),
            )
          : const [],
      dayNotes: withEverything
          ? List.generate(
              5,
              (i) => DayNote(
                day: DateTime(2026, 9, 5).add(Duration(days: i)),
                notes: 'حساب أسواق الخليج\n400 درهم\n'
                    'على ان يسددهم لاحقا عند استبدال الكاميرات\n'
                    'تم التواصل مع منير\nوقال لا مانع',
              ),
            )
          : const [],
      salaries: withEverything
          ? List.generate(
              3,
              (i) => SalaryPayment(
                id: 's$i',
                employeeId: 'e$i',
                employeeName: 'موظف $i',
                amount: 2100,
                kind: SalaryKind.partial,
                method: PayMethod.cash,
                date: DateTime(2026, 9, 6).add(Duration(days: i)),
                forMonth: DateTime(2026, 9),
                notes: 'تم تسليم دفعة 600 درهم وتم استلام مبلغ 1500 من UNU',
                createdAt: DateTime(2026),
              ),
            )
          : const [],
      debts: withEverything
          ? List.generate(
              4,
              (i) => DebtRecord(
                id: 'd$i',
                personName: 'مدين رقم $i بالاسم الطويل',
                personPhone: '0501234567',
                amount: 1000.0 * (i + 1),
                paid: 200.0 * i,
                reason: 'بضاعة وخدمات متنوعة بوصف طويل',
                date: DateTime(2026, 9, 3),
                dueDate: DateTime(2026, 10, 1),
                createdAt: DateTime(2026),
                updatedAt: DateTime(2026),
              ),
            )
          : const [],
      cashBalance: const CashBalance(cashIn: 7690, cashOut: 7605),
      visitTotals: totals,
      creditTotals: const Totals(),
    );
  }

  test('تقرير أسبوع كامل بكل الأقسام يُبنى بنجاح', () async {
    final bytes = await PdfService.instance.buildReport(
      summary: weekSummary(),
      settings: const ShopSettings(
        shopName: 'الأقصى للإلكترونيات',
        shopPhone: '0559184864',
        shopAddress: 'دبا الفجير/المهلب',
      ),
      options: const ReportOptions(includeSalaries: true, includeDebts: true),
    );
    expect(bytes.length, greaterThan(2000));
  });

  test('تقرير أسبوع بكل الأقسام مطفأة يُبنى بنجاح', () async {
    final bytes = await PdfService.instance.buildReport(
      summary: weekSummary(),
      settings: const ShopSettings(),
      options: const ReportOptions(
        includeVisits: false,
        includeCredits: false,
        includeCash: false,
        includeCashBalance: false,
      ),
    );
    expect(bytes.length, greaterThan(500));
  });

  test('تصدير إكسل لأسبوع كامل يعمل', () async {
    final s = weekSummary();
    // نتحقق أن بناء الأوراق لا يرمي استثناء
    expect(() => ExcelService.instance, returnsNormally);
    expect(s.salaries.length, 3);
    expect(s.debts.length, 4);
  });

  test('اسم مهمة الطباعة للأسبوع لاتيني صالح', () {
    final name = PdfService.printJobName(weekSummary());
    expect(RegExp(r'^[A-Za-z0-9_\-]+$').hasMatch(name), isTrue);
  });

  test('تقرير شهر بحجم كبير جدًا يُبنى بنجاح', () async {
    final visits = List.generate(31, realisticVisit);
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
    expect(bytes.length, greaterThan(2000));
  });
}
