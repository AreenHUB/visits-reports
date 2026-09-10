// كتالوج أنواع القطع والحقول التفصيلية لكل نوع.
// هذا هو مصدر "الاقتراحات" التي تظهر بعد قراءة السيريال.

/// نوع الحقل التفصيلي
enum SpecFieldType { choice, number, toggle, text }

/// حقل تفصيلي واحد ضمن نوع قطعة
class SpecField {
  final String key;
  final String label;
  final SpecFieldType type;

  /// خيارات جاهزة للاختيار السريع (تظهر كأزرار)، ويبقى بإمكانك كتابة قيمة أخرى
  final List<String> options;

  /// لاحقة تظهر بعد الرقم مثل «ميغا» أو «بورت»
  final String suffix;

  const SpecField({
    required this.key,
    required this.label,
    this.type = SpecFieldType.choice,
    this.options = const [],
    this.suffix = '',
  });
}

/// نوع قطعة كامل مع حقوله
class ItemType {
  final String key;
  final String label;
  final String icon;
  final List<SpecField> fields;

  const ItemType({
    required this.key,
    required this.label,
    this.icon = 'inventory',
    this.fields = const [],
  });
}

/// كتالوج الأنواع المدمجة
class ItemTypes {
  ItemTypes._();

  static const camera = ItemType(
    key: 'camera',
    label: 'كاميرا',
    icon: 'camera',
    fields: [
      SpecField(
        key: 'brand',
        label: 'الماركة',
        options: [
          'Hikvision',
          'Dahua',
          'Tiandy',
          'Uniview',
          'UNV',
          'TP-Link',
          'Ezviz',
          'Imou',
        ],
      ),
      SpecField(
        key: 'shape',
        label: 'النوع',
        options: ['Dome دوم', 'Bullet بوليت', 'PTZ متحركة', 'Fisheye', 'Cube'],
      ),
      SpecField(
        key: 'mp',
        label: 'الدقة',
        type: SpecFieldType.number,
        options: ['2', '4', '5', '6', '8'],
        suffix: 'ميغا',
      ),
      SpecField(
        key: 'tech',
        label: 'التقنية',
        options: ['IP', 'Analog HD', 'TVI', 'AHD'],
      ),
      SpecField(key: 'full_color', label: 'فول كولر', type: SpecFieldType.toggle),
      SpecField(key: 'motorized', label: 'متحركة', type: SpecFieldType.toggle),
      SpecField(key: 'audio', label: 'صوت', type: SpecFieldType.toggle),
      SpecField(
        key: 'placement',
        label: 'التركيب',
        options: ['داخلية', 'خارجية'],
      ),
      SpecField(
        key: 'lens',
        label: 'العدسة',
        options: ['2.8mm', '3.6mm', '4mm', '6mm', 'Varifocal'],
      ),
    ],
  );

  static const switchType = ItemType(
    key: 'switch',
    label: 'سويتش',
    icon: 'hub',
    fields: [
      SpecField(
        key: 'brand',
        label: 'الماركة',
        options: [
          'Hikvision',
          'Dahua',
          'Tiandy',
          'IP-COM',
          'Oxion',
          'TP-Link',
          'Cisco',
          'D-Link',
          'Mikrotik',
        ],
      ),
      SpecField(
        key: 'ports',
        label: 'عدد البورتات',
        type: SpecFieldType.number,
        options: ['4', '5', '8', '16', '24', '48'],
        suffix: 'بورت',
      ),
      SpecField(
        key: 'poe',
        label: 'التغذية',
        options: ['PoE', 'عادي'],
      ),
      SpecField(
        key: 'managed',
        label: 'الإدارة',
        options: ['Managed', 'Unmanaged'],
      ),
      SpecField(
        key: 'speed',
        label: 'السرعة',
        options: ['100Mbps', 'Gigabit', '10G'],
      ),
    ],
  );

  static const nvr = ItemType(
    key: 'nvr',
    label: 'NVR / DVR',
    icon: 'dvr',
    fields: [
      SpecField(
        key: 'brand',
        label: 'الماركة',
        options: [
          'Hikvision',
          'Dahua',
          'Tiandy',
          'Uniview',
          'UNV',
          'TP-Link',
        ],
      ),
      SpecField(
        key: 'device',
        label: 'الجهاز',
        options: ['NVR', 'DVR', 'XVR'],
      ),
      SpecField(
        key: 'channels',
        label: 'عدد القنوات',
        type: SpecFieldType.number,
        options: ['4', '8', '16', '32', '64'],
        suffix: 'قناة',
      ),
      SpecField(
        key: 'poe_ports',
        label: 'بورتات PoE',
        type: SpecFieldType.number,
        options: ['0', '4', '8', '16'],
        suffix: 'بورت',
      ),
      SpecField(
        key: 'hdd',
        label: 'الهارد',
        options: ['بدون', '1TB', '2TB', '4TB', '6TB', '8TB'],
      ),
    ],
  );

