import 'dart:io';

import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../db/repository.dart';
import '../models/models.dart';
import '../utils/formatting.dart';

/// تصدير البيانات إلى ملف إكسل متعدد الأوراق
class ExcelService {
  ExcelService._();
  static final ExcelService instance = ExcelService._();

  static const _headerColor = '#0E7C66';

  Future<File> export(PeriodSummary s, {String? fileName}) async {
    final excel = Excel.createExcel();

    _buildVisitsSheet(excel, s);
    _buildItemsSheet(excel, s);
    _buildCreditsSheet(excel, s);
    _buildPaymentsSheet(excel, s);
    _buildCashSheet(excel, s);
    if (s.salaries.isNotEmpty) _buildSalariesSheet(excel, s);
    if (s.debts.isNotEmpty) _buildDebtsSheet(excel, s);
    _buildSummarySheet(excel, s);

    // نحذف الورقة الافتراضية الفارغة
    if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');

    final bytes = excel.encode();
    if (bytes == null) {
      throw Exception('تعذّر إنشاء ملف الإكسل');
    }

    final dir = await getTemporaryDirectory();
    final out = Directory(p.join(dir.path, 'reports'));
    if (!await out.exists()) await out.create(recursive: true);

    final name = fileName ?? _defaultName(s);
    final file = File(p.join(out.path, name));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// اسم لاتيني للسبب نفسه المذكور في PdfService.fileNameFor
  static String _defaultName(PeriodSummary s) {
    String d(DateTime x) =>
        '${x.year}-${x.month.toString().padLeft(2, '0')}-'
        '${x.day.toString().padLeft(2, '0')}';

    final sameDay = s.from.year == s.to.year &&
        s.from.month == s.to.month &&
        s.from.day == s.to.day;

    return sameDay
        ? 'Report_${d(s.from)}.xlsx'
        : 'Report_${d(s.from)}_to_${d(s.to)}.xlsx';
  }

  // ------------------------------------------------------------- الأوراق

  void _buildVisitsSheet(Excel excel, PeriodSummary s) {
    final sheet = excel['الزيارات'];
    _headerRow(sheet, [
      'التاريخ',
      'اليوم',
      'الوقت',
      'اسم العميل',
      'رقم الهاتف',
      'العنوان',
      'الهدف من الزيارة',
      'الحالة',
      'سبب عدم التنفيذ',
      'عدد القطع الصادرة',
      'عدد القطع الراجعة',
      'قيمة القطع',
      'قيمة المرتجع',
      'الصافي',
      'المدفوع',
      'المتبقي',
      'ملاحظات اليوم',
    ]);

    for (final vf in s.visits) {
      final v = vf.visit;
      final t = vf.totals;
      sheet.appendRow([
        TextCellValue(Fmt.date(v.date)),
        TextCellValue(Fmt.weekday(v.date)),
        TextCellValue(Fmt.time(v.date)),
        TextCellValue(v.customerName),
        TextCellValue(v.customerPhone),
        TextCellValue(v.customerAddress),
        TextCellValue(v.purpose),
        TextCellValue(v.status.label),
        TextCellValue(v.notDoneReason),
        IntCellValue(vf.outItems.fold(0, (a, i) => a + i.qty)),
        IntCellValue(vf.returnedItems.fold(0, (a, i) => a + i.qty)),
        DoubleCellValue(t.itemsTotal),
        DoubleCellValue(t.returnedTotal),
        DoubleCellValue(t.net),
        DoubleCellValue(t.paid),
        DoubleCellValue(t.remaining),
        TextCellValue(v.dayNotes),
      ]);
    }

    _totalsRow(sheet, [
      'الإجمالي',
      '',
      '',
      '',
      '',
      '',
      '',
      '',
      '',
    ], [
      s.itemsOutCount.toDouble(),
      s.itemsReturnedCount.toDouble(),
      s.visitTotals.itemsTotal,
      s.visitTotals.returnedTotal,
      s.visitTotals.net,
      s.visitTotals.paid,
      s.visitTotals.remaining,
    ]);

    _autoWidth(sheet, 17);
  }

  void _buildItemsSheet(Excel excel, PeriodSummary s) {
    final sheet = excel['القطع'];
    _headerRow(sheet, [
      'التاريخ',
      'الجهة',
      'الاسم',
      'الرقم التسلسلي SN',
      'نوع القطعة',
      'التسمية / الوصف',
      'التفاصيل',
      'الحركة',
      'الكمية',
      'السعر',
      'الإجمالي',
      'ملاحظات',
    ]);

    void addItems(List<Item> items, String source, String party, DateTime date) {
      for (final i in items) {
        sheet.appendRow([
          TextCellValue(Fmt.date(date)),
          TextCellValue(source),
          TextCellValue(party),
          TextCellValue(i.serial),
          TextCellValue(i.typeLabel),
          TextCellValue(i.customName.isEmpty ? i.description : i.customName),
          TextCellValue(i.specsSummary),
          TextCellValue(i.kind.label),
          IntCellValue(i.qty),
          DoubleCellValue(i.price),
          DoubleCellValue(i.total),
          TextCellValue(i.notes),
        ]);
      }
    }

    for (final vf in s.visits) {
      addItems(vf.items, 'زيارة', vf.visit.customerName, vf.visit.date);
    }
    for (final cf in s.credits) {
      addItems(cf.items, 'سحب آجل', cf.credit.personName, cf.credit.date);
    }

    _autoWidth(sheet, 12);
  }

  void _buildCreditsSheet(Excel excel, PeriodSummary s) {
    final sheet = excel['السحب الآجل'];
    _headerRow(sheet, [
      'التاريخ',
      'اسم الشخص',
      'رقم الهاتف',
      'تاريخ الاستحقاق',
      'عدد القطع',
      'قيمة القطع',
      'المرتجع',
      'الصافي',
      'المدفوع',
      'المتبقي',
      'الحالة',
      'ملاحظات',
    ]);

    for (final cf in s.credits) {
      final c = cf.credit;
      final t = cf.totals;
      sheet.appendRow([
        TextCellValue(Fmt.date(c.date)),
        TextCellValue(c.personName),
        TextCellValue(c.personPhone),
        TextCellValue(c.dueDate == null ? '' : Fmt.date(c.dueDate!)),
        IntCellValue(cf.items.fold(0, (a, i) => a + i.qty)),
        DoubleCellValue(t.itemsTotal),
        DoubleCellValue(t.returnedTotal),
        DoubleCellValue(t.net),
        DoubleCellValue(t.paid),
        DoubleCellValue(t.remaining),
        TextCellValue(c.settled ? 'مسدَّد' : 'آجل'),
        TextCellValue(c.notes),
      ]);
    }

    _totalsRow(sheet, ['الإجمالي', '', '', '', ''], [
      s.creditTotals.itemsTotal,
      s.creditTotals.returnedTotal,
      s.creditTotals.net,
      s.creditTotals.paid,
      s.creditTotals.remaining,
    ]);

    _autoWidth(sheet, 12);
  }

  void _buildPaymentsSheet(Excel excel, PeriodSummary s) {
    final sheet = excel['الدفعات'];
    _headerRow(sheet, ['التاريخ', 'الجهة', 'الاسم', 'المبلغ', 'ملاحظات']);

    for (final vf in s.visits) {
      for (final pay in vf.payments) {
        sheet.appendRow([
          TextCellValue(Fmt.date(pay.date)),
          TextCellValue('زيارة'),
          TextCellValue(vf.visit.customerName),
          DoubleCellValue(pay.amount),
          TextCellValue(pay.notes),
        ]);
      }
    }
    for (final cf in s.credits) {
      for (final pay in cf.payments) {
        sheet.appendRow([
          TextCellValue(Fmt.date(pay.date)),
          TextCellValue('سحب آجل'),
          TextCellValue(cf.credit.personName),
          DoubleCellValue(pay.amount),
          TextCellValue(pay.notes),
        ]);
      }
    }

    _totalsRow(sheet, ['الإجمالي', '', ''], [s.grandTotals.paid]);
    _autoWidth(sheet, 5);
  }

  /// ورقة الحركات المالية المستقلة: كل درهم دخل أو خرج
  void _buildCashSheet(Excel excel, PeriodSummary s) {
    final sheet = excel['الحركات المالية'];
    _headerRow(sheet, [
      'التاريخ',
      'الوقت',
      'الاتجاه',
      'التصنيف',
      'البيان',
      'الجهة / الزبون',
      'طريقة الدفع',
      'وارد',
      'صادر',
      'مرتبط بدين',
      'ملاحظات',
    ]);

    for (final e in s.cash) {
      final isIncome = e.direction == CashDirection.income;
      sheet.appendRow([
        TextCellValue(Fmt.date(e.date)),
        TextCellValue(Fmt.time(e.date)),
        TextCellValue(e.direction.label),
        TextCellValue(e.categoryLabel),
        TextCellValue(e.description),
        TextCellValue(e.partyName),
        TextCellValue(e.method.label),
        DoubleCellValue(isIncome ? e.amount : 0),
        DoubleCellValue(isIncome ? 0 : e.amount),
        TextCellValue(e.linkedCreditId == null ? '' : 'نعم'),
        TextCellValue(e.notes),
      ]);
    }

    final c = s.cashTotals;
    _totalsRow(sheet, ['الإجمالي', '', '', '', '', '', ''], [c.income, c.expense]);
    _autoWidth(sheet, 11);
  }

  /// ورقة رواتب الموظفين
  void _buildSalariesSheet(Excel excel, PeriodSummary s) {
    final sheet = excel['رواتب الموظفين'];
    _headerRow(sheet, [
      'التاريخ',
      'الموظف',
      'نوع الدفعة',
      'عن شهر',
      'طريقة الدفع',
      'المبلغ',
      'ملاحظات',
    ]);

    for (final p in s.salaries) {
      sheet.appendRow([
        TextCellValue(Fmt.date(p.date)),
        TextCellValue(p.employeeName),
        TextCellValue(p.kind.label),
        TextCellValue(p.forMonth == null ? '' : Fmt.monthName(p.forMonth!)),
        TextCellValue(p.method.label),
        DoubleCellValue(p.amount),
        TextCellValue(p.notes),
      ]);
    }

    _totalsRow(sheet, ['الإجمالي', '', '', '', ''], [s.salariesTotal]);
    _autoWidth(sheet, 7);
  }

  /// ورقة ديون العملاء
  void _buildDebtsSheet(Excel excel, PeriodSummary s) {
    final sheet = excel['ديون العملاء'];
    _headerRow(sheet, [
      'التاريخ',
      'الاسم',
      'الهاتف',
      'العنوان',
      'السبب',
      'تاريخ الاستحقاق',
      'مبلغ الدين',
      'المسدَّد',
      'المتبقي',
      'الحالة',
      'ملاحظات',
    ]);

    for (final d in s.debts) {
      sheet.appendRow([
        TextCellValue(Fmt.date(d.date)),
        TextCellValue(d.personName),
        TextCellValue(d.personPhone),
        TextCellValue(d.personAddress),
        TextCellValue(d.reason),
        TextCellValue(d.dueDate == null ? '' : Fmt.date(d.dueDate!)),
        DoubleCellValue(d.amount),
        DoubleCellValue(d.paid),
        DoubleCellValue(d.remaining),
        TextCellValue(d.isOverdue ? 'متأخر' : (d.isPaidOff ? 'مسدَّد' : 'قائم')),
        TextCellValue(d.notes),
      ]);
    }

    _totalsRow(
      sheet,
      ['الإجمالي', '', '', '', '', ''],
      [
        s.debts.fold(0.0, (a, d) => a + d.amount),
        s.debts.fold(0.0, (a, d) => a + d.paid),
        s.debtsTotal,
      ],
    );
    _autoWidth(sheet, 11);
  }

  void _buildSummarySheet(Excel excel, PeriodSummary s) {
    final sheet = excel['الملخص'];
    final g = s.grandTotals;

    void line(String k, Object v, {bool bold = false}) {
      sheet.appendRow([
        TextCellValue(k),
        v is num ? DoubleCellValue(v.toDouble()) : TextCellValue('$v'),
      ]);
      if (bold) {
        final r = sheet.maxRows - 1;
        for (var c = 0; c < 2; c++) {
          sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r))
              .cellStyle = CellStyle(bold: true);
        }
      }
    }

