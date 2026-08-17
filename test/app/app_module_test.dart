import 'package:arrow_ops/app/app_module.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('module registry exposes the planned top-level modules in order', () {
    expect(ArrowOpsModules.all.map((module) => module.id), const [
      ArrowOpsModuleId.customers,
      ArrowOpsModuleId.items,
      ArrowOpsModuleId.orders,
      ArrowOpsModuleId.inventory,
      ArrowOpsModuleId.invoices,
      ArrowOpsModuleId.analytics,
      ArrowOpsModuleId.sync,
    ]);
  });

  test('module registry supports lookup by module id', () {
    expect(ArrowOpsModules.byId(ArrowOpsModuleId.orders).label, 'Aufträge');
    expect(ArrowOpsModules.indexOf(ArrowOpsModuleId.analytics), 5);
  });
}
