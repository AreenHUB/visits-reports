import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_database.dart';
import '../db/repository.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../utils/formatting.dart';
import '../utils/theme.dart';
import '../widgets/common.dart';

/// تسجيل حركة مالية: مبلغ دخل أو خرج من المحل خارج نطاق الزيارات
class CashFormScreen extends ConsumerStatefulWidget {
  final String? entryId;
  final DateTime? initialDate;
  final CashDirection initialDirection;

  const CashFormScreen({
    super.key,
    this.entryId,
    this.initialDate,
    this.initialDirection = CashDirection.income,
  });

  @override
  ConsumerState<CashFormScreen> createState() => _CashFormScreenState();
}

class _CashFormScreenState extends ConsumerState<CashFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _amount = TextEditingController();
  final _description = TextEditingController();
  final _party = TextEditingController();
  final _notes = TextEditingController();

  late CashDirection _direction;
  CashCategory _category = CashCategory.sale;
  PayMethod _method = PayMethod.cash;
  DateTime _date = DateTime.now();

  /// عند اختيار «تحصيل دين من عميل» نربط الحركة بسجل الدين
  DebtRecord? _linkedDebt;

  /// أو بسجل سحب آجل، إن كان الدين ناتجًا عن بضاعة مسحوبة
  CreditFull? _linkedCredit;

  String _entryId = '';
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _direction = widget.initialDirection;
    _category = CashCategory.forDirection(_direction).first;
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    _party.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.entryId == null) {
      _entryId = AppDatabase.newId();
      _date = widget.initialDate ?? DateTime.now();
      setState(() => _loading = false);
      return;
    }

    final e = await Repository.instance.cashEntryById(widget.entryId!);
    if (!mounted) return;
    if (e == null) {
      setState(() => _loading = false);
      return;
    }

    _entryId = e.id;
    _direction = e.direction;
    _category = CashCategory.byKey(e.categoryKey);
    _method = e.method;
    _date = e.date;
    _amount.text = e.amount == 0 ? '' : e.amount.toString();
    _description.text = e.description;
    _party.text = e.partyName;
    _notes.text = e.notes;

    if (e.linkedCreditId != null) {
      _linkedCredit = await Repository.instance.creditFull(e.linkedCreditId!);
    }
    if (e.linkedDebtId != null) {
      _linkedDebt = await Repository.instance.debtById(e.linkedDebtId!);
    }

    if (mounted) setState(() => _loading = false);
  }

  bool get _isDebtPayment => _category.key == CashCategory.debtPayment.key;

  void _setDirection(CashDirection d) {
    setState(() {
      _direction = d;
      // نعيد التصنيف لأول تصنيف من الاتجاه الجديد
      _category = CashCategory.forDirection(d).first;
      _linkedCredit = null;
      _linkedDebt = null;
    });
  }

  /// اختيار ما يُخصم منه التحصيل: دين عميل أو سحب آجل
  Future<void> _pickDebtSource() async {
    final debts = await Repository.instance.unpaidDebts();
    final credits = await ref.read(unsettledCreditsProvider.future);
    if (!mounted) return;

    if (debts.isEmpty && credits.isEmpty) {
      showSnack(
        context,
        'لا توجد ديون قائمة. سجّل الدين أولًا من تبويب «المزيد ← ديون العملاء»',
        error: true,
      );
      return;
    }

    final chosen = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _DebtSourcePicker(debts: debts, credits: credits),
    );
    if (chosen == null || !mounted) return;

    setState(() {
      if (chosen is DebtRecord) {
        _linkedDebt = chosen;
        _linkedCredit = null;
        if (_party.text.trim().isEmpty) _party.text = chosen.personName;
        if (_amount.text.trim().isEmpty) {
          _amount.text = chosen.remaining.toStringAsFixed(2);
        }
      } else if (chosen is CreditFull) {
        _linkedCredit = chosen;
        _linkedDebt = null;
        if (_party.text.trim().isEmpty) _party.text = chosen.credit.personName;
        if (_amount.text.trim().isEmpty) {
          _amount.text = chosen.totals.remaining.toStringAsFixed(2);
        }
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_isDebtPayment && _linkedCredit == null && _linkedDebt == null) {
      final proceed = await confirmDialog(
        context,
        title: 'بدون ربط بدين',
        message: 'لم تربط هذا التحصيل بأي دين، فلن يُخصم من رصيد أحد.\n\n'
            'هل تريد حفظه كوارد عام؟',
        confirmLabel: 'حفظ',
      );
      if (!proceed) return;
    }

    setState(() => _saving = true);

    try {
      final now = DateTime.now();
      await Repository.instance.saveCashEntry(CashEntry(
        id: _entryId,
        direction: _direction,
        categoryKey: _category.key,
        categoryLabel: _category.label,
        description: _description.text.trim(),
        partyName: _party.text.trim(),
        amount: double.tryParse(_amount.text.trim().replaceAll(',', '')) ?? 0,
        method: _method,
        date: _date,
        notes: _notes.text.trim(),
        linkedCreditId: _isDebtPayment ? _linkedCredit?.credit.id : null,
        linkedDebtId: _isDebtPayment ? _linkedDebt?.id : null,
        createdAt: now,
        updatedAt: now,
      ));

      if (!mounted) return;
      bumpRefresh(ref);
      Navigator.pop(context, true);
      showSnack(context, widget.entryId == null ? 'تم تسجيل الحركة' : 'تم حفظ التعديلات');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, 'تعذّر الحفظ: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingView());

    final isIncome = _direction == CashDirection.income;
    final color = isIncome ? AppTheme.success : AppTheme.danger;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.entryId == null ? 'حركة مالية جديدة' : 'تعديل الحركة'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4)),
            )
          else
            TextButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check_rounded, size: 19),
              label: const Text('حفظ'),
            ),
        ],
      ),

      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 100),
          children: [
            // وارد أم صادر
            SegmentedButton<CashDirection>(
              segments: const [
                ButtonSegment(
                  value: CashDirection.income,
                  label: Text('وارد (دخل)'),
                  icon: Icon(Icons.south_west_rounded, size: 18),
                ),
                ButtonSegment(
                  value: CashDirection.expense,
                  label: Text('صادر (خرج)'),
                  icon: Icon(Icons.north_east_rounded, size: 18),
                ),
              ],
              selected: {_direction},
              onSelectionChanged: (s) => _setDirection(s.first),
            ),

            const SizedBox(height: 16),

            // المبلغ
            TextFormField(
              controller: _amount,
              autofocus: widget.entryId == null,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: color),
              decoration: InputDecoration(
                labelText: 'المبلغ *',
                prefixIcon: Icon(
                  isIncome ? Icons.add_circle_outline_rounded : Icons.remove_circle_outline_rounded,
                  color: color,
                ),
                suffixText: Fmt.currencySymbol,
                fillColor: color.withValues(alpha: 0.05),
              ),
              validator: (v) {
                final amount = double.tryParse((v ?? '').trim().replaceAll(',', ''));
                if (amount == null || amount <= 0) return 'أدخل مبلغًا صحيحًا';
                return null;
              },
            ),

            // التصنيف
            SectionHeader(
              isIncome ? 'نوع الوارد' : 'نوع الصادر',
              icon: Icons.category_rounded,
            ),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: CashCategory.forDirection(_direction).map((c) {
                final sel = c.key == _category.key;
                return ChoiceChip(
                  label: Text(c.label, style: const TextStyle(fontSize: 12.5)),
                  selected: sel,
                  onSelected: (_) => setState(() {
                    _category = c;
                    if (c.key != CashCategory.debtPayment.key) _linkedCredit = null;
                  }),
                );
              }).toList(),
            ),

            // ربط التحصيل بدين عميل أو بسحب آجل
            if (_isDebtPayment) ...[
              const SizedBox(height: 12),
              _LinkedDebtBox(
                debt: _linkedDebt,
                credit: _linkedCredit,
                onPick: _pickDebtSource,
                onClear: () => setState(() {
                  _linkedDebt = null;
                  _linkedCredit = null;
                }),
              ),
            ],

            // التفاصيل
            const SectionHeader('التفاصيل', icon: Icons.description_rounded),

            TextFormField(
              controller: _description,
              decoration: InputDecoration(
                labelText: 'البيان',
                hintText: isIncome
                    ? 'بيع كاميرا، رسوم رخصة، سداد دين...'
                    : 'شراء بضاعة، وقود، إيجار...',
                prefixIcon: const Icon(Icons.notes_rounded),
              ),
            ),
            const SizedBox(height: 11),

            TextFormField(
              controller: _party,
              decoration: InputDecoration(
                labelText: isIncome ? 'اسم الزبون (اختياري)' : 'الجهة / المورّد (اختياري)',
                prefixIcon: const Icon(Icons.person_outline_rounded),
              ),
            ),

            // طريقة الدفع
            const SectionHeader('طريقة الدفع', icon: Icons.credit_card_rounded),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: PayMethod.values.map((m) {
                final sel = m == _method;
                return ChoiceChip(
                  avatar: Icon(_methodIcon(m), size: 15),
                  label: Text(m.label, style: const TextStyle(fontSize: 12.5)),
                  selected: sel,
                  onSelected: (_) => setState(() => _method = m),
                );
              }).toList(),
            ),

            // التاريخ
            const SectionHeader('التاريخ والوقت', icon: Icons.calendar_month_rounded),
            Row(children: [
              Expanded(
                flex: 3,
                child: InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                      locale: const Locale('ar'),
                    );
                    if (picked == null) return;
                    setState(() => _date = DateTime(picked.year, picked.month,
                        picked.day, _date.hour, _date.minute));
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'التاريخ',
                      prefixIcon: Icon(Icons.calendar_today_rounded, size: 19),
                    ),
                    child: Text(Fmt.dateWithDay(_date),
                        style: const TextStyle(fontSize: 14)),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                flex: 2,
                child: InkWell(
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(_date),
                    );
                    if (picked == null) return;
                    setState(() => _date = DateTime(_date.year, _date.month,
                        _date.day, picked.hour, picked.minute));
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'الوقت',
                      prefixIcon: Icon(Icons.access_time_rounded, size: 19),
                    ),
                    child: Text(Fmt.time(_date), style: const TextStyle(fontSize: 14)),
                  ),
                ),
              ),
            ]),

            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'ملاحظات (اختياري)',
                prefixIcon: Icon(Icons.sticky_note_2_outlined),
              ),
            ),
          ],
        ),
      ),

      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_rounded),
              label: Text(isIncome ? 'حفظ الوارد' : 'حفظ الصادر'),
              style: FilledButton.styleFrom(backgroundColor: color),
            ),
          ),
        ),
      ),
    );
  }

  static IconData _methodIcon(PayMethod m) => switch (m) {
        PayMethod.cash => Icons.payments_rounded,
        PayMethod.card => Icons.credit_card_rounded,
        PayMethod.transfer => Icons.account_balance_rounded,
        PayMethod.cheque => Icons.receipt_long_rounded,
        PayMethod.other => Icons.more_horiz_rounded,
      };
}


