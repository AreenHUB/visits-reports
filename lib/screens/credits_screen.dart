import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/repository.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../utils/formatting.dart';
import '../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/item_editor.dart';
import 'credit_form_screen.dart';

/// قائمة السحوبات الآجلة (الديون)
class CreditsScreen extends ConsumerWidget {
  const CreditsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final creditsAsync = ref.watch(creditsProvider);
    final filter = ref.watch(creditFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('السحب الآجل'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(104),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'ابحث بالاسم أو الهاتف',
                  prefixIcon: Icon(Icons.search_rounded),
                  isDense: true,
                ),
                onChanged: (v) => ref.read(creditSearchProvider.notifier).state = v,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: SegmentedButton<CreditFilter>(
                segments: const [
                  ButtonSegment(value: CreditFilter.all, label: Text('الكل')),
                  ButtonSegment(value: CreditFilter.unsettled, label: Text('غير مسدَّد')),
                  ButtonSegment(value: CreditFilter.settled, label: Text('مسدَّد')),
                ],
                selected: {filter},
                onSelectionChanged: (s) =>
                    ref.read(creditFilterProvider.notifier).state = s.first,
                style: SegmentedButton.styleFrom(
                  textStyle: const TextStyle(fontSize: 12.5),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ]),
        ),
      ),

      body: RefreshIndicator(
        onRefresh: () async => bumpRefresh(ref),
        child: creditsAsync.when(
          loading: () => const LoadingView(),
          error: (e, _) => ErrorView(e, onRetry: () => bumpRefresh(ref)),
          data: (credits) {
            if (credits.isEmpty) {
              return ListView(children: [
                const SizedBox(height: 60),
                EmptyState(
                  icon: Icons.handshake_outlined,
                  title: 'لا توجد سحوبات آجلة',
                  subtitle: 'سجّل هنا القطع التي يسحبها المتعاملون بالدين',
                  action: FilledButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CreditFormScreen()),
                    ),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('سحب جديد'),
                  ),
                ),
              ]);
            }

            var totals = const Totals();
            for (final c in credits) {
              totals = totals + c.totals;
            }
            final unpaidCount =
                credits.where((c) => !c.credit.settled && c.totals.remaining > 0.009).length;

            return ListView(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 90),
              children: [
                Row(children: [
                  Expanded(
                    child: StatCard(
                      label: 'السجلات',
                      value: '${credits.length}',
                      icon: Icons.receipt_long_rounded,
                      color: AppTheme.seed,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatCard(
                      label: 'غير مسدَّد',
                      value: '$unpaidCount',
                      icon: Icons.pending_actions_rounded,
                      color: AppTheme.warning,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatCard(
                      label: 'إجمالي الدين',
                      value: Fmt.moneyShort(totals.remaining),
                      icon: Icons.account_balance_wallet_rounded,
                      color: totals.remaining > 0.009 ? AppTheme.danger : AppTheme.success,
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                ...credits.map((cf) => _CreditCard(cf: cf)),
              ],
            );
          },
        ),
      ),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CreditFormScreen()),
        ),
        icon: const Icon(Icons.add_rounded),
        label: const Text('سحب جديد'),
      ),
    );
  }
}

class _CreditCard extends ConsumerWidget {
  final CreditFull cf;
  const _CreditCard({required this.cf});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = cf.credit;
    final t = cf.totals;
    final scheme = Theme.of(context).colorScheme;

