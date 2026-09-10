import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_database.dart';
import '../db/repository.dart';
import '../models/models.dart';

final repoProvider = Provider<Repository>((ref) => Repository.instance);

/// يزداد بعد كل عملية حفظ/حذف ليُعاد تحميل القوائم
final refreshTickProvider = StateProvider<int>((ref) => 0);

void bumpRefresh(WidgetRef ref) =>
    ref.read(refreshTickProvider.notifier).state++;

void bumpRefreshRef(Ref ref) =>
    ref.read(refreshTickProvider.notifier).state++;

// ------------------------------------------------------------- التاريخ المختار

/// اليوم المعروض في شاشة «زيارات اليوم»
final selectedDayProvider = StateProvider<DateTime>(
  (ref) => AppDatabase.dayStart(DateTime.now()),
);

/// فترة التقرير المخصص
class DateRange {
  final DateTime from;
  final DateTime to;
  const DateRange(this.from, this.to);

  static DateRange today() {
    final n = DateTime.now();
    return DateRange(AppDatabase.dayStart(n), AppDatabase.dayStart(n));
  }

  static DateRange thisWeek() {
    final n = DateTime.now();
    final start = AppDatabase.dayStart(n.subtract(Duration(days: n.weekday - 1)));
    return DateRange(start, AppDatabase.dayStart(n));
  }

  static DateRange thisMonth() {
    final n = DateTime.now();
    return DateRange(DateTime(n.year, n.month, 1), AppDatabase.dayStart(n));
  }

  static DateRange lastMonth() {
    final n = DateTime.now();
    final first = DateTime(n.year, n.month - 1, 1);
    final last = DateTime(n.year, n.month, 0);
    return DateRange(first, last);
  }

  static DateRange monthOf(DateTime d) =>
      DateRange(DateTime(d.year, d.month, 1), DateTime(d.year, d.month + 1, 0));

  DateRange copyWith({DateTime? from, DateTime? to}) =>
      DateRange(from ?? this.from, to ?? this.to);

  bool get isSingleDay =>
      from.year == to.year && from.month == to.month && from.day == to.day;
}

final reportRangeProvider = StateProvider<DateRange>((ref) => DateRange.today());

// ---------------------------------------------------------------- الزيارات

/// زيارات اليوم المحدد
final dayVisitsProvider = FutureProvider.autoDispose<List<VisitFull>>((ref) async {
  ref.watch(refreshTickProvider);
  final day = ref.watch(selectedDayProvider);
  return ref.read(repoProvider).visitsFull(from: day, to: day);
});

/// كل الزيارات مع بحث اختياري
final visitSearchProvider = StateProvider<String>((ref) => '');

final allVisitsProvider = FutureProvider.autoDispose<List<VisitFull>>((ref) async {
  ref.watch(refreshTickProvider);
  final q = ref.watch(visitSearchProvider);
  return ref.read(repoProvider).visitsFull(search: q.isEmpty ? null : q);
});

final visitFullProvider =
    FutureProvider.autoDispose.family<VisitFull?, String>((ref, id) async {
  ref.watch(refreshTickProvider);
  return ref.read(repoProvider).visitFull(id);
});

// ------------------------------------------------------------- السحب الآجل

final creditSearchProvider = StateProvider<String>((ref) => '');

/// فلتر: الكل / غير المسدد / المسدد
enum CreditFilter { all, unsettled, settled }

final creditFilterProvider = StateProvider<CreditFilter>((ref) => CreditFilter.all);

final creditsProvider = FutureProvider.autoDispose<List<CreditFull>>((ref) async {
  ref.watch(refreshTickProvider);
  final q = ref.watch(creditSearchProvider);
  final f = ref.watch(creditFilterProvider);
  return ref.read(repoProvider).creditsFull(
        search: q.isEmpty ? null : q,
        settled: switch (f) {
          CreditFilter.all => null,
          CreditFilter.unsettled => false,
          CreditFilter.settled => true,
        },
      );
});

final creditFullProvider =
    FutureProvider.autoDispose.family<CreditFull?, String>((ref, id) async {
  ref.watch(refreshTickProvider);
  return ref.read(repoProvider).creditFull(id);
});

// ----------------------------------------------------------------- العملاء

final customerSearchProvider = StateProvider<String>((ref) => '');

final customersProvider = FutureProvider.autoDispose<List<Customer>>((ref) async {
  ref.watch(refreshTickProvider);
  final q = ref.watch(customerSearchProvider);
  return ref.read(repoProvider).customers(search: q.isEmpty ? null : q);
});

