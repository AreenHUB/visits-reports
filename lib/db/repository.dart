import 'dart:convert';

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../models/models.dart';
import 'app_database.dart';

/// طبقة الوصول للبيانات: كل الاستعلامات التي تحتاجها الشاشات والتقارير
class Repository {
  Repository._();
  static final Repository instance = Repository._();

  Future<Database> get _db async => AppDatabase.instance.database;

  // ------------------------------------------------------------- العملاء

  Future<List<Customer>> customers({String? search}) async {
    final db = await _db;
    final rows = search == null || search.trim().isEmpty
        ? await db.query('customers', orderBy: 'name COLLATE NOCASE ASC')
        : await db.query(
            'customers',
            where: 'name LIKE ? OR phone LIKE ? OR address LIKE ?',
            whereArgs: List.filled(3, '%${search.trim()}%'),
            orderBy: 'name COLLATE NOCASE ASC',
          );
    return rows.map(Customer.fromMap).toList();
  }

  Future<Customer?> customerById(String id) async {
    final db = await _db;
    final rows = await db.query('customers', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Customer.fromMap(rows.first);
  }

  Future<void> saveCustomer(Customer c) async {
    final db = await _db;
    await db.insert('customers', c.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteCustomer(String id) async {
    final db = await _db;
    await db.delete('customers', where: 'id = ?', whereArgs: [id]);
  }

  /// يجد عميلًا بنفس الاسم والهاتف أو ينشئ واحدًا جديدًا
  Future<Customer> findOrCreateCustomer({
    required String name,
    String phone = '',
    String address = '',
  }) async {
    final db = await _db;
    final rows = await db.query(
      'customers',
      where: 'name = ? AND phone = ?',
      whereArgs: [name.trim(), phone.trim()],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final existing = Customer.fromMap(rows.first);
      // نحدّث العنوان إن كان فارغًا سابقًا
      if (existing.address.trim().isEmpty && address.trim().isNotEmpty) {
        existing.address = address.trim();
        await saveCustomer(existing);
      }
      return existing;
    }
    final c = Customer(
      id: AppDatabase.newId(),
      name: name.trim(),
      phone: phone.trim(),
      address: address.trim(),
      createdAt: DateTime.now(),
    );
    await saveCustomer(c);
    return c;
  }

  // ------------------------------------------------------------- الزيارات

  Future<List<Visit>> visits({
    DateTime? from,
    DateTime? to,
    String? customerId,
    String? search,
    int? limit,
  }) async {
    final db = await _db;
    final where = <String>[];
    final args = <Object?>[];

    if (from != null) {
      where.add('date >= ?');
      args.add(AppDatabase.dayStart(from).millisecondsSinceEpoch);
    }
    if (to != null) {
      where.add('date <= ?');
      args.add(AppDatabase.dayEnd(to).millisecondsSinceEpoch);
    }
    if (customerId != null) {
      where.add('customer_id = ?');
      args.add(customerId);
    }
    if (search != null && search.trim().isNotEmpty) {
      where.add('(customer_name LIKE ? OR purpose LIKE ? OR day_notes LIKE ? OR customer_phone LIKE ?)');
      args.addAll(List.filled(4, '%${search.trim()}%'));
    }

    final rows = await db.query(
      'visits',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'date DESC, created_at DESC',
      limit: limit,
    );
    return rows.map(Visit.fromMap).toList();
  }

  Future<Visit?> visitById(String id) async {
    final db = await _db;
    final rows = await db.query('visits', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Visit.fromMap(rows.first);
  }

  /// الزيارة مع قطعها ودفعاتها
  Future<VisitFull?> visitFull(String id) async {
    final v = await visitById(id);
    if (v == null) return null;
    return VisitFull(
      visit: v,
      items: await itemsForVisit(id),
      payments: await paymentsForVisit(id),
    );
  }

  /// يجلب عدة زيارات كاملة دفعة واحدة — يستخدمه مولّد التقارير
  Future<List<VisitFull>> visitsFull({
    DateTime? from,
    DateTime? to,
    String? customerId,
    String? search,
  }) async {
    final list = await visits(from: from, to: to, customerId: customerId, search: search);
    if (list.isEmpty) return [];

    final db = await _db;
    final ids = list.map((v) => v.id).toList();
    final placeholders = List.filled(ids.length, '?').join(',');

    final itemRows = await db.query(
      'items',
      where: 'visit_id IN ($placeholders)',
      whereArgs: ids,
      orderBy: 'sort_order ASC, created_at ASC',
    );
    final payRows = await db.query(
      'payments',
      where: 'visit_id IN ($placeholders)',
      whereArgs: ids,
      orderBy: 'date ASC',
    );

    final itemsByVisit = <String, List<Item>>{};
    for (final r in itemRows) {
      final it = AppDatabase.itemFromMap(r);
      itemsByVisit.putIfAbsent(it.visitId!, () => []).add(it);
    }
    final paysByVisit = <String, List<Payment>>{};
    for (final r in payRows) {
      final p = Payment.fromMap(r);
      paysByVisit.putIfAbsent(p.visitId!, () => []).add(p);
    }

    return list
        .map((v) => VisitFull(
              visit: v,
              items: itemsByVisit[v.id] ?? const [],
              payments: paysByVisit[v.id] ?? const [],
            ))
        .toList();
  }

  Future<void> saveVisit(Visit v) async {
    final db = await _db;
    v.updatedAt = DateTime.now();
    await db.insert('visits', v.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteVisit(String id) async {
    final db = await _db;
    // القطع والدفعات تُحذف تلقائيًا بفضل ON DELETE CASCADE
    await db.delete('visits', where: 'id = ?', whereArgs: [id]);
  }

  // ------------------------------------------------------- السحب الآجل

  Future<List<CreditRecord>> credits({
    DateTime? from,
    DateTime? to,
    String? search,
    bool? settled,
    bool onlyUnpaid = false,
  }) async {
    final db = await _db;
    final where = <String>[];
    final args = <Object?>[];

    if (from != null) {
      where.add('date >= ?');
      args.add(AppDatabase.dayStart(from).millisecondsSinceEpoch);
    }
    if (to != null) {
      where.add('date <= ?');
      args.add(AppDatabase.dayEnd(to).millisecondsSinceEpoch);
    }
    if (settled != null) {
      where.add('settled = ?');
      args.add(settled ? 1 : 0);
    }
    if (search != null && search.trim().isNotEmpty) {
      where.add('(person_name LIKE ? OR person_phone LIKE ? OR notes LIKE ?)');
      args.addAll(List.filled(3, '%${search.trim()}%'));
    }

    final rows = await db.query(
      'credits',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'date DESC, created_at DESC',
    );
    return rows.map(CreditRecord.fromMap).toList();
  }

  Future<CreditRecord?> creditById(String id) async {
    final db = await _db;
    final rows = await db.query('credits', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : CreditRecord.fromMap(rows.first);
  }

  Future<CreditFull?> creditFull(String id) async {
    final c = await creditById(id);
    if (c == null) return null;
    return CreditFull(
      credit: c,
      items: await itemsForCredit(id),
      payments: await paymentsForCredit(id),
    );
  }

  Future<List<CreditFull>> creditsFull({
    DateTime? from,
    DateTime? to,
    String? search,
    bool? settled,
  }) async {
    final list = await credits(from: from, to: to, search: search, settled: settled);
    if (list.isEmpty) return [];

    final db = await _db;
    final ids = list.map((c) => c.id).toList();
    final placeholders = List.filled(ids.length, '?').join(',');

    final itemRows = await db.query(
      'items',
      where: 'credit_id IN ($placeholders)',
      whereArgs: ids,
      orderBy: 'sort_order ASC, created_at ASC',
    );
    final payRows = await db.query(
      'payments',
      where: 'credit_id IN ($placeholders)',
      whereArgs: ids,
      orderBy: 'date ASC',
    );

    final itemsByCredit = <String, List<Item>>{};
    for (final r in itemRows) {
      final it = AppDatabase.itemFromMap(r);
      itemsByCredit.putIfAbsent(it.creditId!, () => []).add(it);
    }
    final paysByCredit = <String, List<Payment>>{};
    for (final r in payRows) {
      final p = Payment.fromMap(r);
      paysByCredit.putIfAbsent(p.creditId!, () => []).add(p);
    }

    return list
        .map((c) => CreditFull(
              credit: c,
              items: itemsByCredit[c.id] ?? const [],
              payments: paysByCredit[c.id] ?? const [],
            ))
        .toList();
  }

  Future<void> saveCredit(CreditRecord c) async {
    final db = await _db;
    c.updatedAt = DateTime.now();
    await db.insert('credits', c.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteCredit(String id) async {
    final db = await _db;
    await db.delete('credits', where: 'id = ?', whereArgs: [id]);
  }

  // --------------------------------------------------------------- القطع

  Future<List<Item>> itemsForVisit(String visitId) async {
    final db = await _db;
    final rows = await db.query(
      'items',
      where: 'visit_id = ?',
      whereArgs: [visitId],
      orderBy: 'sort_order ASC, created_at ASC',
    );
    return rows.map(AppDatabase.itemFromMap).toList();
  }

  Future<List<Item>> itemsForCredit(String creditId) async {
    final db = await _db;
    final rows = await db.query(
      'items',
      where: 'credit_id = ?',
      whereArgs: [creditId],
      orderBy: 'sort_order ASC, created_at ASC',
    );
    return rows.map(AppDatabase.itemFromMap).toList();
  }

  Future<void> saveItem(Item i) async {
    final db = await _db;
    await db.insert('items', AppDatabase.itemToMap(i),
        conflictAlgorithm: ConflictAlgorithm.replace);
    if (i.serial.trim().isNotEmpty) await rememberSerial(i);
  }

  /// يستبدل كل قطع زيارة/سحب دفعة واحدة داخل معاملة
  Future<void> replaceItems({
    String? visitId,
    String? creditId,
    required List<Item> items,
  }) async {
    final db = await _db;
    await db.transaction((txn) async {
      if (visitId != null) {
        await txn.delete('items', where: 'visit_id = ?', whereArgs: [visitId]);
      } else if (creditId != null) {
        await txn.delete('items', where: 'credit_id = ?', whereArgs: [creditId]);
      }
      for (var idx = 0; idx < items.length; idx++) {
        final it = items[idx]
          ..visitId = visitId
          ..creditId = creditId
          ..sortOrder = idx;
        await txn.insert('items', AppDatabase.itemToMap(it),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });

    for (final it in items) {
      if (it.serial.trim().isNotEmpty) await rememberSerial(it);
    }
  }

  Future<void> deleteItem(String id) async {
    final db = await _db;
    await db.delete('items', where: 'id = ?', whereArgs: [id]);
  }

  /// تتبّع سيريال: أين ذهبت هذه القطعة ومتى — سجل كامل بالترتيب الزمني
  Future<List<SerialTrace>> traceSerial(String serial) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT i.*,
             v.customer_name AS v_name, v.date AS v_date,
             c.person_name  AS c_name, c.date AS c_date
      FROM items i
      LEFT JOIN visits  v ON v.id = i.visit_id
      LEFT JOIN credits c ON c.id = i.credit_id
      WHERE i.serial = ? COLLATE NOCASE
      ORDER BY COALESCE(v.date, c.date, i.created_at) DESC
    ''', [serial.trim()]);

    return rows.map((r) {
      final item = AppDatabase.itemFromMap(r);
      final isVisit = r['visit_id'] != null;
      return SerialTrace(
        item: item,
        isVisit: isVisit,
        partyName: (isVisit ? r['v_name'] : r['c_name']) as String? ?? '',
        date: DateTime.fromMillisecondsSinceEpoch(
          ((isVisit ? r['v_date'] : r['c_date']) as int?) ??
              item.createdAt.millisecondsSinceEpoch,
        ),
        recordId: (isVisit ? r['visit_id'] : r['credit_id']) as String,
      );
    }).toList();
  }

  // --------------------------------------------------- ذاكرة السيريالات

  /// يحفظ ما تعلّمه التطبيق عن هذا السيريال ليقترحه لاحقًا
  Future<void> rememberSerial(Item i) async {
    final serial = i.serial.trim();
    if (serial.isEmpty) return;
    final db = await _db;
    final existing = await db.query('serial_memory',
        where: 'serial = ? COLLATE NOCASE', whereArgs: [serial], limit: 1);

    await db.insert(
      'serial_memory',
      {
        'serial': serial,
        'type_key': i.typeKey,
        'type_label': i.typeLabel,
        'custom_name': i.customName,
        'specs': jsonEncode(i.specs),
        'last_price': i.price,
        'use_count': existing.isEmpty ? 1 : (((existing.first['use_count'] as int?) ?? 0) + 1),
        'last_used': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// اقتراح للسيريال: مطابقة تامة أولًا، ثم مطابقة بالبادئة (نفس دفعة القطع)
  Future<SerialMemory?> suggestForSerial(String serial) async {
    final s = serial.trim();
    if (s.isEmpty) return null;
    final db = await _db;

    final exact = await db.query('serial_memory',
        where: 'serial = ? COLLATE NOCASE', whereArgs: [s], limit: 1);
    if (exact.isNotEmpty) return _memoryFromMap(exact.first);

    // نجرّب بادئات متناقصة الطول: القطع من نفس الموديل تتشارك بداية السيريال
    for (final len in [10, 8, 6, 5, 4]) {
      if (s.length <= len) continue;
      final rows = await db.query(
        'serial_memory',
        where: 'serial LIKE ? COLLATE NOCASE',
        whereArgs: ['${s.substring(0, len)}%'],
        orderBy: 'use_count DESC, last_used DESC',
        limit: 1,
      );
      if (rows.isNotEmpty) return _memoryFromMap(rows.first);
    }
    return null;
  }

  /// آخر الأنواع المستخدمة — تظهر كاختصارات سريعة
  Future<List<SerialMemory>> recentTypes({int limit = 8}) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT * FROM serial_memory
      GROUP BY type_key, custom_name
      ORDER BY last_used DESC
      LIMIT ?
    ''', [limit]);
    return rows.map(_memoryFromMap).toList();
  }

  SerialMemory _memoryFromMap(Map<String, Object?> m) => SerialMemory(
        serial: m['serial'] as String,
        typeKey: (m['type_key'] as String?) ?? 'other',
        typeLabel: (m['type_label'] as String?) ?? 'أخرى',
        customName: (m['custom_name'] as String?) ?? '',
        specs: AppDatabase.decodeSpecs(m['specs']),
        lastPrice: ((m['last_price'] as num?) ?? 0).toDouble(),
        useCount: ((m['use_count'] as num?) ?? 1).toInt(),
        lastUsed: DateTime.fromMillisecondsSinceEpoch((m['last_used'] as int?) ?? 0),
      );

  // ------------------------------------------------------------ الدفعات

  Future<List<Payment>> paymentsForVisit(String visitId) async {
    final db = await _db;
    final rows =
        await db.query('payments', where: 'visit_id = ?', whereArgs: [visitId], orderBy: 'date ASC');
    return rows.map(Payment.fromMap).toList();
  }

  Future<List<Payment>> paymentsForCredit(String creditId) async {
    final db = await _db;
    final rows = await db.query('payments',
        where: 'credit_id = ?', whereArgs: [creditId], orderBy: 'date ASC');
    return rows.map(Payment.fromMap).toList();
  }

  Future<void> savePayment(Payment p) async {
    final db = await _db;
    await db.insert('payments', p.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deletePayment(String id) async {
    final db = await _db;
    await db.delete('payments', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> replacePayments({
    String? visitId,
    String? creditId,
    required List<Payment> payments,
  }) async {
    final db = await _db;
    await db.transaction((txn) async {
      if (visitId != null) {
        await txn.delete('payments', where: 'visit_id = ?', whereArgs: [visitId]);
      } else if (creditId != null) {
        await txn.delete('payments', where: 'credit_id = ?', whereArgs: [creditId]);
      }
      for (final p in payments) {
        p.visitId = visitId;
        p.creditId = creditId;
        await txn.insert('payments', p.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  // ------------------------------------------------- الحركات المالية

  Future<List<CashEntry>> cashEntries({
    DateTime? from,
    DateTime? to,
    CashDirection? direction,
    String? search,
  }) async {
    final db = await _db;
    final where = <String>[];
    final args = <Object?>[];

    if (from != null) {
      where.add('date >= ?');
      args.add(AppDatabase.dayStart(from).millisecondsSinceEpoch);
    }
    if (to != null) {
      where.add('date <= ?');
      args.add(AppDatabase.dayEnd(to).millisecondsSinceEpoch);
    }
    if (direction != null) {
      where.add('direction = ?');
      args.add(direction.name);
    }
    if (search != null && search.trim().isNotEmpty) {
      where.add('(description LIKE ? OR party_name LIKE ? OR notes LIKE ? OR category_label LIKE ?)');
      args.addAll(List.filled(4, '%${search.trim()}%'));
    }

    final rows = await db.query(
      'cash_entries',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'date DESC, created_at DESC',
    );
    return rows.map(CashEntry.fromMap).toList();
  }

  Future<CashEntry?> cashEntryById(String id) async {
    final db = await _db;
    final rows =
        await db.query('cash_entries', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : CashEntry.fromMap(rows.first);
  }

  Future<void> saveCashEntry(CashEntry e) async {
    final db = await _db;
    e.updatedAt = DateTime.now();
    await db.insert('cash_entries', e.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);

    // تحصيل دين من عميل مرتبط بسجل دين: يُخصم من رصيد ذلك الدين
    // مباشرة، فلا يحتاج المستخدم لتسجيله مرتين.
    if (e.linkedDebtId != null) {
      await _applyDebtCollection(e);
    }

    // سداد دين مرتبط بسحب آجل يُسجَّل أيضًا كدفعة على ذلك السحب،
    // حتى يبقى رصيد السحب صحيحًا في مكان واحد.
    if (e.linkedCreditId != null) {
      await db.delete('payments', where: 'id = ?', whereArgs: ['cash_${e.id}']);
      if (e.direction == CashDirection.income) {
        await db.insert(
          'payments',
          Payment(
            id: 'cash_${e.id}',
            creditId: e.linkedCreditId,
            amount: e.amount,
            date: e.date,
            notes: e.description.isEmpty ? e.categoryLabel : e.description,
          ).toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await _refreshCreditSettlement(e.linkedCreditId!);
    }
  }

  Future<void> deleteCashEntry(String id) async {
    final db = await _db;
    final entry = await cashEntryById(id);

    // نتراجع عن أثر الحركة على الدين قبل حذفها
    if (entry?.linkedDebtId != null) {
      await _revertDebtCollection(entry!);
    }

    await db.delete('payments', where: 'id = ?', whereArgs: ['cash_$id']);
    await db.delete('cash_entries', where: 'id = ?', whereArgs: [id]);

    if (entry?.linkedCreditId != null) {
      await _refreshCreditSettlement(entry!.linkedCreditId!);
    }
  }

  /// يعيد حساب المسدَّد على دين عميل من مجموع الحركات المرتبطة به.
  ///
  /// نحسبه من الحركات بدل الجمع التراكمي حتى يبقى صحيحًا مهما
  /// عُدِّلت الحركات أو حُذفت.
  Future<void> _applyDebtCollection(CashEntry e) async {
    final debt = await debtById(e.linkedDebtId!);
    if (debt == null) return;
    await _recomputeDebtPaid(debt);
  }

  Future<void> _revertDebtCollection(CashEntry e) async {
    final debt = await debtById(e.linkedDebtId!);
    if (debt == null) return;
    await _recomputeDebtPaid(debt, excludeEntryId: e.id);
  }

  /// يجمع كل الحركات المرتبطة بالدين ويكتب الناتج في حقل المسدَّد
  Future<void> _recomputeDebtPaid(
    DebtRecord debt, {
    String? excludeEntryId,
  }) async {
    final db = await _db;
    final rows = await db.rawQuery(
      "SELECT COALESCE(SUM(amount), 0) AS v FROM cash_entries "
      "WHERE linked_debt_id = ? AND direction = 'income'"
      "${excludeEntryId == null ? '' : ' AND id != ?'}",
      [debt.id, ?excludeEntryId],
    );

    final collected = ((rows.first['v'] as num?) ?? 0).toDouble();

    // ما سُجِّل يدويًا على الدين قبل الربط يبقى محفوظًا
    final manual = debt.manualPaid;
    await db.update(
      'debts',
      {
        'paid': manual + collected,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [debt.id],
    );
  }

  /// الديون غير المسدَّدة — لربط تحصيل الدين بها
  Future<List<DebtRecord>> unpaidDebts() async {
    final all = await debts(activeOnly: true);
    return all.where((d) => d.remaining > 0.009).toList();
  }

  /// يعيد حساب حالة السداد لسحب آجل بعد تغيّر دفعاته
  Future<void> _refreshCreditSettlement(String creditId) async {
    final cf = await creditFull(creditId);
    if (cf == null) return;
    final settled = cf.totals.remaining <= 0.009 && cf.items.isNotEmpty;
    if (settled != cf.credit.settled) {
      await saveCredit(cf.credit.copyWith(settled: settled));
    }
  }

  /// السحوبات الآجلة التي ما زال عليها رصيد — لربط سداد الدين بها
  Future<List<CreditFull>> unsettledCredits() async {
    final all = await creditsFull(settled: false);
    return all.where((c) => c.totals.remaining > 0.009).toList();
  }

  // ---------------------------------------------------- ملاحظات اليوم

  /// ملاحظة عامة على يوم كامل، تظهر في أعلى التقرير اليومي
  Future<String> dayNote(DateTime day) async {
    final db = await _db;
    final key = AppDatabase.dayStart(day).millisecondsSinceEpoch;
    final rows =
        await db.query('day_notes', where: 'day = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? '' : (rows.first['notes'] as String?) ?? '';
  }

  Future<void> setDayNote(DateTime day, String notes) async {
    final db = await _db;
    final key = AppDatabase.dayStart(day).millisecondsSinceEpoch;
    if (notes.trim().isEmpty) {
      await db.delete('day_notes', where: 'day = ?', whereArgs: [key]);
      return;
    }
    await db.insert(
      'day_notes',
      {
        'day': key,
        'notes': notes.trim(),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// كل ملاحظات الأيام ضمن فترة، مرتّبة زمنيًا
  Future<List<DayNote>> dayNotesInRange(DateTime from, DateTime to) async {
    final db = await _db;
    final rows = await db.query(
      'day_notes',
      where: 'day >= ? AND day <= ?',
      whereArgs: [
        AppDatabase.dayStart(from).millisecondsSinceEpoch,
        AppDatabase.dayEnd(to).millisecondsSinceEpoch,
      ],
      orderBy: 'day ASC',
    );
    return rows
        .map((r) => DayNote(
              day: DateTime.fromMillisecondsSinceEpoch(r['day'] as int),
              notes: (r['notes'] as String?) ?? '',
            ))
        .where((n) => n.notes.trim().isNotEmpty)
        .toList();
  }

  // ------------------------------------------------------ رصيد الكاش

  /// رصيد الكاش داخل المحل: النقد فقط، دون البطاقة أو التحويل.
  ///
  /// يجمع كل ما دخل نقدًا (دفعات الزيارات والسحوبات والوارد المستقل)
  /// ناقص كل ما خرج نقدًا (المصاريف ودفعات الرواتب).
  /// رصيد الكاش داخل المحل: النقد فقط، دون البطاقة أو التحويل البنكي.
  ///
  /// [upTo] يحدّ الحساب حتى نهاية ذلك اليوم (الرصيد التراكمي حتى تاريخ).
  /// [from] يحصر الحساب في فترة (حركة الكاش في يوم أو مدى).
  ///
  /// التحويل الداخلي بين الكاش والبنك يُحتسب هنا لأنه ينقل نقدًا فعليًا
  /// من الدرج أو إليه، وإن كان لا يُعدّ دخلًا ولا مصروفًا للمحل.
  Future<CashBalance> cashBalance({DateTime? upTo, DateTime? from}) async {
    final db = await _db;

    final upperMs =
        upTo == null ? null : AppDatabase.dayEnd(upTo).millisecondsSinceEpoch;
    final lowerMs =
        from == null ? null : AppDatabase.dayStart(from).millisecondsSinceEpoch;

    String range(String col) {
      final parts = <String>[];
      if (lowerMs != null) parts.add(' AND $col >= $lowerMs');
      if (upperMs != null) parts.add(' AND $col <= $upperMs');
      return parts.join();
    }

    // الوارد النقدي المستقل (بما فيه السحب من البنك)
    final incomeRow = await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) AS v FROM cash_entries
      WHERE direction = 'income' AND method = 'cash'${range('date')}
    ''');

    // الصادر النقدي (بما فيه الإيداع في البنك)
    final expenseRow = await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) AS v FROM cash_entries
      WHERE direction = 'expense' AND method = 'cash'
        AND id NOT LIKE 'salary_%'${range('date')}
    ''');

    // رواتب مدفوعة نقدًا
    final salaryRow = await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) AS v FROM salary_payments
      WHERE method = 'cash'${range('date')}
    ''');

    // دفعات الزيارات والسحوبات النقدية.
    // الدفعات التي أنشأتها حركة صندوق (id يبدأ بـ cash_) مستبعدة
    // لأن الحركة نفسها محسوبة أعلاه، فلا تُحتسب مرتين.
    final visitPayRow = await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) AS v FROM payments
      WHERE method = 'cash' AND id NOT LIKE 'cash_%'${range('date')}
    ''');

    double val(List<Map<String, Object?>> rows) =>
        ((rows.first['v'] as num?) ?? 0).toDouble();

    return CashBalance(
      cashIn: val(incomeRow) + val(visitPayRow),
      cashOut: val(expenseRow) + val(salaryRow),
    );
  }

  /// حركة الكاش في يوم واحد — كم دخل الدرج وكم خرج منه ذلك اليوم
  Future<CashBalance> dayCashFlow(DateTime day) =>
      cashBalance(from: day, upTo: day);

  /// صورة كاملة عن الكاش: حركة اليوم والرصيد المتراكم حتى نهايته
  Future<CashSnapshot> cashSnapshot(DateTime day) async {
    final today = await dayCashFlow(day);
    final running = await cashBalance(upTo: day);
    return CashSnapshot(day: today, running: running);
  }

  // ------------------------------------------------------- الموظفون

  Future<List<Employee>> employees({bool? active, String? search}) async {
    final db = await _db;
    final where = <String>[];
    final args = <Object?>[];

    if (active != null) {
      where.add('active = ?');
      args.add(active ? 1 : 0);
    }
    if (search != null && search.trim().isNotEmpty) {
      where.add('(name LIKE ? OR phone LIKE ? OR role LIKE ?)');
      args.addAll(List.filled(3, '%${search.trim()}%'));
    }

    final rows = await db.query(
      'employees',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'active DESC, name COLLATE NOCASE ASC',
    );
    return rows.map(Employee.fromMap).toList();
  }

  Future<Employee?> employeeById(String id) async {
    final db = await _db;
    final rows = await db.query('employees', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Employee.fromMap(rows.first);
  }

  Future<void> saveEmployee(Employee e) async {
    final db = await _db;
    e.updatedAt = DateTime.now();
    await db.insert('employees', e.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);

    // نحدّث الاسم المنسوخ في الدفعات ليبقى العرض متّسقًا
    await db.update('salary_payments', {'employee_name': e.name},
        where: 'employee_id = ?', whereArgs: [e.id]);
  }

  Future<void> deleteEmployee(String id) async {
    final db = await _db;
    await db.delete('employees', where: 'id = ?', whereArgs: [id]);
  }

  Future<EmployeeFull?> employeeFull(String id) async {
    final e = await employeeById(id);
    if (e == null) return null;
    return EmployeeFull(employee: e, payments: await salaryPaymentsFor(id));
  }

  /// كل الموظفين مع دفعاتهم دفعة واحدة
  Future<List<EmployeeFull>> employeesFull({bool? active}) async {
    final list = await employees(active: active);
    if (list.isEmpty) return [];

    final db = await _db;
    final rows = await db.query('salary_payments', orderBy: 'date DESC');
    final byEmployee = <String, List<SalaryPayment>>{};
    for (final r in rows) {
      final p = SalaryPayment.fromMap(r);
      byEmployee.putIfAbsent(p.employeeId, () => []).add(p);
    }

    return list
        .map((e) =>
            EmployeeFull(employee: e, payments: byEmployee[e.id] ?? const []))
        .toList();
  }

  Future<List<SalaryPayment>> salaryPaymentsFor(String employeeId) async {
    final db = await _db;
    final rows = await db.query('salary_payments',
        where: 'employee_id = ?', whereArgs: [employeeId], orderBy: 'date DESC');
    return rows.map(SalaryPayment.fromMap).toList();
  }

  /// دفعات الرواتب ضمن فترة — تُستخدم في التقرير
  Future<List<SalaryPayment>> salaryPayments({DateTime? from, DateTime? to}) async {
    final db = await _db;
    final where = <String>[];
    final args = <Object?>[];

    if (from != null) {
      where.add('date >= ?');
      args.add(AppDatabase.dayStart(from).millisecondsSinceEpoch);
    }
    if (to != null) {
      where.add('date <= ?');
      args.add(AppDatabase.dayEnd(to).millisecondsSinceEpoch);
    }

    final rows = await db.query(
      'salary_payments',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'date DESC',
    );
    return rows.map(SalaryPayment.fromMap).toList();
  }

  Future<void> saveSalaryPayment(SalaryPayment p) async {
    final db = await _db;
    await db.insert('salary_payments', p.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);

    // نسجّل قيدًا مرآةً في الصندوق ليظهر الراتب ضمن صادر اليوم،
    // فيرى المستخدم سبب نقص الكاش في مكانه الطبيعي.
    await _syncSalaryCashEntry(p);
  }

  Future<void> deleteSalaryPayment(String id) async {
    final db = await _db;
    await db.delete('salary_payments', where: 'id = ?', whereArgs: [id]);
    await db.delete('cash_entries', where: 'id = ?', whereArgs: ['salary_$id']);
  }

  /// معرّف القيد المرآة لدفعة راتب
  static String salaryEntryId(String paymentId) => 'salary_$paymentId';

  /// ينشئ أو يحدّث قيد الصندوق المقابل لدفعة راتب.
  ///
  /// القيد يحمل معرّفًا مشتقًا من الدفعة، ويُستبعد من حساب الكاش
  /// حتى لا يُخصم المبلغ مرتين (مرة من جدول الرواتب ومرة من الصندوق).
  Future<void> _syncSalaryCashEntry(SalaryPayment p) async {
    final db = await _db;
    final id = salaryEntryId(p.id);
    final now = DateTime.now();

    await db.insert(
      'cash_entries',
      CashEntry(
        id: id,
        direction: CashDirection.expense,
        categoryKey: CashCategory.salary.key,
        categoryLabel: CashCategory.salary.label,
        description: '${p.kind.label} — ${p.employeeName}',
        partyName: p.employeeName,
        amount: p.amount,
        method: p.method,
        date: p.date,
        notes: p.notes,
        createdAt: now,
        updatedAt: now,
      ).toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // --------------------------------------------------- ديون العملاء

  Future<List<DebtRecord>> debts({String? search, bool activeOnly = false}) async {
    final db = await _db;
    final where = <String>[];
    final args = <Object?>[];

    if (search != null && search.trim().isNotEmpty) {
      where.add('(person_name LIKE ? OR person_phone LIKE ? OR reason LIKE ?)');
      args.addAll(List.filled(3, '%${search.trim()}%'));
    }
    if (activeOnly) where.add('(amount - paid) > 0.009');

    final rows = await db.query(
      'debts',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'date DESC',
    );
    return rows.map(DebtRecord.fromMap).toList();
  }

  Future<DebtRecord?> debtById(String id) async {
    final db = await _db;
    final rows = await db.query('debts', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : DebtRecord.fromMap(rows.first);
  }

  Future<void> saveDebt(DebtRecord d) async {
    final db = await _db;
    d.updatedAt = DateTime.now();
    await db.insert('debts', d.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteDebt(String id) async {
    final db = await _db;
    await db.delete('debts', where: 'id = ?', whereArgs: [id]);
  }

  /// إجمالي ما لنا عند الناس من ديون غير مسدَّدة
  Future<double> totalDebtsOutstanding() async {
    final db = await _db;
    final rows = await db.rawQuery(
        'SELECT COALESCE(SUM(amount - paid), 0) AS v FROM debts WHERE (amount - paid) > 0.009');
    return ((rows.first['v'] as num?) ?? 0).toDouble();
  }

  // ------------------------------------------------- خيارات التقرير

  Future<ReportOptions> reportOptions() async =>
      ReportOptions.fromMap(await allSettings());

  Future<void> saveReportOptions(ReportOptions o) async {
    for (final e in o.toMap().entries) {
      await setSetting(e.key, e.value);
    }
  }

  // ---------------------------------------------------------- الإعدادات

  Future<String?> setting(String key) async {
    final db = await _db;
    final rows = await db.query('settings', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await _db;
    await db.insert('settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, String>> allSettings() async {
    final db = await _db;
    final rows = await db.query('settings');
    return {
      for (final r in rows) r['key'] as String: (r['value'] as String?) ?? '',
    };
  }

  // ---------------------------------------------------- ملخصات وإحصاءات

  /// ملخص فترة: يستخدمه التقرير اليومي والشهري ولوحة المعلومات
  Future<PeriodSummary> summary({required DateTime from, required DateTime to}) async {
    final vs = await visitsFull(from: from, to: to);
    final cs = await creditsFull(from: from, to: to);
    final cash = await cashEntries(from: from, to: to);
    final notes = await dayNotesInRange(from, to);
    final salaries = await salaryPayments(from: from, to: to);
    final debtList = await debts(activeOnly: true);
    final balance = await cashBalance(upTo: to);
    final periodCash = await cashBalance(from: from, upTo: to);

    var visitTotals = const Totals();
    for (final v in vs) {
      visitTotals = visitTotals + v.totals;
    }
    var creditTotals = const Totals();
    for (final c in cs) {
      creditTotals = creditTotals + c.totals;
    }

    return PeriodSummary(
      from: from,
      to: to,
      visits: vs,
      credits: cs,
      cash: cash,
      dayNotes: notes,
      salaries: salaries,
      debts: debtList,
      cashBalance: balance,
      periodCashFlow: periodCash,
      visitTotals: visitTotals,
      creditTotals: creditTotals,
    );
  }

  /// إجمالي الديون غير المسددة (زيارات + سحب آجل)
  Future<double> totalOutstanding() async {
    final db = await _db;

    final visitRow = await db.rawQuery('''
      SELECT
        (SELECT COALESCE(SUM(CASE WHEN kind = 'out' THEN price * qty ELSE -price * qty END), 0)
         FROM items WHERE visit_id IS NOT NULL) -
        (SELECT COALESCE(SUM(amount), 0) FROM payments WHERE visit_id IS NOT NULL) AS due
    ''');
    final creditRow = await db.rawQuery('''
      SELECT
        (SELECT COALESCE(SUM(CASE WHEN kind = 'out' THEN price * qty ELSE -price * qty END), 0)
         FROM items i JOIN credits c ON c.id = i.credit_id WHERE c.settled = 0) -
        (SELECT COALESCE(SUM(p.amount), 0)
         FROM payments p JOIN credits c ON c.id = p.credit_id WHERE c.settled = 0) AS due
    ''');

    final a = ((visitRow.first['due'] as num?) ?? 0).toDouble();
    final b = ((creditRow.first['due'] as num?) ?? 0).toDouble();
    return a + b;
  }
}

/// أثر سيريال واحد عبر الزيارات والسحوبات
class SerialTrace {
  final Item item;
  final bool isVisit;
  final String partyName;
  final DateTime date;
  final String recordId;

  const SerialTrace({
    required this.item,
    required this.isVisit,
    required this.partyName,
    required this.date,
    required this.recordId,
  });
}

/// ملخص فترة زمنية — المادة الخام للتقارير
class PeriodSummary {
  final DateTime from;
  final DateTime to;
  final List<VisitFull> visits;
  final List<CreditFull> credits;

  /// الحركات المالية المستقلة عن الزيارات
  final List<CashEntry> cash;

  /// ملاحظات الأيام ضمن الفترة
  final List<DayNote> dayNotes;

  /// دفعات الرواتب ضمن الفترة
  final List<SalaryPayment> salaries;

  /// الديون غير المسدَّدة (كل الديون القائمة، لا المرتبطة بالفترة فقط)
  final List<DebtRecord> debts;

  /// رصيد الكاش داخل المحل حتى نهاية الفترة (تراكمي)
  final CashBalance cashBalance;

  /// حركة الكاش داخل الفترة نفسها: كم دخل الدرج وكم خرج منه
  final CashBalance periodCashFlow;

  final Totals visitTotals;
  final Totals creditTotals;

  const PeriodSummary({
    required this.from,
    required this.to,
    required this.visits,
    required this.credits,
    this.cash = const [],
    this.dayNotes = const [],
    this.salaries = const [],
    this.debts = const [],
    this.cashBalance = const CashBalance(),
    this.periodCashFlow = const CashBalance(),
    required this.visitTotals,
    required this.creditTotals,
  });

  int get visitCount => visits.length;
  int get doneCount => visits.where((v) => v.visit.status == VisitStatus.done).length;
  int get notDoneCount => visits.where((v) => v.visit.status == VisitStatus.notDone).length;
  int get partialCount => visits.where((v) => v.visit.status == VisitStatus.partial).length;

  int get itemsOutCount =>
      visits.fold(0, (s, v) => s + v.outItems.fold(0, (a, i) => a + i.qty));
  int get itemsReturnedCount =>
      visits.fold(0, (s, v) => s + v.returnedItems.fold(0, (a, i) => a + i.qty));

  Totals get grandTotals => visitTotals + creditTotals;

  /// إجماليات الصندوق: الوارد والصادر المستقلان عن الزيارات
  CashTotals get cashTotals => CashTotals.from(cash);

  List<CashEntry> get income =>
      cash.where((e) => e.direction == CashDirection.income).toList();
  List<CashEntry> get expenses =>
      cash.where((e) => e.direction == CashDirection.expense).toList();

  /// الحركات مجمّعة حسب التصنيف، لعرضها ملخّصة في التقرير
  Map<String, List<CashEntry>> cashByCategory(CashDirection d) {
    final map = <String, List<CashEntry>>{};
    for (final e in cash.where((e) => e.direction == d)) {
      map.putIfAbsent(e.categoryLabel, () => []).add(e);
    }
    return map;
  }

  /// صافي حركة النقد في الفترة:
  /// ما حُصّل من الزيارات والسحوبات + الوارد المستقل - الصادر
  double get netCashFlow => grandTotals.paid + cashTotals.net;

  /// إجمالي الرواتب المدفوعة في الفترة
  double get salariesTotal => salaries.fold(0.0, (s, p) => s + p.amount);

  /// الرواتب مجمّعة حسب الموظف
  Map<String, List<SalaryPayment>> get salariesByEmployee {
    final map = <String, List<SalaryPayment>>{};
    for (final p in salaries) {
      map.putIfAbsent(p.employeeName, () => []).add(p);
    }
    return map;
  }

  /// إجمالي الديون القائمة على العملاء
  double get debtsTotal => debts.fold(0.0, (s, d) => s + d.remaining);

  /// صافي التحويلات الداخلية بين الكاش والبنك في الفترة.
  ///
  /// سالب يعني أن مالًا انتقل من الدرج إلى البنك، وموجب يعني العكس.
  /// هذا ليس دخلًا ولا مصروفًا — المال يبقى ملك المحل.
  double get internalTransfers => CashTotals.transfersOf(cash);

  /// هل في الفترة تحويلات داخلية تستحق العرض؟
  bool get hasTransfers => internalTransfers.abs() > 0.009;

  bool get isEmpty =>
      visits.isEmpty && credits.isEmpty && cash.isEmpty && salaries.isEmpty;
}

/// رصيد الكاش داخل المحل — النقد فقط
class CashBalance {
  final double cashIn;
  final double cashOut;

  const CashBalance({this.cashIn = 0, this.cashOut = 0});

  double get balance => cashIn - cashOut;
}

/// صورة الكاش في يوم: حركته ذلك اليوم، والرصيد المتراكم حتى نهايته
class CashSnapshot {
  /// ما دخل وخرج نقدًا في هذا اليوم وحده
  final CashBalance day;

  /// الرصيد المتراكم منذ البداية حتى نهاية هذا اليوم
  final CashBalance running;

  const CashSnapshot({
    this.day = const CashBalance(),
    this.running = const CashBalance(),
  });

  /// صافي حركة اليوم: موجب إذا زاد الدرج، سالب إذا نقص
  double get dayNet => day.balance;

  /// الكاش الموجود فعليًا في نهاية اليوم
  double get closingBalance => running.balance;

  /// الرصيد في بداية اليوم = رصيد النهاية ناقص حركة اليوم
  double get openingBalance => running.balance - day.balance;
}

/// ملاحظة عامة على يوم كامل
class DayNote {
  final DateTime day;
  final String notes;

  const DayNote({required this.day, required this.notes});
}
