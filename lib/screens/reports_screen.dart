import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../db/repository.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../services/excel_service.dart';
import '../services/pdf_service.dart';
import '../services/share_service.dart';
import '../utils/formatting.dart';
import '../utils/theme.dart';
import '../widgets/common.dart';
import 'cash_screen.dart';
import 'home_screen.dart';

/// شاشة التقارير: اختيار فترة ثم تصدير PDF أو إكسل أو مشاركة
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(reportRangeProvider);
    final summaryAsync = ref.watch(periodSummaryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('التقارير')),
      body: Column(children: [
        _RangeSelector(range: range),
        const Divider(height: 1),
        Expanded(
          child: summaryAsync.when(
            loading: () => const LoadingView(message: 'جارٍ حساب التقرير...'),
            error: (e, _) => ErrorView(e, onRetry: () => bumpRefresh(ref)),
            data: (summary) => _ReportBody(summary: summary),
          ),
        ),
      ]),
    );
  }
}

// -------------------------------------------------------------- اختيار الفترة

class _RangeSelector extends ConsumerWidget {
  final DateRange range;
  const _RangeSelector({required this.range});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    void setRange(DateRange r) => ref.read(reportRangeProvider.notifier).state = r;

    return Container(
      color: scheme.surface,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(children: [
        // اختصارات سريعة
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _quickChip(context, 'اليوم', () => setRange(DateRange.today()),
                  _isSame(range, DateRange.today())),
              _quickChip(context, 'هذا الأسبوع', () => setRange(DateRange.thisWeek()),
                  _isSame(range, DateRange.thisWeek())),
              _quickChip(context, 'هذا الشهر', () => setRange(DateRange.thisMonth()),
                  _isSame(range, DateRange.thisMonth())),
              _quickChip(context, 'الشهر الماضي', () => setRange(DateRange.lastMonth()),
                  _isSame(range, DateRange.lastMonth())),
              _quickChip(context, 'أمس', () {
                final y = DateTime.now().subtract(const Duration(days: 1));
                setRange(DateRange(DateTime(y.year, y.month, y.day),
                    DateTime(y.year, y.month, y.day)));
              }, false),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // من - إلى
        Row(children: [
          Expanded(
            child: _DateBox(
              label: 'من',
              date: range.from,
              onPick: (d) => setRange(range.copyWith(
                from: d,
                to: d.isAfter(range.to) ? d : range.to,
              )),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: _DateBox(
              label: 'إلى',
              date: range.to,
              onPick: (d) => setRange(range.copyWith(
                to: d,
                from: d.isBefore(range.from) ? d : range.from,
              )),
            ),
          ),
        ]),
      ]),
    );
  }

  static bool _isSame(DateRange a, DateRange b) =>
      a.from.year == b.from.year &&
      a.from.month == b.from.month &&
      a.from.day == b.from.day &&
      a.to.year == b.to.year &&
      a.to.month == b.to.month &&
      a.to.day == b.to.day;

  Widget _quickChip(
    BuildContext context,
    String label,
    VoidCallback onTap,
    bool selected,
  ) =>
      Padding(
        padding: const EdgeInsetsDirectional.only(end: 6),
        child: ChoiceChip(
          label: Text(label, style: const TextStyle(fontSize: 12.5)),
          selected: selected,
          onSelected: (_) => onTap(),
          visualDensity: VisualDensity.compact,
        ),
      );
}

class _DateBox extends StatelessWidget {
  final String label;
  final DateTime date;
  final ValueChanged<DateTime> onPick;

  const _DateBox({required this.label, required this.date, required this.onPick});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: date,
            firstDate: DateTime(2020),
            lastDate: DateTime(2100),
            locale: const Locale('ar'),
          );
          if (picked != null) onPick(picked);
        },
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            prefixIcon: const Icon(Icons.calendar_today_rounded, size: 17),
          ),
          child: Text(Fmt.date(date), style: const TextStyle(fontSize: 13.5)),
        ),
      );
}

