import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/repository.dart';
import '../providers/providers.dart';
import '../services/backup_service.dart';
import '../services/share_service.dart';
import '../utils/formatting.dart';
import '../utils/theme.dart';
import '../widgets/common.dart';

/// الإعدادات: بيانات المحل، النسخ الاحتياطي، معلومات التطبيق
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showSnack(context, 'حدث خطأ: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _backup() => _run(() async {
        final origin = ShareService.originFrom(context);
        final file = await BackupService.instance.createBackup();
        if (!mounted) return;

        await ShareService.instance.shareFile(
          file,
          text: 'نسخة احتياطية — ${Fmt.dateTime(DateTime.now())}',
          subject: 'نسخة احتياطية لتطبيق الأقصى',
          origin: origin,
        );
      });

  Future<void> _restore() => _run(() async {
        final ok = await confirmDialog(
          context,
          title: 'استعادة نسخة احتياطية',
          message:
              'سيتم استبدال كل البيانات الحالية ببيانات النسخة.\n\nيُنصح بأخذ نسخة من البيانات الحالية أولًا.\n\nهل تريد المتابعة؟',
          confirmLabel: 'استعادة',
          destructive: true,
        );
        if (!ok || !mounted) return;

        final result = await BackupService.instance.restoreFromPicker();
        if (!mounted) return;

        bumpRefresh(ref);
        showSnack(context, result.summary, error: !result.ok);
      });

  Future<void> _wipe() => _run(() async {
        final ok = await confirmDialog(
          context,
          title: 'حذف كل البيانات',
          message:
              'سيتم حذف جميع الزيارات والعملاء والسحوبات والقطع نهائيًا.\n\nهذا الإجراء لا يمكن التراجع عنه!',
          confirmLabel: 'حذف الكل',
          destructive: true,
        );
        if (!ok || !mounted) return;

        // تأكيد ثانٍ لأن العملية لا رجعة فيها
        final confirmed = await confirmDialog(
          context,
          title: 'تأكيد أخير',
          message: 'هل أنت متأكد تمامًا؟ لن تتمكن من استرجاع البيانات إلا من نسخة احتياطية.',
          confirmLabel: 'نعم، احذف',
          destructive: true,
        );
        if (!confirmed || !mounted) return;

        await BackupService.instance.wipeAll();
        if (!mounted) return;
        bumpRefresh(ref);
        showSnack(context, 'تم حذف جميع البيانات');
      });

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: Stack(children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 30),
          children: [
            const SectionHeader('بيانات المحل', icon: Icons.store_rounded),
            settingsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => ErrorView(e),
              data: (s) => _ShopSettingsForm(settings: s),
            ),

            const SectionHeader('النسخ الاحتياطي', icon: Icons.backup_rounded),
            _InfoBox(
              icon: Icons.lock_rounded,
              color: AppTheme.info,
              text:
                  'بياناتك محفوظة مشفّرة على جهازك فقط. النسخة الاحتياطية ملف يحتوي كل السجلات — احفظه في مكان آمن.',
            ),
            const SizedBox(height: 10),

            _ActionTile(
              icon: Icons.cloud_upload_rounded,
              color: AppTheme.success,
              title: 'إنشاء نسخة احتياطية',
              subtitle: 'حفظ أو إرسال ملف يحتوي كل البيانات',
              onTap: _busy ? null : _backup,
            ),
            _ActionTile(
              icon: Icons.cloud_download_rounded,
              color: AppTheme.info,
              title: 'استعادة نسخة احتياطية',
              subtitle: 'استبدال البيانات الحالية بملف نسخة',
              onTap: _busy ? null : _restore,
            ),

            const SectionHeader('إحصاءات قاعدة البيانات', icon: Icons.storage_rounded),
            const _StatsBox(),

            const SectionHeader('منطقة الخطر', icon: Icons.warning_amber_rounded),
            _ActionTile(
              icon: Icons.delete_forever_rounded,
              color: AppTheme.danger,
              title: 'حذف كل البيانات',
              subtitle: 'لا يمكن التراجع — خذ نسخة احتياطية أولًا',
              onTap: _busy ? null : _wipe,
            ),

            const SizedBox(height: 24),
            Center(
              child: Column(children: [
                Text('تطبيق الأقصى',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary,
                    )),
                Text('الإصدار 1.2.0',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.outline)),
              ]),
            ),
          ],
        ),
        if (_busy)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black.withValues(alpha: 0.2),
              child: const Center(child: CircularProgressIndicator()),
            ),
          ),
      ]),
    );
  }
}

