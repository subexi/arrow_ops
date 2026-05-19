import 'package:arrow_ops/features/customer/data/customer_csv_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const csvHeader = 'c_id,c_company,c_dealer,c_vat,c_vat_id,c_last_name,c_first_name,c_careof_b,c_street_b,c_house_number_b,c_postal_code_b,c_city_b,c_state_b,c_country_b_id,c_careof_d,c_street_d,c_house_number_d,c_postal_code_d,c_city_d,c_state_d,c_country_d_id,c_mail,c_phone,c_web,c_social_media,c_lat,c_long,c_note,c_total_value_eur,c_total_value_usd,c_last_modified';

  final service = CustomerCsvService();

  test('ermittelt BZ-Bolzano fuer Merano bei italienischer Rechnungsadresse', () {
    final csv = [
      csvHeader,
      '1,-,0,0,-,Doe,Jane,-,Via Roma,1,39012,Merano,-,it,-,Via Roma,1,39012,Merano,-,it,-,-,-,-,0,0,-,0,0,0',
    ].join('\n');

    final customers = service.importCustomers(csv);

    expect(customers, hasLength(1));
    expect(customers.single.cStateB, 'BZ-Bolzano');
    expect(customers.single.cCityB, 'Merano (BZ)');
  });

  test('ermittelt PC-Piacenza fuer Piacenza bei italienischer Rechnungsadresse', () {
    final csv = [
      csvHeader,
      '1,-,0,0,-,Doe,Jane,-,Via Roma,1,29121,Piacenza,,IT,-,Via Roma,1,29121,Piacenza,-,it,-,-,-,-,0,0,-,0,0,0',
    ].join('\n');

    final customers = service.importCustomers(csv);

    expect(customers, hasLength(1));
    expect(customers.single.cStateB, 'PC-Piacenza');
    expect(customers.single.cCityB, 'Piacenza (PC)');
  });

  test('ermittelt BZ-Bolzano fuer Merano bei Schraegstrich im Ortsnamen', () {
    final csv = [
      csvHeader,
      '1,-,0,0,-,Doe,Jane,-,Via Roma,1,39012,Merano/Sinich,-,it,-,Via Roma,1,39012,Merano,-,it,-,-,-,-,0,0,-,0,0,0',
    ].join('\n');

    final customers = service.importCustomers(csv);

    expect(customers, hasLength(1));
    expect(customers.single.cStateB, 'BZ-Bolzano');
  });

  test('ermittelt VI-Vicenza fuer San Giuseppe Di Cassola bei italienischer Rechnungsadresse', () {
    final csv = [
      csvHeader,
      '1,-,0,0,-,Doe,Jane,-,Via Roma,1,36022,San Giuseppe Di Cassola,-,it,-,Via Roma,1,36022,San Giuseppe Di Cassola,-,it,-,-,-,-,0,0,-,0,0,0',
    ].join('\n');

    final customers = service.importCustomers(csv);

    expect(customers, hasLength(1));
    expect(customers.single.cStateB, 'VI-Vicenza');
  });

  test('ermittelt MI-Milano fuer Milano bei italienischer Rechnungsadresse', () {
    final csv = [
      csvHeader,
      '1,-,0,0,-,Doe,Jane,-,Via Roma,1,20121,Milano,-,it,-,Via Roma,1,20121,Milano,-,it,-,-,-,-,0,0,-,0,0,0',
    ].join('\n');

    final customers = service.importCustomers(csv);

    expect(customers, hasLength(1));
    expect(customers.single.cStateB, 'MI-Milano');
  });

  test('ermittelt BZ-Bolzano fuer Oberbozen / Ritten bei italienischer Rechnungsadresse', () {
    final csv = [
      csvHeader,
      '1,-,0,0,-,Doe,Jane,-,Via Roma,1,39054,Oberbozen / Ritten,-,it,-,Via Roma,1,39054,Oberbozen / Ritten,-,it,-,-,-,-,0,0,-,0,0,0',
    ].join('\n');

    final customers = service.importCustomers(csv);

    expect(customers, hasLength(1));
    expect(customers.single.cStateB, 'BZ-Bolzano');
  });

  test('ermittelt BO-Bologna ueber generische Provinznamen-Erkennung', () {
    final csv = [
      csvHeader,
      '1,-,0,0,-,Doe,Jane,-,Via Roma,1,40121,Bologna,-,it,-,Via Roma,1,40121,Bologna,-,it,-,-,-,-,0,0,-,0,0,0',
    ].join('\n');

    final customers = service.importCustomers(csv);

    expect(customers, hasLength(1));
    expect(customers.single.cStateB, 'BO-Bologna');
  });

  test('ermittelt AL-Alessandria fuer Schreibvariante Allessandra', () {
    final csv = [
      csvHeader,
      '1,-,0,0,-,Doe,Jane,-,Via Roma,1,15121,Allessandra,-,it,-,Via Roma,1,15121,Allessandra,-,it,-,-,-,-,0,0,-,0,0,0',
    ].join('\n');

    final customers = service.importCustomers(csv);

    expect(customers, hasLength(1));
    expect(customers.single.cStateB, 'AL-Alessandria');
  });

  test('ermittelt PC-Piacenza fuer Piacenza mit Klammerzusatz', () {
    final csv = [
      csvHeader,
      '1,-,0,0,-,Doe,Jane,-,Via Roma,1,29121,Piacenza (PC),-,it,-,Via Roma,1,29121,Piacenza,-,it,-,-,-,-,0,0,-,0,0,0',
    ].join('\n');

    final customers = service.importCustomers(csv);

    expect(customers, hasLength(1));
    expect(customers.single.cStateB, 'PC-Piacenza');
  });

  test('kanonisiert c_state_b Provinzcode BZ zu BZ-Bolzano', () {
    final csv = [
      csvHeader,
      '1,-,0,0,-,Doe,Jane,-,Via Roma,1,39012,Merano,BZ,it,-,Via Roma,1,39012,Merano,-,it,-,-,-,-,0,0,-,0,0,0',
    ].join('\n');

    final customers = service.importCustomers(csv);

    expect(customers, hasLength(1));
    expect(customers.single.cStateB, 'BZ-Bolzano');
  });

  test('kanonisiert c_state_b Provinzcode RM zu RM-Roma', () {
    final csv = [
      csvHeader,
      '1,-,0,0,-,Doe,Jane,-,Via Roma,1,00100,Roma,RM,it,-,Via Roma,1,00100,Roma,-,it,-,-,-,-,0,0,-,0,0,0',
    ].join('\n');

    final customers = service.importCustomers(csv);

    expect(customers, hasLength(1));
    expect(customers.single.cStateB, 'RM-Roma');
  });

  test('ermittelt Provinz aus Ortsstring mit Provinzcode in Klammern', () {
    final csv = [
      csvHeader,
      '1,-,0,0,-,Doe,Jane,-,Via Roma,1,39012,Merano (BZ),-,it,-,Via Roma,1,39012,Merano,-,it,-,-,-,-,0,0,-,0,0,0',
    ].join('\n');

    final customers = service.importCustomers(csv);

    expect(customers, hasLength(1));
    expect(customers.single.cStateB, 'BZ-Bolzano');
  });

  test('behaelt vorhandenen c_state_b Wert bei', () {
    final csv = [
      csvHeader,
      '1,-,0,0,-,Doe,Jane,-,Via Roma,1,39012,Merano,Bestehend,it,-,Via Roma,1,39012,Merano,-,it,-,-,-,-,0,0,-,0,0,0',
    ].join('\n');

    final customers = service.importCustomers(csv);

    expect(customers, hasLength(1));
    expect(customers.single.cStateB, 'Bestehend');
  });

  test('leitet fuer nicht-italienische Rechnungsadresse keine Provinz ab', () {
    final csv = [
      csvHeader,
      '1,-,0,0,-,Doe,Jane,-,Via Roma,1,39012,Merano,-,de,-,Via Roma,1,39012,Merano,-,it,-,-,-,-,0,0,-,0,0,0',
    ].join('\n');

    final customers = service.importCustomers(csv);

    expect(customers, hasLength(1));
    expect(customers.single.cStateB, '-');
  });
}
