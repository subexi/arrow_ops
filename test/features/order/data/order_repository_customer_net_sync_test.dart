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

  test('retoure plus stornierung nimmt erloes raus und fuehrt bestand zurueck', () async {
    await itemRepository.saveCatalogueItem(
      const ItemCatalogueRow(
        icId: 200,
        icIdi: 'R-200',
        icStock: 10,
      ),
    );

    await orderRepository.saveOrder(
      const OrderRow(
        oId: 'O-RET-1',
        oCustomerId: '1000000001',
        oDate: '2026-07-10',
        oValueGoods: 50,
        oTotalPrice: 59.5,
        oShipping: 0,
        oVat: 9.5,
        oCanceled: 1,
        oReturned: 1,
      ),
    );

    await orderRepository.saveItemOrdered(
      const ItemOrderedRow(
        ioOrderId: 'O-RET-1',
        ioPos: 1,
        ioQuantity: 2,
        ioItemId: 200,
        ioIdi: 'R-200',
      ),
    );

    var customer = await customerRepository.getById('1000000001');
    expect(customer, isNotNull);
    expect(customer!.cTotalValueEur, closeTo(0.0, 0.0001));

    var catalogueItem = (await itemRepository.getCatalogueItems())
        .firstWhere((item) => item.icId == 200);
    expect(catalogueItem.icStock, 12);

    final returnedOrder = await orderRepository.getOrderById('O-RET-1');
    expect(returnedOrder, isNotNull);

    await orderRepository.saveOrder(
      returnedOrder!.copyWith(
        oCanceled: 0,
        oReturned: 0,
      ),
      originalOrderId: returnedOrder.oId,
    );

    customer = await customerRepository.getById('1000000001');
    expect(customer, isNotNull);
    expect(customer!.cTotalValueEur, closeTo(50.0, 0.0001));

    catalogueItem = (await itemRepository.getCatalogueItems())
        .firstWhere((item) => item.icId == 200);
    expect(catalogueItem.icStock, 10);
  });

  test('aktualisiert nachlieferungsstatus sofort in pending-counts bei positionsaenderung', () async {
    await itemRepository.saveCatalogueItem(
      const ItemCatalogueRow(icId: 300, icIdi: 'B-300'),
    );

    await orderRepository.saveOrder(
      const OrderRow(
        oId: 'O-BO-1',
        oCustomerId: '1000000001',
        oDate: '2026-07-15',
      ),
    );

    await orderRepository.saveItemOrdered(
      const ItemOrderedRow(
        ioOrderId: 'O-BO-1',
        ioPos: 1,
        ioQuantity: 1,
        ioItemId: 300,
        ioIdi: 'B-300',
        ioBackorderPending: 0,
      ),
    );

    var counts = await orderRepository.getPendingBackorderCountsByOrderIds(
      const ['O-BO-1'],
    );
    expect(counts['O-BO-1'], 0);

    final savedItems = await orderRepository.getItemsForOrder('O-BO-1');
    expect(savedItems, isNotEmpty);
    final current = savedItems.first;

    await orderRepository.saveItemOrdered(
      ItemOrderedRow(
        ioId: current.ioId,
        ioOrderId: current.ioOrderId,
        ioPos: current.ioPos,
        ioQuantity: current.ioQuantity,
        ioItemId: current.ioItemId,
        ioIdi: current.ioIdi,
        ioDescriptionDeLong: current.ioDescriptionDeLong,
        ioDescriptionEnLong: current.ioDescriptionEnLong,
        ioHts: current.ioHts,
        ioColor: current.ioColor,
        ioUnitPrice: current.ioUnitPrice,
        ioDiscount: current.ioDiscount,
        ioTotalPrice: current.ioTotalPrice,
        ioItemWeight: current.ioItemWeight,
        ioTotalWeight: current.ioTotalWeight,
        ioPhoto: current.ioPhoto,
        ioBackorderPending: 1,
      ),
    );

    counts = await orderRepository.getPendingBackorderCountsByOrderIds(
      const ['O-BO-1'],
    );
    expect(counts['O-BO-1'], 1);

    final updatedItems = await orderRepository.getItemsForOrder('O-BO-1');
    final updated = updatedItems.first;
    await orderRepository.saveItemOrdered(
      ItemOrderedRow(
        ioId: updated.ioId,
        ioOrderId: updated.ioOrderId,
        ioPos: updated.ioPos,
        ioQuantity: updated.ioQuantity,
        ioItemId: updated.ioItemId,
        ioIdi: updated.ioIdi,
        ioDescriptionDeLong: updated.ioDescriptionDeLong,
        ioDescriptionEnLong: updated.ioDescriptionEnLong,
        ioHts: updated.ioHts,
        ioColor: updated.ioColor,
        ioUnitPrice: updated.ioUnitPrice,
        ioDiscount: updated.ioDiscount,
        ioTotalPrice: updated.ioTotalPrice,
        ioItemWeight: updated.ioItemWeight,
        ioTotalWeight: updated.ioTotalWeight,
        ioPhoto: updated.ioPhoto,
        ioBackorderPending: 0,
      ),
    );

    counts = await orderRepository.getPendingBackorderCountsByOrderIds(
      const ['O-BO-1'],
    );
    expect(counts['O-BO-1'], 0);
  });

  test('liefert retourenanzahl je auftrag fuer positionsretouren', () async {
    await itemRepository.saveCatalogueItem(
      const ItemCatalogueRow(icId: 350, icIdi: 'R-350'),
    );
    await itemRepository.saveCatalogueItem(
      const ItemCatalogueRow(icId: 351, icIdi: 'R-351'),
    );

    await orderRepository.saveOrder(
      const OrderRow(
        oId: 'O-RET-CNT-1',
        oCustomerId: '1000000001',
        oDate: '2026-07-16',
      ),
    );
    await orderRepository.saveOrder(
      const OrderRow(
        oId: 'O-RET-CNT-2',
        oCustomerId: '1000000001',
        oDate: '2026-07-17',
      ),
    );

    await orderRepository.saveItemOrdered(
      const ItemOrderedRow(
        ioOrderId: 'O-RET-CNT-1',
        ioPos: 1,
        ioQuantity: 1,
        ioItemId: 350,
        ioIdi: 'R-350',
        ioReturned: 1,
      ),
    );
    await orderRepository.saveItemOrdered(
      const ItemOrderedRow(
        ioOrderId: 'O-RET-CNT-1',
        ioPos: 2,
        ioQuantity: 1,
        ioItemId: 351,
        ioIdi: 'R-351',
        ioReturned: 0,
      ),
    );

    final returnedCounts = await orderRepository.getReturnedItemCountsByOrderIds(
      const ['O-RET-CNT-1', 'O-RET-CNT-2'],
    );

    expect(returnedCounts['O-RET-CNT-1'], 1);
    expect(returnedCounts['O-RET-CNT-2'], 0);
  });

  test('unterstuetzt retouren pro position inkl. bestandssync ohne doppelte buchung', () async {
    await itemRepository.saveCatalogueItem(
      const ItemCatalogueRow(
        icId: 400,
        icIdi: 'RET-400',
        icStock: 10,
      ),
    );
    await itemRepository.saveCatalogueItem(
      const ItemCatalogueRow(
        icId: 401,
        icIdi: 'RET-401',
        icStock: 5,
      ),
    );

    await orderRepository.saveOrder(
      const OrderRow(
        oId: 'O-RET-PART-1',
        oCustomerId: '1000000001',
        oDate: '2026-08-01',
      ),
    );

    await orderRepository.saveItemOrdered(
      const ItemOrderedRow(
        ioOrderId: 'O-RET-PART-1',
        ioPos: 1,
        ioQuantity: 2,
        ioItemId: 400,
        ioIdi: 'RET-400',
        ioReturned: 1,
      ),
    );
    await orderRepository.saveItemOrdered(
      const ItemOrderedRow(
        ioOrderId: 'O-RET-PART-1',
        ioPos: 2,
        ioQuantity: 1,
        ioItemId: 401,
        ioIdi: 'RET-401',
        ioReturned: 0,
      ),
    );

    var item400 = (await itemRepository.getCatalogueItems())
        .firstWhere((item) => item.icId == 400);
    var item401 = (await itemRepository.getCatalogueItems())
        .firstWhere((item) => item.icId == 401);
    expect(item400.icStock, 12);
    expect(item401.icStock, 5);

    await orderRepository.saveOrder(
      const OrderRow(
        oId: 'O-RET-PART-1',
        oCustomerId: '1000000001',
        oDate: '2026-08-01',
        oCanceled: 1,
        oReturned: 1,
      ),
      originalOrderId: 'O-RET-PART-1',
    );

    item400 = (await itemRepository.getCatalogueItems())
        .firstWhere((item) => item.icId == 400);
    item401 = (await itemRepository.getCatalogueItems())
        .firstWhere((item) => item.icId == 401);
    expect(item400.icStock, 12);
    expect(item401.icStock, 6);

    await orderRepository.saveOrder(
      const OrderRow(
        oId: 'O-RET-PART-1',
        oCustomerId: '1000000001',
        oDate: '2026-08-01',
        oCanceled: 0,
        oReturned: 0,
      ),
      originalOrderId: 'O-RET-PART-1',
    );

    item400 = (await itemRepository.getCatalogueItems())
        .firstWhere((item) => item.icId == 400);
    item401 = (await itemRepository.getCatalogueItems())
        .firstWhere((item) => item.icId == 401);
    expect(item400.icStock, 12);
    expect(item401.icStock, 5);

    final savedItems = await orderRepository.getItemsForOrder('O-RET-PART-1');
    final returnedItem = savedItems.firstWhere((entry) => entry.ioItemId == 400);
    await orderRepository.deleteItemOrdered(returnedItem.ioId!);

    item400 = (await itemRepository.getCatalogueItems())
        .firstWhere((item) => item.icId == 400);
    expect(item400.icStock, 10);
  });
}
