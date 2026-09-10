import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../db/repository.dart';
import '../models/item_types.dart';
import '../models/models.dart';
import '../utils/formatting.dart';
import '../utils/theme.dart';
import 'common.dart';

/// محرّر قطعة واحدة: النوع، التفاصيل، التسمية، السعر.
///
/// يُفتح كورقة سفلية بعد قراءة السيريال، ويقترح تلقائيًا النوع والتفاصيل
/// إن سبق أن أُدخل سيريال مشابه.
class ItemEditorSheet extends StatefulWidget {
  final Item item;

  /// هل هذه قطعة جديدة (تُقترح عليها القيم) أم تعديل قطعة قائمة
  final bool isNew;

  const ItemEditorSheet({super.key, required this.item, this.isNew = false});

  /// يفتح المحرّر ويعيد القطعة بعد التعديل، أو null إن أُلغي
  static Future<Item?> show(
    BuildContext context, {
    required Item item,
    bool isNew = false,
  }) =>
      showModalBottomSheet<Item>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => ItemEditorSheet(item: item, isNew: isNew),
      );

  @override
  State<ItemEditorSheet> createState() => _ItemEditorSheetState();
}

class _ItemEditorSheetState extends State<ItemEditorSheet> {
  late Item _item;
  late final TextEditingController _serial;
  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _qty;
  late final TextEditingController _notes;

  /// اقتراح جاهز من ذاكرة السيريالات، يظهر كشريط في الأعلى
  SerialMemory? _suggestion;
  bool _suggestionApplied = false;
  bool _loadingSuggestion = false;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _serial = TextEditingController(text: _item.serial);
    _name = TextEditingController(text: _item.customName);
    _price = TextEditingController(text: _item.price == 0 ? '' : _item.price.toString());
    _qty = TextEditingController(text: '${_item.qty}');
    _notes = TextEditingController(text: _item.notes);