    _headerRow(sheet, ['البيان', 'القيمة']);
    line('الفترة', Fmt.range(s.from, s.to));
    line('عدد الزيارات', s.visitCount);
    line('زيارات تمت', s.doneCount);
    line('زيارات لم تتم', s.notDoneCount);
    line('زيارات جزئية', s.partialCount);
    line('عدد السحوبات الآجلة', s.credits.length);
    line('قطع صادرة', s.itemsOutCount);
    line('قطع راجعة', s.itemsReturnedCount);
    line('', '');
    line('قيمة القطع - الزيارات', s.visitTotals.itemsTotal);
    line('المحصّل - الزيارات', s.visitTotals.paid);
    line('المتبقي - الزيارات', s.visitTotals.remaining);
    line('', '');
    line('قيمة القطع - السحب الآجل', s.creditTotals.itemsTotal);
    line('المحصّل - السحب الآجل', s.creditTotals.paid);
    line('المتبقي - السحب الآجل', s.creditTotals.remaining);
    line('', '');
    line('إجمالي قيمة القطع', g.itemsTotal, bold: true);
    line('إجمالي المرتجع', g.returnedTotal, bold: true);
    line('الصافي', g.net, bold: true);
    line('إجمالي المحصّل', g.paid, bold: true);
    line('إجمالي المتبقي', g.remaining, bold: true);
    line('', '');
    line('الوارد الآخر (بيع، سداد دين، رخص...)', s.cashTotals.income);
    line('الصادر (مصاريف ومشتريات)', s.cashTotals.expense);
    line('إجمالي الداخل', g.paid + s.cashTotals.income, bold: true);
    line('صافي حركة النقد', s.netCashFlow, bold: true);
    line('', '');
    line('الكاش الموجود في المحل (نقدًا فقط)', s.cashBalance.balance, bold: true);
    if (s.salaries.isNotEmpty) {
      line('', '');
      line('رواتب مدفوعة في الفترة', s.salariesTotal);
    }
    if (s.debts.isNotEmpty) {
      line('', '');
      line('ديون قائمة على العملاء', s.debtsTotal);
    }

