import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// إدارة مفتاح تشفير قاعدة البيانات.
///
/// يُولَّد مفتاح عشوائي قوي (256 بت) مرة واحدة عند أول تشغيل، ويُحفَظ في
/// مخزن أندرويد الآمن (Android Keystore / EncryptedSharedPreferences)،
/// فلا يخرج من الجهاز ولا يظهر في أي ملف نصي.
class SecureKey {
  SecureKey._();

  static const _keyName = 'db_encryption_key_v1';

  // resetOnError: false مهم جدًا — لو مُسح المفتاح تلقائيًا فلن تُقرأ القاعدة أبدًا
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false),
  );

  static String? _cached;

  /// يعيد المفتاح الحالي، أو ينشئ واحدًا جديدًا إذا كان أول تشغيل
  static Future<String> getOrCreate() async {
    if (_cached != null) return _cached!;

    String? key;
    try {
      key = await _storage.read(key: _keyName);
    } catch (_) {
      // قد يفشل القراءة إذا تلف المخزن، عندها نولّد مفتاحًا جديدًا
      key = null;
    }

    if (key == null || key.isEmpty) {
      key = _generateKey();
      await _storage.write(key: _keyName, value: key);
    }

    _cached = key;
    return key;
  }

  /// هل يوجد مفتاح محفوظ مسبقًا؟ مفيد للتحقق قبل الاستعادة
  static Future<bool> exists() async {
    try {
      final k = await _storage.read(key: _keyName);
      return k != null && k.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// يُستخدم عند استعادة نسخة احتياطية مشفّرة بمفتاح آخر
  static Future<void> replace(String key) async {
    await _storage.write(key: _keyName, value: key);
    _cached = key;
  }

  static String _generateKey() {
    final rand = Random.secure();
    final bytes = List<int>.generate(32, (_) => rand.nextInt(256));
    return base64Url.encode(bytes);
  }
}
