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

/// إضافة أو تعديل زيارة
class VisitFormScreen extends ConsumerStatefulWidget {
  /// معرّف زيارة قائمة للتعديل، أو null لزيارة جديدة
  final String? visitId;

  /// تاريخ مبدئي للزيارة الجديدة
  final DateTime? initialDate;

  const VisitFormScreen({super.key, this.visitId, this.initialDate});

  @override
  ConsumerState<VisitFormScreen> createState() => _VisitFormScreenState();
}

class _VisitFormScreenState extends ConsumerState<VisitFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _purpose = TextEditingController();
  final _reason = TextEditingController();
  final _notes = TextEditingController();

  DateTime _date = DateTime.now();
  VisitStatus _status = VisitStatus.done;
  String _customerId = '';
  String _visitId = '';

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
    _address.dispose();
    _purpose.dispose();
    _reason.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.visitId == null) {
      _visitId = AppDatabase.newId();
      _date = widget.initialDate ?? DateTime.now();
      setState(() => _loading = false);
      return;
    }

    final vf = await Repository.instance.visitFull(widget.visitId!);
    if (!mounted) return;

    if (vf == null) {
      setState(() => _loading = false);
      return;
    }

    final v = vf.visit;
    _visitId = v.id;
    _customerId = v.customerId;
    _name.text = v.customerName;
    _phone.text = v.customerPhone;
    _address.text = v.customerAddress;
    _purpose.text = v.purpose;
    _reason.text = v.notDoneReason;
    _notes.text = v.dayNotes;
    _date = v.date;
    _status = v.status;
    _items
      ..clear()
      ..addAll(vf.items);
    _payments
      ..clear()
      ..addAll(vf.payments);

    setState(() => _loading = false);
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Totals get _totals => Totals(
        itemsTotal: _items
            .where((i) => i.kind == MovementKind.out)
            .fold(0.0, (s, i) => s + i.total),
        returnedTotal: _items
            .where((i) => i.kind == MovementKind.returned)
            .fold(0.0, (s, i) => s + i.total),
        paid: _payments.fold(0.0, (s, p) => s + p.amount),
      );

  // ----------------------------------------------------------- اختيار العميل

  Future<void> _pickCustomer() async {
    final customers = await Repository.instance.customers();
    if (!mounted) return;

    final chosen = await showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CustomerPicker(customers: customers),
    );
    if (chosen == null) return;

    setState(() {
      _customerId = chosen.id;
      _name.text = chosen.name;
      _phone.text = chosen.phone;
      _address.text = chosen.address;
    });
    _markDirty();
  }

  // ------------------------------------------------------------- القطع

  /// يفتح الماسح ثم يمرّ على كل سيريال ليُسأل عن نوعه
  Future<void> _scanItems() async {
    final existing = _items.map((i) => i.serial).where((s) => s.isNotEmpty).toSet();

    final serials = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => ScannerScreen(continuous: true, existing: existing),
      ),
    );
    if (serials == null || serials.isEmpty || !mounted) return;

    // نمر على السيريالات واحدًا واحدًا: لكل واحد نفتح المحرّر مع الاقتراح
    for (var idx = 0; idx < serials.length; idx++) {
      if (!mounted) return;

      final serial = serials[idx];
      final draft = Item(
        id: AppDatabase.newId(),
        visitId: _visitId,
        serial: serial,
        typeKey: 'other',
        typeLabel: 'أخرى',
        sortOrder: _items.length,
        createdAt: DateTime.now(),
      );

      // نعرض تقدّم المعالجة في شريط علوي
      final result = await ItemEditorSheet.show(context, item: draft, isNew: true);
      if (result != null) {
        setState(() => _items.add(result));
        _markDirty();
      }
    }

    if (mounted && serials.isNotEmpty) {
      showSnack(context, 'تمت إضافة ${_items.length} قطعة');
    }
  }

  Future<void> _addManualItem() async {
    final draft = Item(
      id: AppDatabase.newId(),
      visitId: _visitId,
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

  Future<void> _editItem(int index) async {
    final result = await ItemEditorSheet.show(context, item: _items[index]);
    if (result == null) return;
    setState(() => _items[index] = result);
    _markDirty();
  }

  Future<void> _deleteItem(int index) async {
    final ok = await confirmDialog(
      context,
      title: 'حذف القطعة',
      message: 'هل تريد حذف «${_items[index].description}» من هذه الزيارة؟',
      confirmLabel: 'حذف',
      destructive: true,
    );
    if (!ok) return;
    setState(() => _items.removeAt(index));
    _markDirty();
  }

  // ---------------------------------------------------------- الدفعات

  Future<void> _addPayment() async {
    final remaining = _totals.remaining;
    final result = await PaymentEditorSheet.show(
      context,
      suggestedAmount: remaining > 0 ? remaining : null,
      visitId: _visitId,
    );
    if (result == null) return;
    setState(() => _payments.add(result));
    _markDirty();
  }

  Future<void> _editPayment(int index) async {
    final result = await PaymentEditorSheet.show(
      context,
      existing: _payments[index],
      visitId: _visitId,
    );
    if (result == null) return;
    setState(() => _payments[index] = result);
    _markDirty();
  }

  void _deletePayment(int index) {
    setState(() => _payments.removeAt(index));
    _markDirty();
  }

  // ------------------------------------------------------------ الحفظ

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final repo = Repository.instance;

      // نربط الزيارة بعميل: القائم أو ننشئ واحدًا جديدًا
      var customerId = _customerId;
      if (customerId.isEmpty) {
        final c = await repo.findOrCreateCustomer(
          name: _name.text.trim(),
          phone: _phone.text.trim(),
          address: _address.text.trim(),
        );
        customerId = c.id;
      } else {
        // نحدّث بيانات العميل إن عدّلها المستخدم هنا
        final existing = await repo.customerById(customerId);
        if (existing != null) {
          await repo.saveCustomer(existing.copyWith(
            name: _name.text.trim(),
            phone: _phone.text.trim(),
            address: _address.text.trim(),
          ));
        }
      }

      final now = DateTime.now();
      final visit = Visit(
        id: _visitId,
        customerId: customerId,
        customerName: _name.text.trim(),
        customerPhone: _phone.text.trim(),
        customerAddress: _address.text.trim(),
        date: _date,
        purpose: _purpose.text.trim(),
        status: _status,
        notDoneReason: _status == VisitStatus.notDone ? _reason.text.trim() : '',
        dayNotes: _notes.text.trim(),
        createdAt: widget.visitId == null ? now : now,
        updatedAt: now,
      );

      await repo.saveVisit(visit);
      await repo.replaceItems(visitId: _visitId, items: _items);
      await repo.replacePayments(visitId: _visitId, payments: _payments);

      if (!mounted) return;
      bumpRefresh(ref);
      Navigator.pop(context, true);
      showSnack(context, widget.visitId == null ? 'تمت إضافة الزيارة' : 'تم حفظ التعديلات');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, 'تعذّر الحفظ: $e', error: true);
    }
  }

  Future<bool> _confirmExit() async {
    if (!_dirty) return true;
    return confirmDialog(
      context,
      title: 'تجاهل التعديلات؟',
      message: 'لديك تعديلات لم تُحفظ. هل تريد الخروج دون حفظ؟',
      confirmLabel: 'خروج',
      cancelLabel: 'متابعة التعديل',
      destructive: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: LoadingView(message: 'جارٍ التحميل...'));
    }

    final scheme = Theme.of(context).colorScheme;
    final totals = _totals;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final canExit = await _confirmExit();
        if (canExit && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.visitId == null ? 'زيارة جديدة' : 'تعديل الزيارة'),
          actions: [
            if (_saving)
              const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
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
              // ------------------------------------------------ العميل
              SectionHeader(
                'بيانات العميل',
                icon: Icons.person_rounded,
                trailing: TextButton.icon(
                  onPressed: _pickCustomer,
                  icon: const Icon(Icons.contacts_rounded, size: 17),
                  label: const Text('اختيار من القائمة'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ),

              TextFormField(
                controller: _name,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'الاسم *',
                  prefixIcon: Icon(Icons.badge_outlined),
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
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'رقم الهاتف',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 11),

              TextFormField(
                controller: _address,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'العنوان',
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
              ),

              // ------------------------------------------ تفاصيل الزيارة
              const SectionHeader('تفاصيل الزيارة', icon: Icons.event_note_rounded),

              _DateTimeField(
                date: _date,
                onChanged: (d) {
                  setState(() => _date = d);
                  _markDirty();
                },
              ),
              const SizedBox(height: 11),

              TextFormField(
                controller: _purpose,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'الهدف من الزيارة',
                  hintText: 'تركيب كاميرات، صيانة، معاينة...',
                  prefixIcon: Icon(Icons.flag_outlined),
                ),
              ),
              const SizedBox(height: 12),

              // حالة الزيارة
              Text('حالة الزيارة',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  )),
              const SizedBox(height: 7),
              SegmentedButton<VisitStatus>(
                segments: const [
                  ButtonSegment(value: VisitStatus.done, label: Text('تمت')),
                  ButtonSegment(value: VisitStatus.partial, label: Text('جزئية')),
                  ButtonSegment(value: VisitStatus.notDone, label: Text('لم تتم')),
                ],
                selected: {_status},
                onSelectionChanged: (s) {
                  setState(() => _status = s.first);
                  _markDirty();
                },
              ),

              if (_status == VisitStatus.notDone) ...[
                const SizedBox(height: 11),
                TextFormField(
                  controller: _reason,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'سبب عدم التنفيذ',
                    hintText: 'العميل غير موجود، تأجيل، نقص قطع...',
                    prefixIcon: const Icon(Icons.info_outline_rounded),
                    fillColor: AppTheme.danger.withValues(alpha: 0.04),
                  ),
                ),
              ],

              // ------------------------------------------------- القطع
              SectionHeader(
                'القطع (${_items.length})',
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
                _EmptyBox(
                  icon: Icons.qr_code_scanner_rounded,
                  text: 'لم تُضف قطع بعد',
                  hint: 'اضغط «مسح» لقراءة الأرقام التسلسلية بالكاميرا',
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

              // ---------------------------------------------- الدفعات
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
                _EmptyBox(
                  icon: Icons.money_off_rounded,
                  text: 'لم تُسجَّل دفعات',
                  hint: totals.net > 0
                      ? 'المستحق: ${Fmt.money(totals.net)}'
                      : 'أضف دفعة عند استلام أي مبلغ',
                )
              else
                ...List.generate(
                  _payments.length,
                  (i) => _PaymentTile(
                    payment: _payments[i],
                    onTap: () => _editPayment(i),
                    onDelete: () => _deletePayment(i),
                  ),
                ),

              // --------------------------------------------- ملاحظات
              const SectionHeader('ملاحظات اليوم', icon: Icons.sticky_note_2_rounded),
              TextFormField(
                controller: _notes,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'أي ملاحظات تريد إدراجها في التقرير...',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),

        // شريط الإجماليات السفلي
        bottomNavigationBar: _TotalsBar(totals: totals, onSave: _saving ? null : _save),
      ),
    );
  }
}

