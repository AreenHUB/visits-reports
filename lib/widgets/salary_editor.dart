import 'package:flutter/material.dart';

import '../db/app_database.dart';
import '../models/models.dart';
import '../utils/formatting.dart';
import '../utils/theme.dart';

/// إضافة أو تعديل بيانات موظف
class EmployeeEditorSheet extends StatefulWidget {
  final Employee? existing;

  const EmployeeEditorSheet({super.key, this.existing});

  static Future<Employee?> show(BuildContext context, {Employee? existing}) =>
      showModalBottomSheet<Employee>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => EmployeeEditorSheet(existing: existing),
      );

  @override
  State<EmployeeEditorSheet> createState() => _EmployeeEditorSheetState();
}

class _EmployeeEditorSheetState extends State<EmployeeEditorSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _role;
  late final TextEditingController _salary;
  late final TextEditingController _notes;
  late bool _active;

  /// وظائف شائعة تُختار بضغطة
  static const _roles = ['فني', 'مساعد فني', 'سائق', 'محاسب', 'بائع', 'عامل'];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _phone = TextEditingController(text: e?.phone ?? '');
    _role = TextEditingController(text: e?.role ?? '');
    _salary = TextEditingController(
      text: (e?.monthlySalary ?? 0) == 0 ? '' : '${e!.monthlySalary}',
    );
    _notes = TextEditingController(text: e?.notes ?? '');
    _active = e?.active ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _role.dispose();
    _salary.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final now = DateTime.now();
    final e = widget.existing;

    Navigator.pop(
      context,
      Employee(
        id: e?.id ?? AppDatabase.newId(),
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        role: _role.text.trim(),
        monthlySalary:
            double.tryParse(_salary.text.trim().replaceAll(',', '')) ?? 0,
        notes: _notes.text.trim(),
        active: _active,
        createdAt: e?.createdAt ?? now,
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
                  Icon(Icons.badge_rounded, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.existing == null ? 'موظف جديد' : 'تعديل بيانات الموظف',
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
                    labelText: 'اسم الموظف *',
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
                  controller: _role,
                  decoration: const InputDecoration(
                    labelText: 'الوظيفة',
                    prefixIcon: Icon(Icons.work_outline_rounded),
                  ),
                ),
                const SizedBox(height: 7),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _roles
                        .map((r) => ActionChip(
                              label: Text(r,
                                  style: const TextStyle(fontSize: 12)),
                              onPressed: () =>
                                  setState(() => _role.text = r),
                              visualDensity: VisualDensity.compact,
                            ))
                        .toList(),
                  ),
                ),
                const SizedBox(height: 11),

                TextFormField(
                  controller: _salary,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.left,
                  decoration: const InputDecoration(
                    labelText: 'الراتب الشهري المتّفق عليه (اختياري)',
                    prefixIcon: Icon(Icons.payments_outlined),
                    suffixText: Fmt.currencySymbol,
                    helperText: 'يُستخدم لحساب المتبقي من راتب الشهر',
                  ),
                ),
                const SizedBox(height: 11),

                TextFormField(
                  controller: _notes,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات (اختياري)',
                    prefixIcon: Icon(Icons.sticky_note_2_outlined),
                  ),
                ),
                const SizedBox(height: 6),

                SwitchListTile(
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                  title: const Text('موظف نشط',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    _active
                        ? 'يظهر في أعلى القائمة'
                        : 'يبقى سجلّه محفوظًا لكنه يظهر كغير نشط',
                    style: const TextStyle(fontSize: 12),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),

                const SizedBox(height: 14),
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

/// تسجيل دفعة راتب لموظف
class SalaryPaymentSheet extends StatefulWidget {
  final Employee employee;
  final SalaryPayment? existing;

  const SalaryPaymentSheet({
    super.key,
    required this.employee,
    this.existing,
  });

  static Future<SalaryPayment?> show(
    BuildContext context, {
    required Employee employee,
    SalaryPayment? existing,
  }) =>
      showModalBottomSheet<SalaryPayment>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) =>
            SalaryPaymentSheet(employee: employee, existing: existing),
      );

  @override
  State<SalaryPaymentSheet> createState() => _SalaryPaymentSheetState();
}

