import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_database.dart';
import '../db/repository.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../services/pdf_service.dart';
import '../services/share_service.dart';
import '../utils/formatting.dart';
import '../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/day_note_editor.dart';
import 'cash_form_screen.dart';
import 'cash_screen.dart';
import 'visit_detail_screen.dart';
import 'visit_form_screen.dart';

/// الشاشة الرئيسية: كل ما جرى في اليوم المحدد — زيارات وحركات مالية وملاحظات
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(selectedDayProvider);
    final visitsAsync = ref.watch(dayVisitsProvider);
    final cashAsync = ref.watch(dayCashProvider);
    final noteAsync = ref.watch(dayNoteProvider);
    final isToday = AppDatabase.dayStart(DateTime.now()) == AppDatabase.dayStart(day);

    return Scaffold(
      appBar: AppBar(
        title: Column(children: [
          const Text('يوميّة العمل'),
          Text(
            Fmt.relativeDay(day),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ]),
        leading: IconButton(
          tooltip: 'اليوم السابق',
          icon: const Icon(Icons.chevron_right_rounded),
          onPressed: () => ref.read(selectedDayProvider.notifier).state =
              day.subtract(const Duration(days: 1)),
        ),
        actions: [
          IconButton(
            tooltip: 'اليوم التالي',
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: isToday
                ? null
                : () => ref.read(selectedDayProvider.notifier).state =
                    day.add(const Duration(days: 1)),
          ),
          IconButton(
            tooltip: 'اختيار تاريخ',
            icon: const Icon(Icons.calendar_month_rounded),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: day,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
                locale: const Locale('ar'),
              );
              if (picked != null) {
                ref.read(selectedDayProvider.notifier).state =
                    AppDatabase.dayStart(picked);
              }
            },
          ),
        ],
      ),

      body: RefreshIndicator(
        onRefresh: () async => bumpRefresh(ref),
        child: visitsAsync.when(
          loading: () => const LoadingView(),
          error: (e, _) => ErrorView(e, onRetry: () => bumpRefresh(ref)),
          data: (visits) => _DayContent(
            visits: visits,
            cash: cashAsync.valueOrNull ?? const [],
            dayNote: noteAsync.valueOrNull ?? '',
            day: day,
          ),
        ),
      ),

      floatingActionButton: _DayFab(day: day),
    );
  }
}

/// أزرار الإضافة: زيارة، وارد، صادر
class _DayFab extends StatelessWidget {
  final DateTime day;
  const _DayFab({required this.day});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          FloatingActionButton.small(
            heroTag: 'home_expense',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CashFormScreen(
                  initialDate: day,
                  initialDirection: CashDirection.expense,
                ),
              ),
            ),
            backgroundColor: AppTheme.danger,
            foregroundColor: Colors.white,
            tooltip: 'تسجيل صادر',
            child: const Icon(Icons.north_east_rounded),
          ),
          const SizedBox(width: 10),
          FloatingActionButton.small(
            heroTag: 'home_income',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CashFormScreen(
                  initialDate: day,
                  initialDirection: CashDirection.income,
                ),
              ),
            ),
            backgroundColor: AppTheme.success,
            foregroundColor: Colors.white,
            tooltip: 'تسجيل وارد',
            child: const Icon(Icons.south_west_rounded),
          ),
        ]),
        const SizedBox(height: 10),
        FloatingActionButton.extended(
          heroTag: 'home_visit',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => VisitFormScreen(initialDate: day)),
          ),
          icon: const Icon(Icons.add_rounded),
          label: const Text('زيارة جديدة'),
        ),
      ],
    );
  }
}

class _DayContent extends ConsumerWidget {
  final List<VisitFull> visits;
  final List<CashEntry> cash;
  final String dayNote;
  final DateTime day;