// ---------------------------------------------------------------- المكوّنات

class _TotalsBar extends StatelessWidget {
  final Totals totals;
  final VoidCallback? onSave;

  const _TotalsBar({required this.totals, this.onSave});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -2)),
        ],
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
                onPressed: onSave,
                icon: const Icon(Icons.save_rounded),
                label: const Text('حفظ الزيارة'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _DateTimeField extends StatelessWidget {
  final DateTime date;
  final ValueChanged<DateTime> onChanged;

  const _DateTimeField({required this.date, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        flex: 3,
        child: InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: date,
              firstDate: DateTime(2020),
              lastDate: DateTime(2100),
              locale: const Locale('ar'),
            );
            if (picked == null) return;
            onChanged(DateTime(
                picked.year, picked.month, picked.day, date.hour, date.minute));
          },
          borderRadius: BorderRadius.circular(12),
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'التاريخ',
              prefixIcon: Icon(Icons.calendar_today_rounded, size: 19),
            ),
            child: Text(Fmt.dateWithDay(date), style: const TextStyle(fontSize: 14)),
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
              initialTime: TimeOfDay.fromDateTime(date),
            );
            if (picked == null) return;
            onChanged(DateTime(
                date.year, date.month, date.day, picked.hour, picked.minute));
          },
          borderRadius: BorderRadius.circular(12),
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'الوقت',
              prefixIcon: Icon(Icons.access_time_rounded, size: 19),
            ),
            child: Text(Fmt.time(date), style: const TextStyle(fontSize: 14)),
          ),
        ),
      ),
    ]);
  }
}

