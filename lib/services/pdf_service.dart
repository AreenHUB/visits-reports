import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../db/repository.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../utils/formatting.dart';

/// توليد تقارير PDF بالعربية (اتجاه من اليمين لليسار)
class PdfService {
  PdfService._();
  static final PdfService instance = PdfService._();

  pw.Font? _regular;
  pw.Font? _bold;

  static const _green = PdfColor.fromInt(0xFF0E7C66);
  static const _greenLight = PdfColor.fromInt(0xFFE6F2EF);
  static const _grey = PdfColor.fromInt(0xFF6B7280);
  static const _greyLight = PdfColor.fromInt(0xFFF3F4F6);
  static const _line = PdfColor.fromInt(0xFFD8DEDC);
  static const _red = PdfColor.fromInt(0xFFC62828);
  static const _amber = PdfColor.fromInt(0xFFEF6C00);

  Future<void> _loadFonts() async {
    if (_regular != null) return;
    // خط Cairo متغيّر (variable) فنستخدم نفس الملف للعادي والعريض؛
    // التمييز يظهر عبر fontWeight في نمط النص.
    final font = pw.Font.ttf(await rootBundle.load('assets/fonts/Cairo.ttf'));
    _regular = font;
    _bold = font;
  }

  pw.TextStyle _s({
    double size = 10,
    bool bold = false,
    PdfColor color = PdfColors.black,
  }) => pw.TextStyle(
    font: bold ? _bold : _regular,
    fontSize: size,
    color: color,
    fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
  );

