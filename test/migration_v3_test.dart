@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// يتحقق أن الترقية من الإصدار 2 إلى 3 تضيف جداول الرواتب والديون
/// دون المساس بأي بيانات موجودة — وهذا ما يحدث عند التحديث فوق القديم.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  const employeesSql = '''
    CREATE TABLE IF NOT EXISTS employees (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      phone TEXT DEFAULT '',
      role TEXT DEFAULT '',
      monthly_salary REAL DEFAULT 0,
      notes TEXT DEFAULT '',
      active INTEGER DEFAULT 1,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''';

  const salarySql = '''
    CREATE TABLE IF NOT EXISTS salary_payments (
      id TEXT PRIMARY KEY,
      employee_id TEXT NOT NULL,
      employee_name TEXT NOT NULL,
      amount REAL NOT NULL DEFAULT 0,
      kind TEXT DEFAULT 'partial',
      method TEXT DEFAULT 'cash',
      date INTEGER NOT NULL,
      for_month INTEGER,
      notes TEXT DEFAULT '',
      created_at INTEGER NOT NULL
    )
  ''';

  const debtsSql = '''
    CREATE TABLE IF NOT EXISTS debts (
      id TEXT PRIMARY KEY,
      person_name TEXT NOT NULL,
      person_phone TEXT DEFAULT '',
      person_address TEXT DEFAULT '',
      amount REAL NOT NULL DEFAULT 0,
      paid REAL NOT NULL DEFAULT 0,
      reason TEXT DEFAULT '',
      date INTEGER NOT NULL,
      due_date INTEGER,
      notes TEXT DEFAULT '',
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''';

  Future<void> migrate(Database db, int from, int to) async {
    if (from < 3) {
      await db.execute(employeesSql);
      await db.execute(salarySql);
      await db.execute(debtsSql);
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_salary_employee ON salary_payments (employee_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_debts_date ON debts (date)');
    }
  }

  test('الترقية من 2 إلى 3 تحافظ على كل البيانات القديمة', () async {
    final dir = await Directory.systemTemp.createTemp('alaqsa_mig_v3');
    final path = '${dir.path}/test_v2.db';
    addTearDown(() async => dir.delete(recursive: true));

    final now = DateTime.now().millisecondsSinceEpoch;

    // قاعدة بالإصدار 2 فيها زيارات وقطع وحركات مالية
    var db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        singleInstance: false,
        onCreate: (db, v) async {
          await db.execute('''
            CREATE TABLE visits (
              id TEXT PRIMARY KEY,
              customer_name TEXT NOT NULL,
              date INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE items (
              id TEXT PRIMARY KEY,
              visit_id TEXT,
              serial TEXT,
              price REAL
            )
          ''');
          await db.execute('''
            CREATE TABLE cash_entries (
              id TEXT PRIMARY KEY,
              direction TEXT NOT NULL DEFAULT 'income',
              category_key TEXT NOT NULL,
              category_label TEXT NOT NULL,
              amount REAL NOT NULL DEFAULT 0,
              method TEXT DEFAULT 'cash',
              date INTEGER NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
        },
      ),
    );

    await db.insert('visits', {
      'id': 'v1',
      'customer_name': 'عميل من الإصدار الثاني',
      'date': now,
    });
    await db.insert('items', {
      'id': 'i1',
      'visit_id': 'v1',
      'serial': 'SN-KEEP-ME-123',
      'price': 750.0,
    });
    await db.insert('cash_entries', {
      'id': 'c1',
      'direction': 'income',
      'category_key': 'sale',
      'category_label': 'بيع',
      'amount': 320.0,
      'method': 'cash',
      'date': now,
      'created_at': now,
      'updated_at': now,
    });
    await db.close();

    // نفتحها بالإصدار 3 فتُشغَّل الترقية
    db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 3,
        singleInstance: false,
        onUpgrade: migrate,
      ),
    );

    // كل البيانات القديمة سليمة
    final visits = await db.query('visits');
    expect(visits.length, 1);
    expect(visits.first['customer_name'], 'عميل من الإصدار الثاني');

    final items = await db.query('items');
    expect(items.first['serial'], 'SN-KEEP-ME-123');
    expect(items.first['price'], 750.0);

    final cash = await db.query('cash_entries');
    expect(cash.length, 1);
    expect(cash.first['amount'], 320.0);

    // الجداول الجديدة موجودة وقابلة للكتابة
    await db.insert('employees', {
      'id': 'e1',
      'name': 'موظف تجريبي',
      'monthly_salary': 3000.0,
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('salary_payments', {
      'id': 's1',
      'employee_id': 'e1',
      'employee_name': 'موظف تجريبي',
      'amount': 1500.0,
      'kind': 'partial',
      'method': 'cash',
      'date': now,
      'created_at': now,
    });
    await db.insert('debts', {
      'id': 'd1',
      'person_name': 'مدين تجريبي',
      'amount': 500.0,
      'paid': 100.0,
      'date': now,
      'created_at': now,
      'updated_at': now,
    });

    expect((await db.query('employees')).length, 1);
    expect((await db.query('salary_payments')).first['amount'], 1500.0);
    expect((await db.query('debts')).first['person_name'], 'مدين تجريبي');

    await db.close();
  });

  test('الترقية من 1 إلى 3 دفعة واحدة تعمل أيضًا', () async {
    final dir = await Directory.systemTemp.createTemp('alaqsa_mig_v1v3');
    final path = '${dir.path}/test_v1.db';
    addTearDown(() async => dir.delete(recursive: true));

    final now = DateTime.now().millisecondsSinceEpoch;

    var db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        singleInstance: false,
        onCreate: (db, v) async {
          await db.execute('''
            CREATE TABLE visits (
              id TEXT PRIMARY KEY,
              customer_name TEXT NOT NULL,
              date INTEGER NOT NULL
            )
          ''');
        },
      ),
    );
    await db.insert('visits',
        {'id': 'v1', 'customer_name': 'عميل قديم جدًا', 'date': now});
    await db.close();

    db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 3,
        singleInstance: false,
        onUpgrade: (db, from, to) async {
          // نحاكي الترقية المتدرّجة: 1 ثم 2 ثم 3
          if (from < 2) {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS cash_entries (
                id TEXT PRIMARY KEY,
                direction TEXT NOT NULL DEFAULT 'income',
                category_key TEXT NOT NULL,
                category_label TEXT NOT NULL,
                amount REAL NOT NULL DEFAULT 0,
                method TEXT DEFAULT 'cash',
                date INTEGER NOT NULL,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
              )
            ''');
          }
          await migrate(db, from, to);
        },
      ),
    );

    expect((await db.query('visits')).first['customer_name'], 'عميل قديم جدًا');
    expect((await db.query('employees')).isEmpty, isTrue);
    expect((await db.query('debts')).isEmpty, isTrue);

    await db.close();
  });

  test('إعادة تشغيل ترقية 3 لا تمسح البيانات', () async {
    final path = inMemoryDatabasePath;
    final now = DateTime.now().millisecondsSinceEpoch;

    final db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 3, singleInstance: false),
    );
    await db.execute(debtsSql);
    await db.insert('debts', {
      'id': 'keep',
      'person_name': 'يجب أن يبقى',
      'amount': 200.0,
      'paid': 0.0,
      'date': now,
      'created_at': now,
      'updated_at': now,
    });

    await migrate(db, 2, 3);

    final rows = await db.query('debts');
    expect(rows.length, 1);
    expect(rows.first['person_name'], 'يجب أن يبقى');

    await db.close();
  });
}
