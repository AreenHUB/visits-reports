import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// شاشة قراءة الباركود / QR بكاميرا الجوال.
///
/// وضعان:
/// - قراءة واحدة: تُغلق الشاشة فور القراءة وتعيد السيريال
/// - قراءة متتابعة: تبقى مفتوحة وتجمع عدة سيريالات بالترتيب
class ScannerScreen extends StatefulWidget {
  /// إن كان true تبقى الكاميرا مفتوحة لقراءة عدة قطع متتالية
  final bool continuous;

  /// سيريالات مقروءة مسبقًا — لمنع التكرار
  final Set<String> existing;

  const ScannerScreen({
    super.key,
    this.continuous = true,
    this.existing = const {},
  });

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  late final MobileScannerController _controller;

  /// السيريالات المقروءة في هذه الجلسة، بالترتيب
  final List<String> _scanned = [];

  /// نمنع القراءة المتكررة لنفس الرمز خلال فترة قصيرة
  String? _lastCode;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _torch = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      formats: const [
        BarcodeFormat.code128,
        BarcodeFormat.code39,
        BarcodeFormat.code93,
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
        BarcodeFormat.upcA,
        BarcodeFormat.upcE,
        BarcodeFormat.qrCode,
        BarcodeFormat.dataMatrix,
        BarcodeFormat.itf14,
      ],
      detectionSpeed: DetectionSpeed.normal,
      autoStart: true,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    final raw = capture.barcodes
        .map((b) => b.rawValue?.trim() ?? '')
        .firstWhere((v) => v.isNotEmpty, orElse: () => '');
    if (raw.isEmpty) return;

    final now = DateTime.now();
    // نتجاهل نفس الرمز إذا تكرّر خلال ثانيتين
    if (raw == _lastCode && now.difference(_lastAt) < const Duration(seconds: 2)) return;
    _lastCode = raw;
    _lastAt = now;

    final duplicate = _scanned.contains(raw) || widget.existing.contains(raw);

    if (!widget.continuous) {
      HapticFeedback.mediumImpact();
      Navigator.pop(context, [raw]);
      return;
    }

    if (duplicate) {
      HapticFeedback.heavyImpact();
      _flash('هذا الرقم مقروء مسبقًا: $raw', isError: true);
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _scanned.add(raw));
    _flash('تمت القراءة: $raw');
  }

  void _flash(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg, textDirection: TextDirection.ltr),
        duration: const Duration(milliseconds: 1100),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 190, left: 20, right: 20),
      ));
  }

  Future<void> _manualEntry() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إدخال الرقم يدويًا'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.left,
          decoration: const InputDecoration(
            labelText: 'الرقم التسلسلي SN',
            hintText: 'اكتب الرقم هنا',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('إضافة'),
          ),
        ],
      ),
    );

    if (value == null || value.isEmpty || !mounted) return;

    if (!widget.continuous) {
      Navigator.pop(context, [value]);
      return;
    }
    if (_scanned.contains(value) || widget.existing.contains(value)) {
      _flash('هذا الرقم مقروء مسبقًا', isError: true);
      return;
    }
    setState(() => _scanned.add(value));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.continuous ? 'قراءة الأرقام التسلسلية' : 'قراءة رقم تسلسلي'),
        actions: [
          IconButton(
            tooltip: 'الفلاش',
            icon: Icon(_torch ? Icons.flash_on_rounded : Icons.flash_off_rounded),
            onPressed: () async {
              await _controller.toggleTorch();
              if (mounted) setState(() => _torch = !_torch);
            },
          ),
          IconButton(
            tooltip: 'تبديل الكاميرا',
            icon: const Icon(Icons.cameraswitch_rounded),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          errorBuilder: (context, error) => _CameraError(error: error),
          fit: BoxFit.cover,
        ),

        // إطار التصويب
        IgnorePointer(
          child: Center(
            child: Container(
              width: 265,
              height: 165,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.greenAccent, width: 2.5),
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),

        const IgnorePointer(
          child: Align(
            alignment: Alignment(0, -0.62),
            child: Text(
              'وجّه الكاميرا نحو الباركود',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(blurRadius: 8, color: Colors.black)],
              ),
            ),
          ),
        ),

        // قائمة ما تمت قراءته
        if (widget.continuous)
          Align(
            alignment: Alignment.bottomCenter,
            child: _ScannedPanel(
              scanned: _scanned,
              onRemove: (i) => setState(() => _scanned.removeAt(i)),
              onManual: _manualEntry,
              onDone: () => Navigator.pop(context, _scanned),
            ),
          )
        else
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: OutlinedButton.icon(
                onPressed: _manualEntry,
                icon: const Icon(Icons.keyboard_rounded),
                label: const Text('إدخال يدوي'),
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.black54,
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// اللوحة السفلية التي تعرض الأرقام المقروءة بالترتيب
class _ScannedPanel extends StatelessWidget {
  final List<String> scanned;
  final void Function(int) onRemove;
  final VoidCallback onManual;
  final VoidCallback onDone;

  const _ScannedPanel({
    required this.scanned,
    required this.onRemove,
    required this.onManual,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xF21B1F1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.greenAccent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${scanned.length}',
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Text('رقم مقروء',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            const Spacer(),
            TextButton.icon(
              onPressed: onManual,
              icon: const Icon(Icons.keyboard_rounded, size: 18),
              label: const Text('يدوي'),
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
            ),
          ]),

          if (scanned.isNotEmpty) ...[
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 132),
              child: ListView.builder(
                shrinkWrap: true,
                reverse: true,
                itemCount: scanned.length,
                itemBuilder: (context, i) {
                  final idx = scanned.length - 1 - i;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(children: [
                      SizedBox(
                        width: 26,
                        child: Text('${idx + 1}.',
                            style: const TextStyle(color: Colors.white38, fontSize: 12)),
                      ),
                      Expanded(
                        child: Text(
                          scanned[idx],
                          textDirection: TextDirection.ltr,
                          textAlign: TextAlign.left,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontFamily: 'monospace',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close_rounded, size: 17, color: Colors.white54),
                        onPressed: () => onRemove(idx),
                      ),
                    ]),
                  );
                },
              ),
            ),
          ],

          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onDone,
              icon: const Icon(Icons.check_rounded),
              label: Text(scanned.isEmpty ? 'إغلاق' : 'إضافة ${scanned.length} قطعة'),
            ),
          ),
        ]),
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  final MobileScannerException error;
  const _CameraError({required this.error});

  @override
  Widget build(BuildContext context) {
    final message = switch (error.errorCode) {
      MobileScannerErrorCode.permissionDenied =>
        'لم يُسمح للتطبيق باستخدام الكاميرا.\nافتح إعدادات التطبيق وفعّل صلاحية الكاميرا.',
      MobileScannerErrorCode.unsupported => 'الكاميرا غير مدعومة على هذا الجهاز',
      _ => 'تعذّر تشغيل الكاميرا\n${error.errorDetails?.message ?? ''}',
    };

    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(30),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.no_photography_rounded, size: 56, color: Colors.white38),
        const SizedBox(height: 16),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.6),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: () => Navigator.pop(context, <String>[]),
          icon: const Icon(Icons.keyboard_rounded),
          label: const Text('أدخل الأرقام يدويًا'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white38),
          ),
        ),
      ]),
    );
  }
}