/// نموذج بيانات المحل — تظهر في ترويسة التقارير
class _ShopSettingsForm extends ConsumerStatefulWidget {
  final ShopSettings settings;
  const _ShopSettingsForm({required this.settings});

  @override
  ConsumerState<_ShopSettingsForm> createState() => _ShopSettingsFormState();
}

class _ShopSettingsFormState extends ConsumerState<_ShopSettingsForm> {
  late final TextEditingController _shop;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final s = widget.settings;
    _shop = TextEditingController(text: s.shopName);
    _phone = TextEditingController(text: s.shopPhone);
    _address = TextEditingController(text: s.shopAddress);
  }

  @override
  void dispose() {
    _shop.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final repo = Repository.instance;
    final map = ShopSettings(
      shopName: _shop.text.trim(),
      shopPhone: _phone.text.trim(),
      shopAddress: _address.text.trim(),
      // الحقلان لم يعودا يظهران في الواجهة ولا في التقارير،
      // لكن نحافظ على قيمتيهما المحفوظتين بدل مسحهما.
      managerName: widget.settings.managerName,
      technicianName: widget.settings.technicianName,
    ).toMap();

    for (final e in map.entries) {
      await repo.setSetting(e.key, e.value);
    }

    if (!mounted) return;
    setState(() => _dirty = false);
    ref.invalidate(settingsProvider);
    showSnack(context, 'تم حفظ البيانات');
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      TextField(
        controller: _shop,
        decoration: const InputDecoration(
          labelText: 'اسم المحل / الشركة',
          prefixIcon: Icon(Icons.store_outlined),
          helperText: 'يظهر في ترويسة التقارير',
        ),
        onChanged: (_) => setState(() => _dirty = true),
      ),
      const SizedBox(height: 11),
      TextField(
        controller: _phone,
        keyboardType: TextInputType.phone,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.left,
        decoration: const InputDecoration(
          labelText: 'هاتف المحل',
          prefixIcon: Icon(Icons.phone_outlined),
        ),
        onChanged: (_) => setState(() => _dirty = true),
      ),
      const SizedBox(height: 11),
      TextField(
        controller: _address,
        decoration: const InputDecoration(
          labelText: 'عنوان المحل',
          prefixIcon: Icon(Icons.location_on_outlined),
        ),
        onChanged: (_) => setState(() => _dirty = true),
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _dirty ? _save : null,
          icon: const Icon(Icons.save_rounded),
          label: const Text('حفظ بيانات المحل'),
        ),
      ),
    ]);
  }
}

class _StatsBox extends StatelessWidget {
  const _StatsBox();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<BackupStats>(
      future: BackupService.instance.stats(),
      builder: (context, snap) {
        final s = snap.data;
        if (s == null) {
          return const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final scheme = Theme.of(context).colorScheme;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(children: [
            _statLine('الزيارات', '${s.visits}'),
            _statLine('العملاء', '${s.customers}'),
            _statLine('السحوبات الآجلة', '${s.credits}'),
            _statLine('القطع المسجّلة', '${s.items}'),
            _statLine('الدفعات', '${s.payments}'),
            _statLine('الحركات المالية', '${s.cashEntries}'),
            _statLine('الأرقام التسلسلية المحفوظة', '${s.serials}'),
            const Divider(height: 18),
            _statLine('حجم قاعدة البيانات', s.sizeLabel, bold: true),
          ]),
        );
      },
    );
  }

  Widget _statLine(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          const Spacer(),
          Text(value,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w700,
              )),
        ]),
      );
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _ActionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          title: Text(title,
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
          subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
          trailing: const Icon(Icons.chevron_left_rounded),
          onTap: onTap,
          enabled: onTap != null,
        ),
      );
}

class _InfoBox extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _InfoBox({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 12.5, height: 1.5)),
          ),
        ]),
      );
}
