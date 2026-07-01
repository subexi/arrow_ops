class ItemCatalogueRow {
  const ItemCatalogueRow({
    required this.icId,
    this.icIdi = '',
    this.category = '',
    this.icIde = '',
    this.icIdv = '',
    this.icDescriptionDeLong = '',
    this.icDescriptionEnLong = '',
    this.icPriceNet = 0,
    this.icPriceWholesaleNet = 0,
    this.icPurchasePriceNet = 0,
    this.icWeight = 0,
    this.icSourceOfSupply = '',
    this.icHts = '',
    this.icDrawing = '',
    this.icImagePath = '',
    this.icNote = '',
    this.icStock = 0,
    this.icIc = 0,
    this.icArchive = 0,
  });

  final int icId;
  final String icIdi;
  final String category;
  final String icIde;
  final String icIdv;
  final String icDescriptionDeLong;
  final String icDescriptionEnLong;
  final double icPriceNet;
  final double icPriceWholesaleNet;
  final double icPurchasePriceNet;
  final double icWeight;
  final String icSourceOfSupply;
  final String icHts;
  final String icDrawing;
  final String icImagePath;
  final String icNote;
  final int icStock;
  final int icIc;
  final int icArchive;

  factory ItemCatalogueRow.fromMap(Map<String, Object?> map) {
    return ItemCatalogueRow(
      icId: _int(map['ic_id']),
      icIdi: _string(map['ic_idi']),
      category: _string(map['category']),
      icIde: _string(map['ic_ide']),
      icIdv: _string(map['ic_idv']),
      icDescriptionDeLong: _string(map['ic_description_de_long']),
      icDescriptionEnLong: _string(map['ic_description_en_long']),
      icPriceNet: _double(map['ic_price_net']),
      icPriceWholesaleNet: _double(map['ic_price_wholesale_net']),
      icPurchasePriceNet: _double(map['ic_purchase_price_net']),
      icWeight: _double(map['ic_weight']),
      icSourceOfSupply: _string(map['ic_source_of_supply']),
      icHts: _string(map['ic_hts']),
      icDrawing: _string(map['ic_drawing']),
      icImagePath: _string(map['ic_image_path']),
      icNote: _string(map['ic_note']),
      icStock: _int(map['ic_stock']),
      icIc: _int(map['ic_ic']),
      icArchive: _int(map['ic_archive']),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'ic_id': icId,
      'ic_idi': icIdi,
      'category': category,
      'ic_ide': icIde,
      'ic_idv': icIdv,
      'ic_description_de_long': icDescriptionDeLong,
      'ic_description_en_long': icDescriptionEnLong,
      'ic_price_net': icPriceNet,
      'ic_price_wholesale_net': icPriceWholesaleNet,
      'ic_purchase_price_net': icPurchasePriceNet,
      'ic_weight': icWeight,
      'ic_source_of_supply': icSourceOfSupply,
      'ic_hts': icHts,
      'ic_drawing': icDrawing,
      'ic_image_path': icImagePath,
      'ic_note': icNote,
      'ic_stock': icStock,
      'ic_ic': icIc,
      'ic_archive': icArchive,
    };
  }

  ItemCatalogueRow copyWith({
    int? icId,
    String? icIdi,
    String? category,
    String? icIde,
    String? icIdv,
    String? icDescriptionDeLong,
    String? icDescriptionEnLong,
    double? icPriceNet,
    double? icPriceWholesaleNet,
    double? icPurchasePriceNet,
    double? icWeight,
    String? icSourceOfSupply,
    String? icHts,
    String? icDrawing,
    String? icImagePath,
    String? icNote,
    int? icStock,
    int? icIc,
    int? icArchive,
  }) {
    return ItemCatalogueRow(
      icId: icId ?? this.icId,
      icIdi: icIdi ?? this.icIdi,
      category: category ?? this.category,
      icIde: icIde ?? this.icIde,
      icIdv: icIdv ?? this.icIdv,
      icDescriptionDeLong: icDescriptionDeLong ?? this.icDescriptionDeLong,
      icDescriptionEnLong: icDescriptionEnLong ?? this.icDescriptionEnLong,
      icPriceNet: icPriceNet ?? this.icPriceNet,
      icPriceWholesaleNet: icPriceWholesaleNet ?? this.icPriceWholesaleNet,
      icPurchasePriceNet: icPurchasePriceNet ?? this.icPurchasePriceNet,
      icWeight: icWeight ?? this.icWeight,
      icSourceOfSupply: icSourceOfSupply ?? this.icSourceOfSupply,
      icHts: icHts ?? this.icHts,
      icDrawing: icDrawing ?? this.icDrawing,
      icImagePath: icImagePath ?? this.icImagePath,
      icNote: icNote ?? this.icNote,
      icStock: icStock ?? this.icStock,
      icIc: icIc ?? this.icIc,
      icArchive: icArchive ?? this.icArchive,
    );
  }

  static int _int(Object? value) => int.tryParse(value?.toString().trim() ?? '') ?? 0;

  static double _double(Object? value) =>
      double.tryParse(value?.toString().trim().replaceAll(',', '.') ?? '') ?? 0;

  static String _string(Object? value) => value?.toString().trim() ?? '';
}

