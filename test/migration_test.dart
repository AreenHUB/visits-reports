@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// يتحقق أن ترقية المخطط من الإصدار 1 إلى 2 تضيف الجداول الجديدة
/// دون المساس بأي بيانات موجودة — وهذا ما يحدث عند تثبيت تحديث فوق القديم.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  const cashTableSql = '''
    CREATE TABLE IF NOT EXISTS cash_entries (
      id TEXT PRIMARY KEY,
      direction TEXT NOT NULL DEFAULT 'income',
      category_key TEXT NOT NULL,
      category_label TEXT NOT NULL,
      description TEXT DEFAULT '',
      party_name TEXT DEFAULT '',
      amount REAL NOT NULL DEFAULT 0,
      method TEXT DEFAULT 'cash',
      date INTEGER NOT NULL,
      notes TEXT DEFAULT '',
      linked_credit_id TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''';

  const dayNotesSql = '''
    CREATE TABLE IF NOT EXISTS day_notes (
      day INTEGER PRIMARY KEY,
      notes TEXT DEFAULT '',
      updated_at INTEGER NOT NULL
    )
  ''';

  Future<void> migrate(Database db, int from, int to) async {
    if (from < 2) {
      await db.execute(cashTableSql);
      await db.execute(dayNotesSql);
      await db.execute('CREATE INDEX IF NOT EXISTS idx_cash_date ON cash_entries (date)');
    }
  }

  test('الترقية من 1 إلى 2 تحافظ على البيانات القديمة', () async {
    // ملف حقيقي لأن قاعدة الذاكرة لا تبقى بعد الإغلاق
    final dir = await Directory.systemTemp.createTemp('alaqsa_mig');
    final path = '${dir.path}/test_v1.db';
    addTearDown(() async => dir.delete(recursive: true));

    // نبني قاعدة بالإصدار القديم ونضع فيها بيانات
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
          await db.execute('''
            CREATE TABLE items (
              id TEXT PRIMARY KEY,
              visit_id TEXT,
              serial TEXT,
              price REAL
            )
          ''');
        },
      ),
    );

    await db.insert('visits', {
      'id': 'v1',
      'customer_name': 'عميل قديم',
      'date': DateTime(2026, 9, 1).millisecondsSinceEpoch,
    });
    await db.insert('items', {
      'id': 'i1',
      'visit_id': 'v1',
      'serial': 'SN-OLD-123',
      'price': 450.0,
    });
    await db.close();

    // نفتحها بالإصدار الجديد فتُشغَّل الترقية
    db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        singleInstance: false,
        onUpgrade: migrate,
      ),
    );

    // البيانات القديمة سليمة
    final visits = await db.query('visits');
    expect(visits.length, 1);
    expect(visits.first['customer_name'], 'عميل قديم');

    final items = await db.query('items');
    expect(items.length, 1);
    expect(items.first['serial'], 'SN-OLD-123');
    expect(items.first['price'], 450.0);

    // الجداول الجديدة موجودة وقابلة للكتابة
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('cash_entries', {
      'id': 'c1',
      'direction': 'income',
      'category_key': 'sale',
      'category_label': 'بيع أغراض من المحل',
      'amount': 200.0,
      'date': now,
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('day_notes', {
      'day': now,
      'notes': 'ملاحظة تجريبية',
      'updated_at': now,
    });

    expect((await db.query('cash_entries')).length, 1);
    expect((await db.query('day_notes')).first['notes'], 'ملاحظة تجريبية');

    await db.close();
  });

  test('إعادة تشغيل الترقية لا تُسقط البيانات (idempotent)', () async {
    final path = inMemoryDatabasePath;

    final db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 1, singleInstance: false),
    );
    await db.execute(cashTableSql);

    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('cash_entries', {
      'id': 'keep-me',
      'direction': 'expense',
      'category_key': 'purchase',
      'category_label': 'شراء بضاعة',
      'amount': 75.0,
      'date': now,
      'created_at': now,
      'updated_at': now,
    });

    // تشغيل نفس الترقية مرة أخرى: CREATE TABLE IF NOT EXISTS لا يمسح شيئًا
    await migrate(db, 1, 2);

    final rows = await db.query('cash_entries');
    expect(rows.length, 1);
    expect(rows.first['id'], 'keep-me');
    expect(rows.first['amount'], 75.0);

    await db.close();
  });
}