/// صندوق يوضّح بأي دين ارتبط هذا التحصيل
class _LinkedDebtBox extends StatelessWidget {
  final DebtRecord? debt;
  final CreditFull? credit;
  final VoidCallback onPick;
  final VoidCallback onClear;

  const _LinkedDebtBox({
    required this.debt,
    required this.credit,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (debt == null && credit == null) {
      return Column(children: [
        OutlinedButton.icon(
          onPressed: onPick,
          icon: const Icon(Icons.link_rounded, size: 19),
          label: const Text('اربط بدين على عميل (اختياري)'),
          style:
              OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
        ),
        const SizedBox(height: 6),
        Text(
          'الربط يخصم المبلغ من رصيد ذلك الدين تلقائيًا',
          style: TextStyle(fontSize: 11.5, color: scheme.outline),
        ),
      ]);
    }

    final name = debt?.personName ?? credit!.credit.personName;
    final remaining = debt?.remaining ?? credit!.totals.remaining;
    final kind = debt != null ? 'دين عميل' : 'سحب آجل';

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: AppTheme.info.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.info.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        const Icon(Icons.link_rounded, size: 19, color: AppTheme.info),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('مرتبط بـ $kind',
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.info)),
            Text(name,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            Text(
              'المتبقي عليه: ${Fmt.money(remaining)}',
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
          ]),
        ),
        IconButton(
          icon: const Icon(Icons.close_rounded, size: 19),
          onPressed: onClear,
          visualDensity: VisualDensity.compact,
        ),
      ]),
    );
  }
}