// ------------------------------------------------------------- محتوى التقرير

class _ReportBody extends ConsumerStatefulWidget {
  final PeriodSummary summary;
  const _ReportBody({required this.summary});

  @override
  ConsumerState<_ReportBody> createState() => _ReportBodyState();
}

class _ReportBodyState extends ConsumerState<_ReportBody> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showSnack(context, 'حدث خطأ: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<File> _buildPdfFile() async {
    final settings = await ref.read(settingsProvider.future);
    final options = await ref.read(reportOptionsProvider.future);
    final bytes = await PdfService.instance.buildReport(
      summary: widget.summary,
      settings: settings,
      options: options,
    );
    return PdfService.instance.saveToFile(bytes, PdfService.fileNameFor(widget.summary));
  }

  Future<void> _sharePdf() => _run(() async {
        final origin = ShareService.originFrom(context);
        final settings = await ref.read(settingsProvider.future);
        final file = await _buildPdfFile();
        await ShareService.instance.shareFile(
          file,
          text: ShareService.reportMessage(widget.summary, settings),
          subject: 'تقرير الزيارات — ${Fmt.range(widget.summary.from, widget.summary.to)}',
          origin: origin,
        );
      });

  Future<void> _previewPdf() => _run(() async {
        final settings = await ref.read(settingsProvider.future);
        final options = await ref.read(reportOptionsProvider.future);
        final bytes = await PdfService.instance.buildReport(
          summary: widget.summary,
          settings: settings,
          options: options,
        );
        if (!mounted) return;

        try {
          await Printing.layoutPdf(
            onLayout: (_) async => bytes,
            // اسم لاتيني: إطار الطباعة في أندرويد لا يقبل كل الأحرف
            name: PdfService.printJobName(widget.summary),
            // الملف مُولَّد مسبقًا بمقاس A4، فلا داعي لإعادة تخطيطه
            // لكل مقاس ورق — وهذا ما كان يُسقط المعاينة في التقارير الطويلة.
            dynamicLayout: false,
          );
        } catch (e) {
          // إن تعذّرت المعاينة (لا خدمة طباعة على الجهاز مثلًا) نحفظ الملف
          // ونعرضه للمشاركة بدل أن يتوقف التطبيق.
          if (!mounted) return;
          final file = await PdfService.instance
              .saveToFile(bytes, PdfService.fileNameFor(widget.summary));
          if (!mounted) return;
          showSnack(context, 'تعذّرت المعاينة على هذا الجهاز، تم تجهيز الملف للمشاركة');
          await ShareService.instance.shareFile(
            file,
            subject: 'تقرير الزيارات',
            origin: ShareService.originFrom(context),
          );
        }
      });

  Future<void> _shareExcel() => _run(() async {
        final origin = ShareService.originFrom(context);
        final file = await ExcelService.instance.export(widget.summary);
        await ShareService.instance.shareFile(
          file,
          text: 'تقرير الزيارات — ${Fmt.range(widget.summary.from, widget.summary.to)}',
          subject: 'تقرير إكسل',
          origin: origin,
        );
      });

  @override
  Widget build(BuildContext context) {
    final s = widget.summary;
    final g = s.grandTotals;

    return Stack(children: [
      ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 30),
        children: [
          // أزرار التصدير
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : _sharePdf,
                icon: const Icon(Icons.share_rounded, size: 19),
                label: const Text('مشاركة PDF'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: _busy ? null : _shareExcel,
                icon: const Icon(Icons.table_chart_rounded, size: 19),
                label: const Text('إكسل'),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _previewPdf,
            icon: const Icon(Icons.visibility_rounded, size: 19),
            label: const Text('معاينة / طباعة التقرير'),
          ),
          const SizedBox(height: 8),
          const _ReportOptionsBar(),

          const SizedBox(height: 16),

          // بطاقات الإحصاء
          Row(children: [
            Expanded(
              child: StatCard(
                label: 'الزيارات',
                value: '${s.visitCount}',
                icon: Icons.event_available_rounded,
                color: AppTheme.seed,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatCard(
                label: 'تمت',
                value: '${s.doneCount}',
                icon: Icons.check_circle_rounded,
                color: AppTheme.success,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatCard(
                label: 'لم تتم',
                value: '${s.notDoneCount}',
                icon: Icons.cancel_rounded,
                color: AppTheme.danger,
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: StatCard(
                label: 'قطع صادرة',
                value: '${s.itemsOutCount}',
                icon: Icons.upload_rounded,
                color: AppTheme.warning,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatCard(
                label: 'قطع راجعة',
                value: '${s.itemsReturnedCount}',
                icon: Icons.download_rounded,
                color: AppTheme.info,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatCard(
                label: 'سحب آجل',
                value: '${s.credits.length}',
                icon: Icons.handshake_rounded,
                color: AppTheme.accent,
              ),
            ),
          ]),

          // حركة الصندوق
          const SectionHeader('حركة النقد', icon: Icons.account_balance_wallet_rounded),
          Row(children: [
            Expanded(
              child: StatCard(
                label: 'إجمالي الداخل',
                value: Fmt.moneyShort(g.paid + s.cashTotals.income),
                icon: Icons.south_west_rounded,
                color: AppTheme.success,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatCard(
                label: 'إجمالي الخارج',
                value: Fmt.moneyShort(s.cashTotals.expense),
                icon: Icons.north_east_rounded,
                color: AppTheme.danger,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatCard(
                label: 'صافي النقد',
                value: Fmt.moneyShort(s.netCashFlow),
                icon: Icons.savings_rounded,
                color: s.netCashFlow >= 0 ? AppTheme.info : AppTheme.warning,
              ),
            ),
          ]),

          // الملخص المالي
          const SectionHeader('الملخص المالي', icon: Icons.account_balance_wallet_rounded),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            ),
            child: Column(children: [
              _Line('قيمة القطع', g.itemsTotal),
              if (g.returnedTotal > 0.009) ...[
                const Divider(height: 16),
                _Line('قيمة المرتجع', g.returnedTotal, color: AppTheme.warning),
                const Divider(height: 16),
                _Line('الصافي', g.net, bold: true),
              ],
              const Divider(height: 16),
              _Line('المحصّل', g.paid, color: AppTheme.success),
              const Divider(height: 16),
              _Line('المتبقي', g.remaining,
                  color: context.colorForRemaining(g.remaining), bold: true, large: true),
            ]),
          ),

          // تفصيل: زيارات مقابل آجل
          if (s.credits.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: _MiniPanel(
                  title: 'الزيارات',
                  paid: s.visitTotals.paid,
                  remaining: s.visitTotals.remaining,
                  total: s.visitTotals.net,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniPanel(
                  title: 'السحب الآجل',
                  paid: s.creditTotals.paid,
                  remaining: s.creditTotals.remaining,
                  total: s.creditTotals.net,
                ),
              ),
            ]),
          ],

          // ملاحظات الأيام
          if (s.dayNotes.isNotEmpty) ...[
            const SectionHeader('ملاحظات الأيام', icon: Icons.sticky_note_2_rounded),
            ...s.dayNotes.map((n) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.accent.withValues(alpha: 0.25)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(Fmt.dateWithDay(n.day),
                          style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.accent)),
                      const SizedBox(height: 3),
                      Text(n.notes, style: const TextStyle(fontSize: 13, height: 1.5)),
                    ],
                  ),
                )),
          ],

          // الحركات المالية
          if (s.cash.isNotEmpty) ...[
            SectionHeader('الحركات المالية (${s.cash.length})',
                icon: Icons.receipt_long_rounded),
            ...s.cash.map((e) => CashTile(entry: e)),
          ],

          // قائمة الزيارات
          if (s.visits.isNotEmpty) ...[
            SectionHeader('الزيارات (${s.visits.length})', icon: Icons.list_alt_rounded),
            ...s.visits.map((vf) => VisitCard(vf: vf, showDate: !s.from.isAtSameMomentAs(s.to))),
          ],

          if (s.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: EmptyState(
                icon: Icons.inbox_rounded,
                title: 'لا توجد سجلات في هذه الفترة',
                subtitle: 'جرّب اختيار فترة أخرى',
              ),
            ),
        ],
      ),

      if (_busy)
        Positioned.fill(
          child: ColoredBox(
            color: Colors.black.withValues(alpha: 0.25),
            child: const Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 14),
                    Text('جارٍ إنشاء الملف...'),
                  ]),
                ),
              ),
            ),
          ),
        ),
    ]);
  }
}

