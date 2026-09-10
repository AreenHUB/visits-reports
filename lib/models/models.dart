// نماذج البيانات الأساسية للتطبيق

/// حالة الزيارة
enum VisitStatus { done, notDone, partial }

extension VisitStatusX on VisitStatus {
  String get label => switch (this) {
        VisitStatus.done => 'تمت',
        VisitStatus.notDone => 'لم تتم',
        VisitStatus.partial => 'جزئية',
      };

  static VisitStatus fromCode(String? c) =>
      VisitStatus.values.firstWhere((e) => e.name == c, orElse: () => VisitStatus.done);
}

/// نوع حركة القطعة: صادر للعميل / وارد راجع للمحل
enum MovementKind { out, returned }

extension MovementKindX on MovementKind {
  String get label => this == MovementKind.out ? 'صادر' : 'راجع';

  static MovementKind fromCode(String? c) =>
      MovementKind.values.firstWhere((e) => e.name == c, orElse: () => MovementKind.out);
}

/// العميل
class Customer {
  final String id;
  String name;
  String phone;
  String address;
  String notes;
  final DateTime createdAt;

  Customer({
    required this.id,
    required this.name,
    this.phone = '',
    this.address = '',
    this.notes = '',
    required this.createdAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'phone': phone,
        'address': address,
        'notes': notes,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory Customer.fromMap(Map<String, Object?> m) => Customer(
        id: m['id'] as String,
        name: (m['name'] as String?) ?? '',
        phone: (m['phone'] as String?) ?? '',
        address: (m['address'] as String?) ?? '',
        notes: (m['notes'] as String?) ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch((m['created_at'] as int?) ?? 0),
      );

  Customer copyWith({String? name, String? phone, String? address, String? notes}) => Customer(
        id: id,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        address: address ?? this.address,
        notes: notes ?? this.notes,
        createdAt: createdAt,
      );
}

/// الزيارة
class Visit {
  final String id;
  String customerId;

  // نسخة من بيانات العميل وقت الزيارة، حتى لو تغيّرت لاحقًا يبقى التقرير صحيحًا
  String customerName;
  String customerPhone;
  String customerAddress;

  DateTime date;
  String purpose;
  VisitStatus status;
  String notDoneReason;
  String dayNotes;
  String signaturePath;
  final DateTime createdAt;
  DateTime updatedAt;

  Visit({
    required this.id,
    required this.customerId,
    required this.customerName,
    this.customerPhone = '',
    this.customerAddress = '',
    required this.date,
    this.purpose = '',
    this.status = VisitStatus.done,
    this.notDoneReason = '',
    this.dayNotes = '',
    this.signaturePath = '',
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'customer_id': customerId,
        'customer_name': customerName,
        'customer_phone': customerPhone,
        'customer_address': customerAddress,
        'date': date.millisecondsSinceEpoch,
        'purpose': purpose,
        'status': status.name,
        'not_done_reason': notDoneReason,
        'day_notes': dayNotes,
        'signature_path': signaturePath,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory Visit.fromMap(Map<String, Object?> m) => Visit(
        id: m['id'] as String,
        customerId: (m['customer_id'] as String?) ?? '',
        customerName: (m['customer_name'] as String?) ?? '',
        customerPhone: (m['customer_phone'] as String?) ?? '',
        customerAddress: (m['customer_address'] as String?) ?? '',
        date: DateTime.fromMillisecondsSinceEpoch((m['date'] as int?) ?? 0),
        purpose: (m['purpose'] as String?) ?? '',
        status: VisitStatusX.fromCode(m['status'] as String?),
        notDoneReason: (m['not_done_reason'] as String?) ?? '',
        dayNotes: (m['day_notes'] as String?) ?? '',
        signaturePath: (m['signature_path'] as String?) ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch((m['created_at'] as int?) ?? 0),
        updatedAt: DateTime.fromMillisecondsSinceEpoch((m['updated_at'] as int?) ?? 0),
      );

  Visit copyWith({
    String? customerId,
    String? customerName,
    String? customerPhone,
    String? customerAddress,
    DateTime? date,
    String? purpose,
    VisitStatus? status,
    String? notDoneReason,
    String? dayNotes,
    String? signaturePath,
  }) =>
      Visit(
        id: id,
        customerId: customerId ?? this.customerId,
        customerName: customerName ?? this.customerName,
        customerPhone: customerPhone ?? this.customerPhone,
        customerAddress: customerAddress ?? this.customerAddress,
        date: date ?? this.date,
        purpose: purpose ?? this.purpose,
        status: status ?? this.status,
        notDoneReason: notDoneReason ?? this.notDoneReason,
        dayNotes: dayNotes ?? this.dayNotes,
        signaturePath: signaturePath ?? this.signaturePath,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );
}

/// قطعة ضمن زيارة أو ضمن سحب آجل
class Item {
  final String id;

  // ترتبط القطعة بزيارة أو بسحب آجل — أحدهما فقط
  String? visitId;
  String? creditId;

  String serial;

  /// مفتاح نوع القطعة (camera / switch / nvr / router / ap / repeater / other)
  String typeKey;
  String typeLabel;

  /// تسمية يدوية اختيارية تُكتب بجانب القطعة
  String customName;

  /// الحقول التفصيلية، تختلف حسب النوع، تُحفظ كـ JSON
  Map<String, Object?> specs;

  double price;
  int qty;
  MovementKind kind;
  String notes;
  int sortOrder;
  final DateTime createdAt;

  Item({
    required this.id,
    this.visitId,
    this.creditId,
    this.serial = '',
    required this.typeKey,
    required this.typeLabel,
    this.customName = '',
    Map<String, Object?>? specs,
    this.price = 0,
    this.qty = 1,
    this.kind = MovementKind.out,
    this.notes = '',
    this.sortOrder = 0,
    required this.createdAt,
  }) : specs = specs ?? {};

  double get total => price * qty;

  /// وصف مختصر يظهر في القوائم والتقارير
  String get description {
    final name = customName.trim();
    if (name.isNotEmpty) return name;
    final summary = specsSummary;
    return summary.isEmpty ? typeLabel : '$typeLabel - $summary';
  }

  String get specsSummary => specs.entries
      .where((e) => e.value != null && e.value != false && '${e.value}'.trim().isNotEmpty)
      .map((e) => e.value == true ? e.key : '${e.value}')
      .join('، ');

  Item copyWith({
    String? serial,
    String? typeKey,
    String? typeLabel,
    String? customName,
    Map<String, Object?>? specs,
    double? price,
    int? qty,
    MovementKind? kind,
    String? notes,
    int? sortOrder,
  }) =>
      Item(
        id: id,
        visitId: visitId,
        creditId: creditId,
        serial: serial ?? this.serial,
        typeKey: typeKey ?? this.typeKey,
        typeLabel: typeLabel ?? this.typeLabel,
        customName: customName ?? this.customName,
        specs: specs ?? Map<String, Object?>.from(this.specs),
        price: price ?? this.price,
        qty: qty ?? this.qty,
        kind: kind ?? this.kind,
        notes: notes ?? this.notes,
        sortOrder: sortOrder ?? this.sortOrder,
        createdAt: createdAt,
      );
}

/// سحب آجل: متعامل سحب قطعًا من المحل بالدين
class CreditRecord {
  final String id;
  String personName;
  String personPhone;
  DateTime date;
  DateTime? dueDate;
  String notes;
  String signaturePath;
  bool settled;
  final DateTime createdAt;
  DateTime updatedAt;

  CreditRecord({
    required this.id,
    required this.personName,
    this.personPhone = '',
    required this.date,
    this.dueDate,
    this.notes = '',
    this.signaturePath = '',
    this.settled = false,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'person_name': personName,
        'person_phone': personPhone,
        'date': date.millisecondsSinceEpoch,
        'due_date': dueDate?.millisecondsSinceEpoch,
        'notes': notes,
        'signature_path': signaturePath,
        'settled': settled ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory CreditRecord.fromMap(Map<String, Object?> m) => CreditRecord(
        id: m['id'] as String,
        personName: (m['person_name'] as String?) ?? '',
        personPhone: (m['person_phone'] as String?) ?? '',
        date: DateTime.fromMillisecondsSinceEpoch((m['date'] as int?) ?? 0),
        dueDate:
            m['due_date'] == null ? null : DateTime.fromMillisecondsSinceEpoch(m['due_date'] as int),
        notes: (m['notes'] as String?) ?? '',
        signaturePath: (m['signature_path'] as String?) ?? '',
        settled: ((m['settled'] as int?) ?? 0) == 1,
        createdAt: DateTime.fromMillisecondsSinceEpoch((m['created_at'] as int?) ?? 0),
        updatedAt: DateTime.fromMillisecondsSinceEpoch((m['updated_at'] as int?) ?? 0),
      );

  CreditRecord copyWith({
    String? personName,
    String? personPhone,
    DateTime? date,
    DateTime? dueDate,
    bool clearDueDate = false,
    String? notes,
    String? signaturePath,
    bool? settled,
  }) =>
      CreditRecord(
        id: id,
        personName: personName ?? this.personName,
        personPhone: personPhone ?? this.personPhone,
        date: date ?? this.date,
        dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
        notes: notes ?? this.notes,
        signaturePath: signaturePath ?? this.signaturePath,
        settled: settled ?? this.settled,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );
}

/// دفعة على حساب زيارة أو سحب آجل، لتتبع السداد التدريجي
class Payment {
  final String id;
  String? visitId;
  String? creditId;
  double amount;
  DateTime date;
  String notes;

  Payment({
    required this.id,
    this.visitId,
    this.creditId,
    required this.amount,
    required this.date,
    this.notes = '',
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'visit_id': visitId,
        'credit_id': creditId,
        'amount': amount,
        'date': date.millisecondsSinceEpoch,
        'notes': notes,
      };

  factory Payment.fromMap(Map<String, Object?> m) => Payment(
        id: m['id'] as String,
        visitId: m['visit_id'] as String?,
        creditId: m['credit_id'] as String?,
        amount: ((m['amount'] as num?) ?? 0).toDouble(),
        date: DateTime.fromMillisecondsSinceEpoch((m['date'] as int?) ?? 0),
        notes: (m['notes'] as String?) ?? '',
      );
}

/// ذاكرة السيريالات: يتعلّم التطبيق من إدخالاتك ليقترح النوع تلقائيًا
class SerialMemory {
  final String serial;
  String typeKey;
  String typeLabel;
  String customName;
  Map<String, Object?> specs;
  double lastPrice;
  int useCount;
  DateTime lastUsed;

  SerialMemory({
    required this.serial,
    required this.typeKey,
    required this.typeLabel,
    this.customName = '',
    Map<String, Object?>? specs,
    this.lastPrice = 0,
    this.useCount = 1,
    required this.lastUsed,
  }) : specs = specs ?? {};
}

/// إجماليات محسوبة لزيارة أو لسحب آجل
class Totals {
  final double itemsTotal;
  final double returnedTotal;
  final double paid;

  const Totals({this.itemsTotal = 0, this.returnedTotal = 0, this.paid = 0});

  double get net => itemsTotal - returnedTotal;
  double get remaining => net - paid;

  Totals operator +(Totals o) => Totals(
        itemsTotal: itemsTotal + o.itemsTotal,
        returnedTotal: returnedTotal + o.returnedTotal,
        paid: paid + o.paid,
      );
}

/// زيارة مع قطعها وإجمالياتها — الشكل الذي تستهلكه الشاشات والتقارير
class VisitFull {
  final Visit visit;
  final List<Item> items;
  final List<Payment> payments;

  const VisitFull({required this.visit, this.items = const [], this.payments = const []});

  List<Item> get outItems => items.where((i) => i.kind == MovementKind.out).toList();
  List<Item> get returnedItems => items.where((i) => i.kind == MovementKind.returned).toList();

  Totals get totals => Totals(
        itemsTotal: outItems.fold(0.0, (s, i) => s + i.total),
        returnedTotal: returnedItems.fold(0.0, (s, i) => s + i.total),
        paid: payments.fold(0.0, (s, p) => s + p.amount),
      );
}

/// سحب آجل مع قطعه وإجمالياته
class CreditFull {
  final CreditRecord credit;
  final List<Item> items;
  final List<Payment> payments;

  const CreditFull({required this.credit, this.items = const [], this.payments = const []});

  Totals get totals => Totals(
        itemsTotal: items
            .where((i) => i.kind == MovementKind.out)
            .fold(0.0, (s, i) => s + i.total),
        returnedTotal: items
            .where((i) => i.kind == MovementKind.returned)
            .fold(0.0, (s, i) => s + i.total),
        paid: payments.fold(0.0, (s, p) => s + p.amount),
      );
}

// ---------------------------------------------------------------------------
// الحركات المالية: كل درهم يدخل أو يخرج من المحل خارج نطاق الزيارات
// ---------------------------------------------------------------------------

/// اتجاه الحركة المالية
enum CashDirection { income, expense }

extension CashDirectionX on CashDirection {
  String get label => this == CashDirection.income ? 'وارد' : 'صادر';

  static CashDirection fromCode(String? c) => CashDirection.values
      .firstWhere((e) => e.name == c, orElse: () => CashDirection.income);
}

/// طريقة الدفع
enum PayMethod { cash, card, transfer, cheque, other }

extension PayMethodX on PayMethod {
  String get label => switch (this) {
        PayMethod.cash => 'كاش',
        PayMethod.card => 'بطاقة',
        PayMethod.transfer => 'تحويل بنكي',
        PayMethod.cheque => 'شيك',
        PayMethod.other => 'أخرى',
      };

  static PayMethod fromCode(String? c) =>
      PayMethod.values.firstWhere((e) => e.name == c, orElse: () => PayMethod.cash);
}

/// تصنيف الحركة المالية — يظهر مجمّعًا في التقرير اليومي
class CashCategory {
  final String key;
  final String label;
  final CashDirection direction;

  const CashCategory(this.key, this.label, this.direction);

  static const sale = CashCategory('sale', 'بيع أغراض من المحل', CashDirection.income);
  static const debtPayment =
      CashCategory('debt_payment', 'سداد دين', CashDirection.income);
  static const license =
      CashCategory('license', 'رسوم إصدار رخصة كاميرات', CashDirection.income);
  static const service = CashCategory('service', 'أجرة خدمة أو صيانة', CashDirection.income);
  static const otherIncome = CashCategory('other_income', 'وارد آخر', CashDirection.income);

  static const purchase =
      CashCategory('purchase', 'شراء بضاعة', CashDirection.expense);
  static const expenseLicense =
      CashCategory('license_fee', 'رسوم رخصة مدفوعة', CashDirection.expense);
  static const salary = CashCategory('salary', 'رواتب وأجور', CashDirection.expense);
  static const transport = CashCategory('transport', 'مواصلات ووقود', CashDirection.expense);
  static const rent = CashCategory('rent', 'إيجار وفواتير', CashDirection.expense);
  static const otherExpense =
      CashCategory('other_expense', 'صادر آخر', CashDirection.expense);

  static const incomeCategories = [
    sale,
    debtPayment,
    license,
    service,
    otherIncome,
  ];

  static const expenseCategories = [
    purchase,
    expenseLicense,
    salary,
    transport,
    rent,
    otherExpense,
  ];

  static const all = [...incomeCategories, ...expenseCategories];

  static CashCategory byKey(String key) =>
      all.firstWhere((c) => c.key == key, orElse: () => otherIncome);

  static List<CashCategory> forDirection(CashDirection d) =>
      d == CashDirection.income ? incomeCategories : expenseCategories;
}

/// حركة مالية مستقلة: دخل أو خرج من المحل بغير زيارة
class CashEntry {
  final String id;
  CashDirection direction;
  String categoryKey;
  String categoryLabel;

  /// وصف حر: ماذا كانت هذه الحركة
  String description;

  /// الطرف المقابل: الزبون أو الجهة، اختياري
  String partyName;

  double amount;
  PayMethod method;
  DateTime date;
  String notes;

  /// يربط سداد الدين بسجل السحب الآجل، ليُحتسب ضمن دفعاته
  String? linkedCreditId;

  final DateTime createdAt;
  DateTime updatedAt;

  CashEntry({
    required this.id,
    this.direction = CashDirection.income,
    required this.categoryKey,
    required this.categoryLabel,
    this.description = '',
    this.partyName = '',
    this.amount = 0,
    this.method = PayMethod.cash,
    required this.date,
    this.notes = '',
    this.linkedCreditId,
    required this.createdAt,
    required this.updatedAt,
  });

  /// المبلغ بإشارته: موجب للوارد وسالب للصادر
  double get signed => direction == CashDirection.income ? amount : -amount;

  Map<String, Object?> toMap() => {
        'id': id,
        'direction': direction.name,
        'category_key': categoryKey,
        'category_label': categoryLabel,
        'description': description,
        'party_name': partyName,
        'amount': amount,
        'method': method.name,
        'date': date.millisecondsSinceEpoch,
        'notes': notes,
        'linked_credit_id': linkedCreditId,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory CashEntry.fromMap(Map<String, Object?> m) => CashEntry(
        id: m['id'] as String,
        direction: CashDirectionX.fromCode(m['direction'] as String?),
        categoryKey: (m['category_key'] as String?) ?? 'other_income',
        categoryLabel: (m['category_label'] as String?) ?? 'وارد آخر',
        description: (m['description'] as String?) ?? '',
        partyName: (m['party_name'] as String?) ?? '',
        amount: ((m['amount'] as num?) ?? 0).toDouble(),
        method: PayMethodX.fromCode(m['method'] as String?),
        date: DateTime.fromMillisecondsSinceEpoch((m['date'] as int?) ?? 0),
        notes: (m['notes'] as String?) ?? '',
        linkedCreditId: m['linked_credit_id'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch((m['created_at'] as int?) ?? 0),
        updatedAt: DateTime.fromMillisecondsSinceEpoch((m['updated_at'] as int?) ?? 0),
      );

  CashEntry copyWith({
    CashDirection? direction,
    String? categoryKey,
    String? categoryLabel,
    String? description,
    String? partyName,
    double? amount,
    PayMethod? method,
    DateTime? date,
    String? notes,
    String? linkedCreditId,
    bool clearLink = false,
  }) =>
      CashEntry(
        id: id,
        direction: direction ?? this.direction,
        categoryKey: categoryKey ?? this.categoryKey,
        categoryLabel: categoryLabel ?? this.categoryLabel,
        description: description ?? this.description,
        partyName: partyName ?? this.partyName,
        amount: amount ?? this.amount,
        method: method ?? this.method,
        date: date ?? this.date,
        notes: notes ?? this.notes,
        linkedCreditId: clearLink ? null : (linkedCreditId ?? this.linkedCreditId),
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );
}

/// إجماليات الصندوق لفترة
class CashTotals {
  final double income;
  final double expense;

  const CashTotals({this.income = 0, this.expense = 0});

  double get net => income - expense;

  CashTotals operator +(CashTotals o) =>
      CashTotals(income: income + o.income, expense: expense + o.expense);

  static CashTotals from(Iterable<CashEntry> entries) {
    var inc = 0.0;
    var exp = 0.0;
    for (final e in entries) {
      if (e.direction == CashDirection.income) {
        inc += e.amount;
      } else {
        exp += e.amount;
      }
    }
    return CashTotals(income: inc, expense: exp);
  }
}
