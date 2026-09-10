import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_database.dart';
import '../db/repository.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../utils/formatting.dart';
import '../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/item_editor.dart';
import '../widgets/payment_editor.dart';
import 'scanner_screen.dart';

/// تسجيل سحب قطع بالآجل من المحل
class CreditFormScreen extends ConsumerStatefulWidget {
  final String? creditId;
  const CreditFormScreen({super.key, this.creditId});

  @override
  ConsumerState<CreditFormScreen> createState() => _CreditFormScreenState();
}

class _CreditFormScreenState extends ConsumerState<CreditFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _notes = TextEditingController();

  DateTime _date = DateTime.now();
  DateTime? _dueDate;
  bool _settled = false;
  String _creditId = '';

  final List<Item> _items = [];
  final List<Payment> _payments = [];

  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.creditId == null) {
      _creditId = AppDatabase.newId();
      setState(() => _loading = false);
      return;
    }

    final cf = await Repository.instance.creditFull(widget.creditId!);
    if (!mounted) return;
    if (cf == null) {
      setState(() => _loading = false);
      return;
    }

    final c = cf.credit;
    _creditId = c.id;
    _name.text = c.personName;
    _phone.text = c.personPhone;
    _notes.text = c.notes;
    _date = c.date;
    _dueDate = c.dueDate;
    _settled = c.settled;
    _items
      ..clear()
      ..addAll(cf.items);
    _payments
      ..clear()
      ..addAll(cf.payments);

    setState(() => _loading = false);
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Totals get _totals => Totals(
        itemsTotal:
            _items.where((i) => i.kind == MovementKind.out).fold(0.0, (s, i) => s + i.total),
        returnedTotal: _items
            .where((i) => i.kind == MovementKind.returned)
            .fold(0.0, (s, i) => s + i.total),
        paid: _payments.fold(0.0, (s, p) => s + p.amount),
      );

  Future<void> _scanItems() async {
    final existing = _items.map((i) => i.serial).where((s) => s.isNotEmpty).toSet();
    final serials = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => ScannerScreen(continuous: true, existing: existing),
      ),
    );
    if (serials == null || serials.isEmpty || !mounted) return;

    for (final serial in serials) {
      if (!mounted) return;
      final draft = Item(
        id: AppDatabase.newId(),
        creditId: _creditId,
        serial: serial,
        typeKey: 'other',
        typeLabel: 'أخرى',
        sortOrder: _items.length,
        createdAt: DateTime.now(),
      );
      final result = await ItemEditorSheet.show(context, item: draft, isNew: true);
      if (result != null) {
        setState(() => _items.add(result));
        _markDirty();
      }
    }
  }

  Future<void> _addManualItem() async {
    final draft = Item(
      id: AppDatabase.newId(),
      creditId: _creditId,
      typeKey: 'other',
      typeLabel: 'أخرى',
      sortOrder: _items.length,
      createdAt: DateTime.now(),
    );
    final result = await ItemEditorSheet.show(context, item: draft, isNew: true);
    if (result == null) return;
    setState(() => _items.add(result));
    _markDirty();
  }

  Future<void> _editItem(int i) async {
    final result = await ItemEditorSheet.show(context, item: _items[i]);
    if (result == null) return;
    setState(() => _items[i] = result);
    _markDirty();
  }

  Future<void> _deleteItem(int i) async {
    final ok = await confirmDialog(
      context,
      title: 'حذف القطعة',
      message: 'هل تريد حذف «${_items[i].description}»؟',
      confirmLabel: 'حذف',
      destructive: true,
    );
    if (!ok) return;
    setState(() => _items.removeAt(i));
    _markDirty();
  }

  Future<void> _addPayment() async {
    final remaining = _totals.remaining;
    final result = await PaymentEditorSheet.show(
      context,
      suggestedAmount: remaining > 0 ? remaining : null,
      creditId: _creditId,
    );
    if (result == null) return;
    setState(() {
      _payments.add(result);
      // إذا سُدّد كامل المبلغ نعلّم السجل تلقائيًا كمسدَّد
      if (_totals.remaining <= 0.009) _settled = true;
    });
    _markDirty();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final repo = Repository.instance;
      final now = DateTime.now();

      await repo.saveCredit(CreditRecord(
        id: _creditId,
        personName: _name.text.trim(),
        personPhone: _phone.text.trim(),
        date: _date,
        dueDate: _dueDate,
        notes: _notes.text.trim(),
        settled: _settled,
        createdAt: now,
        updatedAt: now,
      ));
      await repo.replaceItems(creditId: _creditId, items: _items);
      await repo.replacePayments(creditId: _creditId, payments: _payments);

      if (!mounted) return;
      bumpRefresh(ref);
      Navigator.pop(context, true);
      showSnack(context, widget.creditId == null ? 'تم تسجيل السحب' : 'تم حفظ التعديلات');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, 'تعذّر الحفظ: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingView());

    final totals = _totals;
    final scheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await confirmDialog(
          context,
          title: 'تجاهل التعديلات؟',
          message: 'لديك تعديلات لم تُحفظ.',
          confirmLabel: 'خروج',
          cancelLabel: 'متابعة',
          destructive: true,
        );
        if (ok && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.creditId == null ? 'سحب آجل جديد' : 'تعديل السحب'),
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
          onChanged: _markDirty,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 100),
            children: [
              const SectionHeader('بيانات المتعامل', icon: Icons.person_rounded),

              TextFormField(
                controller: _name,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'اسم الشخص *',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'الاسم مطلوب' : null,
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

              const SectionHeader('التواريخ', icon: Icons.calendar_month_rounded),

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
                      if (picked != null) {
                        setState(() => _date = picked);
                        _markDirty();
                      }
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'تاريخ السحب',
                        prefixIcon: Icon(Icons.today_rounded, size: 19),
                      ),
                      child: Text(Fmt.date(_date), style: const TextStyle(fontSize: 14)),
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _dueDate ?? _date.add(const Duration(days: 30)),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                        locale: const Locale('ar'),
                      );
                      if (picked != null) {
                        setState(() => _dueDate = picked);
                        _markDirty();
                      }
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'تاريخ الاستحقاق',
                        prefixIcon: const Icon(Icons.event_rounded, size: 19),
                        suffixIcon: _dueDate == null
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 17),
                                onPressed: () {
                                  setState(() => _dueDate = null);
                                  _markDirty();
                                },
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

              // القطع
              SectionHeader(
                'القطع المسحوبة (${_items.length})',
                icon: Icons.inventory_2_rounded,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton.filledTonal(
                    onPressed: _addManualItem,
                    icon: const Icon(Icons.add_rounded, size: 20),
                    tooltip: 'إضافة يدوية',
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 6),
                  FilledButton.icon(
                    onPressed: _scanItems,
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                    label: const Text('مسح'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 38),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                  ),
                ]),
              ),

              if (_items.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 22),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Text('لم تُضف قطع بعد',
                      style: TextStyle(color: scheme.outline, fontSize: 13)),
                )
              else
                ...List.generate(
                  _items.length,
                  (i) => ItemTile(
                    item: _items[i],
                    index: i,
                    onTap: () => _editItem(i),
                    onDelete: () => _deleteItem(i),
                  ),
                ),

              // الدفعات
              SectionHeader(
                'الدفعات (${_payments.length})',
                icon: Icons.payments_rounded,
                trailing: FilledButton.tonalIcon(
                  onPressed: _addPayment,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('إضافة دفعة'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    textStyle: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ),

              if (_payments.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Text(
                    totals.net > 0 ? 'المستحق: ${Fmt.money(totals.net)}' : 'لا دفعات',
                    style: TextStyle(color: scheme.outline, fontSize: 13),
                  ),
                )
              else
                ...List.generate(_payments.length, (i) {
                  final p = _payments[i];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.success.withValues(alpha: 0.22)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.payments_rounded, size: 19, color: AppTheme.success),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(Fmt.money(p.amount),
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w800)),
                          Text(
                            p.notes.isEmpty
                                ? Fmt.date(p.date)
                                : '${Fmt.date(p.date)} — ${p.notes}',
                            style:
                                TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                          ),
                        ]),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.delete_outline_rounded,
                            size: 19, color: scheme.outline),
                        onPressed: () {
                          setState(() => _payments.removeAt(i));
                          _markDirty();
                        },
                      ),
                    ]),
                  );
                }),

              const SectionHeader('الحالة والملاحظات', icon: Icons.info_outline_rounded),

              SwitchListTile(
                value: _settled,
                onChanged: (v) {
                  setState(() => _settled = v);
                  _markDirty();
                },
                title: const Text('تم السداد بالكامل',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: Text(
                  _settled ? 'لن يظهر ضمن الديون المستحقة' : 'سيظهر ضمن الديون المستحقة',
                  style: const TextStyle(fontSize: 12),
                ),
                secondary: Icon(
                  _settled ? Icons.check_circle_rounded : Icons.pending_rounded,
                  color: _settled ? AppTheme.success : AppTheme.warning,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 6),
              ),
              const SizedBox(height: 8),

              TextFormField(
                controller: _notes,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات',
                  hintText: 'أي تفاصيل عن هذا السحب...',
                  alignLabelWithHint: true,
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
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TotalsRow(totals, compact: true),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.save_rounded),
                    label: const Text('حفظ السحب'),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