    if (s.dayNotes.isNotEmpty) {
      line('', '');
      line('ملاحظات الأيام', '');
      for (final n in s.dayNotes) {
        line(Fmt.date(n.day), n.notes);
      }
    }

    sheet.setColumnWidth(0, 30);
    sheet.setColumnWidth(1, 22);
  }

  // ------------------------------------------------------------- المساعدات

  void _headerRow(Sheet sheet, List<String> headers) {
    sheet.appendRow(headers.map<CellValue?>(TextCellValue.new).toList());
    for (var c = 0; c < headers.length; c++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0)).cellStyle = CellStyle(
        bold: true,
        fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
        backgroundColorHex: ExcelColor.fromHexString(_headerColor),
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
      );
    }
  }

  /// صف إجماليات في نهاية الورقة: نصوص أولًا ثم أرقام
  void _totalsRow(Sheet sheet, List<String> labels, List<double> values) {
    sheet.appendRow([
      ...labels.map<CellValue?>(TextCellValue.new),
      ...values.map<CellValue?>(DoubleCellValue.new),
    ]);
    final r = sheet.maxRows - 1;
    for (var c = 0; c < labels.length + values.length; c++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r)).cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#E6F2EF'),
      );
    }
  }

  void _autoWidth(Sheet sheet, int columns) {
    for (var c = 0; c < columns; c++) {
      sheet.setColumnWidth(c, 16);
    }
  }
}
