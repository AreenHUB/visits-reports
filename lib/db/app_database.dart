import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../models/models.dart';
import 'secure_key.dart';

/// قاعدة بيانات مشفّرة (SQLCipher) تحفظ كل شيء محليًا على الجهاز.
/// مفتاح التشفير يُولَّد عشوائيًا مرة واحدة ويُخزَّن في مخزن أندرويد الآمن.
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  static const _dbFileName = 'alaqsa_visits.db';
  static const _schemaVersion = 4;

  Database? _db;

  Future<Database> get database async => _db ??= await _open();

  Future<String> get databasePath async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, _dbFileName);
  }

  /// مجلد المرفقات: التواقيع والصور
  Future<Directory> get attachmentsDir async {
    final dir = await getApplicationDocumentsDirectory();
    final att = Directory(p.join(dir.path, 'attachments'));
    if (!await att.exists()) await att.create(recursive: true);
    return att;
  }

  Future<Database> _open() async {
    final path = await databasePath;
    final key = await SecureKey.getOrCreate();
    return openDatabase(
      path,
      password: key,
      version: _schemaVersion,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async => _createSchema(db),
      onUpgrade: _migrate,
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// يغلق الاتصال ليتمكن الاستعادة من استبدال ملف القاعدة
  Future<void> reopen() async {
    await close();
    await database;
  }

  Future<void> _createSchema(Database db) async {
    final batch = db.batch();

    batch.execute('''
      CREATE TABLE customers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT DEFAULT '',
        address TEXT DEFAULT '',
        notes TEXT DEFAULT '',
        created_at INTEGER NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE visits (
        id TEXT PRIMARY KEY,
        customer_id TEXT,
        customer_name TEXT NOT NULL,
        customer_phone TEXT DEFAULT '',
        customer_address TEXT DEFAULT '',
        date INTEGER NOT NULL,
        purpose TEXT DEFAULT '',
        status TEXT DEFAULT 'done',
        not_done_reason TEXT DEFAULT '',
        day_notes TEXT DEFAULT '',
        signature_path TEXT DEFAULT '',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE SET NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE credits (
        id TEXT PRIMARY KEY,
        person_name TEXT NOT NULL,
        person_phone TEXT DEFAULT '',
        date INTEGER NOT NULL,
        due_date INTEGER,
        notes TEXT DEFAULT '',
        signature_path TEXT DEFAULT '',
        settled INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE items (
        id TEXT PRIMARY KEY,
        visit_id TEXT,
        credit_id TEXT,
        serial TEXT DEFAULT '',
        type_key TEXT NOT NULL,
        type_label TEXT NOT NULL,
        custom_name TEXT DEFAULT '',
        specs TEXT DEFAULT '{}',
        price REAL DEFAULT 0,
        qty INTEGER DEFAULT 1,
        kind TEXT DEFAULT 'out',
        notes TEXT DEFAULT '',
        sort_order INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (visit_id) REFERENCES visits (id) ON DELETE CASCADE,
        FOREIGN KEY (credit_id) REFERENCES credits (id) ON DELETE CASCADE
      )
    ''');

    batch.execute('''
      CREATE TABLE payments (
        id TEXT PRIMARY KEY,
        visit_id TEXT,
        credit_id TEXT,
        amount REAL NOT NULL,
        date INTEGER NOT NULL,
        method TEXT DEFAULT 'cash',
        notes TEXT DEFAULT '',
        FOREIGN KEY (visit_id) REFERENCES visits (id) ON DELETE CASCADE,
        FOREIGN KEY (credit_id) REFERENCES credits (id) ON DELETE CASCADE
      )
    ''');

    // ذاكرة السيريالات لاقتراح النوع تلقائيًا عند إعادة القراءة
    batch.execute('''
      CREATE TABLE serial_memory (
        serial TEXT PRIMARY KEY,
        type_key TEXT NOT NULL,
        type_label TEXT NOT NULL,
        custom_name TEXT DEFAULT '',
        specs TEXT DEFAULT '{}',
        last_price REAL DEFAULT 0,
        use_count INTEGER DEFAULT 1,
        last_used INTEGER NOT NULL
      )
    ''');

    // إعدادات عامة: اسم المحل، الشعار، العملة...
    batch.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    batch.execute(_cashEntriesTableSql);
    batch.execute(_dayNotesTableSql);
    batch.execute(_employeesTableSql);
    batch.execute(_salaryPaymentsTableSql);
    batch.execute(_debtsTableSql);

    batch.execute('CREATE INDEX idx_visits_date ON visits (date)');
    batch.execute('CREATE INDEX idx_visits_customer ON visits (customer_id)');
    batch.execute('CREATE INDEX idx_credits_date ON credits (date)');
    batch.execute('CREATE INDEX idx_credits_settled ON credits (settled)');
    batch.execute('CREATE INDEX idx_items_visit ON items (visit_id)');
    batch.execute('CREATE INDEX idx_items_credit ON items (credit_id)');
    batch.execute('CREATE INDEX idx_items_serial ON items (serial)');
    batch.execute('CREATE INDEX idx_payments_visit ON payments (visit_id)');
    batch.execute('CREATE INDEX idx_payments_credit ON payments (credit_id)');
    batch.execute('CREATE INDEX idx_cash_date ON cash_entries (date)');
    batch.execute('CREATE INDEX idx_cash_direction ON cash_entries (direction)');
    batch.execute('CREATE INDEX idx_salary_employee ON salary_payments (employee_id)');
    batch.execute('CREATE INDEX idx_salary_date ON salary_payments (date)');
    batch.execute('CREATE INDEX idx_debts_date ON debts (date)');

    await batch.commit(noResult: true);
  }

  // ------------------------------------------------------------ الترقيات
  //
  // كل ترقية تضيف ما نقص فقط ولا تمسّ البيانات الموجودة، حتى يبقى كل شيء
  // سليمًا عند تثبيت نسخة جديدة من التطبيق فوق القديمة.

  /// جدول الحركات المالية المستقلة عن الزيارات
  static const _cashEntriesTableSql = '''
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
      linked_debt_id TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      FOREIGN KEY (linked_credit_id) REFERENCES credits (id) ON DELETE SET NULL,
      FOREIGN KEY (linked_debt_id) REFERENCES debts (id) ON DELETE SET NULL
    )
  ''';

  /// ملاحظات عامة على اليوم كله، تُرسل مع التقرير للمدير
  static const _dayNotesTableSql = '''
    CREATE TABLE IF NOT EXISTS day_notes (
      day INTEGER PRIMARY KEY,
      notes TEXT DEFAULT '',
      updated_at INTEGER NOT NULL
    )
  ''';


  /// جدول الموظفين
  static const _employeesTableSql = '''
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

  /// دفعات الرواتب المسلّمة للموظفين
  static const _salaryPaymentsTableSql = '''
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
      created_at INTEGER NOT NULL,
      FOREIGN KEY (employee_id) REFERENCES employees (id) ON DELETE CASCADE
    )
  ''';

  /// ديون العملاء — للتذكير بمن عليه دين
  static const _debtsTableSql = '''
    CREATE TABLE IF NOT EXISTS debts (
      id TEXT PRIMARY KEY,
      person_name TEXT NOT NULL,
      person_phone TEXT DEFAULT '',
      person_address TEXT DEFAULT '',
      amount REAL NOT NULL DEFAULT 0,
      paid REAL NOT NULL DEFAULT 0,
      manual_paid REAL NOT NULL DEFAULT 0,
      reason TEXT DEFAULT '',
      date INTEGER NOT NULL,
      due_date INTEGER,
      notes TEXT DEFAULT '',
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''';

  Future<void> _migrate(Database db, int from, int to) async {
    // الترقية إلى الإصدار 2: الحركات المالية وملاحظات اليوم
    if (from < 2) {
      await db.execute(_cashEntriesTableSql);
      await db.execute(_dayNotesTableSql);
      await db.execute('CREATE INDEX IF NOT EXISTS idx_cash_date ON cash_entries (date)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_cash_direction ON cash_entries (direction)');
    }

    // الترقية إلى الإصدار 3: الرواتب وديون العملاء
    if (from < 3) {
      await db.execute(_employeesTableSql);
      await db.execute(_salaryPaymentsTableSql);
      await db.execute(_debtsTableSql);
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_salary_employee ON salary_payments (employee_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_salary_date ON salary_payments (date)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_debts_date ON debts (date)');
    }

    // الترقية إلى الإصدار 4: طريقة الدفع للدفعات، وربط الحركة بدين عميل.
    // ALTER TABLE ADD COLUMN لا يمسّ أي صف موجود؛ الصفوف القديمة تأخذ
    // القيمة الافتراضية 'cash' وهو ما كان يفترضه الحساب سابقًا.
    if (from < 4) {
      await _addColumnIfMissing(db, 'payments', 'method', "TEXT DEFAULT 'cash'");
      await _addColumnIfMissing(db, 'cash_entries', 'linked_debt_id', 'TEXT');
      await _addColumnIfMissing(
          db, 'debts', 'manual_paid', 'REAL NOT NULL DEFAULT 0');

      // الديون القديمة: ما سُدِّد فيها كان كله يدويًا
      await db.execute(
          'UPDATE debts SET manual_paid = paid WHERE manual_paid = 0 AND paid > 0');
    }
  }

  /// يضيف عمودًا إن لم يكن موجودًا — يجعل الترقية آمنة عند إعادة تشغيلها
  Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    final exists = cols.any((c) => c['name'] == column);
    if (exists) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }

  // ---------------------------------------------------------------- الأدوات

  static final _rand = Random.secure();

  /// معرّف فريد قصير ومقروء
  static String newId() {
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final salt = List.generate(6, (_) => _rand.nextInt(36).toRadixString(36)).join();
    return '$now$salt';
  }

  static Map<String, Object?> decodeSpecs(Object? raw) {
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw as String);
      return decoded is Map ? Map<String, Object?>.from(decoded) : {};
    } catch (_) {
      return {};
    }
  }

  static Item itemFromMap(Map<String, Object?> m) => Item(
        id: m['id'] as String,
        visitId: m['visit_id'] as String?,
        creditId: m['credit_id'] as String?,
        serial: (m['serial'] as String?) ?? '',
        typeKey: (m['type_key'] as String?) ?? 'other',
        typeLabel: (m['type_label'] as String?) ?? 'أخرى',
        customName: (m['custom_name'] as String?) ?? '',
        specs: decodeSpecs(m['specs']),
        price: ((m['price'] as num?) ?? 0).toDouble(),
        qty: ((m['qty'] as num?) ?? 1).toInt(),
        kind: MovementKindX.fromCode(m['kind'] as String?),
        notes: (m['notes'] as String?) ?? '',
        sortOrder: ((m['sort_order'] as num?) ?? 0).toInt(),
        createdAt: DateTime.fromMillisecondsSinceEpoch((m['created_at'] as int?) ?? 0),
      );

  static Map<String, Object?> itemToMap(Item i) => {
        ...i.toMapNoSpecs(),
        'specs': jsonEncode(i.specs),
      };

  /// بداية اليوم — تُستخدم لتجميع الزيارات حسب اليوم
  static DateTime dayStart(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime dayEnd(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59, 999);
}

extension ItemMapping on Item {
  Map<String, Object?> toMapNoSpecs() => {
        'id': id,
        'visit_id': visitId,
        'credit_id': creditId,
        'serial': serial,
        'type_key': typeKey,
        'type_label': typeLabel,
        'custom_name': customName,
        'price': price,
        'qty': qty,
        'kind': kind.name,
        'notes': notes,
        'sort_order': sortOrder,
        'created_at': createdAt.millisecondsSinceEpoch,
      };
}
