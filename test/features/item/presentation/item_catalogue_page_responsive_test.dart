import 'package:arrow_ops/features/item/presentation/item_catalogue_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpCataloguePage(
    WidgetTester tester, {
    required Size surfaceSize,
  }) async {
    await tester.binding.setSurfaceSize(surfaceSize);

    await tester.pumpWidget(
      const MaterialApp(
        home: ItemCataloguePage(
          loadOnInit: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('vermeidet RenderFlex-Overflow bei schmaler und niedriger Ansicht', (tester) async {
    addTearDown(() async {
      await binding.setSurfaceSize(null);
    });

    await pumpCataloguePage(
      tester,
      surfaceSize: const Size(820, 620),
    );

    expect(find.byType(ItemCataloguePage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('vermeidet RenderFlex-Overflow bei sehr schmaler Ansicht', (tester) async {
    addTearDown(() async {
      await binding.setSurfaceSize(null);
    });

    await pumpCataloguePage(
      tester,
      surfaceSize: const Size(700, 620),
    );

    expect(find.byType(ItemCataloguePage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('vermeidet RenderFlex-Overflow bei sehr kleiner Hoehe', (tester) async {
    addTearDown(() async {
      await binding.setSurfaceSize(null);
    });

    await pumpCataloguePage(
      tester,
      surfaceSize: const Size(700, 540),
    );

    expect(find.byType(ItemCataloguePage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('vermeidet RenderFlex-Overflow im Landscape-Mini-Viewport', (tester) async {
    addTearDown(() async {
      await binding.setSurfaceSize(null);
    });

    await pumpCataloguePage(
      tester,
      surfaceSize: const Size(960, 420),
    );

    expect(find.byType(ItemCataloguePage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
