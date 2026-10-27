class IncomingInvoiceRow {
  const IncomingInvoiceRow({
    required this.riId,
    this.riDate = '',
    this.riName = '',
    this.riUsage = '',
    this.riKat1 = '',
    this.riKat2 = '',
    this.riCountry = '',
    this.riGross = 0,
    this.riVatRate = 0,
    this.riNet = 0,
    this.riVat = 0,
  });

  final int riId;
  final String riDate;
  final String riName;
  final String riUsage;
  final String riKat1;
  final String riKat2;
  final String riCountry;
  final double riGross;
  final double riVatRate;
  final double riNet;
  final double riVat;

  factory IncomingInvoiceRow.fromMap(Map<String, Object?> map) {
    return IncomingInvoiceRow(
      riId: _int(map['ri_id']),
      riDate: _string(map['ri_date']),
      riName: _string(map['ri_name']),
      riUsage: _string(map['ri_usage']),
      riKat1: _string(map['ri_kat1']),
      riKat2: _string(map['ri_kat2']),
      riCountry: _string(map['ri_country']),
      riGross: _double(map['ri_gross']),
      riVatRate: _double(map['ri_vat_rate']),
      riNet: _double(map['ri_net']),
      riVat: _double(map['ri_vat']),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'ri_id': riId,
      'ri_date': riDate,
      'ri_name': riName,
      'ri_usage': riUsage,
      'ri_kat1': riKat1,
      'ri_kat2': riKat2,
      'ri_country': riCountry,
      'ri_gross': riGross,
      'ri_vat_rate': riVatRate,
      'ri_net': riNet,
      'ri_vat': riVat,
    };
  }

  IncomingInvoiceRow copyWith({
    int? riId,
    String? riDate,
    String? riName,
    String? riUsage,
    String? riKat1,
    String? riKat2,
    String? riCountry,
    double? riGross,
    double? riVatRate,
    double? riNet,
    double? riVat,
  }) {
    return IncomingInvoiceRow(
      riId: riId ?? this.riId,
      riDate: riDate ?? this.riDate,
      riName: riName ?? this.riName,
      riUsage: riUsage ?? this.riUsage,
      riKat1: riKat1 ?? this.riKat1,
      riKat2: riKat2 ?? this.riKat2,
      riCountry: riCountry ?? this.riCountry,
      riGross: riGross ?? this.riGross,
      riVatRate: riVatRate ?? this.riVatRate,
      riNet: riNet ?? this.riNet,
      riVat: riVat ?? this.riVat,
    );
  }

  static int _int(Object? value) => int.tryParse(value?.toString().trim() ?? '') ?? 0;

  static double _double(Object? value) =>
      double.tryParse(value?.toString().trim().replaceAll(',', '.') ?? '') ?? 0;

  static String _string(Object? value) => value?.toString().trim() ?? '';
}
