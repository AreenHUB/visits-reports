import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../db/repository.dart';
import '../providers/providers.dart';
import '../utils/formatting.dart';

/// مشاركة الملفات: واتساب، البريد، الحفظ... عبر لوحة المشاركة في أندرويد
class ShareService {
  ShareService._();
  static final ShareService instance = ShareService._();

  /// يشارك ملفًا واحدًا مع نص مرافق.
  ///
  /// نمرّر النوع (mimeType) صراحةً ونسمّي الملف باسم لاتيني عند المشاركة،
  /// لأن بعض تطبيقات المشاركة على أندرويد ترفض الأسماء غير اللاتينية
  /// أو تفشل صامتةً معها.
  Future<void> shareFile(
    File file, {
    String? text,
    String? subject,
    Rect? origin,
  }) async {
    final path = file.path;
    final mime = _mimeFor(path);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: mime)],
        text: text,
        subject: subject,
        sharePositionOrigin: origin,
      ),
    );
  }

  static String? _mimeFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (lower.endsWith('.json')) return 'application/json';
    return null;
  }

  Future<void> shareFiles(
    List<File> files, {
    String? text,
    String? subject,
    Rect? origin,
  }) async {
    await SharePlus.instance.share(
      ShareParams(
        files: files.map((f) => XFile(f.path)).toList(),
        text: text,
        subject: subject,
        sharePositionOrigin: origin,
      ),
    );
  }

  Future<void> shareText(String text, {Rect? origin}) async {
    await SharePlus.instance.share(
      ShareParams(text: text, sharePositionOrigin: origin),
    );
  }

  /// نص مرافق للتقرير — يظهر في رسالة الواتساب مع الملف
  static String reportMessage(PeriodSummary s, ShopSettings st) {
    final g = s.grandTotals;
    final b = StringBuffer();

    if (st.shopName.isNotEmpty) b.writeln('*${st.shopName}*');
    b.writeln(s.from == s.to ? '*تقرير الزيارات اليومي*' : '*تقرير الزيارات*');
    b.writeln(Fmt.range(s.from, s.to));
    b.writeln('');
    b.writeln('عدد الزيارات: ${s.visitCount}');
    if (s.doneCount > 0) b.writeln('تمت: ${s.doneCount}');
    if (s.notDoneCount > 0) b.writeln('لم تتم: ${s.notDoneCount}');
    if (s.partialCount > 0) b.writeln('جزئية: ${s.partialCount}');
    if (s.credits.isNotEmpty) b.writeln('سحب آجل: ${s.credits.length}');
    b.writeln('');
    b.writeln('قيمة القطع: ${Fmt.moneyShort(g.itemsTotal)}');
    if (g.returnedTotal > 0.009) {
      b.writeln('المرتجع: ${Fmt.moneyShort(g.returnedTotal)}');
      b.writeln('الصافي: ${Fmt.moneyShort(g.net)}');
    }
    b.writeln('المحصّل: ${Fmt.moneyShort(g.paid)}');
    b.writeln('*المتبقي: ${Fmt.moneyShort(g.remaining)}*');

    // حركة الصندوق: الوارد والصادر خارج الزيارات
    final c = s.cashTotals;
    if (s.cash.isNotEmpty) {
      b.writeln('');
      b.writeln('— الصندوق —');
      if (c.income > 0.009) b.writeln('وارد آخر: ${Fmt.moneyShort(c.income)}');
      if (c.expense > 0.009) b.writeln('صادر: ${Fmt.moneyShort(c.expense)}');
      b.writeln('*صافي حركة النقد: ${Fmt.moneyShort(s.netCashFlow)}*');
    }

    // ملاحظات اليوم تُرسل نصًا مع الملف
    if (s.dayNotes.isNotEmpty) {
      b.writeln('');
      b.writeln('— ملاحظات —');
      for (final n in s.dayNotes) {
        b.writeln(s.dayNotes.length == 1
            ? n.notes
            : '${Fmt.date(n.day)}: ${n.notes}');
      }
    }

    return b.toString();
  }

  /// موضع نافذة المشاركة — مطلوب على الأجهزة اللوحية
  static Rect? originFrom(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }
}
