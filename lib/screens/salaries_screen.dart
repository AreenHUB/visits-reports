import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_database.dart';
import '../db/repository.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../utils/formatting.dart';
import '../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/salary_editor.dart';

/// شاشة رواتب الموظفين: لكل موظف مكانه الخاص بدفعاته وتواريخها
class SalariesScreen extends ConsumerWidget {
  const SalariesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(employeesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('رواتب الموظفين')),
      body: RefreshIndicator(
        onRefresh: () async => bumpRefresh(ref),
        child: async.when(
          loading: () => const LoadingView(),
          error: (e, _) => ErrorView(e, onRetry: () => bumpRefresh(ref)),
          data: (list) {
            if (list.isEmpty) {
              return ListView(children: [
                const SizedBox(height: 60),
                EmptyState(
                  icon: Icons.groups_outlined,
                  title: 'لا يوجد موظفون',
                  subtitle:
                      'أضف موظفًا ليكون له مكان خاص تُسجَّل فيه رواتبه ودفعاته بتواريخها',
                  action: FilledButton.icon(
                    onPressed: () => _addEmployee(context, ref),
                    icon: const Icon(Icons.person_add_rounded),
                    label: const Text('إضافة موظف'),
                  ),
                ),
              ]);
            }

            final month = DateTime.now();
            final paidThisMonth =
                list.fold(0.0, (s, e) => s + e.paidInMonth(month));
            final totalAll = list.fold(0.0, (s, e) => s + e.totalPaid);

            return ListView(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 90),
              children: [
                Row(children: [
                  Expanded(
                    child: StatCard(
                      label: 'الموظفون',
                      value: '${list.where((e) => e.employee.active).length}',
                      icon: Icons.groups_rounded,
                      color: AppTheme.seed,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatCard(
                      label: 'مدفوع هذا الشهر',
                      value: Fmt.moneyShort(paidThisMonth),
                      icon: Icons.calendar_month_rounded,
                      color: AppTheme.info,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatCard(
                      label: 'الإجمالي',
                      value: Fmt.moneyShort(totalAll),
                      icon: Icons.payments_rounded,
                      color: AppTheme.warning,
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                ...list.map((ef) => _EmployeeCard(ef: ef)),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addEmployee(context, ref),
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('موظف جديد'),
      ),
    );
  }

  Future<void> _addEmployee(BuildContext context, WidgetRef ref) async {
    final result = await EmployeeEditorSheet.show(context);
    if (result == null || !context.mounted) return;
    await Repository.instance.saveEmployee(result);
    if (!context.mounted) return;
    bumpRefresh(ref);
    showSnack(context, 'تمت إضافة الموظف');
  }
}

/// بطاقة موظف تفتح على سجلّ دفعاته
class _EmployeeCard extends ConsumerWidget {
  final EmployeeFull ef;
  const _EmployeeCard({required this.ef});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = ef.employee;
    final scheme = Theme.of(context).colorScheme;
    final month = DateTime.now();
    final paidThisMonth = ef.paidInMonth(month);
    final remaining =
        e.monthlySalary > 0 ? e.monthlySalary - paidThisMonth : 0.0;

    return Card(
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EmployeeDetailScreen(employeeId: e.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 12, 13, 11),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: e.active
                    ? scheme.primary.withValues(alpha: 0.15)
                    : scheme.surfaceContainerHighest,
                child: Text(
                  e.name.isEmpty ? '?' : e.name.characters.first,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: e.active ? scheme.primary : scheme.outline,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(e.name,
                          style: const TextStyle(
                              fontSize: 15.5, fontWeight: FontWeight.w800),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (!e.active)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: const Text('غير نشط',
                            style: TextStyle(fontSize: 10.5)),
                      ),
                  ]),
                  if (e.role.isNotEmpty || e.phone.isNotEmpty)
                    Text(
                      [e.role, e.phone].where((x) => x.isNotEmpty).join('  •  '),
                      style: TextStyle(
                          fontSize: 11.5, color: scheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ]),
              ),
            ]),

            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Row(children: [
                Expanded(
                  child: MoneyBadge(
                    label: 'مدفوع هذا الشهر',
                    value: paidThisMonth,
                    color: AppTheme.success,
                  ),
                ),
                if (e.monthlySalary > 0) ...[
                  Expanded(
                    child: MoneyBadge(
                      label: 'الراتب المتّفق',
                      value: e.monthlySalary,
                    ),
                  ),
                  Expanded(
                    child: MoneyBadge(
                      label: remaining > 0.009 ? 'المتبقي' : 'مكتمل',
                      value: remaining > 0 ? remaining : 0,
                      color: remaining > 0.009
                          ? AppTheme.danger
                          : AppTheme.success,
                      bold: true,
                    ),
                  ),
                ] else
                  Expanded(
                    child: MoneyBadge(
                      label: 'إجمالي المدفوع',
                      value: ef.totalPaid,
                    ),
                  ),
              ]),
            ),

            if (ef.lastPayment != null) ...[
              const SizedBox(height: 7),
              Row(children: [
                Icon(Icons.history_rounded, size: 14, color: scheme.outline),
                const SizedBox(width: 5),
                Text(
                  'آخر دفعة: ${Fmt.moneyShort(ef.lastPayment!.amount)} '
                  'في ${Fmt.date(ef.lastPayment!.date)}',
                  style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                ),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}

/// تفاصيل موظف: كل دفعاته بتواريخها
class EmployeeDetailScreen extends ConsumerWidget {
  final String employeeId;
  const EmployeeDetailScreen({super.key, required this.employeeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(employeeFullProvider(employeeId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('سجلّ الراتب'),
        actions: [
          IconButton(
            tooltip: 'تعديل بيانات الموظف',
            icon: const Icon(Icons.edit_rounded),
            onPressed: () async {
              final ef = await Repository.instance.employeeFull(employeeId);
              if (ef == null || !context.mounted) return;
              final result =
                  await EmployeeEditorSheet.show(context, existing: ef.employee);
              if (result == null || !context.mounted) return;
              await Repository.instance.saveEmployee(result);
              if (!context.mounted) return;
              bumpRefresh(ref);
              showSnack(context, 'تم حفظ البيانات');
            },
          ),
          IconButton(
            tooltip: 'حذف الموظف',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () async {
              final ok = await confirmDialog(
                context,
                title: 'حذف الموظف',
                message: 'سيتم حذف الموظف وكل سجلّ دفعاته نهائيًا.',
                confirmLabel: 'حذف',
                destructive: true,
              );
              if (!ok || !context.mounted) return;
              await Repository.instance.deleteEmployee(employeeId);
              if (!context.mounted) return;
              bumpRefresh(ref);
              Navigator.pop(context);
              showSnack(context, 'تم حذف الموظف');
            },
          ),
        ],
      ),

      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(e),
        data: (ef) {
          if (ef == null) {
            return const EmptyState(
                icon: Icons.person_off_rounded, title: 'الموظف غير موجود');
          }

          final e = ef.employee;
          final scheme = Theme.of(context).colorScheme;
          final month = DateTime.now();
          final paidThisMonth = ef.paidInMonth(month);

          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 90),
            children: [
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(16),
                  border:
                      Border.all(color: scheme.primary.withValues(alpha: 0.22)),
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.name,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      DetailRow(
                          icon: Icons.badge_outlined,
                          label: 'الوظيفة',
                          value: e.role),
                      DetailRow(
                          icon: Icons.phone_outlined,
                          label: 'الهاتف',
                          value: e.phone),
                      if (e.monthlySalary > 0)
                        DetailRow(
                          icon: Icons.payments_outlined,
                          label: 'الراتب الشهري',
                          value: Fmt.money(e.monthlySalary),
                        ),
                      DetailRow(
                          icon: Icons.sticky_note_2_outlined,
                          label: 'ملاحظات',
                          value: e.notes),
                    ]),
              ),

              const SectionHeader('الملخص', icon: Icons.summarize_rounded),
              Row(children: [
                Expanded(
                  child: StatCard(
                    label: 'مدفوع هذا الشهر',
                    value: Fmt.moneyShort(paidThisMonth),
                    icon: Icons.calendar_month_rounded,
                    color: AppTheme.success,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StatCard(
                    label: 'إجمالي المدفوع',
                    value: Fmt.moneyShort(ef.totalPaid),
                    icon: Icons.payments_rounded,
                    color: AppTheme.info,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StatCard(
                    label: 'عدد الدفعات',
                    value: '${ef.payments.length}',
                    icon: Icons.receipt_long_rounded,
                    color: AppTheme.accent,
                  ),
                ),
              ]),

              SectionHeader('الدفعات (${ef.payments.length})',
                  icon: Icons.history_rounded),

              if (ef.payments.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 22),
                  child: Center(
                    child: Text('لا توجد دفعات مسجّلة',
                        style: TextStyle(color: scheme.outline, fontSize: 13)),
                  ),
                )
              else
                ...ef.payments.map((p) => _SalaryTile(
                      payment: p,
                      onEdit: () async {
                        final result = await SalaryPaymentSheet.show(
                          context,
                          employee: e,
                          existing: p,
                        );
                        if (result == null || !context.mounted) return;
                        await Repository.instance.saveSalaryPayment(result);
                        if (!context.mounted) return;
                        bumpRefresh(ref);
                        showSnack(context, 'تم حفظ الدفعة');
                      },
                      onDelete: () async {
                        final ok = await confirmDialog(
                          context,
                          title: 'حذف الدفعة',
                          message:
                              'سيتم حذف دفعة ${Fmt.money(p.amount)} بتاريخ ${Fmt.date(p.date)}.',
                          confirmLabel: 'حذف',
                          destructive: true,
                        );
                        if (!ok || !context.mounted) return;
                        await Repository.instance.deleteSalaryPayment(p.id);
                        if (!context.mounted) return;
                        bumpRefresh(ref);
                        showSnack(context, 'تم حذف الدفعة');
                      },
                    )),
            ],
          );
        },
      ),

      floatingActionButton: async.valueOrNull == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () async {
                final ef = async.valueOrNull;
                if (ef == null) return;
                final result = await SalaryPaymentSheet.show(
                  context,
                  employee: ef.employee,
                );
                if (result == null || !context.mounted) return;
                await Repository.instance.saveSalaryPayment(result);
                if (!context.mounted) return;
                bumpRefresh(ref);
                showSnack(context, 'تم تسجيل الدفعة');
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('تسليم دفعة'),
            ),
    );
  }
}

class _SalaryTile extends StatelessWidget {
  final SalaryPayment payment;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _SalaryTile({
    required this.payment,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (payment.kind) {
      SalaryKind.full => AppTheme.success,
      SalaryKind.partial => AppTheme.info,
      SalaryKind.advance => AppTheme.warning,
      SalaryKind.bonus => AppTheme.accent,
    };

    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.payments_rounded, size: 19, color: color),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(Fmt.money(payment.amount),
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w800)),
                const SizedBox(width: 7),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(payment.kind.label,
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: color)),
                ),
              ]),
              const SizedBox(height: 3),
              Text(
                [
                  Fmt.dateWithDay(payment.date),
                  payment.method.label,
                  if (payment.forMonth != null)
                    'عن ${Fmt.monthName(payment.forMonth!)}',
                ].join('  •  '),
                style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
              ),
              if (payment.notes.isNotEmpty)
                Text(payment.notes,
                    style: TextStyle(fontSize: 11.5, color: scheme.outline),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
            ]),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.delete_outline_rounded,
                size: 19, color: scheme.outline),
            onPressed: onDelete,
          ),
        ]),
      ),
    );
  }
}

/// معرّف مساعد لإنشاء موظف جديد
String newEmployeeId() => AppDatabase.newId();
