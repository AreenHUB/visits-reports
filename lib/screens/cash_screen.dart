import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/repository.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../utils/formatting.dart';
import '../utils/theme.dart';
import '../widgets/common.dart';
import 'cash_form_screen.dart';

/// شاشة الصندوق: كل ما دخل وخرج من المحل خارج نطاق الزيارات
class CashScreen extends ConsumerWidget {
  const CashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(cashEntriesProvider);
    final filter = ref.watch(cashDirectionFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('الصندوق'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(104),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'ابحث بالبيان أو الاسم',
                  prefixIcon: Icon(Icons.search_rounded),
                  isDense: true,
                ),
                onChanged: (v) => ref.read(cashSearchProvider.notifier).state = v,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: SegmentedButton<CashDirection?>(
                segments: const [
                  ButtonSegment(value: null, label: Text('الكل')),
                  ButtonSegment(value: CashDirection.income, label: Text('وارد')),
                  ButtonSegment(value: CashDirection.expense, label: Text('صادر')),
                ],
                selected: {filter},
                onSelectionChanged: (s) =>
                    ref.read(cashDirectionFilterProvider.notifier).state = s.first,
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
        child: entriesAsync.when(
          loading: () => const LoadingView(),
          error: (e, _) => ErrorView(e, onRetry: () => bumpRefresh(ref)),
          data: (entries) {
            if (entries.isEmpty) {
              return ListView(children: [
                const SizedBox(height: 60),
                EmptyState(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'لا توجد حركات مالية',
                  subtitle:
                      'سجّل هنا كل مبلغ يدخل أو يخرج من المحل خارج الزيارات:\nبيع، سداد دين، رسوم رخصة، مصاريف...',
                  action: FilledButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CashFormScreen()),
                    ),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('حركة جديدة'),
                  ),
                ),
              ]);
            }

            final totals = CashTotals.from(entries);

            return ListView(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 90),
              children: [
                Row(children: [
                  Expanded(
                    child: StatCard(
                      label: 'الوارد',
                      value: Fmt.moneyShort(totals.income),
                      icon: Icons.south_west_rounded,
                      color: AppTheme.success,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatCard(
                      label: 'الصادر',
                      value: Fmt.moneyShort(totals.expense),
                      icon: Icons.north_east_rounded,
                      color: AppTheme.danger,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatCard(
                      label: 'الصافي',
                      value: Fmt.moneyShort(totals.net),
                      icon: Icons.account_balance_wallet_rounded,
                      color: totals.net >= 0 ? AppTheme.info : AppTheme.warning,
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                ...entries.map((e) => CashTile(entry: e)),
              ],
            );
          },
        ),
      ),

      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'cash_expense',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    const CashFormScreen(initialDirection: CashDirection.expense),
              ),
            ),
            backgroundColor: AppTheme.danger,
            foregroundColor: Colors.white,
            tooltip: 'تسجيل صادر',
            child: const Icon(Icons.north_east_rounded),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'cash_income',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    const CashFormScreen(initialDirection: CashDirection.income),
              ),
            ),
            backgroundColor: AppTheme.success,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.south_west_rounded),
            label: const Text('وارد'),
          ),
        ],
      ),
    );
  }
}

/// بطاقة حركة مالية واحدة
class CashTile extends ConsumerWidget {
  final CashEntry entry;
  final bool showDate;

  const CashTile({super.key, required this.entry, this.showDate = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final isIncome = entry.direction == CashDirection.income;
    final color = isIncome ? AppTheme.success : AppTheme.danger;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => CashFormScreen(entryId: entry.id)),
        ),
        onLongPress: () async {
          final ok = await confirmDialog(
            context,
            title: 'حذف الحركة',
            message:
                'سيتم حذف «${entry.description.isEmpty ? entry.categoryLabel : entry.description}» '
                'بمبلغ ${Fmt.money(entry.amount)}.',
            confirmLabel: 'حذف',
            destructive: true,
          );
          if (!ok || !context.mounted) return;
          await Repository.instance.deleteCashEntry(entry.id);
          if (!context.mounted) return;
          bumpRefresh(ref);
          showSnack(context, 'تم حذف الحركة');
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                isIncome ? Icons.south_west_rounded : Icons.north_east_rounded,
                color: color,
                size: 20,
              ),
            ),
            const SizedBox(width: 11),

            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  entry.description.isEmpty ? entry.categoryLabel : entry.description,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    entry.categoryLabel,
                    if (entry.partyName.isNotEmpty) entry.partyName,
                  ].join('  •  '),
                  style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(entry.method.label,
                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600)),
                  ),
                  if (entry.linkedCreditId != null) ...[
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.info.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.link_rounded, size: 11, color: AppTheme.info),
                        SizedBox(width: 3),
                        Text('مرتبط بدين',
                            style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.info)),
                      ]),
                    ),
                  ],
                  const Spacer(),
                  if (showDate)
                    Text(
                      '${Fmt.date(entry.date)}  ${Fmt.time(entry.date)}',
                      style: TextStyle(fontSize: 10.5, color: scheme.outline),
                    ),
                ]),
              ]),
            ),

            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(
                '${isIncome ? '+' : '−'} ${Fmt.moneyShort(entry.amount)}',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: color),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
