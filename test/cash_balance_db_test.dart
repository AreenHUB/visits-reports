@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// يتحقق أن حساب رصيد الكاش يعدّ النقد فقط ويستبعد البطاقة والتحويل،
/// وأنه يطرح المصاريف ودفعات الرواتب النقدية.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  final now = DateTime.now().millisecondsSinceEpoch;

  setUp(() async {
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1, singleInstance: false),
    );

    await db.execute('''
      CREATE TABLE cash_entries (
        id TEXT PRIMARY KEY,
        direction TEXT NOT NULL,
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
        date INTEGER NOT NULL
      )
    ''');
  });

  tearDown(() async => db.close());

  /// يحاكي استعلامات cashBalance في المستودع
  Future<double> balance() async {
    double v(List<Map<String, Object?>> r) =>
        ((r.first['v'] as num?) ?? 0).toDouble();

    final income = v(await db.rawQuery(
        "SELECT COALESCE(SUM(amount),0) AS v FROM cash_entries WHERE direction='income' AND method='cash'"));
    final expense = v(await db.rawQuery(
        "SELECT COALESCE(SUM(amount),0) AS v FROM cash_entries WHERE direction='expense' AND method='cash'"));
    final salary = v(await db.rawQuery(
        "SELECT COALESCE(SUM(amount),0) AS v FROM salary_payments WHERE method='cash'"));
    final visitPay = v(await db.rawQuery(
        "SELECT COALESCE(SUM(amount),0) AS v FROM payments WHERE id NOT LIKE 'cash_%'"));

    return (income + visitPay) - (expense + salary);
  }

  Future<void> addCash(String id, String dir, double amount, String method) =>
      db.insert('cash_entries', {
        'id': id,
        'direction': dir,
        'amount': amount,
        'method': method,
        'date': now,
      });

  test('البطاقة والتحويل لا يدخلان في رصيد الكاش', () async {
    await addCash('c1', 'income', 1000, 'cash');
    await addCash('c2', 'income', 5000, 'card');
    await addCash('c3', 'income', 3000, 'transfer');
    await addCash('c4', 'income', 2000, 'cheque');

    // النقد فقط يُحتسب
    expect(await balance(), 1000);
  });

  test('المصاريف النقدية تُطرح والبطاقية لا', () async {
    await addCash('c1', 'income', 2000, 'cash');
    await addCash('c2', 'expense', 500, 'cash');
    await addCash('c3', 'expense', 900, 'card');

    expect(await balance(), 1500);
  });

  test('رواتب مدفوعة نقدًا تُطرح من الرصيد', () async {
    await addCash('c1', 'income', 5000, 'cash');
    await db.insert('salary_payments',
        {'id': 's1', 'amount': 1200, 'method': 'cash', 'date': now});
    await db.insert('salary_payments',
        {'id': 's2', 'amount': 800, 'method': 'transfer', 'date': now});

    // 5000 - 1200 = 3800، والتحويل لا يؤثر
    expect(await balance(), 3800);
  });

  test('دفعات الزيارات تُضاف، وحركات الصندوق المرتبطة لا تُحتسب مرتين',
      () async {
    await db.insert('payments', {'id': 'p1', 'amount': 700, 'date': now});
    // دفعة أُنشئت من حركة صندوق: تبدأ بـ cash_ فتُستبعد لتفادي التكرار
    await db.insert('payments', {'id': 'cash_x1', 'amount': 300, 'date': now});
    await addCash('x1', 'income', 300, 'cash');

    // 700 (دفعة زيارة) + 300 (حركة الصندوق) = 1000، بلا احتساب مزدوج
    expect(await balance(), 1000);
  });

  test('الرصيد يصبح سالبًا إذا تجاوز الخارج الداخل', () async {
    await addCash('c1', 'income', 200, 'cash');
    await addCash('c2', 'expense', 900, 'cash');

    expect(await balance(), -700);
  });

  test('قاعدة فارغة تعطي رصيدًا صفرًا', () async {
    expect(await balance(), 0);
  });
}
