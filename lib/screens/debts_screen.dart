import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_database.dart';
import '../db/repository.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../utils/formatting.dart';
import '../utils/theme.dart';
import '../widgets/common.dart';

/// ديون العملاء: تذكير بمن عليه دين، يُحذف عند السداد
class DebtsScreen extends ConsumerWidget {
  const DebtsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(debtsProvider);
    final activeOnly = ref.watch(debtActiveOnlyProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ديون العملاء'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(102),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'ابحث بالاسم أو الهاتف أو السبب',
                  prefixIcon: Icon(Icons.search_rounded),
                  isDense: true,
                ),
                onChanged: (v) =>
                    ref.read(debtSearchProvider.notifier).state = v,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('القائمة فقط')),
                  ButtonSegment(value: false, label: Text('الكل')),
                ],
                selected: {activeOnly},
                onSelectionChanged: (s) =>
                    ref.read(debtActiveOnlyProvider.notifier).state = s.first,
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
        child: async.when(
          loading: () => const LoadingView(),
          error: (e, _) => ErrorView(e, onRetry: () => bumpRefresh(ref)),
          data: (debts) {
            if (debts.isEmpty) {
              return ListView(children: [
                const SizedBox(height: 60),
                EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: activeOnly ? 'لا توجد ديون قائمة' : 'لا توجد ديون',
                  subtitle:
                      'سجّل هنا من عليه دين لك، ليبقى تذكيرًا حتى يُسدَّد',
                  action: FilledButton.icon(
                    onPressed: () => _addDebt(context, ref),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('إضافة دين'),
                  ),
                ),
              ]);
            }

            final total = debts.fold(0.0, (s, d) => s + d.remaining);
            final overdue = debts.where((d) => d.isOverdue).length;

            return ListView(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 90),
              children: [
                Row(children: [
                  Expanded(
                    child: StatCard(
                      label: 'عدد المدينين',
                      value: '${debts.where((d) => !d.isPaidOff).length}',
                      icon: Icons.people_outline_rounded,
                      color: AppTheme.seed,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatCard(
                      label: 'متأخرة',
                      value: '$overdue',
                      icon: Icons.warning_amber_rounded,
                      color: overdue > 0 ? AppTheme.danger : AppTheme.success,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatCard(
                      label: 'إجمالي الديون',
                      value: Fmt.moneyShort(total),
                      icon: Icons.account_balance_wallet_rounded,
                      color: total > 0.009 ? AppTheme.warning : AppTheme.success,
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                ...debts.map((d) => _DebtCard(debt: d)),
              ],
            );
          },
        ),
      ),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addDebt(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('دين جديد'),
      ),
    );
  }

  Future<void> _addDebt(BuildContext context, WidgetRef ref) async {
    final result = await DebtEditorSheet.show(context);
    if (result == null || !context.mounted) return;
    await Repository.instance.saveDebt(result);
    if (!context.mounted) return;
    bumpRefresh(ref);
    showSnack(context, 'تم تسجيل الدين');
  }
}

