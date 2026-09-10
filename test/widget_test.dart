import 'package:alaqsa_visits/db/repository.dart';
import 'package:alaqsa_visits/models/item_types.dart';
import 'package:alaqsa_visits/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('حساب الإجماليات', () {
    Item item({
      double price = 0,
      int qty = 1,
      MovementKind kind = MovementKind.out,
    }) =>
        Item(
          id: 'i',
          typeKey: 'camera',
          typeLabel: 'كاميرا',
          price: price,
          qty: qty,
          kind: kind,
          createdAt: DateTime(2026),
        );

    Visit visit() => Visit(
          id: 'v',
          customerId: 'c',
          customerName: 'عميل',
          date: DateTime(2026, 9, 6),
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );

    test('الصافي = الصادر ناقص الراجع', () {
      final vf = VisitFull(
        visit: visit(),
        items: [
          item(price: 100, qty: 2),
          item(price: 50, kind: MovementKind.returned),
        ],
      );

      expect(vf.totals.itemsTotal, 200);
      expect(vf.totals.returnedTotal, 50);
      expect(vf.totals.net, 150);
    });

    test('المتبقي يقل مع كل دفعة', () {
      final vf = VisitFull(
        visit: visit(),
        items: [item(price: 300)],
        payments: [
          Payment(id: 'p1', amount: 100, date: DateTime(2026)),
          Payment(id: 'p2', amount: 50, date: DateTime(2026)),
        ],
      );

      expect(vf.totals.paid, 150);
      expect(vf.totals.remaining, 150);
    });

    test('السداد الكامل يجعل المتبقي صفرًا', () {
      final vf = VisitFull(
        visit: visit(),
        items: [item(price: 250)],
        payments: [Payment(id: 'p', amount: 250, date: DateTime(2026))],
      );

      expect(vf.totals.remaining, 0);
    });

    test('جمع إجماليات عدة زيارات', () {
      const a = Totals(itemsTotal: 100, paid: 40);
      const b = Totals(itemsTotal: 200, returnedTotal: 20, paid: 60);
      final sum = a + b;

      expect(sum.itemsTotal, 300);
      expect(sum.returnedTotal, 20);
      expect(sum.paid, 100);
      expect(sum.net, 280);
      expect(sum.remaining, 180);
    });
  });

  group('وصف القطعة', () {
    test('التسمية اليدوية لها الأولوية', () {
      final i = Item(
        id: 'i',
        typeKey: 'camera',
        typeLabel: 'كاميرا',
        customName: 'كاميرا المدخل',
        specs: {'mp': '4 ميغا'},
        createdAt: DateTime(2026),
      );
      expect(i.description, 'كاميرا المدخل');
    });

    test('بدون تسمية يُبنى الوصف من النوع والتفاصيل', () {
      final i = Item(
        id: 'i',
        typeKey: 'camera',
        typeLabel: 'كاميرا',
        specs: {'mp': '4 ميغا', 'placement': 'خارجية'},
        createdAt: DateTime(2026),
      );
      expect(i.description, 'كاميرا - 4 ميغا، خارجية');
    });

    test('التفاصيل الفارغة لا تظهر في الوصف', () {
      final i = Item(
        id: 'i',
        typeKey: 'switch',
        typeLabel: 'سويتش',
        specs: {'ports': '8 بورت', 'poe': '', 'managed': null},
        createdAt: DateTime(2026),
      );
      expect(i.description, 'سويتش - 8 بورت');
    });
  });

  group('كتالوج الأنواع', () {
    test('كل نوع له مفتاح فريد', () {
      final keys = ItemTypes.all.map((t) => t.key).toList();
      expect(keys.toSet().length, keys.length);
    });

    test('النوع المجهول يرجع «أخرى»', () {
      expect(ItemTypes.byKey('لا-يوجد').key, 'other');
    });

    test('الكاميرا تحتوي حقول الميغا وفول كولر والتركيب', () {
      final keys = ItemTypes.camera.fields.map((f) => f.key).toSet();
      expect(keys, containsAll(['mp', 'full_color', 'motorized', 'placement']));
    });

    test('السويتش يحتوي عدد البورتات و PoE', () {
      final keys = ItemTypes.switchType.fields.map((f) => f.key).toSet();
      expect(keys, containsAll(['ports', 'poe']));
    });

    test('NVR يحتوي عدد القنوات', () {
      final keys = ItemTypes.nvr.fields.map((f) => f.key).toSet();
      expect(keys, contains('channels'));
    });
  });

  group('حالة الزيارة', () {
    test('التحويل من نص وإليه', () {
      for (final s in VisitStatus.values) {
        expect(VisitStatusX.fromCode(s.name), s);
      }
    });

    test('النص غير المعروف يرجع «تمت»', () {
      expect(VisitStatusX.fromCode('xyz'), VisitStatus.done);
      expect(VisitStatusX.fromCode(null), VisitStatus.done);
    });
  });

  group('الحركات المالية', () {
    CashEntry entry({
      double amount = 0,
      CashDirection direction = CashDirection.income,
      String category = 'sale',
    }) =>
        CashEntry(
          id: 'e',
          direction: direction,
          categoryKey: category,
          categoryLabel: CashCategory.byKey(category).label,
          amount: amount,
          date: DateTime(2026, 9, 6),
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );

    test('الوارد موجب والصادر سالب', () {
      expect(entry(amount: 100).signed, 100);
      expect(
        entry(amount: 100, direction: CashDirection.expense, category: 'purchase').signed,
        -100,
      );
    });

    test('إجماليات الصندوق تفصل الوارد عن الصادر', () {
      final t = CashTotals.from([
        entry(amount: 500),
        entry(amount: 300),
        entry(amount: 200, direction: CashDirection.expense, category: 'purchase'),
      ]);

      expect(t.income, 800);
      expect(t.expense, 200);
      expect(t.net, 600);
    });

    test('جمع إجماليات صندوقين', () {
      const a = CashTotals(income: 100, expense: 40);
      const b = CashTotals(income: 50, expense: 10);
      final sum = a + b;

      expect(sum.income, 150);
      expect(sum.expense, 50);
      expect(sum.net, 100);
    });

    test('تصنيفات الوارد والصادر منفصلة ولا تتداخل', () {
      for (final c in CashCategory.incomeCategories) {
        expect(c.direction, CashDirection.income, reason: c.label);
      }
      for (final c in CashCategory.expenseCategories) {
        expect(c.direction, CashDirection.expense, reason: c.label);
      }
    });

    test('كل تصنيف له مفتاح فريد', () {
      final keys = CashCategory.all.map((c) => c.key).toList();
      expect(keys.toSet().length, keys.length);
    });

    test('التصنيف المجهول لا يُسقط التطبيق', () {
      expect(CashCategory.byKey('لا-يوجد').key, 'other_income');
    });

    test('التحويل من نص وإليه للاتجاه وطريقة الدفع', () {
      for (final d in CashDirection.values) {
        expect(CashDirectionX.fromCode(d.name), d);
      }
      for (final m in PayMethod.values) {
        expect(PayMethodX.fromCode(m.name), m);
      }
      expect(CashDirectionX.fromCode(null), CashDirection.income);
      expect(PayMethodX.fromCode('xyz'), PayMethod.cash);
    });
  });

  group('ملخص الفترة مع الصندوق', () {
    PeriodSummary summary({
      List<CashEntry> cash = const [],
      Totals visitTotals = const Totals(),
    }) =>
        PeriodSummary(
          from: DateTime(2026, 9, 6),
          to: DateTime(2026, 9, 6),
          visits: const [],
          credits: const [],
          cash: cash,
          visitTotals: visitTotals,
          creditTotals: const Totals(),
        );

    CashEntry cashEntry(double amount, CashDirection d) => CashEntry(
          id: 'c$amount${d.name}',
          direction: d,
          categoryKey: d == CashDirection.income ? 'sale' : 'purchase',
          categoryLabel: 'x',
          amount: amount,
          date: DateTime(2026, 9, 6),
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );

    test('صافي النقد = محصّل الزيارات + الوارد - الصادر', () {
      final s = summary(
        visitTotals: const Totals(itemsTotal: 1000, paid: 400),
        cash: [
          cashEntry(200, CashDirection.income),
          cashEntry(150, CashDirection.expense),
        ],
      );

      expect(s.cashTotals.income, 200);
      expect(s.cashTotals.expense, 150);
      expect(s.netCashFlow, 450);
    });

    test('الفترة ليست فارغة إذا كان فيها حركة مالية فقط', () {
      expect(summary().isEmpty, isTrue);
      expect(summary(cash: [cashEntry(50, CashDirection.income)]).isEmpty, isFalse);
    });

    test('تجميع الحركات حسب التصنيف', () {
      final s = summary(cash: [
        cashEntry(100, CashDirection.income),
        cashEntry(200, CashDirection.income),
        cashEntry(50, CashDirection.expense),
      ]);

      expect(s.income.length, 2);
      expect(s.expenses.length, 1);
    });
  });
}