class _Line extends StatelessWidget {
  final String label;
  final double value;
  final Color? color;
  final bool bold;
  final bool large;

  const _Line(this.label, this.value,
      {this.color, this.bold = false, this.large = false});

  @override
  Widget build(BuildContext context) => Row(children: [
        Text(label,
            style: TextStyle(
              fontSize: large ? 15 : 13.5,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            )),
        const Spacer(),
        Text(Fmt.money(value),
            style: TextStyle(
              fontSize: large ? 17 : 14.5,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w700,
              color: color ?? Theme.of(context).colorScheme.onSurface,
            )),
      ]);
}

class _MiniPanel extends StatelessWidget {
  final String title;
  final double paid;
  final double remaining;
  final double total;

  const _MiniPanel({
    required this.title,
    required this.paid,
    required this.remaining,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w700, color: scheme.primary)),
        const SizedBox(height: 7),
        _row('الإجمالي', total, scheme.onSurface),
        _row('المحصّل', paid, AppTheme.success),
        _row('المتبقي', remaining,
            remaining > 0.009 ? AppTheme.danger : AppTheme.success),
      ]),
    );
  }

  Widget _row(String label, double v, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.5),
        child: Row(children: [
          Text(label, style: const TextStyle(fontSize: 11.5)),
          const Spacer(),
          Text(Fmt.moneyShort(v),
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        ]),
      );
}

