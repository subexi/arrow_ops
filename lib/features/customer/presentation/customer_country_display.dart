import '../domain/customer.dart';

String resolveDisplayCountry({
  required Customer customer,
  required Map<String, String> countryNameByCode,
  String fallbackWhenMissing = '',
}) {
  final preferredCode = _preferredCountryCode(customer);
  if (preferredCode == null) {
    return fallbackWhenMissing;
  }

  final normalized = preferredCode.toLowerCase();
  return countryNameByCode[normalized] ?? preferredCode.toUpperCase();
}

String? _preferredCountryCode(Customer customer) {
  final billing = customer.cCountryBId?.trim();
  if (billing != null && billing.isNotEmpty && billing != '-') {
    return billing;
  }

  final delivery = customer.cCountryDId?.trim();
  if (delivery != null && delivery.isNotEmpty && delivery != '-') {
    return delivery;
  }

  return null;
}
