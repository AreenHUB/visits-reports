import 'package:flutter/material.dart';

import '../utils/formatting.dart';

/// تحرير ملاحظة عامة على يوم كامل — تُرسل في أعلى التقرير للمدير
class DayNoteSheet extends StatefulWidget {
  final DateTime day;
  final String initial;

  const DayNoteSheet({super.key, required this.day, this.initial = ''});

  /// يعيد النص بعد الحفظ، أو null إن أُلغي
  static Future<String?> show(
    BuildContext context, {
    required DateTime day,
    String initial = '',
  }) =>
      showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => DayNoteSheet(day: day, initial: initial),
      );

  @override
  State<DayNoteSheet> createState() => _DayNoteSheetState();
}

class _DayNoteSheetState extends State<DayNoteSheet> {
  late final TextEditingController _controller;

  /// عبارات جاهزة تُضاف بضغطة، توفّر الكتابة المتكررة
  static const _quickPhrases = [
    'يوم هادئ',
    'ضغط عمل عالي',
    'تأخير بسبب المرور',
    'نقص في المخزون',
    'العميل أجّل الموعد',
    'تم إنجاز كل المهام',
  ];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _append(String phrase) {
    final current = _controller.text.trim();
    setState(() {
      _controller.text = current.isEmpty ? phrase : '$current\n$phrase';
      _controller.selection =
          TextSelection.collapsed(offset: _controller.text.length);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

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
              Icon(Icons.edit_note_rounded, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('ملاحظات عن هذا اليوم',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  Text(
                    Fmt.dateWithDay(widget.day),
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: 8),

            Text(
              'تظهر هذه الملاحظات في أعلى التقرير الذي ترسله للمدير',
              style: TextStyle(fontSize: 12, color: scheme.outline),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: 6,
              minLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'اكتب ملخص اليوم، أي أحداث مهمة، أو ما تريد إبلاغ المدير به...',
                alignLabelWithHint: true,
              ),
            ),

            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text('إضافة سريعة',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  )),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _quickPhrases
                  .map((p) => ActionChip(
                        label: Text(p, style: const TextStyle(fontSize: 12)),
                        onPressed: () => _append(p),
                        visualDensity: VisualDensity.compact,
                      ))
                  .toList(),
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
                  onPressed: () => Navigator.pop(context, _controller.text.trim()),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('حفظ الملاحظات'),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
