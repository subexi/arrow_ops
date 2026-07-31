import 'package:arrow_ops/features/analytics/presentation/analytics_page.dart';
import 'package:arrow_ops/features/order/domain/order_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  OrderRow order({
    required String id,
    String tradeShow = '-',
    int putt = 0,
  }) {
    return OrderRow(
      oId: id,
      oCustomerId: 'C-1',
      oDelivery: '2026-06-15',
      oTradeShow: tradeShow,
      oPutt: putt,
    );
  }

  group('wareinsatzAvailableTradeShowOptions', () {
    test('liefert sortierte eindeutige Trade Shows ohne leere und - Werte', () {
      final orders = [
        order(id: '1', tradeShow: 'Ambiente'),
        order(id: '2', tradeShow: 'Christmasworld'),
        order(id: '3', tradeShow: 'Ambiente'),
        order(id: '4', tradeShow: '  '),
        order(id: '5', tradeShow: '-'),
      ];

      final options = wareinsatzAvailableTradeShowOptions(orders);

      expect(options, ['Ambiente', 'Christmasworld']);
    });
  });

  group('wareinsatzFilterOrdersByTradeShowAndPutt', () {
    test('filtert nach mehreren Trade Shows', () {
      final orders = [
        order(id: '1', tradeShow: 'Ambiente'),
        order(id: '2', tradeShow: 'Christmasworld'),
        order(id: '3', tradeShow: 'Tendence'),
      ];

      final result = wareinsatzFilterOrdersByTradeShowAndPutt(
        orders: orders,
        selectedTradeShows: const {'Ambiente', 'Tendence'},
        puttFilter: WareinsatzPuttFilter.all,
      );

      expect(result.map((o) => o.oId), ['1', '3']);
    });

    test('PUTT-Filter nur PUTT', () {
      final orders = [
        order(id: '1', putt: 0),
        order(id: '2', putt: 1),
        order(id: '3', putt: 2),
      ];

      final result = wareinsatzFilterOrdersByTradeShowAndPutt(
        orders: orders,
        selectedTradeShows: const {},
        puttFilter: WareinsatzPuttFilter.onlyPutt,
      );

      expect(result.map((o) => o.oId), ['2', '3']);
    });

    test('PUTT-Filter ohne PUTT', () {
      final orders = [
        order(id: '1', putt: 0),
        order(id: '2', putt: 1),
      ];

      final result = wareinsatzFilterOrdersByTradeShowAndPutt(
        orders: orders,
        selectedTradeShows: const {},
        puttFilter: WareinsatzPuttFilter.withoutPutt,
      );

      expect(result.map((o) => o.oId), ['1']);
    });

    test('kombiniert Trade Show + PUTT Filter', () {
      final orders = [
        order(id: '1', tradeShow: 'Ambiente', putt: 0),
        order(id: '2', tradeShow: 'Ambiente', putt: 1),
        order(id: '3', tradeShow: 'Tendence', putt: 1),
      ];

      final result = wareinsatzFilterOrdersByTradeShowAndPutt(
        orders: orders,
        selectedTradeShows: const {'Ambiente'},
        puttFilter: WareinsatzPuttFilter.onlyPutt,
      );

      expect(result.map((o) => o.oId), ['2']);
    });
  });

  group('wareinsatzRowMatchesScope', () {
    test('withoutBom enthaelt verkaufte Position auch wenn BOM-Menge > 0', () {
      final matches = wareinsatzRowMatchesScope(
        scope: WareinsatzScope.withoutBom,
        soldQuantity: 1,
        bomQuantity: 3,
      );

      expect(matches, isTrue);
    });

    test('withoutBom schliesst reine BOM-Komponenten aus', () {
      final matches = wareinsatzRowMatchesScope(
        scope: WareinsatzScope.withoutBom,
        soldQuantity: 0,
        bomQuantity: 2,
      );

      expect(matches, isFalse);
    });
  });

}
