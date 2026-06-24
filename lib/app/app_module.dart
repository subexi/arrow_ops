import 'package:flutter/material.dart';

import '../features/analytics/presentation/analytics_page.dart';
import '../features/customer/presentation/customer_page.dart';
import '../features/inventory/presentation/parts_procurement_page.dart';
import '../features/invoice/presentation/invoice_page.dart';
import '../features/item/presentation/item_catalogue_page.dart';
import '../features/order/presentation/order_page.dart';
import '../features/sync/presentation/sync_page.dart';

typedef ArrowOpsPageBuilder = Widget Function(BuildContext context);

enum ArrowOpsModuleId {
  customers,
  items,
  orders,
  inventory,
  invoices,
  analytics,
  sync,
}

class ArrowOpsModule {
  const ArrowOpsModule({
    required this.id,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.buildPage,
  });

  final ArrowOpsModuleId id;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final ArrowOpsPageBuilder buildPage;
}

class ArrowOpsModules {
  const ArrowOpsModules._();

  static final List<ArrowOpsModule> all = List.unmodifiable([
    ArrowOpsModule(
      id: ArrowOpsModuleId.customers,
      label: 'Kunden',
      icon: Icons.people_outline,
      selectedIcon: Icons.people,
      buildPage: (_) => const CustomerPage(showModuleNavigation: false),
    ),
    ArrowOpsModule(
      id: ArrowOpsModuleId.items,
      label: 'Artikel',
      icon: Icons.inventory_2_outlined,
      selectedIcon: Icons.inventory_2,
      buildPage: (_) => const ItemCataloguePage(),
    ),
    ArrowOpsModule(
      id: ArrowOpsModuleId.orders,
      label: 'Aufträge',
      icon: Icons.assignment_outlined,
      selectedIcon: Icons.assignment,
      buildPage: (_) => const OrderPage(),
    ),
    ArrowOpsModule(
      id: ArrowOpsModuleId.inventory,
      label: 'Bestandsführung',
      icon: Icons.inventory_outlined,
      selectedIcon: Icons.inventory,
      buildPage: (_) => const PartsProcurementPage(),
    ),
    ArrowOpsModule(
      id: ArrowOpsModuleId.invoices,
      label: 'Rechnungen / Lieferscheine',
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long,
      buildPage: (_) => const InvoicePage(),
    ),
    ArrowOpsModule(
      id: ArrowOpsModuleId.analytics,
      label: 'Auswertung',
      icon: Icons.query_stats_outlined,
      selectedIcon: Icons.query_stats,
      buildPage: (_) => const AnalyticsPage(),
    ),
    ArrowOpsModule(
      id: ArrowOpsModuleId.sync,
      label: 'Sync',
      icon: Icons.cloud_sync_outlined,
      selectedIcon: Icons.cloud_sync,
      buildPage: (_) => const SyncPage(),
    ),
  ]);

  static int indexOf(ArrowOpsModuleId id) {
    return all.indexWhere((module) => module.id == id);
  }

  static ArrowOpsModule byId(ArrowOpsModuleId id) {
    return all.firstWhere((module) => module.id == id);
  }
}