    if (widget.isNew && _item.serial.trim().isNotEmpty) _fetchSuggestion();
  }

  @override
  void dispose() {
    _serial.dispose();
    _name.dispose();
    _price.dispose();
    _qty.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _fetchSuggestion() async {
    setState(() => _loadingSuggestion = true);
    final s = await Repository.instance.suggestForSerial(_serial.text);
    if (!mounted) return;
    setState(() {
      _suggestion = s;
      _loadingSuggestion = false;
    });
  }

  void _applySuggestion() {
    final s = _suggestion;
    if (s == null) return;
    setState(() {
      _item = _item.copyWith(
        typeKey: s.typeKey,
        typeLabel: s.typeLabel,
        customName: s.customName,
        specs: Map<String, Object?>.from(s.specs),
        price: s.lastPrice,
      );
      _name.text = s.customName;
      if (s.lastPrice > 0) _price.text = s.lastPrice.toString();
      _suggestionApplied = true;
    });
    HapticFeedback.selectionClick();
  }

  void _setType(ItemType t) {
    setState(() {
      // تغيير النوع يمسح التفاصيل الخاصة بالنوع السابق
      _item = _item.copyWith(typeKey: t.key, typeLabel: t.label, specs: {});
    });
    HapticFeedback.selectionClick();
  }

  void _setSpec(String key, Object? value) {
    setState(() {
      final specs = Map<String, Object?>.from(_item.specs);
      if (value == null || value == false || '$value'.trim().isEmpty) {
        specs.remove(key);
      } else {
        specs[key] = value;
      }
      _item = _item.copyWith(specs: specs);
    });
  }

  void _save() {
    final price = double.tryParse(_price.text.trim().replaceAll(',', '')) ?? 0;
    final qty = int.tryParse(_qty.text.trim()) ?? 1;

    Navigator.pop(
      context,
      _item.copyWith(
        serial: _serial.text.trim(),
        customName: _name.text.trim(),
        price: price,
        qty: qty < 1 ? 1 : qty,
        notes: _notes.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final type = ItemTypes.byKey(_item.typeKey);
    final scheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Column(children: [
        // مقبض السحب والعنوان
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
          ),
          child: Column(children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Row(children: [
              Icon(_iconFor(type.key), color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.isNew ? 'إضافة قطعة' : 'تعديل القطعة',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
            ]),
          ]),
        ),

        Expanded(
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.fromLTRB(16, 12, 16, 20 + bottomInset),
            children: [
              // شريط الاقتراح
              if (_loadingSuggestion)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: LinearProgressIndicator(minHeight: 2),
                )
              else if (_suggestion != null && !_suggestionApplied)
                _SuggestionBar(
                  suggestion: _suggestion!,
                  onApply: _applySuggestion,
                  onDismiss: () => setState(() => _suggestion = null),
                )
              else if (_suggestionApplied)
                _AppliedBanner(onUndo: () {
                  setState(() {
                    _suggestionApplied = false;
                    _item = _item.copyWith(specs: {}, customName: '');
                    _name.text = '';
                  });
                }),

              // الرقم التسلسلي
              TextField(
                controller: _serial,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.left,
                decoration: InputDecoration(
                  labelText: 'الرقم التسلسلي SN',
                  prefixIcon: const Icon(Icons.qr_code_2_rounded),
                  suffixIcon: IconButton(
                    tooltip: 'بحث عن اقتراح',
                    icon: const Icon(Icons.auto_awesome_rounded),
                    onPressed: _serial.text.trim().isEmpty ? null : _fetchSuggestion,
                  ),
                ),
              ),

              const SectionHeader('نوع القطعة', icon: Icons.category_rounded),
              _TypeGrid(selected: _item.typeKey, onSelect: _setType),

              // الحقول التفصيلية حسب النوع
              if (type.fields.isNotEmpty) ...[
                SectionHeader('تفاصيل ${type.label}', icon: Icons.tune_rounded),
                ...type.fields.map((f) => _SpecFieldWidget(
                      field: f,
                      value: _item.specs[f.key],
                      onChanged: (v) => _setSpec(f.key, v),
                    )),
              ],

              const SectionHeader('التسمية والسعر', icon: Icons.sell_rounded),

              TextField(
                controller: _name,
                decoration: InputDecoration(
                  labelText: 'تسمية القطعة (اختياري)',
                  hintText: _item.description,
                  prefixIcon: const Icon(Icons.label_outline_rounded),
                  helperText: 'اتركها فارغة ليُستخدم الوصف التلقائي',
                ),
              ),
              const SizedBox(height: 12),

              Row(children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.left,
                    decoration: const InputDecoration(
                      labelText: 'السعر',
                      prefixIcon: Icon(Icons.payments_outlined),
                      suffixText: Fmt.currencySymbol,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _qty,
                    keyboardType: TextInputType.number,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.center,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'الكمية'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ]),

              const SizedBox(height: 12),

              // نوع الحركة: صادر أم راجع للمحل
              SegmentedButton<MovementKind>(
                segments: const [
                  ButtonSegment(
                    value: MovementKind.out,
                    label: Text('صادر للعميل'),
                    icon: Icon(Icons.upload_rounded, size: 18),
                  ),
                  ButtonSegment(
                    value: MovementKind.returned,
                    label: Text('راجع للمحل'),
                    icon: Icon(Icons.download_rounded, size: 18),
                  ),
                ],
                selected: {_item.kind},
                onSelectionChanged: (s) =>
                    setState(() => _item = _item.copyWith(kind: s.first)),
              ),

              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات على القطعة (اختياري)',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
              ),

              const SizedBox(height: 16),
              _PreviewCard(item: _previewItem()),
            ],
          ),
        ),

        // زر الحفظ
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(top: BorderSide(color: scheme.outlineVariant)),
          ),
          child: SafeArea(
            top: false,
            child: Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('حفظ القطعة'),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Item _previewItem() {
    final price = double.tryParse(_price.text.trim().replaceAll(',', '')) ?? 0;
    final qty = int.tryParse(_qty.text.trim()) ?? 1;
    return _item.copyWith(
      serial: _serial.text.trim(),
      customName: _name.text.trim(),
      price: price,
      qty: qty < 1 ? 1 : qty,
    );
  }
}

// ---------------------------------------------------------------- الاقتراح

class _SuggestionBar extends StatelessWidget {
  final SerialMemory suggestion;
  final VoidCallback onApply;
  final VoidCallback onDismiss;