/// اختيار مصدر الدين: من ديون العملاء أو من السحوبات الآجلة
class _DebtSourcePicker extends StatelessWidget {
  final List<DebtRecord> debts;
  final List<CreditFull> credits;

  const _DebtSourcePicker({required this.debts, required this.credits});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      expand: false,
      builder: (context, controller) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
          child: Row(children: [
            const Expanded(
              child: Text('اختر الدين المُحصَّل',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.pop(context),
            ),
          ]),
        ),
        Expanded(
          child: ListView(controller: controller, children: [
            if (debts.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                child: Text('ديون العملاء',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: scheme.primary,
                    )),
              ),
              ...debts.map((d) => ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppTheme.warning.withValues(alpha: 0.15),
                      child: Text(
                        d.personName.isEmpty
                            ? '?'
                            : d.personName.characters.first,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.warning),
                      ),
                    ),
                    title: Text(d.personName,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      [
                        Fmt.date(d.date),
                        if (d.reason.isNotEmpty) d.reason,
                      ].join(' — '),
                      style: const TextStyle(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('المتبقي', style: TextStyle(fontSize: 10.5)),
                        Text(Fmt.moneyShort(d.remaining),
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.danger)),
                      ],
                    ),
                    onTap: () => Navigator.pop(context, d),
                  )),
            ],
            if (credits.isNotEmpty) ...[
              const Divider(height: 20),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                child: Text('السحوبات الآجلة',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: scheme.primary,
                    )),
              ),
              ...credits.map((c) => ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppTheme.info.withValues(alpha: 0.15),
                      child: Text(
                        c.credit.personName.isEmpty
                            ? '?'
                            : c.credit.personName.characters.first,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, color: AppTheme.info),
                      ),
                    ),
                    title: Text(c.credit.personName,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      '${Fmt.date(c.credit.date)} — ${c.items.length} قطعة',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('المتبقي', style: TextStyle(fontSize: 10.5)),
                        Text(Fmt.moneyShort(c.totals.remaining),
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.danger)),
                      ],
                    ),
                    onTap: () => Navigator.pop(context, c),
                  )),
            ],
          ]),
        ),
      ]),
    );
  }
}
