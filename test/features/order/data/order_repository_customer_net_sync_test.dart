import 'dart:io';

import 'package:arrow_ops/core/database/app_database.dart';
import 'package:arrow_ops/core/database/database_path_config.dart';
import 'package:arrow_ops/features/customer/data/customer_repository.dart';
import 'package:arrow_ops/features/customer/domain/customer.dart';
import 'package:arrow_ops/features/order/data/order_repository.dart';
import 'package:arrow_ops/features/order/domain/order_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tempDir;
  late CustomerRepository customerRepository;
  late OrderRepository orderRepository;

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
}
