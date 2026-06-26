import 'package:arrow_ops/features/customer/domain/customer.dart';
import 'package:arrow_ops/features/order/presentation/widgets/order_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<Customer> buildCustomers(int count) {
    return List<Customer>.generate(count, (index) {
      final suffix = index.toString().padLeft(3, '0');
      return Customer(
        cId: 'C$suffix',
        cCompany: 'Match Company',
        cLastName: 'Last$suffix',
        cFirstName: 'First$suffix',
        cStreetB: 'Street',
        cHouseNumberB: '1',
        cPostalCodeB: '12345',
        cCityB: 'City',
        cStreetD: 'Street',
        cHouseNumberD: '1',
        cPostalCodeD: '12345',
        cCityD: 'City',
      );
    });
  }

  Future<void> pumpDialog(WidgetTester tester, List<Customer> customers) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: OrderFormDialog(allCustomers: customers, allCountries: const []),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('kundensuche reagiert nach debounce und begrenzt treffer auf 100', (tester) async {
    await pumpDialog(tester, buildCustomers(150));

    final searchField = find.widgetWithText(
      TextFormField,
      'Kunde suchen (Name, Vorname, Ort)',
    );

    expect(searchField, findsOneWidget);

    await tester.enterText(searchField, 'match');

    // Debounce: direkt nach Eingabe sollte die Liste noch nicht sichtbar sein.
    await tester.pump();
    expect(find.byType(ListView), findsNothing);

    await tester.pump(const Duration(milliseconds: 130));
    expect(find.byType(ListView), findsOneWidget);

    // Zu einem hohen, aber noch erlaubten Eintrag scrollen.
    await tester.dragUntilVisible(
      find.text('Last099, First099'),
      find.byType(ListView),
      const Offset(0, -200),
      maxIteration: 80,
    );
    expect(find.text('Last099, First099'), findsOneWidget);

    // Eintrag > 99 darf wegen Limit nicht erreichbar sein.
    var overLimitEntryReachable = true;
    try {
      await tester.dragUntilVisible(
        find.text('Last120, First120'),
        find.byType(ListView),
        const Offset(0, -200),
        maxIteration: 80,
      );
    } catch (_) {
      overLimitEntryReachable = false;
    }

    expect(overLimitEntryReachable, isFalse);
  });
}