  const _SuggestionBar({
    required this.suggestion,
    required this.onApply,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final desc = [
      suggestion.customName.isEmpty ? suggestion.typeLabel : suggestion.customName,
      suggestion.specs.values
          .where((v) => v != null && v != false && '$v'.trim().isNotEmpty)
          .map((v) => v == true ? '' : '$v')
          .where((s) => s.isNotEmpty)
          .join('، '),
    ].where((s) => s.isNotEmpty).join(' - ');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppTheme.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppTheme.info.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        const Icon(Icons.auto_awesome_rounded, color: AppTheme.info, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('اقتراح من إدخال سابق',
                style: TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w700, color: AppTheme.info)),
            const SizedBox(height: 2),
            Text(desc, style: const TextStyle(fontSize: 13), maxLines: 2,
                overflow: TextOverflow.ellipsis),
            if (suggestion.lastPrice > 0)
              Text('آخر سعر: ${Fmt.moneyShort(suggestion.lastPrice)}',
                  style: TextStyle(
                      fontSize: 11.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ]),
        ),
        Column(mainAxisSize: MainAxisSize.min, children: [
          FilledButton(
            onPressed: onApply,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 34),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              backgroundColor: AppTheme.info,
            ),
            child: const Text('تطبيق', style: TextStyle(fontSize: 13)),
          ),
          SizedBox(
            height: 26,
            child: TextButton(
              onPressed: onDismiss,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                textStyle: const TextStyle(fontSize: 11.5),
              ),
              child: const Text('تجاهل'),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _AppliedBanner extends StatelessWidget {
  final VoidCallback onUndo;
  const _AppliedBanner({required this.onUndo});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.success.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(children: [
          const Icon(Icons.check_circle_rounded, size: 17, color: AppTheme.success),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('تم تطبيق الاقتراح',
                style: TextStyle(fontSize: 12.5, color: AppTheme.success)),
          ),
          TextButton(
            onPressed: onUndo,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              textStyle: const TextStyle(fontSize: 12),
            ),
            child: const Text('تراجع'),
          ),
        ]),
      );
}

// ------------------------------------------------------------ شبكة الأنواع

class _TypeGrid extends StatelessWidget {
  final String selected;
  final void Function(ItemType) onSelect;

  const _TypeGrid({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: ItemTypes.all.map((t) {
        final isSel = t.key == selected;
        return InkWell(
          onTap: () => onSelect(t),
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: isSel ? scheme.primary : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSel ? scheme.primary : scheme.outlineVariant,
                width: isSel ? 1.6 : 1,
              ),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                _iconFor(t.key),
                size: 17,
                color: isSel ? scheme.onPrimary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                t.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                  color: isSel ? scheme.onPrimary : scheme.onSurface,
                ),
              ),
            ]),
          ),
        );
      }).toList(),
    );
  }
}

IconData _iconFor(String key) => switch (key) {
      'camera' => Icons.videocam_rounded,
      'switch' => Icons.hub_rounded,
      'nvr' => Icons.dvr_rounded,
      'router' => Icons.router_rounded,
      'ap' => Icons.wifi_rounded,
      'repeater' => Icons.settings_input_antenna_rounded,
      'cable' => Icons.cable_rounded,
      'power' => Icons.power_rounded,
      'storage' => Icons.storage_rounded,
      'accessory' => Icons.construction_rounded,
      _ => Icons.category_rounded,
    };

// ------------------------------------------------------- الحقول التفصيلية

class _SpecFieldWidget extends StatelessWidget {
  final SpecField field;
  final Object? value;
  final ValueChanged<Object?> onChanged;

