import 'package:intl/intl.dart';

/// تنسيق الأرقام والتواريخ والعملة (درهم إماراتي)
class Fmt {
  Fmt._();

  static const currencySymbol = 'د.إ';
  static const currencyCode = 'AED';

  // نثبّت اللغة على en_US في كل المنسّقات حتى تظهر الأرقام غربية (1234)
  // ولا تعتمد على اللغة الافتراضية التي قد لا تكون مهيّأة بعد.
  static const _numLocale = 'en_US';

  static final _money = NumberFormat('#,##0.00', _numLocale);
  static final _moneyShort = NumberFormat('#,##0.##', _numLocale);
  static final _int = NumberFormat('#,##0', _numLocale);

  /// مبلغ مع رمز العملة: «1,250.00 د.إ»
  static String money(num v) => '${_money.format(v)} $currencySymbol';

  /// مبلغ بدون أصفار زائدة: «1,250 د.إ»
  static String moneyShort(num v) => '${_moneyShort.format(v)} $currencySymbol';

  /// رقم فقط بدون رمز — للاستخدام داخل جداول إكسل
  static String moneyRaw(num v) => _money.format(v);

  static String count(num v) => _int.format(v);

  // ------------------------------------------------------------ التواريخ

  static final _date = DateFormat('yyyy/MM/dd', _numLocale);
  static final _dateTime = DateFormat('yyyy/MM/dd  hh:mm a', _numLocale);
  static final _time = DateFormat('hh:mm a', _numLocale);
  static final _monthYear = DateFormat('MM/yyyy', _numLocale);
  static final _fileStamp = DateFormat('yyyy-MM-dd_HHmm', _numLocale);

  static String date(DateTime d) => _date.format(d);
  static String dateTime(DateTime d) => _dateTime.format(d);
  static String time(DateTime d) => _time.format(d);
  static String monthYear(DateTime d) => _monthYear.format(d);
  static String fileStamp(DateTime d) => _fileStamp.format(d);

  static const _weekdaysAr = [
    'الإثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
    'السبت',
    'الأحد',
  ];

  static const _monthsAr = [
    'يناير',
    'فبراير',
    'مارس',
    'أبريل',
    'مايو',
    'يونيو',
    'يوليو',
    'أغسطس',
    'سبتمبر',
    'أكتوبر',
    'نوفمبر',
    'ديسمبر',
  ];

  static String weekday(DateTime d) => _weekdaysAr[d.weekday - 1];
  static String month(DateTime d) => _monthsAr[d.month - 1];

  /// «الأحد 2026/09/06»
  static String dateWithDay(DateTime d) => '${weekday(d)} ${date(d)}';

  /// «سبتمبر 2026»
  static String monthName(DateTime d) => '${month(d)} ${d.year}';

  /// وصف فترة بشكل مقروء
  static String range(DateTime from, DateTime to) {
    final sameDay = from.year == to.year && from.month == to.month && from.day == to.day;
    if (sameDay) return dateWithDay(from);
    return 'من ${date(from)} إلى ${date(to)}';
  }

  /// «اليوم» / «أمس» / التاريخ
  static String relativeDay(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(d.year, d.month, d.day);
    final diff = today.difference(target).inDays;
    if (diff == 0) return 'اليوم';
    if (diff == 1) return 'أمس';
    if (diff == -1) return 'غدًا';
    return dateWithDay(d);
  }
}
