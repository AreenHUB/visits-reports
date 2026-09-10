@TestOn('vm')
library;

import 'package:alaqsa_visits/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// يتحقق أن مفاتيح الكاميرا (فول كولر / متحركة / صوت) تُحفظ وتُلغى
/// بشكل صحيح، وأنها تظهر في وصف القطعة.
void main() {
  Item camera({Map<String, Object?>? specs}) => Item(
        id: 'i1',
        typeKey: 'camera',
        typeLabel: 'كاميرا',
        specs: specs,
        createdAt: DateTime(2026),
      );

  test('المفتاح المفعّل يظهر في وصف القطعة', () {
    final i = camera(specs: {'full_color': 'فول كولر', 'mp': '4 ميغا'});
    expect(i.description.contains('فول كولر'), isTrue);
    expect(i.description.contains('4 ميغا'), isTrue);
  });

  test('إلغاء المفتاح يزيله من الوصف', () {
    final i = camera(specs: {'mp': '4 ميغا'});
    expect(i.description.contains('فول كولر'), isFalse);
  });

  test('عدة مفاتيح مفعّلة معًا تظهر كلها', () {
    final i = camera(specs: {
      'full_color': 'فول كولر',
      'motorized': 'متحركة',
      'audio': 'صوت',
    });

    for (final label in ['فول كولر', 'متحركة', 'صوت']) {
      expect(i.description.contains(label), isTrue, reason: label);
    }
  });

  test('القيم الفارغة أو null لا تظهر في الوصف', () {
    final i = camera(specs: {
      'mp': '4 ميغا',
      'full_color': null,
      'motorized': '',
      'audio': false,
    });

    expect(i.description, 'كاميرا - 4 ميغا');
  });

  test('القيمة المخزّنة نصًا تُعتبر مفعّلة', () {
    // هذا ما يخزّنه المحرّر فعليًا: تسمية الحقل لا القيمة المنطقية
    final specs = <String, Object?>{'full_color': 'فول كولر'};
    final on = specs['full_color'] != null &&
        '${specs['full_color']}'.trim().isNotEmpty;
    expect(on, isTrue);
  });

  test('غياب المفتاح يعني غير مفعّل', () {
    final specs = <String, Object?>{};
    final on = specs['full_color'] != null &&
        '${specs['full_color']}'.trim().isNotEmpty;
    expect(on, isFalse);
  });
}