class _SalaryPaymentSheetState extends State<SalaryPaymentSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _amount;
  late final TextEditingController _notes;
  late SalaryKind _kind;
  late PayMethod _method;
  late DateTime _date;
  DateTime? _forMonth;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _amount = TextEditingController(
      text: (p?.amount ?? 0) == 0 ? '' : '${p!.amount}',
    );
    _notes = TextEditingController(text: p?.notes ?? '');
    _kind = p?.kind ?? SalaryKind.partial;
    _method = p?.method ?? PayMethod.cash;
    _date = p?.date ?? DateTime.now();
    _forMonth = p?.forMonth ?? DateTime(DateTime.now().year, DateTime.now().month);
  }

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final p = widget.existing;

    Navigator.pop(
      context,
      SalaryPayment(
        id: p?.id ?? AppDatabase.newId(),
        employeeId: widget.employee.id,
        employeeName: widget.employee.name,
        amount: double.tryParse(_amount.text.trim().replaceAll(',', '')) ?? 0,
        kind: _kind,
        method: _method,
        date: _date,
        forMonth: _forMonth,
        notes: _notes.text.trim(),
        createdAt: p?.createdAt ?? DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final salary = widget.employee.monthlySalary;

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
                  const Icon(Icons.payments_rounded, color: AppTheme.success),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.existing == null
                                ? 'تسليم دفعة راتب'
                                : 'تعديل الدفعة',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w800),
                          ),
                          Text(widget.employee.name,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: scheme.onSurfaceVariant)),
                        ]),
                  ),
                ]),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _amount,
                  autofocus: widget.existing == null,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.left,
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.success),
                  decoration: const InputDecoration(
                    labelText: 'المبلغ المسلَّم *',
                    prefixIcon: Icon(Icons.attach_money_rounded),
                    suffixText: Fmt.currencySymbol,
                  ),
                  validator: (v) {
                    final a =
                        double.tryParse((v ?? '').trim().replaceAll(',', ''));
                    if (a == null || a <= 0) return 'أدخل مبلغًا صحيحًا';
                    return null;
                  },
                ),

                if (salary > 0) ...[
                  const SizedBox(height: 9),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: ActionChip(
                      avatar: const Icon(Icons.done_all_rounded, size: 16),
                      label: Text('الراتب كاملًا: ${Fmt.moneyShort(salary)}'),
                      onPressed: () => setState(() {
                        _amount.text = salary.toStringAsFixed(2);
                        _kind = SalaryKind.full;
                      }),
                    ),
                  ),
                ],

                const SizedBox(height: 14),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text('نوع الدفعة',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant,
                      )),
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: SalaryKind.values
                      .map((k) => ChoiceChip(
                            label: Text(k.label,
                                style: const TextStyle(fontSize: 12.5)),
                            selected: _kind == k,
                            onSelected: (_) => setState(() => _kind = k),
                          ))
                      .toList(),
                ),

                const SizedBox(height: 14),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text('طريقة الدفع',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant,
                      )),
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: PayMethod.values
                      .map((m) => ChoiceChip(
                            label: Text(m.label,
                                style: const TextStyle(fontSize: 12.5)),
                            selected: _method == m,
                            onSelected: (_) => setState(() => _method = m),
                          ))
                      .toList(),
                ),

                const SizedBox(height: 14),
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
                          labelText: 'تاريخ التسليم',
                          prefixIcon:
                              Icon(Icons.calendar_today_rounded, size: 19),
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
                          initialDate: _forMonth ?? _date,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                          locale: const Locale('ar'),
                          helpText: 'اختر أي يوم من الشهر',
                        );
                        if (picked != null) {
                          setState(() =>
                              _forMonth = DateTime(picked.year, picked.month));
                        }
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'عن شهر',
                          prefixIcon: const Icon(Icons.event_rounded, size: 19),
                          suffixIcon: _forMonth == null
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear_rounded,
                                      size: 17),
                                  onPressed: () =>
                                      setState(() => _forMonth = null),
                                ),
                        ),
                        child: Text(
                          _forMonth == null
                              ? 'غير محدد'
                              : Fmt.monthName(_forMonth!),
                          style: TextStyle(
                            fontSize: 13.5,
                            color: _forMonth == null ? scheme.outline : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                ]),

                const SizedBox(height: 12),
                TextFormField(
                  controller: _notes,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات (اختياري)',
                    prefixIcon: Icon(Icons.notes_rounded),
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
                      label: const Text('حفظ الدفعة'),
                      style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.success),
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
