class PartsProcurementRow {
  const PartsProcurementRow({
    required this.ppId,
    this.ppIdi = '',
    this.ppPurchaseDate = '',
    this.ppQuantity = 0,
    this.ppPriceNet = 0,
    this.ppTotalPriceNet = 0,
    this.ppDescriptionDeLong = '',
    this.ppPointOfUse = '',
    this.ppPartSource = '',
    this.ppMaterial = '',
    this.ppNote = '',
    this.ppDrawing = '',
  });

  final int ppId;
  final String ppIdi;
  final String ppPurchaseDate;
  final int ppQuantity;
  final double ppPriceNet;
  final double ppTotalPriceNet;
  final String ppDescriptionDeLong;
  final String ppPointOfUse;
  final String ppPartSource;
  final String ppMaterial;
  final String ppNote;
  final String ppDrawing;

  factory PartsProcurementRow.fromMap(Map<String, Object?> map) {
    return PartsProcurementRow(
      ppId: _int(map['pp_id']),
      ppIdi: _string(map['pp_idi']),
      ppPurchaseDate: _string(map['pp_purchase_date']),
      ppQuantity: _int(map['pp_quantity']),
      ppPriceNet: _double(map['pp_price_net']),
      ppTotalPriceNet: _double(map['pp_total_price_net']),
      ppDescriptionDeLong: _string(map['pp_description_de_long']),
      ppPointOfUse: _string(map['pp_point_of_use']),
      ppPartSource: _string(map['pp_part_source']),
      ppMaterial: _string(map['pp_material']),
      ppNote: _string(map['pp_note']),
      ppDrawing: _string(map['pp_drawing']),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'pp_id': ppId,
      'pp_idi': ppIdi,
      'pp_purchase_date': ppPurchaseDate,
      'pp_quantity': ppQuantity,
      'pp_price_net': ppPriceNet,
      'pp_total_price_net': ppTotalPriceNet,
      'pp_description_de_long': ppDescriptionDeLong,
      'pp_point_of_use': ppPointOfUse,
      'pp_part_source': ppPartSource,
      'pp_material': ppMaterial,
      'pp_note': ppNote,
      'pp_drawing': ppDrawing,
    };
  }

  PartsProcurementRow copyWith({
    int? ppId,
    String? ppIdi,
    String? ppPurchaseDate,
    int? ppQuantity,
    double? ppPriceNet,
    double? ppTotalPriceNet,
    String? ppDescriptionDeLong,
    String? ppPointOfUse,
    String? ppPartSource,
    String? ppMaterial,
    String? ppNote,
    String? ppDrawing,
  }) {
    return PartsProcurementRow(
      ppId: ppId ?? this.ppId,
      ppIdi: ppIdi ?? this.ppIdi,
      ppPurchaseDate: ppPurchaseDate ?? this.ppPurchaseDate,
      ppQuantity: ppQuantity ?? this.ppQuantity,
      ppPriceNet: ppPriceNet ?? this.ppPriceNet,
      ppTotalPriceNet: ppTotalPriceNet ?? this.ppTotalPriceNet,
      ppDescriptionDeLong: ppDescriptionDeLong ?? this.ppDescriptionDeLong,
      ppPointOfUse: ppPointOfUse ?? this.ppPointOfUse,
      ppPartSource: ppPartSource ?? this.ppPartSource,
      ppMaterial: ppMaterial ?? this.ppMaterial,
      ppNote: ppNote ?? this.ppNote,
      ppDrawing: ppDrawing ?? this.ppDrawing,
    );
  }

  static int _int(Object? value) => int.tryParse(value?.toString().trim() ?? '') ?? 0;

  static double _double(Object? value) =>
      double.tryParse(value?.toString().trim().replaceAll(',', '.') ?? '') ?? 0;

  static String _string(Object? value) => value?.toString().trim() ?? '';
}
