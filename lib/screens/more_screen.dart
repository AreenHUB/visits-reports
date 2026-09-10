import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../utils/formatting.dart';
import '../utils/theme.dart';
import '../widgets/common.dart';
import 'debts_screen.dart';
import 'salaries_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

/// تبويب «المزيد»: الرواتب والديون والبحث والإعدادات
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = ref.watch(cashBalanceProvider);
    final snapshot = ref.watch(daySnapshotProvider);
    final debtsTotal = ref.watch(debtsOutstandingProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('المزيد')),
      body: RefreshIndicator(
        onRefresh: () async => bumpRefresh(ref),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 30),
          children: [
            // رصيد الكاش داخل المحل مع حركة اليوم
            _CashBalanceCard(
              balance: balance.valueOrNull?.balance ?? 0,
              todayNet: snapshot.valueOrNull?.dayNet ?? 0,
              loading: balance.isLoading,
            ),

            const SectionHeader('الأقسام', icon: Icons.apps_rounded),

            _MenuTile(
              icon: Icons.groups_rounded,
              color: AppTheme.info,
              title: 'رواتب الموظفين',
              subtitle: 'سجّل دفعات كل موظف بتواريخها',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SalariesScreen()),
              ),
            ),

            _MenuTile(
              icon: Icons.receipt_long_rounded,
              color: AppTheme.warning,
              title: 'ديون العملاء',
              subtitle: debtsTotal.valueOrNull != null &&
                      debtsTotal.value! > 0.009
                  ? 'قائم: ${Fmt.moneyShort(debtsTotal.value!)}'
                  : 'تذكير بمن عليه دين',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DebtsScreen()),
              ),
            ),

            _MenuTile(
              icon: Icons.search_rounded,
              color: AppTheme.seed,
              title: 'البحث وتتبّع السيريال',
              subtitle: 'ابحث في الزيارات أو تتبّع أي قطعة',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SearchScreen()),
              ),
            ),

            _MenuTile(
              icon: Icons.settings_rounded,
              color: AppTheme.accent,
              title: 'الإعدادات والنسخ الاحتياطي',
              subtitle: 'بيانات المحل، النسخ الاحتياطي، نقل لجهاز آخر',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// بطاقة رصيد الكاش — النقد الموجود فعليًا في المحل
class _CashBalanceCard extends StatelessWidget {
  final double balance;
  final double todayNet;
  final bool loading;

  const _CashBalanceCard({
    required this.balance,
    required this.todayNet,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final positive = balance >= 0;
    final color = positive ? AppTheme.success : AppTheme.danger;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(Icons.savings_rounded, color: color, size: 25),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              'الكاش في المحل',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            if (loading)
              const SizedBox(
                width: 60,
                height: 18,
                child: LinearProgressIndicator(minHeight: 2),
              )
            else
              Text(
                Fmt.money(balance),
                style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
              ),
            const SizedBox(height: 2),
            Text(
              'النقد فقط — لا يشمل البطاقة أو التحويل',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (!loading && todayNet.abs() > 0.009) ...[
              const SizedBox(height: 5),
              Row(children: [
                Icon(
                  todayNet >= 0
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded,
                  size: 14,
                  color: todayNet >= 0 ? AppTheme.success : AppTheme.danger,
                ),
                const SizedBox(width: 5),
                Text(
                  'حركة اليوم: ${todayNet > 0 ? '+' : ''}'
                  '${Fmt.moneyShort(todayNet)}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: todayNet >= 0 ? AppTheme.success : AppTheme.danger,
                  ),
                ),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          title: Text(title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
          trailing: const Icon(Icons.chevron_left_rounded),
          onTap: onTap,
        ),
      );
}
