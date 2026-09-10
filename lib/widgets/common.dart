import 'package:flutter/material.dart';

import '../models/models.dart';
import '../utils/formatting.dart';
import '../utils/theme.dart';

/// شارة حالة الزيارة
class StatusBadge extends StatelessWidget {
  final VisitStatus status;
  final bool small;

  const StatusBadge(this.status, {super.key, this.small = false});

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (status) {
      VisitStatus.done => (AppTheme.success, Icons.check_circle_rounded),
      VisitStatus.notDone => (AppTheme.danger, Icons.cancel_rounded),
      VisitStatus.partial => (AppTheme.warning, Icons.timelapse_rounded),
    };

    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 7 : 9, vertical: small ? 2 : 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: small ? 12 : 15, color: color),
        const SizedBox(width: 4),
        Text(
          status.label,
          style: TextStyle(
            fontSize: small ? 10.5 : 12,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ]),
    );
  }
}

/// شارة مبلغ ملوّنة حسب الحالة (متبقي / مسدّد)
class MoneyBadge extends StatelessWidget {
  final String label;
  final double value;
  final Color? color;
  final bool bold;

  const MoneyBadge({
    super.key,
    required this.label,
    required this.value,
    this.color,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurface;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(label,
          style: TextStyle(
            fontSize: 10.5,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          )),
      const SizedBox(height: 2),
      Text(
        Fmt.moneyShort(value),
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w700,
          color: c,
        ),
      ),
    ]);
  }
}

/// صف الإجماليات المالية المستخدم في بطاقات الزيارة والسحب
class TotalsRow extends StatelessWidget {
  final Totals totals;
  final bool compact;

  const TotalsRow(this.totals, {super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final hasReturn = totals.returnedTotal > 0.009;
    final remainingColor = context.colorForRemaining(totals.remaining);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: compact ? 7 : 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(children: [
        Expanded(child: MoneyBadge(label: 'قيمة القطع', value: totals.itemsTotal)),
        if (hasReturn)
          Expanded(
            child: MoneyBadge(
              label: 'المرتجع',
              value: totals.returnedTotal,
              color: AppTheme.warning,
            ),
          ),
        Expanded(
          child: MoneyBadge(
            label: 'المدفوع',
            value: totals.paid,
            color: AppTheme.success,
          ),
        ),
        Expanded(
          child: MoneyBadge(
            label: 'المتبقي',
            value: totals.remaining,
            color: remainingColor,
            bold: true,
          ),
        ),
      ]),
    );
  }
}

/// بطاقة إحصاء في لوحة المعلومات
class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Icon(icon, size: 18, color: color),
                const Spacer(),
              ]),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  value,
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: color),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// حالة فارغة موحّدة
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 62, color: scheme.outlineVariant),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: scheme.outline),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

/// سطر تفصيلي «مفتاح: قيمة»
class DetailRow extends StatelessWidget {
  final IconData? icon;
  final String label;
  final String value;
  final Color? valueColor;
  final VoidCallback? onTap;

  const DetailRow({
    super.key,
    this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (icon != null) ...[
            Icon(icon, size: 17, color: scheme.onSurfaceVariant),
            const SizedBox(width: 9),
          ],
          Text('$label: ',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              )),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 13.5, color: valueColor ?? scheme.onSurface),
            ),
          ),
          if (onTap != null) Icon(Icons.chevron_left, size: 18, color: scheme.outline),
        ]),
      ),
    );
  }
}

/// عنوان قسم داخل نموذج
class SectionHeader extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Widget? trailing;

  const SectionHeader(this.title, {super.key, this.icon, this.trailing});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Row(children: [
        if (icon != null) ...[
          Icon(icon, size: 19, color: scheme.primary),
          const SizedBox(width: 8),
        ],
        Text(title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: scheme.primary,
            )),
        const Spacer(),
        ?trailing,
      ]),
    );
  }
}

/// رسالة نجاح/خطأ موحّدة
void showSnack(BuildContext context, String message, {bool error = false}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Row(children: [
        Icon(
          error ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
          color: Colors.white,
          size: 20,
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
      ]),
      backgroundColor: error ? AppTheme.danger : AppTheme.success,
      duration: Duration(seconds: error ? 4 : 3),
    ));
}

/// حوار تأكيد قبل الحذف أو أي إجراء لا رجعة فيه
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'تأكيد',
  String cancelLabel = 'إلغاء',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      content: Text(message, style: const TextStyle(fontSize: 14, height: 1.5)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(cancelLabel)),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: AppTheme.danger)
              : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// مؤشر تحميل مع نص
class LoadingView extends StatelessWidget {
  final String? message;
  const LoadingView({super.key, this.message});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          if (message != null) ...[
            const SizedBox(height: 14),
            Text(message!, style: const TextStyle(fontSize: 13)),
          ],
        ]),
      );
}

/// عرض خطأ موحّد لمزوّدات Riverpod
class ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback? onRetry;

  const ErrorView(this.error, {super.key, this.onRetry});

  @override
  Widget build(BuildContext context) => EmptyState(
        icon: Icons.error_outline_rounded,
        title: 'حدث خطأ',
        subtitle: '$error',
        action: onRetry == null
            ? null
            : OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('إعادة المحاولة'),
              ),
      );
}
