import 'dart:io';

import 'package:arrow_ops/core/database/app_database.dart';
import 'package:arrow_ops/core/database/database_path_config.dart';
import 'package:arrow_ops/features/customer/data/customer_repository.dart';
import 'package:arrow_ops/features/customer/domain/customer.dart';
import 'package:arrow_ops/features/item/data/item_repository.dart';
import 'package:arrow_ops/features/item/domain/item_models.dart';
import 'package:arrow_ops/features/order/data/order_repository.dart';
import 'package:arrow_ops/features/order/domain/order_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tempDir;
  late CustomerRepository customerRepository;
  late OrderRepository orderRepository;
  late ItemRepository itemRepository;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await AppDatabase.instance.close();
    tempDir = await Directory.systemTemp.createTemp('arrow_ops_test_db_');
    DatabasePathConfig.setPreferredDatabaseDirectoryPathOverride(tempDir.path);

    customerRepository = const CustomerRepository();
    orderRepository = const OrderRepository();
    itemRepository = const ItemRepository();

    await customerRepository.upsert(
      const Customer(
        cId: '1000000001',
        cLastName: 'MUSTER',
        cFirstName: 'Max',
        cStreetB: 'Testweg',
        cHouseNumberB: '1',
        cPostalCodeB: '12345',
        cCityB: 'Berlin',
        cStreetD: 'Testweg',
        cHouseNumberD: '1',
        cPostalCodeD: '12345',
        cCityD: 'Berlin',
      ),
    );

    await customerRepository.upsert(
      const Customer(
        cId: '1000000002',
        cLastName: 'BEISPIEL',
        cFirstName: 'Erika',
        cStreetB: 'Musterallee',
        cHouseNumberB: '2',
        cPostalCodeB: '54321',
        cCityB: 'Hamburg',
        cStreetD: 'Musterallee',
        cHouseNumberD: '2',
        cPostalCodeD: '54321',
        cCityD: 'Hamburg',
      ),
    );
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    DatabasePathConfig.setPreferredDatabaseDirectoryPathOverride(null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('aktualisiert c_total_value_eur bei save und delete von Auftraegen', () async {
    await orderRepository.saveOrder(
      const OrderRow(
        oId: 'O-1',
        oCustomerId: '1000000001',
        oDate: '2026-06-17',
        oValueGoods: 120.5,
      ),
    );

    var customer1 = await customerRepository.getById('1000000001');
    expect(customer1, isNotNull);
    expect(customer1!.cTotalValueEur, closeTo(120.5, 0.0001));

    await orderRepository.saveOrder(
      const OrderRow(
        oId: 'O-2',
        oCustomerId: '1000000001',
        oDate: '2026-06-17',
        oValueGoods: 79.5,
      ),
    );

    customer1 = await customerRepository.getById('1000000001');
    expect(customer1, isNotNull);
    expect(customer1!.cTotalValueEur, closeTo(200.0, 0.0001));

    await orderRepository.saveOrder(
      const OrderRow(
        oId: 'O-2',
        oCustomerId: '1000000002',
        oDate: '2026-06-18',
        oValueGoods: 40,
      ),
      originalOrderId: 'O-2',
    );

    customer1 = await customerRepository.getById('1000000001');
    final customer2 = await customerRepository.getById('1000000002');
    expect(customer1, isNotNull);
    expect(customer2, isNotNull);
    expect(customer1!.cTotalValueEur, closeTo(120.5, 0.0001));
    expect(customer2!.cTotalValueEur, closeTo(40.0, 0.0001));

    await orderRepository.deleteOrder('O-1');

    customer1 = await customerRepository.getById('1000000001');
    expect(customer1, isNotNull);
    expect(customer1!.cTotalValueEur, closeTo(0.0, 0.0001));
  });

  test('behaelt synchronisierten Umsatz nach Kundenupdate bei', () async {
    await orderRepository.saveOrder(
      const OrderRow(
        oId: 'O-UPD-1',
        oCustomerId: '1000000001',
        oDate: '2026-06-19',
        oValueGoods: 55.25,
      ),
    );

    await customerRepository.update(
      const Customer(
        cId: '1000000001',
        cLastName: 'MUSTER-NEU',
        cFirstName: 'Max',
        cStreetB: 'Testweg',
        cHouseNumberB: '1',
        cPostalCodeB: '12345',
        cCityB: 'Berlin',
        cStreetD: 'Testweg',
        cHouseNumberD: '1',
        cPostalCodeD: '12345',
        cCityD: 'Berlin',
      ),
    );

    final customer = await customerRepository.getById('1000000001');
    expect(customer, isNotNull);
    expect(customer!.cTotalValueEur, closeTo(55.25, 0.0001));
  });

  test('persistiert und laedt tatsaechliche zahlart und gebuehr im repository-roundtrip', () async {
    const savedOrder = OrderRow(
      oId: 'O-ACT-1',
      oCustomerId: '1000000001',
      oDate: '2026-06-20',
      oCurrency: 'EUR',
      oPayment: 1,
      oPaypalFee: 3.25,
      oPaymentActual: 2,
      oPaypalFeeActual: 0,
      oValueGoods: 100,
      oTotalPrice: 119,
      oShipping: 19,
      oVat: 0,
    );

    await orderRepository.saveOrder(savedOrder);

    final loaded = await orderRepository.getOrderById('O-ACT-1');

    expect(loaded, isNotNull);
    expect(loaded!.oPaymentActual, 2);
    expect(loaded.oPaypalFeeActual, closeTo(0, 0.0001));
  });

  test('persistiert null fuer tatsaechliche zahlart im repository-roundtrip', () async {
    const savedOrder = OrderRow(
      oId: 'O-ACT-NULL-1',
      oCustomerId: '1000000001',
      oDate: '2026-06-21',
      oCurrency: 'EUR',
      oPayment: 1,
      oPaypalFee: 2.75,
      oPaymentActual: null,
      oPaypalFeeActual: null,
      oValueGoods: 90,
      oTotalPrice: 111.75,
      oShipping: 19,
      oVat: 0,
    );

    await orderRepository.saveOrder(savedOrder);

    final loaded = await orderRepository.getOrderById('O-ACT-NULL-1');

    expect(loaded, isNotNull);
    expect(loaded!.oPaymentActual, isNull);
    expect(loaded.oPaypalFeeActual, isNull);
  });

  test('liefert positionsanzahl je auftrag inkl. auftraegen ohne positionen', () async {
    await itemRepository.saveCatalogueItem(
      const ItemCatalogueRow(icId: 100, icIdi: 'A-100'),
    );
    await itemRepository.saveCatalogueItem(
      const ItemCatalogueRow(icId: 101, icIdi: 'A-101'),
    );

    await orderRepository.saveOrder(
      const OrderRow(
        oId: 'O-CNT-1',
        oCustomerId: '1000000001',
        oDate: '2026-07-01',
      ),
    );
    await orderRepository.saveOrder(
      const OrderRow(
        oId: 'O-CNT-2',
        oCustomerId: '1000000001',
        oDate: '2026-07-02',
      ),
    );

    await orderRepository.saveItemOrdered(
      const ItemOrderedRow(
        ioOrderId: 'O-CNT-1',
        ioPos: 1,
        ioQuantity: 1,
        ioItemId: 100,
        ioIdi: 'A-100',
      ),
    );
    await orderRepository.saveItemOrdered(
      const ItemOrderedRow(
        ioOrderId: 'O-CNT-1',
        ioPos: 2,
        ioQuantity: 1,
        ioItemId: 101,
        ioIdi: 'A-101',
      ),
    );

    final counts = await orderRepository.getItemCountsByOrderIds(
      const ['O-CNT-1', 'O-CNT-2'],
    );

    expect(counts['O-CNT-1'], 2);
    expect(counts['O-CNT-2'], 0);
  });
}
