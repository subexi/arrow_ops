import 'package:arrow_ops/features/customer/domain/country_tld.dart';
import 'package:arrow_ops/features/customer/domain/customer.dart';
import 'package:arrow_ops/features/customer/presentation/widgets/customer_form_dialog.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Customer buildCustomer({
    required String cityB,
    required String cityD,
    String stateB = '-',
    String stateD = '-',
  }) {
    return Customer(
      cId: '2605191234',
      cLastName: 'MUSTER',
      cFirstName: 'Max',
      cStreetB: 'Via Roma',
      cHouseNumberB: '1',
      cPostalCodeB: '39012',
      cCityB: cityB,
      cStateB: stateB,
      cCountryBId: 'it',
      cStreetD: 'Via Roma',
      cHouseNumberD: '1',
      cPostalCodeD: '39012',
      cCityD: cityD,
      cStateD: stateD,
      cCountryDId: 'it',
    );
  }

  Future<Customer?> openAndSubmitDialog(
    WidgetTester tester, {
    required Customer customer,
  }) async {
    Customer? dialogResult;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return CupertinoButton(
              onPressed: () async {
                dialogResult = await showCupertinoDialog<Customer>(
                  context: context,
                  builder: (_) => CustomerFormDialog(
                    customer: customer,
                    countries: const [
                      CountryTld(coTld: 'it', coName: 'Italy'),
                    ],
                  ),
                );
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Aktualisieren'));
    await tester.pumpAndSettle();

    return dialogResult;
  }

  testWidgets('zeigt italienische Verwaltungseinheit im Formular an', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return CupertinoButton(
              onPressed: () async {
                await showCupertinoDialog<Customer>(
                  context: context,
                  builder: (_) => CustomerFormDialog(
                    customer: buildCustomer(
                      cityB: 'Merano/Sinich',
                      cityD: 'Merano/Sinich',
                    ),
                    countries: const [
                      CountryTld(coTld: 'it', coName: 'Italy'),
                    ],
                  ),
                );
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('BZ-Bolzano'), findsWidgets);
  });

  testWidgets('zeigt Verwaltungseinheit auch bei Country-Alias italy im Bearbeitenformular an', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return CupertinoButton(
              onPressed: () async {
                await showCupertinoDialog<Customer>(
                  context: context,
                  builder: (_) => CustomerFormDialog(
                    customer: Customer(
                      cId: '2605191234',
                      cLastName: 'MUSTER',
                      cFirstName: 'Max',
                      cStreetB: 'Via Roma',
                      cHouseNumberB: '1',
                      cPostalCodeB: '39012',
                      cCityB: 'Merano/Sinich',
                      cStateB: '-',
                      cCountryBId: 'italy',
                      cStreetD: 'Via Roma',
                      cHouseNumberD: '1',
                      cPostalCodeD: '39012',
                      cCityD: 'Merano/Sinich',
                      cStateD: '-',
                      cCountryDId: 'italy',
                    ),
                    countries: const [
                      CountryTld(coTld: 'it', coName: 'Italy'),
                    ],
                  ),
                );
              },
              child: const Text('open alias'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open alias'));
    await tester.pumpAndSettle();

    expect(find.text('BZ-Bolzano'), findsWidgets);
  });

  testWidgets('zeigt VI-Vicenza im Bearbeitenformular fuer San Giuseppe Di Cassola', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return CupertinoButton(
              onPressed: () async {
                await showCupertinoDialog<Customer>(
                  context: context,
                  builder: (_) => CustomerFormDialog(
                    customer: Customer(
                      cId: '1909280846',
                      cLastName: 'MUSTER',
                      cFirstName: 'Max',
                      cStreetB: 'Via Roma',
                      cHouseNumberB: '1',
                      cPostalCodeB: '36022',
                      cCityB: 'San Giuseppe Di Cassola',
                      cStateB: '-',
                      cCountryBId: 'it',
                      cStreetD: 'Via Roma',
                      cHouseNumberD: '1',
                      cPostalCodeD: '36022',
                      cCityD: 'San Giuseppe Di Cassola',
                      cStateD: '-',
                      cCountryDId: 'it',
                    ),
                    countries: const [
                      CountryTld(coTld: 'it', coName: 'Italy'),
                    ],
                  ),
                );
              },
              child: const Text('open cassola'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open cassola'));
    await tester.pumpAndSettle();

    expect(find.text('VI-Vicenza'), findsWidgets);
  });

  testWidgets('zeigt MI-Milano im Bearbeitenformular fuer c_id 1205011849', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return CupertinoButton(
              onPressed: () async {
                await showCupertinoDialog<Customer>(
                  context: context,
                  builder: (_) => CustomerFormDialog(
                    customer: Customer(
                      cId: '1205011849',
                      cLastName: 'MUSTER',
                      cFirstName: 'Max',
                      cStreetB: 'Via Roma',
                      cHouseNumberB: '1',
                      cPostalCodeB: '20121',
                      cCityB: 'Milano',
                      cStateB: '-',
                      cCountryBId: 'it',
                      cStreetD: 'Via Roma',
                      cHouseNumberD: '1',
                      cPostalCodeD: '20121',
                      cCityD: 'Milano',
                      cStateD: '-',
                      cCountryDId: 'it',
                    ),
                    countries: const [
                      CountryTld(coTld: 'it', coName: 'Italy'),
                    ],
                  ),
                );
              },
              child: const Text('open milano'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open milano'));
    await tester.pumpAndSettle();

    expect(find.text('MI-Milano'), findsWidgets);
  });

  testWidgets('zeigt BZ-Bolzano im Bearbeitenformular fuer c_id 1304140005', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return CupertinoButton(
              onPressed: () async {
                await showCupertinoDialog<Customer>(
                  context: context,
                  builder: (_) => CustomerFormDialog(
                    customer: Customer(
                      cId: '1304140005',
                      cLastName: 'MUSTER',
                      cFirstName: 'Max',
                      cStreetB: 'Via Roma',
                      cHouseNumberB: '1',
                      cPostalCodeB: '39054',
                      cCityB: 'Oberbozen / Ritten',
                      cStateB: '-',
                      cCountryBId: 'it',
                      cStreetD: 'Via Roma',
                      cHouseNumberD: '1',
                      cPostalCodeD: '39054',
                      cCityD: 'Oberbozen / Ritten',
                      cStateD: '-',
                      cCountryDId: 'it',
                    ),
                    countries: const [
                      CountryTld(coTld: 'it', coName: 'Italy'),
                    ],
                  ),
                );
              },
              child: const Text('open ritten'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open ritten'));
    await tester.pumpAndSettle();

    expect(find.text('BZ-Bolzano'), findsWidgets);
  });

  testWidgets('akzeptiert Stadtname mit Schraegstrich beim Speichern', (tester) async {
    final result = await openAndSubmitDialog(
      tester,
      customer: buildCustomer(
        cityB: 'Merano/Sinich',
        cityD: 'Merano/Sinich',
      ),
    );

    expect(result, isNotNull);
    expect(result!.cCityB, 'Merano/Sinich (BZ)');
    expect(result.cCityD, 'Merano/Sinich (BZ)');
    expect(result.cStateB, 'BZ-Bolzano');
    expect(result.cStateD, 'BZ-Bolzano');
  });

  testWidgets('akzeptiert Stadtname mit Klammern beim Speichern', (tester) async {
    final result = await openAndSubmitDialog(
      tester,
      customer: buildCustomer(
        cityB: 'Piacenza (PC)',
        cityD: 'Piacenza (PC)',
      ),
    );

    expect(result, isNotNull);
    expect(result!.cCityB, 'Piacenza (PC)');
    expect(result.cCityD, 'Piacenza (PC)');
    expect(result.cStateB, 'PC-Piacenza');
    expect(result.cStateD, 'PC-Piacenza');
  });

  testWidgets('kanonisiert Provinzcode RM beim Speichern zu RM-Roma', (tester) async {
    final result = await openAndSubmitDialog(
      tester,
      customer: buildCustomer(
        cityB: 'Roma',
        cityD: 'Roma',
        stateB: 'RM',
        stateD: 'RM',
      ),
    );

    expect(result, isNotNull);
    expect(result!.cStateB, 'RM-Roma');
    expect(result.cStateD, 'RM-Roma');
  });
}
