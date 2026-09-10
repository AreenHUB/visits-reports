@TestOn('vm')
library;

import 'package:alaqsa_visits/db/repository.dart';
import 'package:alaqsa_visits/models/models.dart';
import 'package:alaqsa_visits/providers/providers.dart';
import 'package:alaqsa_visits/services/pdf_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('رصيد الكاش', () {
    test('الرصيد = الداخل نقدًا ناقص الخارج نقدًا', () {
      const b = CashBalance(cashIn: 5000, cashOut: 1800);
      expect(b.balance, 3200);
    });

    test('الرصيد قد يكون سالبًا', () {
      const b = CashBalance(cashIn: 100, cashOut: 400);
      expect(b.balance, -300);
    });
  });

  group('الرواتب', () {
    Employee emp({double salary = 3000}) => Employee(
          id: 'e1',
          name: 'موظف',
          monthlySalary: salary,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );

    SalaryPayment pay(double amount, DateTime date,
            {SalaryKind kind = SalaryKind.partial}) =>
        SalaryPayment(
          id: 'p$amount${date.month}',
          employeeId: 'e1',
          employeeName: 'موظف',
          amount: amount,
          kind: kind,
          date: date,
          createdAt: date,
        );

    test('إجمالي المدفوع لموظف', () {
      final ef = EmployeeFull(employee: emp(), payments: [
        pay(1000, DateTime(2026, 9, 5)),
        pay(500, DateTime(2026, 9, 20)),
      ]);
      expect(ef.totalPaid, 1500);
    });

    test('المدفوع ضمن شهر محدد فقط', () {
      final ef = EmployeeFull(employee: emp(), payments: [
        pay(1000, DateTime(2026, 9, 5)),
        pay(700, DateTime(2026, 8, 5)),
      ]);
      expect(ef.paidInMonth(DateTime(2026, 9)), 1000);
      expect(ef.paidInMonth(DateTime(2026, 8)), 700);
      expect(ef.paidInMonth(DateTime(2026, 7)), 0);
    });

    test('آخر دفعة هي الأحدث تاريخًا', () {
      final ef = EmployeeFull(employee: emp(), payments: [
        pay(300, DateTime(2026, 9, 1)),
        pay(400, DateTime(2026, 9, 25)),
        pay(200, DateTime(2026, 9, 10)),
      ]);
      expect(ef.lastPayment!.amount, 400);
    });

    test('بدون دفعات لا توجد آخر دفعة', () {
      expect(EmployeeFull(employee: emp()).lastPayment, isNull);
    });

    test('أنواع الدفعات تتحول من نص وإليه', () {
      for (final k in SalaryKind.values) {
        expect(SalaryKindX.fromCode(k.name), k);
      }
      expect(SalaryKindX.fromCode('xyz'), SalaryKind.partial);
    });
  });

  group('ديون العملاء', () {
    DebtRecord debt({
      double amount = 1000,
      double paid = 0,
      DateTime? due,
    }) =>
        DebtRecord(
          id: 'd1',
          personName: 'مدين',
          amount: amount,
          paid: paid,
          date: DateTime(2026, 9, 1),
          dueDate: due,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );

    test('المتبقي = الدين ناقص المسدَّد', () {
      expect(debt(amount: 1000, paid: 300).remaining, 700);
    });

    test('السداد الكامل يجعل الدين مسدَّدًا', () {
      expect(debt(amount: 500, paid: 500).isPaidOff, isTrue);
      expect(debt(amount: 500, paid: 200).isPaidOff, isFalse);
    });

    test('الدين المتأخر يُكتشف بتاريخ الاستحقاق', () {
      final past = DateTime.now().subtract(const Duration(days: 5));
      final future = DateTime.now().add(const Duration(days: 5));

      expect(debt(due: past).isOverdue, isTrue);
      expect(debt(due: future).isOverdue, isFalse);
      expect(debt(due: null).isOverdue, isFalse);
    });

    test('الدين المسدَّد لا يُعتبر متأخرًا حتى لو مضى موعده', () {
      final past = DateTime.now().subtract(const Duration(days: 30));
      expect(debt(amount: 500, paid: 500, due: past).isOverdue, isFalse);
    });
  });

  group('خيارات التقرير', () {
    test('القيم الافتراضية', () {
      const o = ReportOptions();
      expect(o.includeVisits, isTrue);
      expect(o.includeCash, isTrue);
      expect(o.includeCashBalance, isTrue);
      expect(o.includeSalaries, isFalse);
      expect(o.includeDebts, isFalse);
    });

    test('الحفظ والقراءة يحافظان على القيم', () {
      const o = ReportOptions(
        includeVisits: false,
        includeSalaries: true,
        includeDebts: true,
      );
      final restored = ReportOptions.fromMap(o.toMap());

      expect(restored.includeVisits, isFalse);
      expect(restored.includeSalaries, isTrue);
      expect(restored.includeDebts, isTrue);
      expect(restored.includeCash, isTrue);
    });

    test('الإعدادات الفارغة تعطي القيم الافتراضية', () {
      final o = ReportOptions.fromMap({});
      expect(o.includeVisits, isTrue);
      expect(o.includeSalaries, isFalse);
    });

    test('copyWith يغيّر حقلًا واحدًا فقط', () {
      const o = ReportOptions();
      final next = o.copyWith(includeSalaries: true);
      expect(next.includeSalaries, isTrue);
      expect(next.includeVisits, isTrue);
    });
  });

  group('ملخص الفترة مع الأقسام الجديدة', () {
    PeriodSummary summary({
      List<SalaryPayment> salaries = const [],
      List<DebtRecord> debts = const [],
      CashBalance balance = const CashBalance(),
    }) =>
        PeriodSummary(
          from: DateTime(2026, 9, 1),
          to: DateTime(2026, 9, 7),
          visits: const [],
          credits: const [],
          salaries: salaries,
          debts: debts,
          cashBalance: balance,
          visitTotals: const Totals(),
          creditTotals: const Totals(),
        );

    test('إجمالي الرواتب في الفترة', () {
      final s = summary(salaries: [
        SalaryPayment(
          id: 'p1',
          employeeId: 'e1',
          employeeName: 'أ',
          amount: 1200,
          date: DateTime(2026, 9, 3),
          createdAt: DateTime(2026),
        ),
        SalaryPayment(
          id: 'p2',
          employeeId: 'e2',
          employeeName: 'ب',
          amount: 800,
          date: DateTime(2026, 9, 5),
          createdAt: DateTime(2026),
        ),
      ]);
      expect(s.salariesTotal, 2000);
      expect(s.salariesByEmployee.keys.length, 2);
    });

    test('إجمالي الديون القائمة', () {
      final s = summary(debts: [
        DebtRecord(
          id: 'd1',
          personName: 'أ',
          amount: 1000,
          paid: 400,
          date: DateTime(2026, 9, 1),
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
        DebtRecord(
          id: 'd2',
          personName: 'ب',
          amount: 500,
          date: DateTime(2026, 9, 1),
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      ]);
      expect(s.debtsTotal, 1100);
    });

    test('الفترة ليست فارغة إذا كان فيها رواتب فقط', () {
      expect(summary().isEmpty, isTrue);
      expect(
        summary(salaries: [
          SalaryPayment(
            id: 'p',
            employeeId: 'e',
            employeeName: 'أ',
            amount: 100,
            date: DateTime(2026, 9, 2),
            createdAt: DateTime(2026),
          ),
        ]).isEmpty,
        isFalse,
      );
    });
  });

  group('توليد التقرير مع الأقسام الجديدة', () {
    PeriodSummary fullSummary() => PeriodSummary(
          from: DateTime(2026, 9, 1),
          to: DateTime(2026, 9, 7),
          visits: const [],
          credits: const [],
          cash: [
            CashEntry(
              id: 'c1',
              direction: CashDirection.income,
              categoryKey: 'sale',
              categoryLabel: 'بيع',
              amount: 400,
              method: PayMethod.cash,
              date: DateTime(2026, 9, 2),
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
            ),
          ],
          salaries: [
            SalaryPayment(
              id: 'p1',
              employeeId: 'e1',
              employeeName: 'موظف الاختبار',
              amount: 1500,
              kind: SalaryKind.partial,
              date: DateTime(2026, 9, 4),
              forMonth: DateTime(2026, 9),
              notes: 'دفعة أولى',
              createdAt: DateTime(2026),
            ),
          ],
          debts: [
            DebtRecord(
              id: 'd1',
              personName: 'مدين الاختبار',
              personPhone: '0501234567',
              amount: 900,
              paid: 200,
              reason: 'بضاعة',
              date: DateTime(2026, 9, 1),
              dueDate: DateTime(2026, 10, 1),
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
            ),
          ],
          cashBalance: const CashBalance(cashIn: 4000, cashOut: 1500),
          visitTotals: const Totals(),
          creditTotals: const Totals(),
        );

    test('التقرير يُبنى مع كل الأقسام مفعّلة', () async {
      final bytes = await PdfService.instance.buildReport(
        summary: fullSummary(),
        settings: const ShopSettings(shopName: 'الأقصى'),
        options: const ReportOptions(
          includeSalaries: true,
          includeDebts: true,
        ),
      );
      expect(bytes.length, greaterThan(1000));
    });

    test('التقرير يُبنى مع إخفاء الرواتب والديون', () async {
      final bytes = await PdfService.instance.buildReport(
        summary: fullSummary(),
        settings: const ShopSettings(),
        options: const ReportOptions(
          includeSalaries: false,
          includeDebts: false,
          includeCashBalance: false,
        ),
      );
      expect(bytes.length, greaterThan(1000));
    });

    test('إخفاء الأقسام ينتج ملفًا أصغر من إظهارها', () async {
      final withAll = await PdfService.instance.buildReport(
        summary: fullSummary(),
        settings: const ShopSettings(),
        options: const ReportOptions(includeSalaries: true, includeDebts: true),
      );
      final without = await PdfService.instance.buildReport(
        summary: fullSummary(),
        settings: const ShopSettings(),
        options: const ReportOptions(includeSalaries: false, includeDebts: false),
      );
      expect(without.length, lessThan(withAll.length));
    });
  });

  group('اسم مهمة الطباعة', () {
    test('لاتيني بلا أحرف عربية ولا امتداد', () {
      final s = PeriodSummary(
        from: DateTime(2026, 9, 1),
        to: DateTime(2026, 9, 7),
        visits: const [],
        credits: const [],
        visitTotals: const Totals(),
        creditTotals: const Totals(),
      );

      final name = PdfService.printJobName(s);
      expect(name, 'Report_2026-09-01_to_2026-09-07');
      expect(name.contains('.pdf'), isFalse);
      expect(RegExp(r'^[A-Za-z0-9_\-]+$').hasMatch(name), isTrue);
    });

    test('اليوم الواحد يعطي اسمًا بتاريخ واحد', () {
      final s = PeriodSummary(
        from: DateTime(2026, 9, 7),
        to: DateTime(2026, 9, 7),
        visits: const [],
        credits: const [],
        visitTotals: const Totals(),
        creditTotals: const Totals(),
      );
      expect(PdfService.printJobName(s), 'Report_2026-09-07');
    });
  });
}