  const _DayContent({
    required this.visits,
    required this.cash,
    required this.dayNote,
    required this.day,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isEmpty = visits.isEmpty && cash.isEmpty;

    if (isEmpty) {
      return ListView(
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          const SizedBox(height: 50),
          EmptyState(
            icon: Icons.event_busy_rounded,
            title: 'لا توجد حركة في ${Fmt.relativeDay(day)}',
            subtitle: 'سجّل زيارة، أو حركة مالية دخلت أو خرجت من المحل',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: _DayNoteCard(day: day, note: dayNote),
          ),
        ],
      );
    }

    var visitTotals = const Totals();
    for (final v in visits) {
      visitTotals = visitTotals + v.totals;
    }
    final cashTotals = CashTotals.from(cash);
    final done = visits.where((v) => v.visit.status == VisitStatus.done).length;
    final notDone = visits.where((v) => v.visit.status == VisitStatus.notDone).length;

    // كل ما دخل الصندوق اليوم: محصّل الزيارات + الوارد المستقل
    final totalIn = visitTotals.paid + cashTotals.income;
    final netCash = totalIn - cashTotals.expense;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 130),
      children: [
        // ملخص الحركة المالية لليوم
        Row(children: [
          Expanded(
            child: StatCard(
              label: 'دخل اليوم',
              value: Fmt.moneyShort(totalIn),
              icon: Icons.south_west_rounded,
              color: AppTheme.success,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: StatCard(
              label: 'خرج اليوم',
              value: Fmt.moneyShort(cashTotals.expense),
              icon: Icons.north_east_rounded,
              color: AppTheme.danger,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: StatCard(
              label: 'الصافي',
              value: Fmt.moneyShort(netCash),
              icon: Icons.account_balance_wallet_rounded,
              color: netCash >= 0 ? AppTheme.info : AppTheme.warning,
            ),
          ),
        ]),

        if (visits.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: StatCard(
                label: 'الزيارات',
                value: '${visits.length}',
                icon: Icons.event_available_rounded,
                color: AppTheme.seed,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatCard(
                label: 'تمت',
                value: '$done',
                icon: Icons.check_circle_rounded,
                color: AppTheme.success,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatCard(
                label: notDone > 0 ? 'لم تتم' : 'المتبقي',
                value: notDone > 0 ? '$notDone' : Fmt.moneyShort(visitTotals.remaining),
                icon: notDone > 0 ? Icons.cancel_rounded : Icons.pending_rounded,
                color: notDone > 0 ? AppTheme.danger : AppTheme.warning,
              ),
            ),
          ]),
        ],

        const SizedBox(height: 12),

        // ملاحظات اليوم
        _DayNoteCard(day: day, note: dayNote),

        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => _shareDayReport(context, ref, day),
          icon: const Icon(Icons.picture_as_pdf_rounded, size: 19),
          label: const Text('تقرير اليوم PDF'),
        ),

        // الحركات المالية
        if (cash.isNotEmpty) ...[
          SectionHeader(
            'الحركات المالية (${cash.length})',
            icon: Icons.account_balance_wallet_rounded,
          ),
          ...cash.map((e) => CashTile(entry: e, showDate: false)),
        ],

        // الزيارات
        if (visits.isNotEmpty) ...[
          SectionHeader('الزيارات (${visits.length})', icon: Icons.event_note_rounded),
          ...visits.map((vf) => VisitCard(vf: vf)),
        ],
      ],
    );
  }

  Future<void> _shareDayReport(
    BuildContext context,
    WidgetRef ref,
    DateTime day,
  ) async {
    final origin = ShareService.originFrom(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final summary = await Repository.instance.summary(from: day, to: day);
      final settings = await ref.read(settingsProvider.future);
      final bytes =
          await PdfService.instance.buildReport(summary: summary, settings: settings);
      final file = await PdfService.instance
          .saveToFile(bytes, PdfService.fileNameFor(summary));

      if (!context.mounted) return;
      Navigator.pop(context);

      await ShareService.instance.shareFile(
        file,
        text: ShareService.reportMessage(summary, settings),
        subject: 'تقرير الزيارات اليومي - ${Fmt.date(day)}',
        origin: origin,
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      showSnack(context, 'تعذّر إنشاء التقرير: $e', error: true);
    }
  }
}

/// بطاقة ملاحظات اليوم — تُحرَّر بضغطة وتظهر في التقرير
class _DayNoteCard extends ConsumerWidget {
  final DateTime day;
  final String note;

  const _DayNoteCard({required this.day, required this.note});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final hasNote = note.trim().isNotEmpty;

    return InkWell(
      onTap: () async {
        final result = await DayNoteSheet.show(context, day: day, initial: note);
        if (result == null || !context.mounted) return;
        await Repository.instance.setDayNote(day, result);
        if (!context.mounted) return;
        bumpRefresh(ref);
        showSnack(context, result.isEmpty ? 'تم مسح الملاحظات' : 'تم حفظ ملاحظات اليوم');
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: hasNote
              ? AppTheme.accent.withValues(alpha: 0.07)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasNote
                ? AppTheme.accent.withValues(alpha: 0.3)
                : scheme.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(
            hasNote ? Icons.sticky_note_2_rounded : Icons.edit_note_rounded,
            size: 20,
            color: hasNote ? AppTheme.accent : scheme.outline,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                'ملاحظات عن هذا اليوم',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: hasNote ? AppTheme.accent : scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                hasNote ? note : 'اضغط لإضافة ملاحظات تُرسل مع التقرير للمدير',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: hasNote ? scheme.onSurface : scheme.outline,
                ),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
          Icon(Icons.edit_rounded, size: 16, color: scheme.outline),
        ]),
      ),
    );
  }
}

/// بطاقة زيارة في القوائم
class VisitCard extends StatelessWidget {
  final VisitFull vf;
  final bool showDate;

  const VisitCard({super.key, required this.vf, this.showDate = false});

  @override
  Widget build(BuildContext context) {
    final v = vf.visit;
    final t = vf.totals;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => VisitDetailScreen(visitId: v.id)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 12, 13, 11),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(v.customerName,
                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (showDate) Fmt.date(v.date) else Fmt.time(v.date),
                      if (v.customerPhone.isNotEmpty) v.customerPhone,
                      if (v.customerAddress.isNotEmpty) v.customerAddress,
                    ].join('  •  '),
                    style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ]),
              ),
              StatusBadge(v.status, small: true),
            ]),

            if (v.purpose.isNotEmpty) ...[
              const SizedBox(height: 7),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.flag_outlined, size: 14, color: scheme.outline),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(v.purpose,
                      style: const TextStyle(fontSize: 12.5),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ),
              ]),
            ],

            if (vf.items.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 5, runSpacing: 5, children: [
                _Pill(
                  icon: Icons.inventory_2_rounded,
                  text: '${vf.outItems.fold(0, (a, i) => a + i.qty)} صادر',
                  color: scheme.primary,
                ),
                if (vf.returnedItems.isNotEmpty)
                  _Pill(
                    icon: Icons.assignment_return_rounded,
                    text: '${vf.returnedItems.fold(0, (a, i) => a + i.qty)} راجع',
                    color: AppTheme.warning,
                  ),
                ...vf.items.take(2).map((i) => _Pill(text: i.description, color: scheme.outline)),
                if (vf.items.length > 2)
                  _Pill(text: '+${vf.items.length - 2}', color: scheme.outline),
              ]),
            ],

            const SizedBox(height: 10),
            TotalsRow(t, compact: true),
          ]),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData? icon;
  final String text;
  final Color color;

  const _Pill({this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(
              text,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
      );
}
