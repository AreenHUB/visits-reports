import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' show ConflictAlgorithm;

import '../db/app_database.dart';
import '../db/secure_key.dart';
import '../utils/formatting.dart';

/// النسخ الاحتياطي والاستعادة.
///
/// النسخة ملف JSON يحتوي كل الجداول، ويحمل مفتاح التشفير الخاص بالقاعدة
/// حتى تُستعاد على أي جهاز. لأن الملف يحمل المفتاح، احفظه في مكان موثوق.
class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  static const _formatVersion = 1;

  /// ينشئ ملف نسخة احتياطية ويعيد مساره
  Future<File> createBackup({bool includeKey = true}) async {
    final db = await AppDatabase.instance.database;

    Future<List<Map<String, Object?>>> dump(String table) async =>
        (await db.query(table)).map((r) => Map<String, Object?>.from(r)).toList();

    final data = {
      'format_version': _formatVersion,
      'app': 'alaqsa_visits',
      'created_at': DateTime.now().toIso8601String(),
      if (includeKey) 'db_key': await SecureKey.getOrCreate(),
      'tables': {
        'customers': await dump('customers'),
        'visits': await dump('visits'),
        'credits': await dump('credits'),
        'items': await dump('items'),
        'payments': await dump('payments'),
        'serial_memory': await dump('serial_memory'),
        'settings': await dump('settings'),
        'cash_entries': await dump('cash_entries'),
        'day_notes': await dump('day_notes'),
      },
    };

    final dir = await getTemporaryDirectory();
    final out = Directory(p.join(dir.path, 'backups'));
    if (!await out.exists()) await out.create(recursive: true);

    final file = File(p.join(out.path, 'نسخة_احتياطية_${Fmt.fileStamp(DateTime.now())}.json'));
    await file.writeAsString(jsonEncode(data), flush: true);
    return file;
  }

  /// يستعيد من ملف يختاره المستخدم. يعيد ملخص ما تمت استعادته.
  Future<RestoreResult> restoreFromPicker({bool replaceExisting = true}) async {
    final picked = await FilePicker.pickFile(
      dialogTitle: 'اختر ملف النسخة الاحتياطية',
    );
    if (picked == null) return const RestoreResult(cancelled: true);

    final path = picked.path;
    if (path == null) return const RestoreResult(error: 'تعذّر قراءة الملف');
    return restoreFromFile(File(path), replaceExisting: replaceExisting);
  }

  Future<RestoreResult> restoreFromFile(File file, {bool replaceExisting = true}) async {
    Map<String, Object?> data;
    try {
      data = jsonDecode(await file.readAsString()) as Map<String, Object?>;
    } catch (_) {
      return const RestoreResult(error: 'الملف غير صالح أو تالف');
    }

    if (data['app'] != 'alaqsa_visits') {
      return const RestoreResult(error: 'هذا الملف ليس نسخة احتياطية لهذا التطبيق');
    }

    final tables = data['tables'];
    if (tables is! Map) return const RestoreResult(error: 'الملف لا يحتوي بيانات');

    final db = await AppDatabase.instance.database;
    final counts = <String, int>{};

    // الترتيب مهم: الجداول المرجعية أولًا احترامًا للمفاتيح الأجنبية.
    // النسخ القديمة لا تحتوي الجدولين الأخيرين، وهذا مقبول — تُتخطّى ببساطة.
    const order = [
      'customers',
      'visits',
      'credits',
      'items',
      'payments',
      'serial_memory',
      'settings',
      'cash_entries',
      'day_notes',
    ];

    try {
      await db.transaction((txn) async {
        if (replaceExisting) {
          // نحذف بالترتيب العكسي احترامًا للمفاتيح الأجنبية
          for (final t in order.reversed) {
            await txn.delete(t);
          }
        }
        for (final t in order) {
          final rows = tables[t];
          if (rows is! List) continue;
          var n = 0;
          for (final row in rows) {
            if (row is! Map) continue;
            await txn.insert(
              t,
              Map<String, Object?>.from(row),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            n++;
          }
          counts[t] = n;
        }
      });
    } catch (e) {
      return RestoreResult(error: 'فشلت الاستعادة: $e');
    }

    return RestoreResult(counts: counts);
  }

  /// حفظ نسخة في مجلد يختاره المستخدم (التنزيلات مثلًا)
  Future<String?> saveBackupTo(File backup) async {
    final dir = await FilePicker.getDirectoryPath(
      dialogTitle: 'اختر مكان حفظ النسخة',
    );
    if (dir == null) return null;
    final target = File(p.join(dir, p.basename(backup.path)));
    await target.writeAsBytes(await backup.readAsBytes(), flush: true);
    return target.path;
  }

  /// إحصاءات سريعة تُعرض في شاشة الإعدادات
  Future<BackupStats> stats() async {
    final db = await AppDatabase.instance.database;
    Future<int> count(String t) async =>
        (await db.rawQuery('SELECT COUNT(*) AS c FROM $t')).first['c'] as int? ?? 0;

    final dbFile = File(await AppDatabase.instance.databasePath);
    return BackupStats(
      customers: await count('customers'),
      visits: await count('visits'),
      credits: await count('credits'),
      items: await count('items'),
      payments: await count('payments'),
      serials: await count('serial_memory'),
      cashEntries: await count('cash_entries'),
      dbSizeBytes: await dbFile.exists() ? await dbFile.length() : 0,
    );
  }

  /// حذف كل البيانات — يُستخدم بعد تأكيد صريح من المستخدم
  Future<void> wipeAll() async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      for (final t in [
        'day_notes',
        'cash_entries',
        'payments',
        'items',
        'credits',
        'visits',
        'customers',
        'serial_memory',
      ]) {
        await txn.delete(t);
      }
    });
  }
}

class RestoreResult {
  final Map<String, int> counts;
  final String? error;
  final bool cancelled;

  const RestoreResult({this.counts = const {}, this.error, this.cancelled = false});

  bool get ok => error == null && !cancelled;

  int get total => counts.values.fold(0, (a, b) => a + b);

  String get summary {
    if (cancelled) return 'أُلغيت العملية';
    if (error != null) return error!;
    final parts = [
      '${counts['visits'] ?? 0} زيارة',
      '${counts['credits'] ?? 0} سحب آجل',
      '${counts['items'] ?? 0} قطعة',
      if ((counts['cash_entries'] ?? 0) > 0) '${counts['cash_entries']} حركة مالية',
    ];
    return 'تمت استعادة ${parts.join(' و')}';
  }
}

class BackupStats {
  final int customers;
  final int visits;
  final int credits;
  final int items;
  final int payments;
  final int serials;
  final int cashEntries;
  final int dbSizeBytes;

  const BackupStats({
    this.customers = 0,
    this.visits = 0,
    this.credits = 0,
    this.items = 0,
    this.payments = 0,
    this.serials = 0,
    this.cashEntries = 0,
    this.dbSizeBytes = 0,
  });

  String get sizeLabel {
    if (dbSizeBytes < 1024) return '$dbSizeBytes بايت';
    if (dbSizeBytes < 1024 * 1024) return '${(dbSizeBytes / 1024).toStringAsFixed(1)} ك.ب';
    return '${(dbSizeBytes / (1024 * 1024)).toStringAsFixed(1)} م.ب';
  }
}