    final isOverdue = !c.settled &&
        c.dueDate != null &&
        c.dueDate!.isBefore(DateTime.now()) &&
        t.remaining > 0.009;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isOverdue
              ? AppTheme.danger.withValues(alpha: 0.5)
              : scheme.outlineVariant.withValues(alpha: 0.5),
          width: isOverdue ? 1.4 : 1,
        ),
      ),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => CreditDetailScreen(creditId: c.id)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 12, 13, 11),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.personName,
                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                    [
                      Fmt.date(c.date),
                      if (c.personPhone.isNotEmpty) c.personPhone,
                    ].join('  •  '),
                    style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                  ),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: (c.settled ? AppTheme.success : AppTheme.warning)
                      .withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: (c.settled ? AppTheme.success : AppTheme.warning)
                        .withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  c.settled ? 'مسدَّد' : 'آجل',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: c.settled ? AppTheme.success : AppTheme.warning,
                  ),
                ),
              ),
            ]),

            if (c.dueDate != null) ...[
              const SizedBox(height: 6),
              Row(children: [
                Icon(
                  isOverdue ? Icons.warning_amber_rounded : Icons.event_rounded,
                  size: 14,
                  color: isOverdue ? AppTheme.danger : scheme.outline,
                ),
                const SizedBox(width: 5),
                Text(
                  isOverdue
                      ? 'متأخر! استحقاق: ${Fmt.date(c.dueDate!)}'
                      : 'الاستحقاق: ${Fmt.date(c.dueDate!)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isOverdue ? FontWeight.w700 : FontWeight.w500,
                    color: isOverdue ? AppTheme.danger : scheme.onSurfaceVariant,
                  ),
                ),
              ]),
            ],

            if (cf.items.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 5, runSpacing: 5, children: [
                ...cf.items.take(3).map((i) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 160),
                        child: Text(
                          i.qty > 1 ? '${i.description} ×${i.qty}' : i.description,
                          style: const TextStyle(fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )),
                if (cf.items.length > 3)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('+${cf.items.length - 3}',
                        style: const TextStyle(fontSize: 11)),
                  ),
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

/// تفاصيل سحب آجل واحد
class CreditDetailScreen extends ConsumerWidget {
  final String creditId;
  const CreditDetailScreen({super.key, required this.creditId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(creditFullProvider(creditId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('تفاصيل السحب'),
        actions: [
          IconButton(
            tooltip: 'تعديل',
            icon: const Icon(Icons.edit_rounded),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => CreditFormScreen(creditId: creditId)),
            ),
          ),
          IconButton(
            tooltip: 'حذف',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () async {
              final ok = await confirmDialog(
                context,
                title: 'حذف السجل',
                message: 'سيتم حذف السحب وكل قطعه ودفعاته نهائيًا.',
                confirmLabel: 'حذف',
                destructive: true,
              );
              if (!ok || !context.mounted) return;
              await Repository.instance.deleteCredit(creditId);
              if (!context.mounted) return;
              bumpRefresh(ref);
              Navigator.pop(context);
              showSnack(context, 'تم حذف السجل');
            },
          ),
        ],
      ),
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(e),
        data: (cf) {
          if (cf == null) {
            return const EmptyState(
                icon: Icons.search_off_rounded, title: 'السجل غير موجود');
          }

          final c = cf.credit;
          final t = cf.totals;
          final scheme = Theme.of(context).colorScheme;

          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 30),
            children: [
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: (c.settled ? AppTheme.success : AppTheme.warning)
                      .withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: (c.settled ? AppTheme.success : AppTheme.warning)
                        .withValues(alpha: 0.3),
                  ),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(c.personName,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
                      decoration: BoxDecoration(
                        color: c.settled ? AppTheme.success : AppTheme.warning,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        c.settled ? 'مسدَّد' : 'آجل',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  DetailRow(
                      icon: Icons.phone_outlined, label: 'الهاتف', value: c.personPhone),
                  DetailRow(
                      icon: Icons.today_rounded,
                      label: 'تاريخ السحب',
                      value: Fmt.dateWithDay(c.date)),
                  if (c.dueDate != null)
                    DetailRow(
                      icon: Icons.event_rounded,
                      label: 'الاستحقاق',
                      value: Fmt.dateWithDay(c.dueDate!),
                      valueColor: c.dueDate!.isBefore(DateTime.now()) && !c.settled
                          ? AppTheme.danger
                          : null,
                    ),
                  DetailRow(
                      icon: Icons.sticky_note_2_outlined,
                      label: 'ملاحظات',
                      value: c.notes),
                ]),
              ),

              SectionHeader('القطع المسحوبة (${cf.items.length})',
                  icon: Icons.inventory_2_rounded),
              if (cf.items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Center(
                    child: Text('لا توجد قطع',
                        style: TextStyle(color: scheme.outline, fontSize: 13)),
                  ),
                )
              else
                ...List.generate(
                  cf.items.length,
                  (i) => ItemTile(item: cf.items[i], index: i),
                ),

              if (cf.payments.isNotEmpty) ...[
                SectionHeader('الدفعات (${cf.payments.length})',
                    icon: Icons.payments_rounded),
                ...cf.payments.map((p) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                      decoration: BoxDecoration(
                        color: AppTheme.success.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: AppTheme.success.withValues(alpha: 0.2)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.check_circle_rounded,
                            size: 18, color: AppTheme.success),
                        const SizedBox(width: 10),
                        Expanded(
                          child:
                              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(Fmt.money(p.amount),
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w800)),
                            Text(
                              p.notes.isEmpty
                                  ? Fmt.date(p.date)
                                  : '${Fmt.date(p.date)} — ${p.notes}',
                              style: TextStyle(
                                  fontSize: 11.5, color: scheme.onSurfaceVariant),
                            ),
                          ]),
                        ),
                      ]),
                    )),
              ],

              const SectionHeader('الملخص المالي',
                  icon: Icons.account_balance_wallet_rounded),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: TotalsRow(t),
              ),
            ],
          );
        },
      ),
    );
  }
}
