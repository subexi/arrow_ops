import 'package:flutter/material.dart';

import 'app_breakpoints.dart';
import 'app_module.dart';

class ArrowOpsShell extends StatefulWidget {
  const ArrowOpsShell({
    super.key,
    this.initialModuleId = ArrowOpsModuleId.customers,
  });

  final ArrowOpsModuleId initialModuleId;

  @override
  State<ArrowOpsShell> createState() => _ArrowOpsShellState();
}

class _ArrowOpsShellState extends State<ArrowOpsShell> {
  int _selectedIndex = 0;
  late final List<Widget?> _pages;

  @override
  void initState() {
    super.initState();
    final initialIndex = ArrowOpsModules.indexOf(widget.initialModuleId);
    _selectedIndex = initialIndex < 0 ? 0 : initialIndex;
    _pages = List<Widget?>.filled(ArrowOpsModules.all.length, null);
    _pages[_selectedIndex] = _buildPage(_selectedIndex);
  }

  void _selectDestination(int index) {
    setState(() {
      _selectedIndex = index;
      _pages[index] ??= _buildPage(index);
    });
  }

  Widget _buildPage(int index) {
    return ArrowOpsModules.all[index].buildPage(context);
  }

  @override
  Widget build(BuildContext context) {
    final windowClass = ArrowOpsBreakpoints.of(context);
    final useBottomNavigation = windowClass == ArrowOpsWindowClass.compact;
    final page = IndexedStack(
      index: _selectedIndex,
      children: _pages
          .map((page) => page ?? const SizedBox.shrink())
          .toList(growable: false),
    );

    if (useBottomNavigation) {
      return Scaffold(
        body: page,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: _selectDestination,
          destinations: ArrowOpsModules.all
              .map(
                (module) => NavigationDestination(
                  icon: Icon(module.icon),
                  selectedIcon: Icon(module.selectedIcon),
                  label: module.label,
                ),
              )
              .toList(growable: false),
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: _selectDestination,
            labelType: windowClass == ArrowOpsWindowClass.expanded
                ? NavigationRailLabelType.all
                : NavigationRailLabelType.selected,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Icon(
                Icons.arrow_outward,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            destinations: ArrowOpsModules.all
                .map(
                  (module) => NavigationRailDestination(
                    icon: Icon(module.icon),
                    selectedIcon: Icon(module.selectedIcon),
                    label: Text(module.label),
                  ),
                )
                .toList(growable: false),
          ),
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          Expanded(child: page),
        ],
      ),
    );
  }
}
