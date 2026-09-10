@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// يتحقق أن الترقية إلى الإصدار 4 تضيف الأعمدة الجديدة دون المساس
/// بأي بيانات — وهو ما يحدث عند تثبيت التحديث فوق نسخة المستخدم الحالية.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<void> addColumnIfMissing(
      Database db, String table, String column, String def) async {
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    if (cols.any((c) => c['name'] == column)) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $def');
  }

  Future<void> migrateV4(Database db) async {
    await addColumnIfMissing(db, 'payments', 'method', "TEXT DEFAULT 'cash'");
    await addColumnIfMissing(db, 'cash_entries', 'linked_debt_id', 'TEXT');
    await addColumnIfMissing(
        db, 'debts', 'manual_paid', 'REAL NOT NULL DEFAULT 0');
    await db.execute(
        'UPDATE debts SET manual_paid = paid WHERE manual_paid = 0 AND paid > 0');
  }

  test('الترقية إلى 4 تحافظ على بيانات المستخدم وتضيف الأعمدة', () async {
    final dir = await Directory.systemTemp.createTemp('alaqsa_mig_v4');
    final path = '${dir.path}/v3.db';
    addTearDown(() async => dir.delete(recursive: true));

    final now = DateTime.now().millisecondsSinceEpoch;

    // قاعدة بالإصدار 3 بجداولها كما هي قبل التحديث
    var db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 3,
        singleInstance: false,
        onCreate: (db, v) async {
          await db.execute('''
            CREATE TABLE payments (
              id TEXT PRIMARY KEY,
              visit_id TEXT,
              amount REAL NOT NULL,
              date INTEGER NOT NULL,
              notes TEXT DEFAULT ''
            )
          ''');
          await db.execute('''
            CREATE TABLE cash_entries (
              id TEXT PRIMARY KEY,
              direction TEXT NOT NULL,
              category_key TEXT NOT NULL,
              category_label TEXT NOT NULL,
              amount REAL NOT NULL,
              method TEXT DEFAULT 'cash',
              date INTEGER NOT NULL,
              linked_credit_id TEXT,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE debts (
              id TEXT PRIMARY KEY,
              person_name TEXT NOT NULL,
              amount REAL NOT NULL DEFAULT 0,
              paid REAL NOT NULL DEFAULT 0,
              date INTEGER NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
        },
      ),
    );

    // بيانات موجودة قبل الترقية
    await db.insert('payments', {
      'id': 'hm67r4tptcddttz7',
      'visit_id': 'v1',
      'amount': 640.0,
      'date': now,
      'notes': 'سعر القطعة 500 و أجور 140',
    });
    await db.insert('cash_entries', {
      'id': 'hm68d234rsnswyz5',
      'direction': 'expense',
      'category_key': 'other_expense',
      'category_label': 'صادر آخر',
      'amount': 3600.0,
      'method': 'cash',
      'date': now,
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('debts', {
      'id': 'd1',
      'person_name': 'مدين قديم',
      'amount': 1000.0,
      'paid': 300.0,
      'date': now,
      'created_at': now,
      'updated_at': now,
    });
    await db.close();

    // فتح بالإصدار 4 يشغّل الترقية
    db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 4,
        singleInstance: false,
        onUpgrade: (db, from, to) async => migrateV4(db),
      ),
    );

    // البيانات القديمة سليمة تمامًا
    final pay = (await db.query('payments')).single;
    expect(pay['amount'], 640.0);
    expect(pay['notes'], 'سعر القطعة 500 و أجور 140');
    // الدفعات القديمة تأخذ 'cash' افتراضيًا — وهو ما كان يفترضه الحساب
    expect(pay['method'], 'cash');

    final entry = (await db.query('cash_entries')).single;
    expect(entry['amount'], 3600.0);
    expect(entry['linked_debt_id'], isNull);

    final debt = (await db.query('debts')).single;
    expect(debt['paid'], 300.0);
    // المسدَّد القديم يُنقل إلى manual_paid حتى لا تمحوه إعادة الحساب
    expect(debt['manual_paid'], 300.0);

    await db.close();
  });

  test('إعادة تشغيل ترقية 4 آمنة ولا تكرّر الأعمدة', () async {
    final dir = await Directory.systemTemp.createTemp('alaqsa_mig_v4b');
    final path = '${dir.path}/v4.db';
    addTearDown(() async => dir.delete(recursive: true));

    final now = DateTime.now().millisecondsSinceEpoch;

    final db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 4, singleInstance: false),
    );
    await db.execute('''
      CREATE TABLE payments (
        id TEXT PRIMARY KEY,
        amount REAL NOT NULL,
        date INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE cash_entries (id TEXT PRIMARY KEY, amount REAL)
    ''');
    await db.execute('''
      CREATE TABLE debts (
        id TEXT PRIMARY KEY,
        paid REAL NOT NULL DEFAULT 0
      )
    ''');
    await db.insert('payments', {'id': 'keep', 'amount': 99.0, 'date': now});

    await migrateV4(db);
    await migrateV4(db); // مرة ثانية: يجب ألا ترمي خطأ

    final rows = await db.query('payments');
    expect(rows.length, 1);
    expect(rows.first['amount'], 99.0);

    await db.close();
  });
}
