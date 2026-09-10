import 'package:flutter/material.dart';

import '../db/app_database.dart';
import '../models/models.dart';
import '../utils/formatting.dart';
import '../utils/theme.dart';

/// إضافة أو تعديل دفعة مالية
class PaymentEditorSheet extends StatefulWidget {
  final Payment? existing;
  final double? suggestedAmount;
  final String? visitId;
  final String? creditId;

  const PaymentEditorSheet({
    super.key,
    this.existing,
    this.suggestedAmount,
    this.visitId,
    this.creditId,
  });

  static Future<Payment?> show(
    BuildContext context, {
    Payment? existing,
    double? suggestedAmount,
    String? visitId,
    String? creditId,
  }) =>
      showModalBottomSheet<Payment>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => PaymentEditorSheet(
          existing: existing,
          suggestedAmount: suggestedAmount,
          visitId: visitId,
          creditId: creditId,
        ),
      );

  @override
  State<PaymentEditorSheet> createState() => _PaymentEditorSheetState();
}

class _PaymentEditorSheetState extends State<PaymentEditorSheet> {
  late final TextEditingController _amount;
  late final TextEditingController _notes;
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _amount = TextEditingController(
      text: e != null ? e.amount.toString() : '',
    );
    _notes = TextEditingController(text: e?.notes ?? '');
    _date = e?.date ?? DateTime.now();
  }

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _save() {
    final amount = double.tryParse(_amount.text.trim().replaceAll(',', '')) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل مبلغًا صحيحًا')),
      );
      return;
    }

    Navigator.pop(
      context,
      Payment(
        id: widget.existing?.id ?? AppDatabase.newId(),
        visitId: widget.visitId,
        creditId: widget.creditId,
        amount: amount,
        date: _date,
        notes: _notes.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final suggested = widget.suggestedAmount;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
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
                child: Text(
                  widget.existing == null ? 'إضافة دفعة' : 'تعديل الدفعة',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ]),
            const SizedBox(height: 16),

            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(
                labelText: 'المبلغ المستلم',
                prefixIcon: Icon(Icons.attach_money_rounded),
                suffixText: Fmt.currencySymbol,
              ),
            ),

            // اقتراح: سداد كامل المتبقي بضغطة
            if (suggested != null && suggested > 0.009) ...[
              const SizedBox(height: 9),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: ActionChip(
                  avatar: const Icon(Icons.done_all_rounded, size: 16),
                  label: Text('سداد كامل المتبقي: ${Fmt.moneyShort(suggested)}'),
                  onPressed: () => setState(
                    () => _amount.text = suggested.toStringAsFixed(2),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 13),

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
                  labelText: 'تاريخ الدفعة',
                  prefixIcon: Icon(Icons.calendar_today_rounded, size: 19),
                ),
                child: Text(Fmt.dateWithDay(_date), style: const TextStyle(fontSize: 14)),
              ),
            ),
            const SizedBox(height: 13),

            TextField(
              controller: _notes,
              decoration: const InputDecoration(
                labelText: 'ملاحظات (اختياري)',
                hintText: 'نقدًا، تحويل بنكي، شيك...',
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
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.success),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