class _DebtCard extends ConsumerWidget {
  final DebtRecord debt;
  const _DebtCard({required this.debt});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final paidOff = debt.isPaidOff;
    final overdue = debt.isOverdue;
    final color =
        paidOff ? AppTheme.success : (overdue ? AppTheme.danger : AppTheme.warning);

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: overdue
              ? AppTheme.danger.withValues(alpha: 0.5)
              : scheme.outlineVariant.withValues(alpha: 0.5),
          width: overdue ? 1.4 : 1,
        ),
      ),
      child: InkWell(
        onTap: () async {
          final result = await DebtEditorSheet.show(context, existing: debt);
          if (result == null || !context.mounted) return;
          await Repository.instance.saveDebt(result);
          if (!context.mounted) return;
          bumpRefresh(ref);
          showSnack(context, 'تم حفظ التعديلات');
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 12, 13, 11),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(debt.personName,
                          style: const TextStyle(
                              fontSize: 15.5, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(
                        [
                          Fmt.date(debt.date),
                          if (debt.personPhone.isNotEmpty) debt.personPhone,
                          if (debt.personAddress.isNotEmpty) debt.personAddress,
                        ].join('  •  '),
                        style: TextStyle(
                            fontSize: 11.5, color: scheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ]),
              ),
              if (paidOff)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('مسدَّد',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.success)),
                ),
            ]),

            if (debt.reason.isNotEmpty) ...[
              const SizedBox(height: 7),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.info_outline_rounded, size: 14, color: scheme.outline),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(debt.reason,
                      style: const TextStyle(fontSize: 12.5),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ),
              ]),
            ],

            if (debt.dueDate != null) ...[
              const SizedBox(height: 6),
              Row(children: [
                Icon(
                  overdue ? Icons.warning_amber_rounded : Icons.event_rounded,
                  size: 14,
                  color: overdue ? AppTheme.danger : scheme.outline,
                ),
                const SizedBox(width: 5),
                Text(
                  overdue
                      ? 'متأخر! كان الاستحقاق ${Fmt.date(debt.dueDate!)}'
                      : 'الاستحقاق: ${Fmt.date(debt.dueDate!)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: overdue ? FontWeight.w700 : FontWeight.w500,
                    color: overdue ? AppTheme.danger : scheme.onSurfaceVariant,
                  ),
                ),
              ]),
            ],

            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Row(children: [
                Expanded(
                  child: MoneyBadge(label: 'الدين', value: debt.amount),
                ),
                if (debt.paid > 0.009)
                  Expanded(
                    child: MoneyBadge(
                      label: 'المسدَّد',
                      value: debt.paid,
                      color: AppTheme.success,
                    ),
                  ),
                Expanded(
                  child: MoneyBadge(
                    label: 'المتبقي',
                    value: debt.remaining,
                    color: color,
                    bold: true,
                  ),
                ),
              ]),
            ),

            const SizedBox(height: 9),
            Row(children: [
              if (!paidOff)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _recordPayment(context, ref),
                    icon: const Icon(Icons.payments_rounded, size: 17),
                    label: const Text('تسجيل سداد'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 38),
                      textStyle: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ),
              if (!paidOff) const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => _deleteDebt(context, ref),
                  icon: const Icon(Icons.check_circle_rounded, size: 17),
                  label: Text(paidOff ? 'حذف' : 'سدَّد وحذف'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 38),
                    textStyle: const TextStyle(fontSize: 12.5),
                    backgroundColor: AppTheme.success.withValues(alpha: 0.15),
                    foregroundColor: AppTheme.success,
                  ),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  /// تسجيل سداد على الدين، مع قيد في الصندوق يوضّح مصدر المال
  Future<void> _recordPayment(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<_DebtPaymentInput>(
      context: context,
      builder: (ctx) => _DebtPaymentDialog(debt: debt),
    );

    if (result == null || result.amount <= 0 || !context.mounted) return;
    final amount = result.amount;

    // نسجّل السداد يدويًا على الدين
    final updated = debt.copyWith(
      paid: debt.paid + amount,
      manualPaid: debt.manualPaid + amount,
    );
    await Repository.instance.saveDebt(updated);

    // ونسجّل قيدًا في الصندوق ليظهر من أين جاء هذا المال في يومه
    if (result.recordInCash) {
      final now = DateTime.now();
      await Repository.instance.saveCashEntry(CashEntry(
        id: AppDatabase.newId(),
        direction: CashDirection.income,
        categoryKey: CashCategory.debtPayment.key,
        categoryLabel: CashCategory.debtPayment.label,
        description: 'تحصيل دين من ${debt.personName}',
        partyName: debt.personName,
        amount: amount,
        method: result.method,
        date: result.date,
        notes: debt.reason.isEmpty ? '' : 'عن: ${debt.reason}',
        createdAt: now,
        updatedAt: now,
      ));
    }

    if (!context.mounted) return;
    bumpRefresh(ref);

    if (updated.isPaidOff) {
      final remove = await confirmDialog(
        context,
        title: 'اكتمل السداد',
        message:
            'سدَّد ${debt.personName} كامل الدين.\n\nهل تريد حذف السجل من قائمة التذكير؟',
        confirmLabel: 'حذف',
        cancelLabel: 'إبقاء',
      );
      if (remove && context.mounted) {
        await Repository.instance.deleteDebt(debt.id);
        if (!context.mounted) return;
        bumpRefresh(ref);
        showSnack(context, 'تم حذف الدين المسدَّد');
        return;
      }
    }

    if (context.mounted) showSnack(context, 'تم تسجيل السداد');
  }

  Future<void> _deleteDebt(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(
      context,
      title: 'حذف الدين',
      message: debt.isPaidOff
          ? 'سيتم حذف سجل ${debt.personName} نهائيًا.'
          : 'سيتم اعتبار دين ${debt.personName} مسدَّدًا وحذفه من قائمة التذكير.\n'
              'المتبقي حاليًا: ${Fmt.money(debt.remaining)}',
      confirmLabel: 'حذف',
      destructive: true,
    );
    if (!ok || !context.mounted) return;

    await Repository.instance.deleteDebt(debt.id);
    if (!context.mounted) return;
    bumpRefresh(ref);
    showSnack(context, 'تم حذف الدين');
  }
}