/// اختيار الأقسام التي تُدرَج في ملف التقرير
class _ReportOptionsBar extends ConsumerWidget {
  const _ReportOptionsBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(reportOptionsProvider);
    final scheme = Theme.of(context).colorScheme;

    return async.when(
      loading: () => const SizedBox(height: 44),
      error: (e, _) => const SizedBox.shrink(),
      data: (o) {
        Future<void> update(ReportOptions next) async {
          await Repository.instance.saveReportOptions(next);
          ref.invalidate(reportOptionsProvider);
        }

        Widget chip(String label, bool on, ReportOptions Function() toggle) =>
            FilterChip(
              label: Text(label, style: const TextStyle(fontSize: 12)),
              selected: on,
              onSelected: (_) => update(toggle()),
              visualDensity: VisualDensity.compact,
              showCheckmark: true,
            );

        return Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.tune_rounded, size: 17, color: scheme.primary),
                const SizedBox(width: 7),
                Text(
                  'ما يُدرَج في التقرير',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
              ]),
              const SizedBox(height: 9),
              Wrap(spacing: 6, runSpacing: 6, children: [
                chip('الزيارات', o.includeVisits,
                    () => o.copyWith(includeVisits: !o.includeVisits)),
                chip('السحب الآجل', o.includeCredits,
                    () => o.copyWith(includeCredits: !o.includeCredits)),
                chip('الحركات المالية', o.includeCash,
                    () => o.copyWith(includeCash: !o.includeCash)),
                chip('رصيد الكاش', o.includeCashBalance,
                    () => o.copyWith(includeCashBalance: !o.includeCashBalance)),
                chip('الرواتب', o.includeSalaries,
                    () => o.copyWith(includeSalaries: !o.includeSalaries)),
                chip('ديون العملاء', o.includeDebts,
                    () => o.copyWith(includeDebts: !o.includeDebts)),
              ]),
            ],
          ),
        );
      },
    );
  }
}