  const _SpecFieldWidget({
    required this.field,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return switch (field.type) {
      SpecFieldType.toggle => _toggle(context),
      SpecFieldType.text => _text(context),
      _ => _choice(context),
    };
  }

  /// المفتاح مفعّل إذا كانت هناك قيمة محفوظة أصلًا.
  ///
  /// القيمة تُخزَّن كنص (تسمية الحقل) لتظهر في الوصف والتقرير، لذلك
  /// لا يصحّ مقارنتها بـ true — وهذا ما كان يمنع ظهور المفتاح مفعّلًا
  /// ويمنع إلغاءه بعد التفعيل.
  bool get _isOn =>
      value == true || (value != null && '$value'.trim().isNotEmpty);

  Widget _toggle(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: SwitchListTile(
          value: _isOn,
          onChanged: (v) => onChanged(v ? field.label : null),
          title: Text(field.label, style: const TextStyle(fontSize: 14)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          dense: true,
        ),
      );

  Widget _text(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          initialValue: value == null ? '' : '$value',
          decoration: InputDecoration(labelText: field.label),
          onChanged: onChanged,
        ),
      );

  /// خيارات سريعة كأزرار + إمكانية كتابة قيمة أخرى
  Widget _choice(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = value == null ? '' : '$value';
    final isCustom = current.isNotEmpty && !_matchesOption(current);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(field.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              )),
          if (current.isNotEmpty) ...[
            const Spacer(),
            SizedBox(
              height: 24,
              child: TextButton(
                onPressed: () => onChanged(null),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: Size.zero,
                  textStyle: const TextStyle(fontSize: 11.5),
                ),
                child: const Text('مسح'),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          ...field.options.map((o) {
            final label = field.suffix.isEmpty ? o : '$o ${field.suffix}';
            final isSel = current == label || current == o;
            return ChoiceChip(
              label: Text(label, style: const TextStyle(fontSize: 12.5)),
              selected: isSel,
              onSelected: (_) => onChanged(isSel ? null : label),
              visualDensity: VisualDensity.compact,
            );
          }),
          // زر «قيمة أخرى» للحقول التي لا تكفيها الخيارات الجاهزة
          ActionChip(
            avatar: Icon(isCustom ? Icons.edit_rounded : Icons.add_rounded, size: 15),
            label: Text(isCustom ? current : 'أخرى', style: const TextStyle(fontSize: 12.5)),
            onPressed: () => _askCustom(context, current),
            backgroundColor: isCustom ? scheme.primaryContainer : null,
            visualDensity: VisualDensity.compact,
          ),
        ]),
      ]),
    );
  }

  bool _matchesOption(String v) => field.options.any(
        (o) => v == o || v == (field.suffix.isEmpty ? o : '$o ${field.suffix}'),
      );

  Future<void> _askCustom(BuildContext context, String current) async {
    final controller = TextEditingController(text: _matchesOption(current) ? '' : current);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(field.label),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: field.type == SpecFieldType.number
              ? const TextInputType.numberWithOptions(decimal: true)
              : null,
          decoration: InputDecoration(
            labelText: 'أدخل ${field.label}',
            suffixText: field.suffix.isEmpty ? null : field.suffix,
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (result == null) return;
    if (result.isEmpty) {
      onChanged(null);
      return;
    }
    onChanged(field.suffix.isEmpty ? result : '$result ${field.suffix}');
  }
}

// ------------------------------------------------------------ معاينة القطعة

class _PreviewCard extends StatelessWidget {
  final Item item;
  const _PreviewCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.visibility_rounded, size: 15, color: scheme.primary),
          const SizedBox(width: 6),
          Text('معاينة',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: scheme.primary,
              )),
        ]),
        const SizedBox(height: 8),
        Text(item.description,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
        if (item.serial.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            item.serial,
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: (item.kind == MovementKind.out ? AppTheme.success : AppTheme.warning)
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              item.kind.label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: item.kind == MovementKind.out ? AppTheme.success : AppTheme.warning,
              ),
            ),
          ),
          const Spacer(),
          if (item.qty > 1)
            Text('${item.qty} × ${Fmt.moneyShort(item.price)}  =  ',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          Text(Fmt.money(item.total),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        ]),
      ]),
    );
  }
}

/// بطاقة قطعة في القوائم — تُستخدم في نموذج الزيارة وشاشة التفاصيل
class ItemTile extends StatelessWidget {
  final Item item;
  final int index;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final bool showSerial;

  const ItemTile({
    super.key,
    required this.item,
    required this.index,
    this.onTap,
    this.onDelete,
    this.showSerial = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isReturn = item.kind == MovementKind.returned;
    final accent = isReturn ? AppTheme.warning : scheme.primary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(10, 9, 6, 9),
        decoration: BoxDecoration(
          color: isReturn
              ? AppTheme.warning.withValues(alpha: 0.06)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withValues(alpha: 0.2)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // رقم الترتيب
          Container(
            width: 25,
            height: 25,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text('${index + 1}',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w800, color: accent)),
          ),
          const SizedBox(width: 9),

          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(_iconFor(item.typeKey), size: 15, color: accent),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    item.description,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
              if (showSerial && item.serial.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  'SN: ${item.serial}',
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (item.notes.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(item.notes,
                    style: TextStyle(fontSize: 11.5, color: scheme.outline),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 5),
              Row(children: [
                if (isReturn)
                  Container(
                    margin: const EdgeInsetsDirectional.only(end: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('راجع',
                        style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.warning)),
                  ),
                if (item.qty > 1)
                  Text('${item.qty} × ${Fmt.moneyShort(item.price)}',
                      style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                const Spacer(),
                Text(Fmt.moneyShort(item.total),
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800, color: accent)),
              ]),
            ]),
          ),

          if (onDelete != null)
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
