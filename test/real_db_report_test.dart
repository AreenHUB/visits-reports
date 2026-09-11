@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// يشغّل استعلامات التقرير على قاعدة بيانات حقيقية بنفس مخطط التطبيق،
/// لاكتشاف أي خطأ SQL لا تظهره اختبارات الكائنات الجاهزة.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;

  int ms(int y, int mo, int d, [int h = 0, int mi = 0]) =>
      DateTime(y, mo, d, h, mi).millisecondsSinceEpoch;

  setUp(() async {
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 4, singleInstance: false),
    );

    // نفس مخطط التطبيق بعد الترقية إلى 4
    await db.execute('''
      CREATE TABLE customers (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, phone TEXT DEFAULT '',
        address TEXT DEFAULT '', notes TEXT DEFAULT '', created_at INTEGER NOT NULL)
    ''');
    await db.execute('''
      CREATE TABLE visits (
        id TEXT PRIMARY KEY, customer_id TEXT, customer_name TEXT NOT NULL,
        customer_phone TEXT DEFAULT '', customer_address TEXT DEFAULT '',
        date INTEGER NOT NULL, purpose TEXT DEFAULT '', status TEXT DEFAULT 'done',
        not_done_reason TEXT DEFAULT '', day_notes TEXT DEFAULT '',
        signature_path TEXT DEFAULT '', created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL)
    ''');
    await db.execute('''
      CREATE TABLE credits (
        id TEXT PRIMARY KEY, person_name TEXT NOT NULL, person_phone TEXT DEFAULT '',
        date INTEGER NOT NULL, due_date INTEGER, notes TEXT DEFAULT '',
        signature_path TEXT DEFAULT '', settled INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)
    ''');
    await db.execute('''
      CREATE TABLE items (
        id TEXT PRIMARY KEY, visit_id TEXT, credit_id TEXT, serial TEXT DEFAULT '',
        type_key TEXT NOT NULL, type_label TEXT NOT NULL, custom_name TEXT DEFAULT '',
        specs TEXT DEFAULT '{}', price REAL DEFAULT 0, qty INTEGER DEFAULT 1,
        kind TEXT DEFAULT 'out', notes TEXT DEFAULT '', sort_order INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL)
    ''');
    await db.execute('''
      CREATE TABLE payments (
        id TEXT PRIMARY KEY, visit_id TEXT, credit_id TEXT, amount REAL NOT NULL,
        date INTEGER NOT NULL, method TEXT DEFAULT 'cash', notes TEXT DEFAULT '')
    ''');
    await db.execute('''
      CREATE TABLE cash_entries (
        id TEXT PRIMARY KEY, direction TEXT NOT NULL DEFAULT 'income',
        category_key TEXT NOT NULL, category_label TEXT NOT NULL,
        description TEXT DEFAULT '', party_name TEXT DEFAULT '',
        amount REAL NOT NULL DEFAULT 0, method TEXT DEFAULT 'cash',
        date INTEGER NOT NULL, notes TEXT DEFAULT '', linked_credit_id TEXT,
        linked_debt_id TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)
    ''');
    await db.execute('''
      CREATE TABLE day_notes (
        day INTEGER PRIMARY KEY, notes TEXT DEFAULT '', updated_at INTEGER NOT NULL)
    ''');
    await db.execute('''
      CREATE TABLE employees (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, phone TEXT DEFAULT '',
        role TEXT DEFAULT '', monthly_salary REAL DEFAULT 0, notes TEXT DEFAULT '',
        active INTEGER DEFAULT 1, created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL)
    ''');
    await db.execute('''
      CREATE TABLE salary_payments (
        id TEXT PRIMARY KEY, employee_id TEXT NOT NULL, employee_name TEXT NOT NULL,
        amount REAL NOT NULL DEFAULT 0, kind TEXT DEFAULT 'partial',
        method TEXT DEFAULT 'cash', date INTEGER NOT NULL, for_month INTEGER,
        notes TEXT DEFAULT '', created_at INTEGER NOT NULL)
    ''');
    await db.execute('''
      CREATE TABLE debts (
        id TEXT PRIMARY KEY, person_name TEXT NOT NULL, person_phone TEXT DEFAULT '',
        person_address TEXT DEFAULT '', amount REAL NOT NULL DEFAULT 0,
        paid REAL NOT NULL DEFAULT 0, manual_paid REAL NOT NULL DEFAULT 0,
        reason TEXT DEFAULT '', date INTEGER NOT NULL, due_date INTEGER,
        notes TEXT DEFAULT '', created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)
    ''');
    await db.execute('''
      CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)
    ''');
  });

  tearDown(() async => db.close());

  /// نسخة طبق الأصل من استعلامات cashBalance في المستودع
  Future<Map<String, double>> cashBalanceQueries({
    DateTime? from,
    DateTime? upTo,
  }) async {
    final upperMs = upTo == null
        ? null
        : DateTime(upTo.year, upTo.month, upTo.day, 23, 59, 59, 999)
            .millisecondsSinceEpoch;
    final lowerMs = from == null
        ? null
        : DateTime(from.year, from.month, from.day).millisecondsSinceEpoch;

    String range(String col) {
      final parts = <String>[];
      if (lowerMs != null) parts.add(' AND $col >= $lowerMs');
      if (upperMs != null) parts.add(' AND $col <= $upperMs');
      return parts.join();
    }

    double v(List<Map<String, Object?>> r) =>
        ((r.first['v'] as num?) ?? 0).toDouble();

    final income = v(await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) AS v FROM cash_entries
      WHERE direction = 'income' AND method = 'cash'${range('date')}
    '''));
    final expense = v(await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) AS v FROM cash_entries
      WHERE direction = 'expense' AND method = 'cash'
        AND id NOT LIKE 'salary_%'${range('date')}
    '''));
    final salary = v(await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) AS v FROM salary_payments
      WHERE method = 'cash'${range('date')}
    '''));
    final visitPay = v(await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) AS v FROM payments
      WHERE method = 'cash' AND id NOT LIKE 'cash_%'${range('date')}
    '''));

    return {
      'income': income,
      'expense': expense,
      'salary': salary,
      'visitPay': visitPay,
      'balance': (income + visitPay) - (expense + salary),
    };
  }

  Future<void> seed() async {
    final now = ms(2026, 9, 10);
    await db.insert('visits', {
      'id': 'v1',
      'customer_name': 'عميل',
      'date': ms(2026, 9, 8),
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('items', {
      'id': 'i1',
      'visit_id': 'v1',
      'type_key': 'camera',
      'type_label': 'كاميرا',
      'price': 500.0,
      'created_at': now,
    });
    await db.insert('payments', {
      'id': 'p1',
      'visit_id': 'v1',
      'amount': 400.0,
      'date': ms(2026, 9, 8),
      'method': 'cash',
    });
    await db.insert('cash_entries', {
      'id': 'c1',
      'direction': 'income',
      'category_key': 'sale',
      'category_label': 'بيع',
      'amount': 300.0,
      'method': 'cash',
      'date': ms(2026, 9, 9),
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('employees', {
      'id': 'e1',
      'name': 'عادل',
      'monthly_salary': 3000.0,
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('salary_payments', {
      'id': 's1',
      'employee_id': 'e1',
      'employee_name': 'عادل',
      'amount': 2100.0,
      'method': 'cash',
      'date': ms(2026, 9, 9),
      'created_at': now,
    });
    await db.insert('debts', {
      'id': 'd1',
      'person_name': 'مدين',
      'amount': 1000.0,
      'paid': 0.0,
      'manual_paid': 0.0,
      'date': ms(2026, 9, 7),
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('day_notes', {
      'day': ms(2026, 9, 9),
      'notes': 'ملاحظة اليوم',
      'updated_at': now,
    });
  }

  test('استعلامات الكاش لليوم الواحد تعمل بلا خطأ SQL', () async {
    await seed();
    final r = await cashBalanceQueries(
      from: DateTime(2026, 9, 9),
      upTo: DateTime(2026, 9, 9),
    );
    // 300 وارد − 2100 راتب = −1800
    expect(r['balance'], closeTo(-1800, 0.01));
  });

  test('استعلامات الكاش لفترة أسبوع تعمل بلا خطأ SQL', () async {
    await seed();
    final r = await cashBalanceQueries(
      from: DateTime(2026, 9, 5),
      upTo: DateTime(2026, 9, 11),
    );
    // 300 + 400 − 2100 = −1400
    expect(r['balance'], closeTo(-1400, 0.01));
  });

  test('استعلامات الكاش لفترة ثلاثة أيام تعمل', () async {
    await seed();
    final r = await cashBalanceQueries(
      from: DateTime(2026, 9, 8),
      upTo: DateTime(2026, 9, 10),
    );
    expect(r['balance'], closeTo(-1400, 0.01));
  });

  test('استعلام بلا حدود زمنية يعمل', () async {
    await seed();
    final r = await cashBalanceQueries();
    expect(r['balance'], closeTo(-1400, 0.01));
  });

  test('استعلام بحد أعلى فقط يعمل', () async {
    await seed();
    final r = await cashBalanceQueries(upTo: DateTime(2026, 9, 9));
    expect(r['balance'], closeTo(-1400, 0.01));
  });

  test('استعلام بحد أدنى فقط يعمل', () async {
    await seed();
    final r = await cashBalanceQueries(from: DateTime(2026, 9, 9));
    expect(r['balance'], closeTo(-1800, 0.01));
  });

  test('جلب الزيارات والقطع والدفعات لفترة يعمل', () async {
    await seed();

    final visits = await db.query(
      'visits',
      where: 'date >= ? AND date <= ?',
      whereArgs: [
        ms(2026, 9, 5),
        DateTime(2026, 9, 11, 23, 59, 59, 999).millisecondsSinceEpoch,
      ],
      orderBy: 'date DESC, created_at DESC',
    );
    expect(visits.length, 1);

    final ids = visits.map((v) => v['id']).toList();
    final ph = List.filled(ids.length, '?').join(',');

    final items = await db.query('items',
        where: 'visit_id IN ($ph)', whereArgs: ids, orderBy: 'sort_order ASC');
    expect(items.length, 1);

    final pays = await db.query('payments',
        where: 'visit_id IN ($ph)', whereArgs: ids, orderBy: 'date ASC');
    expect(pays.length, 1);
    expect(pays.first['method'], 'cash');
  });

  test('جلب الرواتب والديون والملاحظات لفترة يعمل', () async {
    await seed();

    final salaries = await db.query(
      'salary_payments',
      where: 'date >= ? AND date <= ?',
      whereArgs: [
        ms(2026, 9, 5),
        DateTime(2026, 9, 11, 23, 59, 59, 999).millisecondsSinceEpoch,
      ],
      orderBy: 'date DESC',
    );
    expect(salaries.length, 1);

    final debts = await db.query('debts',
        where: '(amount - paid) > 0.009', orderBy: 'date DESC');
    expect(debts.length, 1);

    final notes = await db.query(
      'day_notes',
      where: 'day >= ? AND day <= ?',
      whereArgs: [
        ms(2026, 9, 5),
        DateTime(2026, 9, 11, 23, 59, 59, 999).millisecondsSinceEpoch,
      ],
      orderBy: 'day ASC',
    );
    expect(notes.length, 1);
  });

  test('فترة فارغة لا ترمي خطأ', () async {
    await seed();
    final r = await cashBalanceQueries(
      from: DateTime(2025, 1, 1),
      upTo: DateTime(2025, 1, 7),
    );
    expect(r['balance'], 0);
  });

  test('الاستعلام على قاعدة فارغة تمامًا لا يرمي خطأ', () async {
    final r = await cashBalanceQueries(
      from: DateTime(2026, 9, 5),
      upTo: DateTime(2026, 9, 11),
    );
    expect(r['balance'], 0);
  });
}