class _PaymentTile extends StatelessWidget {
  final Payment payment;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _PaymentTile({
    required this.payment,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
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
              Text(Fmt.money(payment.amount),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              Text(
                payment.notes.isEmpty
                    ? Fmt.date(payment.date)
                    : '${Fmt.date(payment.date)} — ${payment.notes}',
                style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.delete_outline_rounded, size: 19, color: scheme.outline),
            onPressed: onDelete,
          ),
        ]),
      ),
    );
  }
}

class _EmptyBox extends StatelessWidget {
  final IconData icon;
  final String text;
  final String hint;

  const _EmptyBox({required this.icon, required this.text, required this.hint});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Column(children: [
        Icon(icon, size: 30, color: scheme.outlineVariant),
        const SizedBox(height: 8),
        Text(text,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            )),
        const SizedBox(height: 3),
        Text(hint,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: scheme.outline)),
      ]),
    );
  }
}

/// اختيار عميل من القائمة مع بحث
class _CustomerPicker extends StatefulWidget {
  final List<Customer> customers;
  const _CustomerPicker({required this.customers});

  @override
  State<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends State<_CustomerPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = _query.trim().isEmpty
        ? widget.customers
        : widget.customers
            .where((c) =>
                c.name.contains(_query) ||
                c.phone.contains(_query) ||
                c.address.contains(_query))
            .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      expand: false,
      builder: (context, controller) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(children: [
            Row(children: [
              const Expanded(
                child: Text('اختيار عميل',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
            ]),
            const SizedBox(height: 6),
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'ابحث بالاسم أو الهاتف',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ]),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const EmptyState(
                  icon: Icons.person_search_rounded,
                  title: 'لا يوجد عملاء مطابقون',
                  subtitle: 'اكتب البيانات يدويًا في النموذج',
                )
              : ListView.separated(
                  controller: controller,
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final c = filtered[i];
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          c.name.isEmpty ? '?' : c.name.characters.first,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      title: Text(c.name,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        [c.phone, c.address].where((s) => s.isNotEmpty).join(' — '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => Navigator.pop(context, c),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}