  /// يبني تقرير فترة كاملة ويعيد بايتات ملف PDF
  Future<Uint8List> buildReport({
    required PeriodSummary summary,
    required ShopSettings settings,
    String? title,
    ReportOptions options = const ReportOptions(),
  }) async {
    await _loadFonts();

    final doc = pw.Document(
      title: title ?? 'تقرير الزيارات',
      author: settings.shopName.isEmpty ? 'الأقصى' : settings.shopName,
    );

    final reportTitle =
        title ??
        (summary.from == summary.to
            ? 'تقرير الزيارات اليومي'
            : 'تقرير الزيارات');

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 34),
          textDirection: pw.TextDirection.rtl,
          theme: pw.ThemeData.withFont(base: _regular, bold: _bold),
        ),
        header: (ctx) => ctx.pageNumber == 1
            ? pw.SizedBox()
            : pw.Container(
                alignment: pw.Alignment.centerRight,
                margin: const pw.EdgeInsets.only(bottom: 10),
                child: pw.Text(reportTitle, style: _s(size: 9, color: _grey)),
              ),
        footer: (ctx) => pw.Container(
          alignment: pw.Alignment.center,
          margin: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(
            'صفحة ${ctx.pageNumber} من ${ctx.pagesCount}',
            style: _s(size: 8, color: _grey),
          ),
        ),
        build: (ctx) => [
          _header(reportTitle, summary, settings),
          pw.SizedBox(height: 14),
          if (summary.dayNotes.isNotEmpty) ...[
            _dayNotesBlock(summary),
            pw.SizedBox(height: 12),
          ],
          _summaryCards(summary),
          pw.SizedBox(height: 10),
          _cashSummaryCards(summary, options),
          pw.SizedBox(height: 16),
          if (options.includeVisits && summary.visits.isNotEmpty) ...[
            _sectionTitle('الزيارات', summary.visits.length),
            pw.SizedBox(height: 8),
            ...summary.visits.map(_visitBlock),
            pw.SizedBox(height: 8),
          ],
          if (options.includeCredits && summary.credits.isNotEmpty) ...[
            _sectionTitle('السحب بالآجل', summary.credits.length),
            pw.SizedBox(height: 8),
            ...summary.credits.map(_creditBlock),
            pw.SizedBox(height: 8),
          ],
          if (options.includeCash && summary.cash.isNotEmpty) ...[
            _sectionTitle('الحركات المالية (وارد وصادر)', summary.cash.length),
            pw.SizedBox(height: 8),
            _cashTable(summary),
            pw.SizedBox(height: 8),
          ],
          if (options.includeSalaries && summary.salaries.isNotEmpty) ...[
            _sectionTitle('رواتب الموظفين', summary.salaries.length),
            pw.SizedBox(height: 8),
            _salariesTable(summary),
            pw.SizedBox(height: 8),
          ],
          if (options.includeDebts && summary.debts.isNotEmpty) ...[
            _sectionTitle('ديون العملاء', summary.debts.length),
            pw.SizedBox(height: 8),
            _debtsTable(summary),
            pw.SizedBox(height: 8),
          ],
          if (summary.isEmpty)
            pw.Container(
              padding: const pw.EdgeInsets.all(24),
              alignment: pw.Alignment.center,
              child: pw.Text(
                'لا توجد سجلات في هذه الفترة',
                style: _s(size: 12, color: _grey),
              ),
            ),
          pw.SizedBox(height: 10),
          _grandTotals(summary),
        ],
      ),
    );

    return doc.save();
  }

  // ------------------------------------------------------------- الترويسة

  pw.Widget _header(String title, PeriodSummary s, ShopSettings st) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: _greenLight,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: _green, width: 0.8),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  st.shopName.isEmpty ? 'الأقصى' : st.shopName,
                  style: _s(size: 17, bold: true, color: _green),
                ),
                if (st.shopPhone.isNotEmpty || st.shopAddress.isNotEmpty)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 2),
                    child: pw.Text(
                      [
                        st.shopAddress,
                        st.shopPhone,
                      ].where((e) => e.isNotEmpty).join('  •  '),
                      style: _s(size: 8.5, color: _grey),
                    ),
                  ),
                pw.SizedBox(height: 6),
                pw.Text(title, style: _s(size: 12, bold: true)),
                pw.SizedBox(height: 2),
                pw.Text(
                  Fmt.range(s.from, s.to),
                  style: _s(size: 10, color: _grey),
                ),
              ],
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('تاريخ الإصدار', style: _s(size: 8, color: _grey)),
              pw.Text(
                Fmt.dateTime(DateTime.now()),
                style: _s(size: 9, bold: true),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------- بطاقات الملخص

  pw.Widget _summaryCards(PeriodSummary s) {
    final t = s.grandTotals;
    return pw.Column(
      children: [
        pw.Row(
          children: [
            _card('عدد الزيارات', Fmt.count(s.visitCount), _green),
            pw.SizedBox(width: 6),
            _card(
              'تمت',
              Fmt.count(s.doneCount),
              const PdfColor.fromInt(0xFF2E7D32),
            ),
            pw.SizedBox(width: 6),
            _card('لم تتم', Fmt.count(s.notDoneCount), _red),
            pw.SizedBox(width: 6),
            _card('قطع صادرة', Fmt.count(s.itemsOutCount), _amber),
            pw.SizedBox(width: 6),
            _card('قطع راجعة', Fmt.count(s.itemsReturnedCount), _grey),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Row(
          children: [
            _card('إجمالي القطع', Fmt.moneyShort(t.itemsTotal), _green),
            pw.SizedBox(width: 6),
            _card('قيمة المرتجع', Fmt.moneyShort(t.returnedTotal), _grey),
            pw.SizedBox(width: 6),
            _card(
              'الصافي',
              Fmt.moneyShort(t.net),
              const PdfColor.fromInt(0xFF1565C0),
            ),
            pw.SizedBox(width: 6),
            _card(
              'المحصّل',
              Fmt.moneyShort(t.paid),
              const PdfColor.fromInt(0xFF2E7D32),
            ),
            pw.SizedBox(width: 6),
            _card(
              'المتبقي',
              Fmt.moneyShort(t.remaining),
              t.remaining > 0.009 ? _red : _green,
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _card(String label, String value, PdfColor color) => pw.Expanded(
    child: pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 5),
      decoration: pw.BoxDecoration(
        color: _greyLight,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: _line, width: 0.5),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            label,
            style: _s(size: 7.5, color: _grey),
            textAlign: pw.TextAlign.center,
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            value,
            style: _s(size: 10, bold: true, color: color),
            textAlign: pw.TextAlign.center,
          ),
        ],
      ),
    ),
  );

  // --------------------------------------------- ملاحظات اليوم للمدير

  pw.Widget _dayNotesBlock(PeriodSummary s) {
    final single = s.dayNotes.length == 1;
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(11),
      decoration: pw.BoxDecoration(
        color: const PdfColor.fromInt(0xFFFDF8EC),
        borderRadius: pw.BorderRadius.circular(9),
        border: pw.Border.all(
          color: const PdfColor.fromInt(0xFFB07D2B),
          width: 0.8,
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            single ? 'ملاحظات عن هذا اليوم' : 'ملاحظات الأيام',
            style: _s(
              size: 10.5,
              bold: true,
              color: const PdfColor.fromInt(0xFF8A5F1B),
            ),
          ),
          pw.SizedBox(height: 5),
          ...s.dayNotes.map(
            (n) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 3),
              child: single
                  ? pw.Text(n.notes, style: _s(size: 10))
                  : pw.RichText(
                      textDirection: pw.TextDirection.rtl,
                      text: pw.TextSpan(
                        children: [
                          pw.TextSpan(
                            text: '${Fmt.dateWithDay(n.day)}: ',
                            style: _s(size: 9.5, bold: true, color: _grey),
                          ),
                          pw.TextSpan(text: n.notes, style: _s(size: 10)),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------ بطاقات الحركة المالية

  pw.Widget _cashSummaryCards(PeriodSummary s, ReportOptions options) {
    final c = s.cashTotals;
    final collected = s.grandTotals.paid;
    final totalIn = collected + c.income;

    return pw.Column(
      children: [
        pw.Row(
          children: [
            _card(
              'محصّل الزيارات',
              Fmt.moneyShort(collected),
              const PdfColor.fromInt(0xFF2E7D32),
            ),
            pw.SizedBox(width: 6),
            _card(
              'وارد آخر',
              Fmt.moneyShort(c.income),
              const PdfColor.fromInt(0xFF2E7D32),
            ),
            pw.SizedBox(width: 6),
            _card('إجمالي الداخل', Fmt.moneyShort(totalIn), _green),
            pw.SizedBox(width: 6),
            _card('إجمالي الخارج', Fmt.moneyShort(c.expense), _red),
            pw.SizedBox(width: 6),
            _card(
              'صافي الصندوق',
              Fmt.moneyShort(totalIn - c.expense),
              const PdfColor.fromInt(0xFF1565C0),
            ),
          ],
        ),
        // رصيد الكاش داخل المحل: النقد فقط، دون بطاقة أو تحويل
        if (options.includeCashBalance) ...[
          pw.SizedBox(height: 8),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 9, horizontal: 12),
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(0xFFEAF5EB),
              borderRadius: pw.BorderRadius.circular(8),
              border: pw.Border.all(
                color: const PdfColor.fromInt(0xFF2E7D32),
                width: 0.9,
              ),
            ),
            child: pw.Row(
              children: [
                pw.Text(
                  'الكاش الموجود في المحل (نقدًا فقط)',
                  style: _s(size: 11, bold: true),
                ),
                pw.Expanded(child: pw.SizedBox()),
                pw.Text(
                  Fmt.money(s.cashBalance.balance),
                  style: _s(
                    size: 13,
                    bold: true,
                    color: s.cashBalance.balance >= 0
                        ? const PdfColor.fromInt(0xFF2E7D32)
                        : _red,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ------------------------------------------------------ جدول الرواتب

  pw.Widget _salariesTable(PeriodSummary s) {
    const headers = [
      'التاريخ',
      'الموظف',
      'نوع الدفعة',
      'عن شهر',
      'الدفع',
      'المبلغ',
    ];

    return pw.Table(
      border: pw.TableBorder.all(color: _line, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.3),
        1: pw.FlexColumnWidth(2.4),
        2: pw.FlexColumnWidth(1.7),
        3: pw.FlexColumnWidth(1.5),
        4: pw.FixedColumnWidth(42),
        5: pw.FlexColumnWidth(1.4),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _greenLight),
          children: headers
              .map(
                (h) => pw.Padding(
                  padding:
                      const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 3),
                  child: pw.Text(
                    h,
                    style: _s(size: 8, bold: true, color: _green),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              )
              .toList(),
        ),
        ...s.salaries.map(
          (p) => pw.TableRow(
            children: [
              _cell(Fmt.date(p.date), align: pw.TextAlign.center, size: 8),
              _cell(p.employeeName, size: 8.5),
              _cell(p.kind.label, size: 8),
              _cell(
                p.forMonth == null ? '—' : Fmt.monthName(p.forMonth!),
                align: pw.TextAlign.center,
                size: 8,
              ),
              _cell(p.method.label, align: pw.TextAlign.center, size: 7.5),
              _cell(
                Fmt.moneyRaw(p.amount),
                align: pw.TextAlign.center,
                size: 8.5,
                bold: true,
              ),
            ],
          ),
        ),
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _greyLight),
          children: [
            _cell('الإجمالي', size: 9, bold: true),
            _cell('', size: 8),
            _cell('', size: 8),
            _cell('', size: 8),
            _cell('', size: 8),
            _cell(
              Fmt.moneyRaw(s.salariesTotal),
              align: pw.TextAlign.center,
              size: 9,
              bold: true,
              color: _red,
            ),
          ],
        ),
      ],
    );
  }

  // ------------------------------------------------------- جدول الديون

  pw.Widget _debtsTable(PeriodSummary s) {
    const headers = [
      'التاريخ',
      'الاسم',
      'الهاتف',
      'السبب',
      'الاستحقاق',
      'الدين',
      'المسدَّد',
      'المتبقي',
    ];

    return pw.Table(
      border: pw.TableBorder.all(color: _line, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.2),
        1: pw.FlexColumnWidth(2),
        2: pw.FlexColumnWidth(1.5),
        3: pw.FlexColumnWidth(1.9),
        4: pw.FlexColumnWidth(1.2),
        5: pw.FlexColumnWidth(1.2),
        6: pw.FlexColumnWidth(1.2),
        7: pw.FlexColumnWidth(1.3),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _greenLight),
          children: headers
              .map(
                (h) => pw.Padding(
                  padding:
                      const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 3),
                  child: pw.Text(
                    h,
                    style: _s(size: 8, bold: true, color: _green),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              )
              .toList(),
        ),
        ...s.debts.map((d) {
          final overdue = d.isOverdue;
          return pw.TableRow(
            decoration: overdue
                ? const pw.BoxDecoration(color: PdfColor.fromInt(0xFFFDF0F0))
                : null,
            children: [
              _cell(Fmt.date(d.date), align: pw.TextAlign.center, size: 8),
              _cell(d.personName, size: 8.5, bold: true),
              _cell(
                d.personPhone.isEmpty ? '—' : d.personPhone,
                size: 8,
                mono: d.personPhone.isNotEmpty,
              ),
              _cell(d.reason.isEmpty ? '—' : d.reason, size: 8),
              _cell(
                d.dueDate == null ? '—' : Fmt.date(d.dueDate!),
                align: pw.TextAlign.center,
                size: 8,
                color: overdue ? _red : PdfColors.black,
                bold: overdue,
              ),
              _cell(
                Fmt.moneyRaw(d.amount),
                align: pw.TextAlign.center,
                size: 8.5,
              ),
              _cell(
                Fmt.moneyRaw(d.paid),
                align: pw.TextAlign.center,
                size: 8.5,
                color: const PdfColor.fromInt(0xFF2E7D32),
              ),
              _cell(
                Fmt.moneyRaw(d.remaining),
                align: pw.TextAlign.center,
                size: 8.5,
                bold: true,
                color: _red,
              ),
            ],
          );
        }),
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _greyLight),
          children: [
            _cell('الإجمالي', size: 9, bold: true),
            _cell('', size: 8),
            _cell('', size: 8),
            _cell('', size: 8),
            _cell('', size: 8),
            _cell('', size: 8),
            _cell('', size: 8),
            _cell(
              Fmt.moneyRaw(s.debtsTotal),
              align: pw.TextAlign.center,
              size: 9,
              bold: true,
              color: _red,
            ),
          ],
        ),
      ],
    );
  }

  /// جدول الحركات المالية المستقلة عن الزيارات
  pw.Widget _cashTable(PeriodSummary s) {
    const headers = [
      'التاريخ',
      'البيان',
      'التصنيف',
      'الجهة',
      'الدفع',
      'وارد',
      'صادر',
      'ملاحظات',
    ];
    final c = s.cashTotals;

    return pw.Column(
      children: [
        pw.Table(
          border: pw.TableBorder.all(color: _line, width: 0.5),
          columnWidths: const {
            0: pw.FlexColumnWidth(1.2),
            1: pw.FlexColumnWidth(2.2),
            2: pw.FlexColumnWidth(1.7),
            3: pw.FlexColumnWidth(1.4),
            4: pw.FixedColumnWidth(38),
            5: pw.FlexColumnWidth(1.2),
            6: pw.FlexColumnWidth(1.2),
            7: pw.FlexColumnWidth(2),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _greenLight),
              children: headers
                  .map(
                    (h) => pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: 3,
                      ),
                      child: pw.Text(
                        h,
                        style: _s(size: 8, bold: true, color: _green),
                        textAlign: pw.TextAlign.center,
                      ),
                    ),
                  )
                  .toList(),
            ),
            ...s.cash.map((e) {
              final isIncome = e.direction == CashDirection.income;
              return pw.TableRow(
                decoration: isIncome
                    ? null
                    : const pw.BoxDecoration(
                        color: PdfColor.fromInt(0xFFFDF0F0),
                      ),
                children: [
                  _cell(Fmt.date(e.date), align: pw.TextAlign.center, size: 8),
                  _cell(
                    e.description.isEmpty ? e.categoryLabel : e.description,
                    size: 8.5,
                  ),
                  _cell(e.categoryLabel, size: 8),
                  _cell(e.partyName.isEmpty ? '—' : e.partyName, size: 8),
                  _cell(e.method.label, align: pw.TextAlign.center, size: 7.5),
                  _cell(
                    isIncome ? Fmt.moneyRaw(e.amount) : '—',
                    align: pw.TextAlign.center,
                    size: 8.5,
                    bold: isIncome,
                    color: isIncome
                        ? const PdfColor.fromInt(0xFF2E7D32)
                        : _grey,
                  ),
                  _cell(
                    isIncome ? '—' : Fmt.moneyRaw(e.amount),
                    align: pw.TextAlign.center,
                    size: 8.5,
                    bold: !isIncome,
                    color: isIncome ? _grey : _red,
                  ),
                  // الملاحظات تظهر للوارد والصادر على حد سواء
                  _cell(e.notes.trim().isEmpty ? '—' : e.notes, size: 8),
                ],
              );
            }),
            // صف الإجمالي
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _greyLight),
              children: [
                _cell('الإجمالي', size: 9, bold: true),
                _cell('', size: 8),
                _cell('', size: 8),
                _cell('', size: 8),
                _cell('', size: 8),
                _cell(
                  Fmt.moneyRaw(c.income),
                  align: pw.TextAlign.center,
                  size: 9,
                  bold: true,
                  color: const PdfColor.fromInt(0xFF2E7D32),
                ),
                _cell(
                  Fmt.moneyRaw(c.expense),
                  align: pw.TextAlign.center,
                  size: 9,
                  bold: true,
                  color: _red,
                ),
                _cell('', size: 8),
              ],
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _sectionTitle(String text, int count) => pw.Container(
    padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 10),
    decoration: pw.BoxDecoration(
      color: _green,
      borderRadius: pw.BorderRadius.circular(7),
    ),
    child: pw.Row(
      children: [
        pw.Text(
          text,
          style: _s(size: 11.5, bold: true, color: PdfColors.white),
        ),
        pw.Spacer(),
        pw.Text(
          '$count',
          style: _s(size: 10, bold: true, color: PdfColors.white),
        ),
      ],
    ),
  );

  // -------------------------------------------------------- كتلة الزيارة

  pw.Widget _visitBlock(VisitFull vf) {
    final v = vf.visit;
    final t = vf.totals;

    // Inseparable يمنع انقسام الزيارة بين صفحتين، فلا يظهر اسم العميل
    // في صفحة وتفاصيله في التي تليها. لو كانت الزيارة أطول من صفحة
    // كاملة يسمح لها بالامتداد حتى لا تختفي.
    return pw.Inseparable(
      canSpan: vf.items.length > 12,
      child: pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 9),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _line),
          borderRadius: pw.BorderRadius.circular(9),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            // رأس الزيارة: الاسم والحالة والتاريخ
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                vertical: 7,
                horizontal: 10,
              ),
              decoration: const pw.BoxDecoration(
                color: _greyLight,
                borderRadius: pw.BorderRadius.only(
                  topRight: pw.Radius.circular(8),
                  topLeft: pw.Radius.circular(8),
                ),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          v.customerName,
                          style: _s(size: 11.5, bold: true),
                        ),
                        if (v.customerPhone.isNotEmpty ||
                            v.customerAddress.isNotEmpty)
                          pw.Text(
                            [
                              v.customerPhone,
                              v.customerAddress,
                            ].where((e) => e.isNotEmpty).join('  •  '),
                            style: _s(size: 8.5, color: _grey),
                          ),
                      ],
                    ),
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      _statusBadge(v.status),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        Fmt.dateTime(v.date),
                        style: _s(size: 8.5, color: _grey),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(10, 8, 10, 9),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (v.purpose.trim().isNotEmpty)
                    _kv('الهدف من الزيارة', v.purpose),
                  if (v.status == VisitStatus.notDone &&
                      v.notDoneReason.trim().isNotEmpty)
                    _kv('سبب عدم التنفيذ', v.notDoneReason, color: _red),
                  if (v.dayNotes.trim().isNotEmpty) _kv('ملاحظات', v.dayNotes),

                  if (vf.items.isNotEmpty) ...[
                    pw.SizedBox(height: 6),
                    _itemsTable(vf.items),
                  ],

                  if (vf.payments.isNotEmpty) ...[
                    pw.SizedBox(height: 6),
                    _paymentsLine(vf.payments),
                  ],

                  pw.SizedBox(height: 7),
                  _moneyRow(t),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  pw.Widget _statusBadge(VisitStatus s) {
    final color = switch (s) {
      VisitStatus.done => const PdfColor.fromInt(0xFF2E7D32),
      VisitStatus.notDone => _red,
      VisitStatus.partial => _amber,
    };
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: pw.BoxDecoration(
        color: color,
        borderRadius: pw.BorderRadius.circular(9),
      ),
      child: pw.Text(
        s.label,
        style: _s(size: 8, bold: true, color: PdfColors.white),
      ),
    );
  }

  pw.Widget _kv(String k, String v, {PdfColor? color}) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 3),
    child: pw.RichText(
      textDirection: pw.TextDirection.rtl,
      text: pw.TextSpan(
        children: [
          pw.TextSpan(
            text: '$k: ',
            style: _s(size: 9, bold: true, color: _grey),
          ),
          pw.TextSpan(
            text: v,
            style: _s(size: 9.5, color: color ?? PdfColors.black),
          ),
        ],
      ),
    ),
  );

  // ---------------------------------------------------------- جدول القطع

  pw.Widget _itemsTable(List<Item> items) {
    // نعرض عمود الملاحظات فقط إن كانت هناك ملاحظة على أي قطعة،
    // حتى لا نضيّع عرض الجدول بلا داعٍ.
    final hasNotes = items.any((i) => i.notes.trim().isNotEmpty);

    final headers = [
      '#',
      'الرقم التسلسلي SN',
      'الوصف',
      'الحركة',
      'الكمية',
      'السعر',
      'الإجمالي',
      if (hasNotes) 'ملاحظات',
    ];

    return pw.Table(
      border: pw.TableBorder.all(color: _line, width: 0.5),
      columnWidths: {
        0: const pw.FixedColumnWidth(18),
        1: const pw.FlexColumnWidth(2.4),
        2: pw.FlexColumnWidth(hasNotes ? 2.6 : 3.4),
        3: const pw.FixedColumnWidth(38),
        4: const pw.FixedColumnWidth(32),
        5: const pw.FlexColumnWidth(1.2),
        6: const pw.FlexColumnWidth(1.3),
        if (hasNotes) 7: const pw.FlexColumnWidth(1.9),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _greenLight),
          children: headers
              .map(
                (h) => pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                    vertical: 4,
                    horizontal: 3,
                  ),
                  child: pw.Text(
                    h,
                    style: _s(size: 8, bold: true, color: _green),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              )
              .toList(),
        ),
        ...items.asMap().entries.map((e) {
          final i = e.value;
          final isReturn = i.kind == MovementKind.returned;
          return pw.TableRow(
            decoration: isReturn
                ? const pw.BoxDecoration(color: PdfColor.fromInt(0xFFFDF6E9))
                : null,
            children: [
              _cell('${e.key + 1}', align: pw.TextAlign.center, size: 8),
              _cell(i.serial.isEmpty ? '—' : i.serial, size: 8, mono: true),
              _cell(i.description, size: 8.5),
              _cell(
                i.kind.label,
                align: pw.TextAlign.center,
                size: 8,
                color: isReturn ? _amber : _green,
                bold: true,
              ),
              _cell('${i.qty}', align: pw.TextAlign.center, size: 8.5),
              _cell(
                Fmt.moneyRaw(i.price),
                align: pw.TextAlign.center,
                size: 8.5,
              ),
              _cell(
                Fmt.moneyRaw(i.total),
                align: pw.TextAlign.center,
                size: 8.5,
                bold: true,
              ),
              if (hasNotes)
                _cell(i.notes.trim().isEmpty ? '—' : i.notes, size: 8),
            ],
          );
        }),
      ],
    );
  }

  pw.Widget _cell(
    String text, {
    pw.TextAlign align = pw.TextAlign.right,
    double size = 9,
    bool bold = false,
    PdfColor color = PdfColors.black,
    bool mono = false,
  }) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 3.5, horizontal: 4),
    child: pw.Text(
      text,
      style: _s(size: size, bold: bold, color: color),
      textAlign: align,
      textDirection: mono ? pw.TextDirection.ltr : null,
    ),
  );

  pw.Widget _paymentsLine(List<Payment> ps) => pw.Container(
    padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 7),
    decoration: pw.BoxDecoration(
      color: const PdfColor.fromInt(0xFFEFF7F0),
      borderRadius: pw.BorderRadius.circular(5),
    ),
    child: pw.Row(
      children: [
        pw.Text('الدفعات: ', style: _s(size: 8.5, bold: true, color: _grey)),
        pw.Expanded(
          child: pw.Text(
            ps
                .map(
                  (p) =>
                      '${Fmt.moneyShort(p.amount)} (${Fmt.date(p.date)})'
                      '${p.notes.isNotEmpty ? ' - ${p.notes}' : ''}',
                )
                .join('  |  '),
            style: _s(size: 8.5),
          ),
        ),
      ],
    ),
  );

  pw.Widget _moneyRow(Totals t) {
    final hasReturn = t.returnedTotal > 0.009;
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: pw.BoxDecoration(
        color: _greyLight,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Row(
        children: [
          _moneyChip('قيمة القطع', t.itemsTotal, PdfColors.black),
          if (hasReturn) _moneyChip('المرتجع', -t.returnedTotal, _amber),
          if (hasReturn) _moneyChip('الصافي', t.net, PdfColors.black),
          _moneyChip('المدفوع', t.paid, const PdfColor.fromInt(0xFF2E7D32)),
          _moneyChip(
            'المتبقي',
            t.remaining,
            t.remaining > 0.009 ? _red : const PdfColor.fromInt(0xFF2E7D32),
            bold: true,
          ),
        ],
      ),
    );
  }

  pw.Widget _moneyChip(
    String label,
    double value,
    PdfColor color, {
    bool bold = false,
  }) => pw.Expanded(
    child: pw.Column(
      children: [
        pw.Text(label, style: _s(size: 7.5, color: _grey)),
        pw.SizedBox(height: 1),
        pw.Text(
          Fmt.moneyShort(value),
          style: _s(size: 9.5, bold: bold || true, color: color),
        ),
      ],
    ),
  );

  // ---------------------------------------------------------- السحب الآجل

  pw.Widget _creditBlock(CreditFull cf) {
    final c = cf.credit;
    final t = cf.totals;

    return pw.Inseparable(
      canSpan: cf.items.length > 12,
      child: pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 9),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(
            color: c.settled ? _line : _amber,
            width: c.settled ? 0.5 : 0.9,
          ),
          borderRadius: pw.BorderRadius.circular(9),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                vertical: 7,
                horizontal: 10,
              ),
              decoration: pw.BoxDecoration(
                color: c.settled
                    ? _greyLight
                    : const PdfColor.fromInt(0xFFFDF3E3),
                borderRadius: const pw.BorderRadius.only(
                  topRight: pw.Radius.circular(8),
                  topLeft: pw.Radius.circular(8),
                ),
              ),
              child: pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          c.personName,
                          style: _s(size: 11.5, bold: true),
                        ),
                        if (c.personPhone.isNotEmpty)
                          pw.Text(
                            c.personPhone,
                            style: _s(size: 8.5, color: _grey),
                          ),
                      ],
                    ),
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: pw.BoxDecoration(
                          color: c.settled
                              ? const PdfColor.fromInt(0xFF2E7D32)
                              : _amber,
                          borderRadius: pw.BorderRadius.circular(9),
                        ),
                        child: pw.Text(
                          c.settled ? 'مسدَّد' : 'آجل',
                          style: _s(
                            size: 8,
                            bold: true,
                            color: PdfColors.white,
                          ),
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        Fmt.date(c.date),
                        style: _s(size: 8.5, color: _grey),
                      ),
                      if (c.dueDate != null)
                        pw.Text(
                          'الاستحقاق: ${Fmt.date(c.dueDate!)}',
                          style: _s(size: 8, color: _amber),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(10, 8, 10, 9),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (c.notes.trim().isNotEmpty) _kv('ملاحظات', c.notes),
                  if (cf.items.isNotEmpty) ...[
                    pw.SizedBox(height: 4),
                    _itemsTable(cf.items),
                  ],
                  if (cf.payments.isNotEmpty) ...[
                    pw.SizedBox(height: 6),
                    _paymentsLine(cf.payments),
                  ],
                  pw.SizedBox(height: 7),
                  _moneyRow(t),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------ الإجمالي العام

  pw.Widget _grandTotals(PeriodSummary s) {
    final v = s.visitTotals;
    final c = s.creditTotals;
    final g = s.grandTotals;

    pw.TableRow row(
      String label,
      Totals t, {
      bool bold = false,
      PdfColor? bg,
    }) => pw.TableRow(
      decoration: bg == null ? null : pw.BoxDecoration(color: bg),
      children: [
        _cell(label, size: 9.5, bold: true),
        _cell(
          Fmt.moneyRaw(t.itemsTotal),
          align: pw.TextAlign.center,
          size: 9.5,
          bold: bold,
        ),
        _cell(
          Fmt.moneyRaw(t.returnedTotal),
          align: pw.TextAlign.center,
          size: 9.5,
          bold: bold,
        ),
        _cell(
          Fmt.moneyRaw(t.net),
          align: pw.TextAlign.center,
          size: 9.5,
          bold: bold,
        ),
        _cell(
          Fmt.moneyRaw(t.paid),
          align: pw.TextAlign.center,
          size: 9.5,
          bold: bold,
          color: const PdfColor.fromInt(0xFF2E7D32),
        ),
        _cell(
          Fmt.moneyRaw(t.remaining),
          align: pw.TextAlign.center,
          size: 9.5,
          bold: true,
          color: t.remaining > 0.009
              ? _red
              : const PdfColor.fromInt(0xFF2E7D32),
        ),
      ],
    );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('الملخص المالي', 0),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.all(color: _line, width: 0.5),
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _greenLight),
              children:
                  [
                        'البيان',
                        'قيمة القطع',
                        'المرتجع',
                        'الصافي',
                        'المحصّل',
                        'المتبقي',
                      ]
                      .map(
                        (h) => pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(
                            vertical: 5,
                            horizontal: 4,
                          ),
                          child: pw.Text(
                            h,
                            style: _s(size: 9, bold: true, color: _green),
                            textAlign: pw.TextAlign.center,
                          ),
                        ),
                      )
                      .toList(),
            ),
            row('الزيارات', v),
            row('السحب الآجل', c),
            row('الإجمالي العام', g, bold: true, bg: _greyLight),
          ],
        ),
        pw.SizedBox(height: 10),
        _cashFlowBox(s),
        pw.SizedBox(height: 8),
        if (g.remaining > 0.009)
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 7, horizontal: 11),
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(0xFFFDECEC),
              borderRadius: pw.BorderRadius.circular(7),
              border: pw.Border.all(color: _red, width: 0.7),
            ),
            child: pw.Row(
              children: [
                pw.Text(
                  'المبلغ المتبقي في الذمة: ',
                  style: _s(size: 11, bold: true),
                ),
                pw.Text(
                  Fmt.money(g.remaining),
                  style: _s(size: 12, bold: true, color: _red),
                ),
              ],
            ),
          )
        else
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 7, horizontal: 11),
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(0xFFEAF5EB),
              borderRadius: pw.BorderRadius.circular(7),
              border: pw.Border.all(
                color: const PdfColor.fromInt(0xFF2E7D32),
                width: 0.7,
              ),
            ),
            child: pw.Text(
              'لا توجد مبالغ متبقية — الحساب مسدَّد بالكامل',
              style: _s(
                size: 11,
                bold: true,
                color: const PdfColor.fromInt(0xFF2E7D32),
              ),
            ),
          ),
        // الخاتمة ملتصقة بالملخص داخل نفس العنصر، فلا تُدفع إلى صفحة جديدة
        pw.SizedBox(height: 14),
        _reportFooterLine(),
      ],
    );
  }

  /// خلاصة حركة النقد: كل درهم دخل وخرج في الفترة
  pw.Widget _cashFlowBox(PeriodSummary s) {
    final c = s.cashTotals;
    final collected = s.grandTotals.paid;
    final totalIn = collected + c.income;
    final net = totalIn - c.expense;

    pw.Widget line(
      String label,
      double value,
      PdfColor color, {
      bool bold = false,
    }) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
      child: pw.Row(
        children: [
          pw.Text(
            label,
            style: _s(size: bold ? 10.5 : 9.5, bold: bold, color: _grey),
          ),
          pw.Expanded(child: pw.SizedBox()),
          pw.Text(
            Fmt.money(value),
            style: _s(size: bold ? 11.5 : 10, bold: true, color: color),
          ),
        ],
      ),
    );

    return pw.Container(
      padding: const pw.EdgeInsets.all(11),
      decoration: pw.BoxDecoration(
        color: _greyLight,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: _line, width: 0.6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            'حركة النقد في الفترة',
            style: _s(size: 11, bold: true, color: _green),
          ),
          pw.SizedBox(height: 5),
          line(
            'المحصّل من الزيارات والسحوبات',
            collected,
            const PdfColor.fromInt(0xFF2E7D32),
          ),
          line(
            'الوارد الآخر (بيع، سداد دين، رسوم رخصة...)',
            c.income,
            const PdfColor.fromInt(0xFF2E7D32),
          ),
          pw.Divider(color: _line, height: 8),
          line(
            'إجمالي الداخل',
            totalIn,
            const PdfColor.fromInt(0xFF2E7D32),
            bold: true,
          ),
          line('إجمالي الخارج (مصاريف ومشتريات)', c.expense, _red),
          pw.Divider(color: _line, height: 8),
          line(
            'صافي حركة النقد',
            net,
            net >= 0 ? const PdfColor.fromInt(0xFF1565C0) : _red,
            bold: true,
          ),
          if (s.salariesTotal > 0.009)
            line('منها رواتب مدفوعة', s.salariesTotal, _red),
          if (s.hasTransfers) ...[
            pw.Divider(color: _line, height: 8),
            line(
              s.internalTransfers < 0
                  ? 'أُودع في البنك (تحويل داخلي)'
                  : 'سُحب من البنك (تحويل داخلي)',
              s.internalTransfers.abs(),
              const PdfColor.fromInt(0xFF1565C0),
            ),
            pw.Text(
              'التحويل بين الكاش والبنك ينقل المال ولا يُعدّ دخلًا ولا مصروفًا',
              style: _s(size: 8, color: _grey),
            ),
          ],
          pw.Divider(color: _line, height: 8),
          line(
            'حركة الكاش في الفترة (نقدًا)',
            s.periodCashFlow.balance,
            s.periodCashFlow.balance >= 0
                ? const PdfColor.fromInt(0xFF2E7D32)
                : _red,
          ),
        ],
      ),
    );
  }

  /// خاتمة التقرير: سطر واحد بلا أسماء
  pw.Widget _reportFooterLine() => pw.Column(
    children: [
      pw.Container(
        height: 0.8,
        color: _line,
        margin: const pw.EdgeInsets.only(bottom: 6),
      ),
      pw.Text('تقرير اليوم', style: _s(size: 10, bold: true, color: _grey)),
    ],
  );

  // ------------------------------------------------------- حفظ الملف

  /// يكتب ملف PDF في مجلد مؤقت ويعيد مساره — جاهز للمشاركة
  Future<File> saveToFile(Uint8List bytes, String fileName) async {
    final dir = await getTemporaryDirectory();
    final reports = Directory(p.join(dir.path, 'reports'));
    if (!await reports.exists()) await reports.create(recursive: true);
    final file = File(p.join(reports.path, fileName));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// اسم ملف وصفي بالعربية والتاريخ
  /// اسم ملف التقرير.
  ///
  /// لاتيني بالكامل: مزوّد الملفات في أندرويد (FileProvider) الذي تستخدمه
  /// المشاركة والطباعة يفشل مع بعض الأحرف العربية في اسم الملف، وهو فشل
  /// يقع في الطبقة الأصلية فيُسقط التطبيق بلا رسالة. لذلك نبقي الاسم
  /// بالحروف والأرقام اللاتينية فقط.
  static String fileNameFor(PeriodSummary s, {String prefix = 'Report'}) {
    String d(DateTime x) =>
        '${x.year}-${x.month.toString().padLeft(2, '0')}-'
        '${x.day.toString().padLeft(2, '0')}';

    final sameDay = s.from.year == s.to.year &&
        s.from.month == s.to.month &&
        s.from.day == s.to.day;

    return sameDay
        ? '${prefix}_${d(s.from)}.pdf'
        : '${prefix}_${d(s.from)}_to_${d(s.to)}.pdf';
  }

  /// ينظّف أي اسم ملف من الأحرف التي قد يرفضها نظام الملفات أو المشاركة
  static String safeFileName(String name) {
    final cleaned = name
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
    return cleaned.isEmpty ? 'file' : cleaned;
  }

  /// اسم لاتيني بسيط لمهمة الطباعة.
  ///
  /// إطار الطباعة في أندرويد يتعامل مع اسم المهمة كنص نظام، وقد يفشل
  /// أو يتصرّف بشكل غير متوقّع مع الأحرف العربية أو الامتداد. لذلك نستخدم
  /// اسمًا بالأرقام والحروف اللاتينية فقط عند المعاينة والطباعة.
  static String printJobName(PeriodSummary s) {
    String d(DateTime x) =>
        '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';

    final sameDay =
        s.from.year == s.to.year &&
        s.from.month == s.to.month &&
        s.from.day == s.to.day;
    return sameDay
        ? 'Report_${d(s.from)}'
        : 'Report_${d(s.from)}_to_${d(s.to)}';
  }
}