/// إضافة أو تعديل دين
class DebtEditorSheet extends StatefulWidget {
  final DebtRecord? existing;

  const DebtEditorSheet({super.key, this.existing});

  static Future<DebtRecord?> show(BuildContext context,
          {DebtRecord? existing}) =>
      showModalBottomSheet<DebtRecord>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => DebtEditorSheet(existing: existing),
      );

  @override
  State<DebtEditorSheet> createState() => _DebtEditorSheetState();
}

class _DebtEditorSheetState extends State<DebtEditorSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  late final TextEditingController _amount;
  late final TextEditingController _paid;
  late final TextEditingController _reason;
  late final TextEditingController _notes;
  late DateTime _date;
  DateTime? _dueDate;

  @override
  void initState() {
    super.initState();
    final d = widget.existing;
    _name = TextEditingController(text: d?.personName ?? '');
    _phone = TextEditingController(text: d?.personPhone ?? '');
    _address = TextEditingController(text: d?.personAddress ?? '');
    _amount =
        TextEditingController(text: (d?.amount ?? 0) == 0 ? '' : '${d!.amount}');
    _paid = TextEditingController(text: (d?.paid ?? 0) == 0 ? '' : '${d!.paid}');
    _reason = TextEditingController(text: d?.reason ?? '');
    _notes = TextEditingController(text: d?.notes ?? '');
    _date = d?.date ?? DateTime.now();
    _dueDate = d?.dueDate;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _amount.dispose();
    _paid.dispose();
    _reason.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final d = widget.existing;
    final now = DateTime.now();

    Navigator.pop(
      context,
      DebtRecord(
        id: d?.id ?? AppDatabase.newId(),
        personName: _name.text.trim(),
        personPhone: _phone.text.trim(),
        personAddress: _address.text.trim(),
        amount: double.tryParse(_amount.text.trim().replaceAll(',', '')) ?? 0,
        paid: double.tryParse(_paid.text.trim().replaceAll(',', '')) ?? 0,
        reason: _reason.text.trim(),
        date: _date,
        dueDate: _dueDate,
        notes: _notes.text.trim(),
        createdAt: d?.createdAt ?? now,
        updatedAt: now,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            child: Form(
              key: _formKey,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                Row(children: [
                  const Icon(Icons.receipt_long_rounded,
                      color: AppTheme.warning),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.existing == null ? 'دين جديد' : 'تعديل الدين',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _name,
                  autofocus: widget.existing == null,
                  decoration: const InputDecoration(
                    labelText: 'اسم العميل *',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'الاسم مطلوب' : null,
                ),
                const SizedBox(height: 11),

                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.left,
                  decoration: const InputDecoration(
                    labelText: 'رقم الهاتف',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: 11),

                TextFormField(
                  controller: _address,
                  decoration: const InputDecoration(
                    labelText: 'العنوان أو معلومات إضافية',
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                ),
                const SizedBox(height: 11),

                Row(children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _amount,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.left,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.warning),
                      decoration: const InputDecoration(
                        labelText: 'مبلغ الدين *',
                        suffixText: Fmt.currencySymbol,
                      ),
                      validator: (v) {
                        final a = double.tryParse(
                            (v ?? '').trim().replaceAll(',', ''));
                        if (a == null || a <= 0) return 'أدخل مبلغًا صحيحًا';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _paid,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.left,
                      decoration: const InputDecoration(
                        labelText: 'المسدَّد',
                        suffixText: Fmt.currencySymbol,
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 11),

                TextFormField(
                  controller: _reason,
                  decoration: const InputDecoration(
                    labelText: 'سبب الدين',
                    hintText: 'بضاعة، خدمة، سلفة...',
                    prefixIcon: Icon(Icons.info_outline_rounded),
                  ),
                ),
                const SizedBox(height: 11),

                Row(children: [
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _date,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                          locale: const Locale('ar'),
                        );
                        if (picked != null) setState(() => _date = picked);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'تاريخ الدين',
                          prefixIcon: Icon(Icons.today_rounded, size: 19),
                        ),
                        child: Text(Fmt.date(_date),
                            style: const TextStyle(fontSize: 14)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate:
                              _dueDate ?? _date.add(const Duration(days: 30)),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                          locale: const Locale('ar'),
                        );
                        if (picked != null) setState(() => _dueDate = picked);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'الاستحقاق',
                          prefixIcon: const Icon(Icons.event_rounded, size: 19),
                          suffixIcon: _dueDate == null
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear_rounded,
                                      size: 17),
                                  onPressed: () =>
                                      setState(() => _dueDate = null),
                                ),
                        ),
                        child: Text(
                          _dueDate == null ? 'غير محدد' : Fmt.date(_dueDate!),
                          style: TextStyle(
                            fontSize: 14,
                            color: _dueDate == null ? scheme.outline : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 11),

                TextFormField(
                  controller: _notes,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات (اختياري)',
                    prefixIcon: Icon(Icons.sticky_note_2_outlined),
                  ),
                ),

                const SizedBox(height: 18),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('إلغاء'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('حفظ'),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// ما يُدخله المستخدم عند تسجيل سداد دين
class _DebtPaymentInput {
  final double amount;
  final PayMethod method;
  final DateTime date;

  /// هل يُسجَّل قيد في الصندوق؟ نطفئه إن كان المال لم يدخل المحل فعليًا
  final bool recordInCash;

  const _DebtPaymentInput({
    required this.amount,
    required this.method,
    required this.date,
    required this.recordInCash,
  });
}

/// حوار تسجيل سداد دين مع طريقة الدفع وتاريخه
class _DebtPaymentDialog extends StatefulWidget {
  final DebtRecord debt;
  const _DebtPaymentDialog({required this.debt});

  @override
  State<_DebtPaymentDialog> createState() => _DebtPaymentDialogState();
}

class _DebtPaymentDialogState extends State<_DebtPaymentDialog> {
  late final TextEditingController _amount;
  PayMethod _method = PayMethod.cash;
  DateTime _date = DateTime.now();
  bool _recordInCash = true;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: widget.debt.remaining.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('تسجيل سداد'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              'المتبقي على ${widget.debt.personName}: '
              '${Fmt.money(widget.debt.remaining)}',
              style: const TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(height: 14),

          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.left,
            decoration: const InputDecoration(
              labelText: 'المبلغ المسدَّد',
              suffixText: Fmt.currencySymbol,
            ),
          ),
          const SizedBox(height: 14),

          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text('طريقة الدفع',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                )),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: PayMethod.values
                .map((m) => ChoiceChip(
                      label: Text(m.label,
                          style: const TextStyle(fontSize: 12)),
                      selected: _method == m,
                      onSelected: (_) => setState(() => _method = m),
                      visualDensity: VisualDensity.compact,
                    ))
                .toList(),
          ),
          const SizedBox(height: 12),

          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
                locale: const Locale('ar'),
              );
              if (picked != null) setState(() => _date = picked);
            },
            borderRadius: BorderRadius.circular(12),
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'تاريخ السداد',
                prefixIcon: Icon(Icons.calendar_today_rounded, size: 18),
                isDense: true,
              ),
              child: Text(Fmt.date(_date),
                  style: const TextStyle(fontSize: 13.5)),
            ),
          ),

          const SizedBox(height: 6),
          CheckboxListTile(
            value: _recordInCash,
            onChanged: (v) => setState(() => _recordInCash = v ?? true),
            title: const Text('تسجيل قيد في الصندوق',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: Text(
              _recordInCash
                  ? 'سيظهر كوارد في حركات ذلك اليوم'
                  : 'لن يظهر في الصندوق ولن يؤثر على الكاش',
              style: const TextStyle(fontSize: 11.5),
            ),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
          ),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () {
            final amount =
                double.tryParse(_amount.text.trim().replaceAll(',', '')) ?? 0;
            Navigator.pop(
              context,
              _DebtPaymentInput(
                amount: amount,
                method: _method,
                date: _date,
                recordInCash: _recordInCash,
              ),
            );
          },
          child: const Text('تسجيل'),
        ),
      ],
    );
  }
}