// ------------------------------------------------- الحركات المالية

final cashSearchProvider = StateProvider<String>((ref) => '');

/// فلتر اتجاه الحركة: الكل / وارد / صادر
final cashDirectionFilterProvider = StateProvider<CashDirection?>((ref) => null);

/// حركات اليوم المحدد
final dayCashProvider = FutureProvider.autoDispose<List<CashEntry>>((ref) async {
  ref.watch(refreshTickProvider);
  final day = ref.watch(selectedDayProvider);
  return ref.read(repoProvider).cashEntries(from: day, to: day);
});

/// كل الحركات مع بحث وفلتر
final cashEntriesProvider = FutureProvider.autoDispose<List<CashEntry>>((ref) async {
  ref.watch(refreshTickProvider);
  final q = ref.watch(cashSearchProvider);
  final dir = ref.watch(cashDirectionFilterProvider);
  return ref.read(repoProvider).cashEntries(
        search: q.isEmpty ? null : q,
        direction: dir,
      );
});

/// السحوبات الآجلة التي عليها رصيد — لربط سداد الدين
final unsettledCreditsProvider =
    FutureProvider.autoDispose<List<CreditFull>>((ref) async {
  ref.watch(refreshTickProvider);
  return ref.read(repoProvider).unsettledCredits();
});

// -------------------------------------------------- ملاحظات اليوم

/// ملاحظة اليوم المحدد
final dayNoteProvider = FutureProvider.autoDispose<String>((ref) async {
  ref.watch(refreshTickProvider);
  final day = ref.watch(selectedDayProvider);
  return ref.read(repoProvider).dayNote(day);
});

// ---------------------------------------------------------------- التقارير

final periodSummaryProvider =
    FutureProvider.autoDispose<PeriodSummary>((ref) async {
  ref.watch(refreshTickProvider);
  final r = ref.watch(reportRangeProvider);
  return ref.read(repoProvider).summary(from: r.from, to: r.to);
});

/// ملخص اليوم لعرضه في لوحة المعلومات
final todaySummaryProvider = FutureProvider.autoDispose<PeriodSummary>((ref) async {
  ref.watch(refreshTickProvider);
  final n = AppDatabase.dayStart(DateTime.now());
  return ref.read(repoProvider).summary(from: n, to: n);
});

final outstandingProvider = FutureProvider.autoDispose<double>((ref) async {
  ref.watch(refreshTickProvider);
  return ref.read(repoProvider).totalOutstanding();
});

// -------------------------------------------------------------- الإعدادات

class ShopSettings {
  final String shopName;
  final String shopPhone;
  final String shopAddress;
  final String managerName;
  final String technicianName;

  const ShopSettings({
    this.shopName = '',
    this.shopPhone = '',
    this.shopAddress = '',
    this.managerName = '',
    this.technicianName = '',
  });

  factory ShopSettings.fromMap(Map<String, String> m) => ShopSettings(
        shopName: m['shop_name'] ?? '',
        shopPhone: m['shop_phone'] ?? '',
        shopAddress: m['shop_address'] ?? '',
        managerName: m['manager_name'] ?? '',
        technicianName: m['technician_name'] ?? '',
      );

  Map<String, String> toMap() => {
        'shop_name': shopName,
        'shop_phone': shopPhone,
        'shop_address': shopAddress,
        'manager_name': managerName,
        'technician_name': technicianName,
      };

  ShopSettings copyWith({
    String? shopName,
    String? shopPhone,
    String? shopAddress,
    String? managerName,
    String? technicianName,
  }) =>
      ShopSettings(
        shopName: shopName ?? this.shopName,
        shopPhone: shopPhone ?? this.shopPhone,
        shopAddress: shopAddress ?? this.shopAddress,
        managerName: managerName ?? this.managerName,
        technicianName: technicianName ?? this.technicianName,
      );
}

final settingsProvider = FutureProvider<ShopSettings>((ref) async {
  ref.watch(refreshTickProvider);
  final all = await ref.read(repoProvider).allSettings();
  return ShopSettings.fromMap(all);
});

/// تتبّع سيريال
final serialTraceProvider =
    FutureProvider.autoDispose.family<List<SerialTrace>, String>((ref, serial) async {
  ref.watch(refreshTickProvider);
  if (serial.trim().isEmpty) return [];
  return ref.read(repoProvider).traceSerial(serial);
});
