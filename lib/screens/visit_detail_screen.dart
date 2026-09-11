import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/repository.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../services/pdf_service.dart';
import '../services/share_service.dart';
import '../utils/formatting.dart';
import '../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/item_editor.dart';
import 'visit_form_screen.dart';

/// عرض تفاصيل زيارة واحدة مع إمكانية التعديل والمشاركة
class VisitDetailScreen extends ConsumerWidget {
  final String visitId;
  const VisitDetailScreen({super.key, required this.visitId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(visitFullProvider(visitId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('تفاصيل الزيارة'),
        actions: [
          IconButton(
            tooltip: 'تعديل',
            icon: const Icon(Icons.edit_rounded),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => VisitFormScreen(visitId: visitId)),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) => _onMenu(context, ref, v),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'share',
                child: ListTile(
                  leading: Icon(Icons.share_rounded),
                  title: Text('مشاركة كـ PDF'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline_rounded, color: AppTheme.danger),
                  title: Text('حذف الزيارة', style: TextStyle(color: AppTheme.danger)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(e),
        data: (vf) {
          if (vf == null) {
            return const EmptyState(
              icon: Icons.search_off_rounded,
              title: 'الزيارة غير موجودة',
            );
          }
          return _Body(vf: vf);
        },
      ),
    );
  }

  Future<void> _onMenu(BuildContext context, WidgetRef ref, String action) async {
    final vf = await Repository.instance.visitFull(visitId);
    if (vf == null || !context.mounted) return;

    if (action == 'delete') {
      final ok = await confirmDialog(
        context,
        title: 'حذف الزيارة',
        message: 'سيتم حذف الزيارة وكل قطعها ودفعاتها نهائيًا.\nهل أنت متأكد؟',
        confirmLabel: 'حذف',
        destructive: true,
      );
      if (!ok || !context.mounted) return;

      await Repository.instance.deleteVisit(visitId);
      if (!context.mounted) return;
      bumpRefresh(ref);
      Navigator.pop(context);
      showSnack(context, 'تم حذف الزيارة');
      return;
    }

    if (action == 'share') {
      if (!context.mounted) return;
      await _shareSingleVisit(context, ref, vf);
    }
  }

  Future<void> _shareSingleVisit(
    BuildContext context,
    WidgetRef ref,
    VisitFull vf,
  ) async {
    final origin = ShareService.originFrom(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final settings = await ref.read(settingsProvider.future);
      final summary = PeriodSummary(
        from: vf.visit.date,
        to: vf.visit.date,
        visits: [vf],
        credits: const [],
        visitTotals: vf.totals,
        creditTotals: const Totals(),
      );

      final bytes = await PdfService.instance.buildReport(
        summary: summary,
        settings: settings,
        title: 'تقرير زيارة — ${vf.visit.customerName}',
      );
      final file = await PdfService.instance.saveToFile(
        bytes,
        // اسم لاتيني: اسم العميل قد يحمل مسافات ورموزًا يرفضها
        // مزوّد الملفات في أندرويد عند المشاركة
        'Visit_${vf.visit.date.year}-'
            '${vf.visit.date.month.toString().padLeft(2, '0')}-'
            '${vf.visit.date.day.toString().padLeft(2, '0')}.pdf',
      );

      if (!context.mounted) return;
      Navigator.pop(context);

      await ShareService.instance.shareFile(
        file,
        text: ShareService.reportMessage(summary, settings),
        subject: 'تقرير زيارة ${vf.visit.customerName}',
        origin: origin,
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      showSnack(context, 'تعذّر إنشاء التقرير: $e', error: true);
    }
  }
}

class _Body extends StatelessWidget {
  final VisitFull vf;
  const _Body({required this.vf});

  @override
  Widget build(BuildContext context) {
    final v = vf.visit;
    final t = vf.totals;
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 30),
      children: [
        // ترويسة العميل
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.22)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: scheme.primary,
                child: Text(
                  v.customerName.isEmpty ? '?' : v.customerName.characters.first,
                  style: TextStyle(
                    color: scheme.onPrimary,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(v.customerName,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(Fmt.dateWithDay(v.date),
                      style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
                ]),
              ),
              StatusBadge(v.status),
            ]),
            const SizedBox(height: 10),
            DetailRow(icon: Icons.phone_outlined, label: 'الهاتف', value: v.customerPhone),
            DetailRow(
                icon: Icons.location_on_outlined, label: 'العنوان', value: v.customerAddress),
            DetailRow(icon: Icons.access_time_rounded, label: 'الوقت', value: Fmt.time(v.date)),
          ]),
        ),

        // الهدف والملاحظات
        if (v.purpose.isNotEmpty || v.notDoneReason.isNotEmpty || v.dayNotes.isNotEmpty) ...[
          const SectionHeader('تفاصيل الزيارة', icon: Icons.event_note_rounded),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Column(children: [
              DetailRow(icon: Icons.flag_outlined, label: 'الهدف', value: v.purpose),
              if (v.notDoneReason.isNotEmpty)
                DetailRow(
                  icon: Icons.info_outline_rounded,
                  label: 'سبب عدم التنفيذ',
                  value: v.notDoneReason,
                  valueColor: AppTheme.danger,
                ),
              DetailRow(
                  icon: Icons.sticky_note_2_outlined, label: 'ملاحظات', value: v.dayNotes),
            ]),
          ),
        ],

        // القطع
        SectionHeader('القطع (${vf.items.length})', icon: Icons.inventory_2_rounded),
        if (vf.items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: Text('لا توجد قطع مسجّلة',
                  style: TextStyle(color: scheme.outline, fontSize: 13)),
            ),
          )
        else
          ...List.generate(
            vf.items.length,
            (i) => ItemTile(item: vf.items[i], index: i),
          ),

        // الدفعات
        if (vf.payments.isNotEmpty) ...[
          SectionHeader('الدفعات (${vf.payments.length})', icon: Icons.payments_rounded),
          ...vf.payments.map((p) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.success.withValues(alpha: 0.2)),
                ),
                child: Row(children: [
                  const Icon(Icons.check_circle_rounded, size: 18, color: AppTheme.success),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(Fmt.money(p.amount),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                      Text(
                        p.notes.isEmpty
                            ? Fmt.date(p.date)
                            : '${Fmt.date(p.date)} — ${p.notes}',
                        style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                      ),
                    ]),
                  ),
                ]),
              )),
        ],

        // الملخص المالي
        const SectionHeader('الملخص المالي', icon: Icons.account_balance_wallet_rounded),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(children: [
            _MoneyLine('قيمة القطع الصادرة', t.itemsTotal),
            if (t.returnedTotal > 0.009) ...[
              const Divider(height: 18),
              _MoneyLine('قيمة القطع الراجعة', t.returnedTotal, color: AppTheme.warning),
              const Divider(height: 18),
              _MoneyLine('الصافي', t.net, bold: true),
            ],
            const Divider(height: 18),
            _MoneyLine('المبلغ المستلم', t.paid, color: AppTheme.success),
            const Divider(height: 18),
            _MoneyLine(
              'المتبقي',
              t.remaining,
              color: context.colorForRemaining(t.remaining),
              bold: true,
              large: true,
            ),
          ]),
        ),
      ],
    );
  }
}

class _MoneyLine extends StatelessWidget {
  final String label;
  final double value;
  final Color? color;
  final bool bold;
  final bool large;

  const _MoneyLine(
    this.label,
    this.value, {
    this.color,
    this.bold = false,
    this.large = false,
  });

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