  static const router = ItemType(
    key: 'router',
    label: 'راوتر',
    icon: 'router',
    fields: [
      SpecField(
        key: 'brand',
        label: 'الماركة',
        options: [
          'TP-Link',
          'Huawei',
          'IP-COM',
          'Mikrotik',
          'Tenda',
          'Cisco',
          'Ubiquiti',
        ],
      ),
      SpecField(key: 'model', label: 'الموديل', type: SpecFieldType.text),
      SpecField(
        key: 'wifi',
        label: 'الواي فاي',
        options: ['WiFi 4', 'WiFi 5', 'WiFi 6', 'بدون'],
      ),
      SpecField(
        key: 'bands',
        label: 'الترددات',
        options: ['2.4GHz', 'Dual Band', 'Tri Band'],
      ),
    ],
  );

  static const accessPoint = ItemType(
    key: 'ap',
    label: 'أكسس بوينت',
    icon: 'wifi',
    fields: [
      SpecField(
        key: 'brand',
        label: 'الماركة',
        options: ['Ubiquiti', 'TP-Link', 'Mikrotik', 'Ruijie', 'Cisco'],
      ),
      SpecField(key: 'model', label: 'الموديل', type: SpecFieldType.text),
      SpecField(
        key: 'placement',
        label: 'التركيب',
        options: ['داخلي', 'خارجي', 'سقفي', 'جداري'],
      ),
      SpecField(
        key: 'bands',
        label: 'الترددات',
        options: ['2.4GHz', 'Dual Band', 'Tri Band'],
      ),
      SpecField(key: 'poe', label: 'يعمل بـ PoE', type: SpecFieldType.toggle),
    ],
  );

  static const repeater = ItemType(
    key: 'repeater',
    label: 'مقوي إشارة (ريبيتر)',
    icon: 'settings_input_antenna',
    fields: [
      SpecField(
        key: 'brand',
        label: 'الماركة',
        options: ['TP-Link', 'Tenda', 'Xiaomi', 'Huawei'],
      ),
      SpecField(key: 'model', label: 'الموديل', type: SpecFieldType.text),
      SpecField(
        key: 'bands',
        label: 'الترددات',
        options: ['2.4GHz', 'Dual Band'],
      ),
    ],
  );

  // أنواع إضافية شائعة في هذا المجال
  static const cable = ItemType(
    key: 'cable',
    label: 'كيبل',
    icon: 'cable',
    fields: [
      SpecField(key: 'kind', label: 'النوع', options: ['Cat5e', 'Cat6', 'Cat6a', 'Fiber', 'كهرباء']),
      SpecField(key: 'length', label: 'الطول', type: SpecFieldType.number, suffix: 'متر'),
    ],
  );

  static const power = ItemType(
    key: 'power',
    label: 'محول / باور',
    icon: 'power',
    fields: [
      SpecField(key: 'volt', label: 'الفولت', options: ['12V', '24V', '48V']),
      SpecField(key: 'amp', label: 'الأمبير', options: ['1A', '2A', '5A', '10A', '20A', '30A']),
      SpecField(key: 'kind', label: 'النوع', options: ['محول', 'باور سبلاي', 'UPS', 'بطارية']),
    ],
  );

  static const storage = ItemType(
    key: 'storage',
    label: 'هارد / تخزين',
    icon: 'storage',
    fields: [
      SpecField(key: 'brand', label: 'الماركة', options: ['Seagate', 'WD', 'Toshiba', 'Hikvision']),
      SpecField(key: 'size', label: 'السعة', options: ['1TB', '2TB', '4TB', '6TB', '8TB', '10TB']),
      SpecField(key: 'kind', label: 'النوع', options: ['HDD', 'SSD', 'Surveillance']),
    ],
  );

  static const accessory = ItemType(
    key: 'accessory',
    label: 'إكسسوار',
    icon: 'construction',
    fields: [
      SpecField(
        key: 'kind',
        label: 'النوع',
        options: ['حامل', 'علبة', 'كونيكتور', 'دكت', 'مسامير', 'باتش كورد'],
      ),
    ],
  );

  static const speaker = ItemType(
    key: 'speaker',
    label: 'سماعات',
    icon: 'speaker',
    fields: [
      SpecField(
        key: 'brand',
        label: 'الماركة',
        options: ['Oxion', 'Bosch', 'TOA', 'JBL', 'Ahuja'],
      ),
      SpecField(key: 'model', label: 'الموديل', type: SpecFieldType.text),
      SpecField(
        key: 'kind',
        label: 'النوع',
        options: ['سقفية', 'جدارية', 'بوق', 'عمود', 'مضخّم'],
      ),
      SpecField(
        key: 'power',
        label: 'القدرة',
        type: SpecFieldType.number,
        options: ['6', '10', '20', '30', '60'],
        suffix: 'واط',
      ),
    ],
  );

  static const other = ItemType(
    key: 'other',
    label: 'أخرى',
    icon: 'category',
    fields: [],
  );

  /// كل الأنواع بالترتيب الذي تظهر به في الواجهة
  static const List<ItemType> all = [
    camera,
    switchType,
    nvr,
    router,
    accessPoint,
    repeater,
    cable,
    power,
    storage,
    speaker,
    accessory,
    other,
  ];

  static ItemType byKey(String key) =>
      all.firstWhere((t) => t.key == key, orElse: () => other);
}