class ItemCategoryRow {
  const ItemCategoryRow({
    required this.icatId,
    this.name = '',
  });

  final int icatId;
  final String name;

  factory ItemCategoryRow.fromMap(Map<String, Object?> map) {
    return ItemCategoryRow(
      icatId: _int(map['icat_id']),
      name: _string(map['name']),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'icat_id': icatId,
      'name': name,
    };
  }

  ItemCategoryRow copyWith({
    int? icatId,
    String? name,
  }) {
    return ItemCategoryRow(
      icatId: icatId ?? this.icatId,
      name: name ?? this.name,
    );
  }

  static int _int(Object? value) => int.tryParse(value?.toString().trim() ?? '') ?? 0;

  static String _string(Object? value) => value?.toString().trim() ?? '';
}

class ItemBomRow {
  static const Object _noValue = Object();

  const ItemBomRow({
    this.ibId,
    required this.ibItemId,
    this.ibParentId,
    this.ibOrder = 0,
    required this.ibQuantity,
  });

  final int? ibId;
  final int ibItemId;
  final int? ibParentId;
  final int ibOrder;
  final int ibQuantity;

  factory ItemBomRow.fromMap(Map<String, Object?> map) {
    return ItemBomRow(
      ibId: _nullableInt(map['ib_id']),
      ibItemId: _int(map['ib_item_id']),
      ibParentId: _nullableInt(map['ib_parent_id']),
      ibOrder: _int(map['ib_order']),
      ibQuantity: _int(map['ib_quantity']),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'ib_id': ibId,
      'ib_item_id': ibItemId,
      'ib_parent_id': ibParentId,
      'ib_order': ibOrder,
      'ib_quantity': ibQuantity,
    };
  }

  ItemBomRow copyWith({
    int? ibId,
    int? ibItemId,
    Object? ibParentId = _noValue,
    int? ibOrder,
    int? ibQuantity,
  }) {
    return ItemBomRow(
      ibId: ibId ?? this.ibId,
      ibItemId: ibItemId ?? this.ibItemId,
      ibParentId: identical(ibParentId, _noValue) ? this.ibParentId : ibParentId as int?,
      ibOrder: ibOrder ?? this.ibOrder,
      ibQuantity: ibQuantity ?? this.ibQuantity,
    );
  }

  static int _int(Object? value) => int.tryParse(value?.toString().trim() ?? '') ?? 0;

  static int? _nullableInt(Object? value) {
    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty || raw == 'null') {
      return null;
    }
    return int.tryParse(raw);
  }
}