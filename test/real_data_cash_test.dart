@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// يتحقق من حسابات الكاش على بيانات مطابقة لبيانات المستخدم الحقيقية،
/// بما فيها الحالة التي أظهرت الفرق بين 85 و−555.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;

  /// التوقيت المحلي للإمارات UTC+4 — نستخدم DateTime محلي كما يفعل التطبيق
  int ms(int y, int mo, int d, [int h = 0, int mi = 0]) =>
      DateTime(y, mo, d, h, mi).millisecondsSinceEpoch;

  int dayStart(int y, int mo, int d) => DateTime(y, mo, d).millisecondsSinceEpoch;
  int dayEnd(int y, int mo, int d) =>
      DateTime(y, mo, d, 23, 59, 59, 999).millisecondsSinceEpoch;

  setUp(() async {
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1, singleInstance: false),
    );

    await db.execute('''
      CREATE TABLE cash_entries (
        id TEXT PRIMARY KEY,
        direction TEXT NOT NULL,
        category_key TEXT NOT NULL,
        amount REAL NOT NULL,
        method TEXT NOT NULL,
        date INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE salary_payments (
        id TEXT PRIMARY KEY,
        amount REAL NOT NULL,
        method TEXT NOT NULL,
        date INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE payments (
        id TEXT PRIMARY KEY,
        amount REAL NOT NULL,
        method TEXT NOT NULL DEFAULT 'cash',
        date INTEGER NOT NULL
      )
    ''');
  });

  tearDown(() async => db.close());

  /// يحاكي cashBalance في المستودع
  Future<double> balance({int? fromMs, int? upToMs}) async {
    String range(String col) {
      final parts = <String>[];
      if (fromMs != null) parts.add(' AND $col >= $fromMs');
      if (upToMs != null) parts.add(' AND $col <= $upToMs');
      return parts.join();
    }

    double v(List<Map<String, Object?>> r) =>
        ((r.first['v'] as num?) ?? 0).toDouble();

    final income = v(await db.rawQuery(
        "SELECT COALESCE(SUM(amount),0) AS v FROM cash_entries "
        "WHERE direction='income' AND method='cash'${range('date')}"));
    final expense = v(await db.rawQuery(
        "SELECT COALESCE(SUM(amount),0) AS v FROM cash_entries "
        "WHERE direction='expense' AND method='cash' "
        "AND id NOT LIKE 'salary_%'${range('date')}"));
    final salary = v(await db.rawQuery(
        "SELECT COALESCE(SUM(amount),0) AS v FROM salary_payments "
        "WHERE method='cash'${range('date')}"));
    final visitPay = v(await db.rawQuery(
        "SELECT COALESCE(SUM(amount),0) AS v FROM payments "
        "WHERE method='cash' AND id NOT LIKE 'cash_%'${range('date')}"));

    return (income + visitPay) - (expense + salary);
  }

  Future<void> cash(String id, String dir, double amount, String method,
          int date, {String category = 'other'}) =>
      db.insert('cash_entries', {
        'id': id,
        'direction': dir,
        'category_key': category,
        'amount': amount,
        'method': method,
        'date': date,
      });

  /// يعيد بناء بيانات المستخدم الحقيقية
  Future<void> seedRealData() async {
    await cash('c1', 'income', 350, 'card', ms(2026, 9, 6));
    await cash('c2', 'income', 1850, 'cash', ms(2026, 9, 7, 17, 30));
    await cash('c3', 'expense', 500, 'cash', ms(2026, 9, 7, 18));
    await cash('c4', 'expense', 557, 'cash', ms(2026, 9, 7, 21, 15));
    await cash('c5', 'expense', 120, 'cash', ms(2026, 9, 7, 22, 35));
    await cash('c6', 'income', 100, 'cash', ms(2026, 9, 8, 19));
    await cash('c7', 'expense', 200, 'cash', ms(2026, 9, 9));
    await cash('c8', 'income', 400, 'cash', ms(2026, 9, 9, 11));
    await cash('c9', 'income', 1500, 'cash', ms(2026, 9, 9, 18));
    await cash('c10', 'expense', 10, 'cash', ms(2026, 9, 9, 20));
    await cash('c11', 'expense', 200, 'cash', ms(2026, 9, 10, 10, 20));
    await cash('c12', 'expense', 50, 'cash', ms(2026, 9, 10, 17, 10));
    await cash('c13', 'income', 2000, 'cash', ms(2026, 9, 10, 18, 30));
    await cash('c14', 'expense', 268, 'cash', ms(2026, 9, 10, 19, 45));
    await cash('c15', 'expense', 3600, 'cash', ms(2026, 9, 10, 23, 23),
        category: 'bank_deposit');

    await db.insert('salary_payments', {
      'id': 's1',
      'amount': 2100,
      'method': 'cash',
      'date': ms(2026, 9, 9),
    });

    await db.insert('payments',
        {'id': 'p1', 'amount': 800, 'method': 'cash', 'date': ms(2026, 9, 10)});
    await db.insert('payments',
        {'id': 'p2', 'amount': 400, 'method': 'cash', 'date': ms(2026, 9, 10)});
    // الدفعة التي وقعت بعد منتصف الليل — سبب الفرق بين 85 و−555
    await db.insert('payments', {
      'id': 'p3',
      'amount': 640,
      'method': 'cash',
      'date': ms(2026, 9, 11, 0, 5),
    });
  }

  test('الرصيد التراكمي الكلي يطابق 85 درهم', () async {
    await seedRealData();
    expect(await balance(), closeTo(85, 0.01));
  });

  test('رصيد نهاية 10/9 هو −555 لأن دفعة 640 وقعت بعد منتصف الليل', () async {
    await seedRealData();
    expect(await balance(upToMs: dayEnd(2026, 9, 10)), closeTo(-555, 0.01));
  });

  test('رصيد نهاية 11/9 يعود إلى 85 بعد احتساب دفعة اليوم', () async {
    await seedRealData();
    expect(await balance(upToMs: dayEnd(2026, 9, 11)), closeTo(85, 0.01));
  });

  test('حركة كاش يوم 11/9 وحده = +640', () async {
    await seedRealData();
    final dayFlow = await balance(
      fromMs: dayStart(2026, 9, 11),
      upToMs: dayEnd(2026, 9, 11),
    );
    expect(dayFlow, closeTo(640, 0.01));
  });

  test('حركة كاش يوم 10/9 وحده تشمل الإيداع البنكي', () async {
    await seedRealData();
    final dayFlow = await balance(
      fromMs: dayStart(2026, 9, 10),
      upToMs: dayEnd(2026, 9, 10),
    );
    // +800 +400 +2000 −200 −50 −268 −3600 = −918
    expect(dayFlow, closeTo(-918, 0.01));
  });

  test('دفعة بالبطاقة لا تدخل الكاش', () async {
    await db.insert('payments',
        {'id': 'pc', 'amount': 3000, 'method': 'card', 'date': ms(2026, 9, 11)});
    expect(await balance(), 0);
  });

  test('قيد الراتب المرآة لا يُخصم مرتين', () async {
    await db.insert('salary_payments', {
      'id': 'sx',
      'amount': 1000,
      'method': 'cash',
      'date': ms(2026, 9, 11),
    });
    // القيد المرآة في الصندوق يحمل بادئة salary_ ويُستبعد من الحساب
    await cash('salary_sx', 'expense', 1000, 'cash', ms(2026, 9, 11),
        category: 'salary');

    expect(await balance(), closeTo(-1000, 0.01));
  });

  test('الرصيد الافتتاحي ليوم = رصيد نهايته ناقص حركته', () async {
    await seedRealData();
    final closing = await balance(upToMs: dayEnd(2026, 9, 10));
    final dayFlow = await balance(
      fromMs: dayStart(2026, 9, 10),
      upToMs: dayEnd(2026, 9, 10),
    );
    final opening = closing - dayFlow;

    // رصيد نهاية 9/9
    final prevClosing = await balance(upToMs: dayEnd(2026, 9, 9));
    expect(opening, closeTo(prevClosing, 0.01));
  });
}
