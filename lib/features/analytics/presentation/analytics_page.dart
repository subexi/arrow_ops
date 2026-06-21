import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../item/data/item_repository.dart';
import '../../item/domain/item_models.dart';
import '../../order/data/order_repository.dart';
import '../../order/domain/order_models.dart';

enum _AnalyticsSubPage { wareinsatz }

enum _PeriodGranularity { month, quarter, year, total }

enum WareinsatzScope { all, bomOnly, withoutBom }

enum _MarginDisplay { absolute, percent }

List<String> wareinsatzExportHeaders(WareinsatzScope scope) {
  return switch (scope) {
    WareinsatzScope.all => const [
        'Bezeichnung',
        'Beschreibung',
        'Menge ohne BOM',
        'BOM-Menge',
        'Gesamtmenge',
      ],
    WareinsatzScope.bomOnly => const [
        'Bezeichnung',
        'Beschreibung',
        'BOM-Menge',
      ],
    WareinsatzScope.withoutBom => const [
        'Bezeichnung',
        'Beschreibung',
        'Menge ohne BOM',
        'EK netto (EUR)',
        'Wert netto (EUR)',
        'Verkauf netto (EUR)',
        'Marge EUR',
      ],
  };
}

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  final OrderRepository _orderRepository = const OrderRepository();
  final ItemRepository _itemRepository = const ItemRepository();
  final TextEditingController _searchController = TextEditingController();

  _AnalyticsSubPage _selectedSubPage = _AnalyticsSubPage.wareinsatz;
  _PeriodGranularity _selectedGranularity = _PeriodGranularity.total;
  WareinsatzScope _selectedScope = WareinsatzScope.all;
  _MarginDisplay _selectedMarginDisplay = _MarginDisplay.absolute;
  int _tableSortColumnIndex = 6;
  bool _tableSortAscending = false;

  bool _loading = true;
  String? _error;
  String _searchQuery = '';

  List<OrderRow> _orders = const [];
  List<ItemOrderedRow> _orderedItems = const [];
  List<ItemCatalogueRow> _catalogueItems = const [];
  List<ItemBomRow> _bomItems = const [];

  String? _selectedMonthKey;
  String? _selectedQuarterKey;
  String? _selectedYearKey;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      final nextQuery = _searchController.text.trim().toLowerCase();
      if (nextQuery == _searchQuery) {
        return;
      }
      setState(() {
        _searchQuery = nextQuery;
      });
    });
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final orders = await _orderRepository.getOrders();
      final itemFutures = orders.map((order) => _orderRepository.getItemsForOrder(order.oId));
      final itemLists = await Future.wait(itemFutures);
      final orderedItems = itemLists.expand((rows) => rows).toList(growable: false);

      final catalogueItems = await _itemRepository.getCatalogueItems();
      final bomItems = await _itemRepository.getBomItems();

      if (!mounted) {
        return;
      }

      setState(() {
        _orders = orders;
        _orderedItems = orderedItems;
        _catalogueItems = catalogueItems;
        _bomItems = bomItems;
        _ensurePeriodDefaults();
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Auswertung konnte nicht geladen werden: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _ensurePeriodDefaults() {
    final monthKeys = _availableMonthKeys(_orders);
    final quarterKeys = _availableQuarterKeys(_orders);
    final yearKeys = _availableYearKeys(_orders);

    if (_selectedMonthKey == null || !monthKeys.contains(_selectedMonthKey)) {
      _selectedMonthKey = monthKeys.isEmpty ? null : monthKeys.first;
    }
    if (_selectedQuarterKey == null || !quarterKeys.contains(_selectedQuarterKey)) {
      _selectedQuarterKey = quarterKeys.isEmpty ? null : quarterKeys.first;
    }
    if (_selectedYearKey == null || !yearKeys.contains(_selectedYearKey)) {
      _selectedYearKey = yearKeys.isEmpty ? null : yearKeys.first;
    }

    if (_selectedGranularity == _PeriodGranularity.month && _selectedMonthKey == null) {
      _selectedGranularity = _PeriodGranularity.total;
    }
    if (_selectedGranularity == _PeriodGranularity.quarter && _selectedQuarterKey == null) {
      _selectedGranularity = _PeriodGranularity.total;
    }
    if (_selectedGranularity == _PeriodGranularity.year && _selectedYearKey == null) {
      _selectedGranularity = _PeriodGranularity.total;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Auswertung'),
        actions: [
          IconButton(
            tooltip: 'Neu laden',
            onPressed: _loading ? null : _loadData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedSubPage.index,
            onDestinationSelected: (index) {
              setState(() {
                _selectedSubPage = _AnalyticsSubPage.values[index];
              });
            },
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.inventory_2_outlined),
                selectedIcon: Icon(Icons.inventory_2),
                label: Text('Wareneinsatz'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: switch (_selectedSubPage) {
              _AnalyticsSubPage.wareinsatz => _buildWareneinsatzView(context),
            },
          ),
        ],
      ),
    );
  }

  Widget _buildWareneinsatzView(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }

    final monthKeys = _availableMonthKeys(_orders);
    final quarterKeys = _availableQuarterKeys(_orders);
    final yearKeys = _availableYearKeys(_orders);
    final filteredOrders = _filterOrdersBySelectedPeriod(_orders);
    final allRows = _buildWareinsatzRows(
      filteredOrders: filteredOrders,
      orderedItems: _orderedItems,
      catalogueItems: _catalogueItems,
      bomItems: _bomItems,
    );
    final rows = _sortWareinsatzRows(_filterRowsBySearch(_filterRowsByScope(allRows)));
    final showMengeOhneBomColumn = _selectedScope != WareinsatzScope.bomOnly;
    final showBomMengeColumn = _selectedScope != WareinsatzScope.withoutBom;
    final showGesamtmengeColumn = _selectedScope == WareinsatzScope.all;
    final showFinancialColumns = _selectedScope == WareinsatzScope.withoutBom;
    final visibleColumnCount = switch (_selectedScope) {
      WareinsatzScope.all => 5,
      WareinsatzScope.bomOnly => 3,
      WareinsatzScope.withoutBom => 7,
    };
    final effectiveSortColumnIndex =
        _tableSortColumnIndex < visibleColumnCount ? _tableSortColumnIndex : 0;

    final totalMengeOhneBom = rows.fold<double>(0, (sum, row) => sum + _displayMengeOhneBom(row));
    final totalBomQty = rows.fold<double>(0, (sum, row) => sum + _displayBomMenge(row));
    final totalGesamtmenge = rows.fold<double>(0, (sum, row) => sum + row.totalQuantity);
    final totalValue = rows.fold<double>(0, (sum, row) => sum + row.totalValueEur);
    final totalSalesNet = rows.fold<double>(0, (sum, row) => sum + row.soldNetValueEur);
    final totalMargin = rows.fold<double>(0, (sum, row) => sum + row.marginEur);
    final totalMarginPercent = totalValue <= 0 ? 0.0 : (totalMargin / totalValue) * 100;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Wareneinsatz',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Aggregation nach Versand-Datum. Beruecksichtigt verkaufte Artikel und zugehoerige BOM-Komponenten.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<_PeriodGranularity>(
                segments: const [
                  ButtonSegment(value: _PeriodGranularity.month, label: Text('Monat')),
                  ButtonSegment(value: _PeriodGranularity.quarter, label: Text('Quartal')),
                  ButtonSegment(value: _PeriodGranularity.year, label: Text('Jahr')),
                  ButtonSegment(value: _PeriodGranularity.total, label: Text('Gesamt')),
                ],
                selected: {_selectedGranularity},
                onSelectionChanged: (selection) {
                  final next = selection.first;
                  setState(() {
                    _selectedGranularity = next;
                    _ensurePeriodDefaults();
                  });
                },
              ),
              SegmentedButton<WareinsatzScope>(
                segments: const [
                  ButtonSegment(value: WareinsatzScope.all, label: Text('Alle Positionen')),
                    ButtonSegment(value: WareinsatzScope.bomOnly, label: Text('nur BOM-Komponenten')),
                    ButtonSegment(value: WareinsatzScope.withoutBom, label: Text('nur ohne BOM')),
                ],
                selected: {_selectedScope},
                onSelectionChanged: (selection) {
                  setState(() {
                    _selectedScope = selection.first;
                  });
                },
              ),
              if (showFinancialColumns)
                SegmentedButton<_MarginDisplay>(
                  segments: const [
                    ButtonSegment(value: _MarginDisplay.absolute, label: Text('Marge EUR')),
                    ButtonSegment(value: _MarginDisplay.percent, label: Text('Marge % auf EK')),
                  ],
                  selected: {_selectedMarginDisplay},
                  onSelectionChanged: (selection) {
                    setState(() {
                      _selectedMarginDisplay = selection.first;
                    });
                  },
                ),
              if (_selectedGranularity == _PeriodGranularity.month)
                _periodDropdown(
                  label: 'Monat',
                  value: _selectedMonthKey,
                  values: monthKeys,
                  onChanged: (value) => setState(() => _selectedMonthKey = value),
                ),
              if (_selectedGranularity == _PeriodGranularity.quarter)
                _periodDropdown(
                  label: 'Quartal',
                  value: _selectedQuarterKey,
                  values: quarterKeys,
                  onChanged: (value) => setState(() => _selectedQuarterKey = value),
                ),
              if (_selectedGranularity == _PeriodGranularity.year)
                _periodDropdown(
                  label: 'Jahr',
                  value: _selectedYearKey,
                  values: yearKeys,
                  onChanged: (value) => setState(() => _selectedYearKey = value),
                ),
              FilledButton.icon(
                onPressed: rows.isEmpty ? null : () => _exportWareinsatzCsv(rows),
                icon: const Icon(Icons.table_chart_outlined),
                label: const Text('CSV exportieren'),
              ),
              FilledButton.tonalIcon(
                onPressed: rows.isEmpty ? null : () => _exportWareinsatzPdf(rows),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('PDF exportieren'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _summaryChip('Auftraege', '${filteredOrders.length}'),
              if (showMengeOhneBomColumn)
                _summaryChip('Menge ohne BOM', _formatQuantity(totalMengeOhneBom)),
              if (showBomMengeColumn)
                _summaryChip('BOM-Menge', _formatQuantity(totalBomQty)),
              if (showGesamtmengeColumn)
                _summaryChip('Gesamtmenge', _formatQuantity(totalGesamtmenge)),
              if (showFinancialColumns) ...[
                _summaryChip('Wert (EUR netto)', _formatMoney(totalValue)),
                _summaryChip('Verkauf (EUR netto)', _formatMoney(totalSalesNet)),
                _summaryChip(
                  _selectedMarginDisplay == _MarginDisplay.percent
                      ? 'Marge % auf EK'
                      : 'Marge EUR',
                  _selectedMarginDisplay == _MarginDisplay.percent
                      ? _formatPercent(totalMarginPercent)
                      : _formatMoney(totalMargin),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: 'Suchen in Bezeichnung und Beschreibung',
              hintText: 'Teiltext, * fuer beliebig, ? fuer ein Zeichen',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Suche loeschen',
                      onPressed: _searchController.clear,
                      icon: const Icon(Icons.clear),
                    ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: rows.isEmpty
                ? const Center(child: Text('Keine Daten fuer den ausgewaehlten Zeitraum.'))
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SingleChildScrollView(
                      child: DataTable(
                        sortColumnIndex: effectiveSortColumnIndex,
                        sortAscending: _tableSortAscending,
                        columns: [
                          DataColumn(
                            label: const Text('Bezeichnung'),
                            onSort: (columnIndex, ascending) =>
                                _onWareneinsatzSortChanged(columnIndex, ascending),
                          ),
                          DataColumn(
                            label: const Text('Beschreibung'),
                            onSort: (columnIndex, ascending) =>
                                _onWareneinsatzSortChanged(columnIndex, ascending),
                          ),
                          if (showMengeOhneBomColumn)
                            DataColumn(
                              numeric: true,
                              label: const Text('Menge ohne BOM'),
                              onSort: (columnIndex, ascending) =>
                                  _onWareneinsatzSortChanged(columnIndex, ascending),
                            ),
                          if (showBomMengeColumn)
                            DataColumn(
                              numeric: true,
                              label: const Text('BOM-Menge'),
                              onSort: (columnIndex, ascending) =>
                                  _onWareneinsatzSortChanged(columnIndex, ascending),
                            ),
                          if (showGesamtmengeColumn)
                            DataColumn(
                              numeric: true,
                              label: const Text('Gesamtmenge'),
                              onSort: (columnIndex, ascending) =>
                                  _onWareneinsatzSortChanged(columnIndex, ascending),
                            ),
                          if (showFinancialColumns) ...[
                            DataColumn(
                              numeric: true,
                              label: const Text('EK netto (EUR)'),
                              onSort: (columnIndex, ascending) =>
                                  _onWareneinsatzSortChanged(columnIndex, ascending),
                            ),
                            DataColumn(
                              numeric: true,
                              label: const Text('Wert netto (EUR)'),
                              onSort: (columnIndex, ascending) =>
                                  _onWareneinsatzSortChanged(columnIndex, ascending),
                            ),
                            DataColumn(
                              numeric: true,
                              label: const Text('Verkauf netto (EUR)'),
                              onSort: (columnIndex, ascending) =>
                                  _onWareneinsatzSortChanged(columnIndex, ascending),
                            ),
                            DataColumn(
                              numeric: true,
                              label: Text(
                                _selectedMarginDisplay == _MarginDisplay.percent
                                    ? 'Marge % auf EK'
                                    : 'Marge EUR',
                              ),
                              onSort: (columnIndex, ascending) =>
                                  _onWareneinsatzSortChanged(columnIndex, ascending),
                            ),
                          ],
                        ],
                        rows: [
                          for (final row in rows)
                            DataRow(
                              cells: [
                                DataCell(Text(row.bezeichnung)),
                                DataCell(
                                  Tooltip(
                                    message: row.beschreibung,
                                    child: Text(
                                      _truncateBeschreibung(row.beschreibung),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                ),
                                if (showMengeOhneBomColumn)
                                  DataCell(Text(_formatQuantity(_displayMengeOhneBom(row)))),
                                if (showBomMengeColumn)
                                  DataCell(Text(_formatQuantity(_displayBomMenge(row)))),
                                if (showGesamtmengeColumn)
                                  DataCell(Text(_formatQuantity(row.totalQuantity))),
                                if (showFinancialColumns) ...[
                                  DataCell(Text(_formatMoney(row.purchasePriceEur))),
                                  DataCell(Text(_formatMoney(row.totalValueEur))),
                                  DataCell(Text(_formatMoney(row.soldNetValueEur))),
                                  DataCell(
                                    Text(
                                      _selectedMarginDisplay == _MarginDisplay.percent
                                          ? _formatPercent(row.marginPercent)
                                          : _formatMoney(row.marginEur),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _periodDropdown({
    required String label,
    required String? value,
    required List<String> values,
    required ValueChanged<String?> onChanged,
  }) {
    return SizedBox(
      width: 180,
      child: DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        items: values
            .map((entry) => DropdownMenuItem<String>(value: entry, child: Text(entry)))
            .toList(growable: false),
        onChanged: values.isEmpty ? null : onChanged,
      ),
    );
  }

  Widget _summaryChip(String label, String value) {
    return Chip(
      label: Text('$label: $value'),
    );
  }

  List<OrderRow> _filterOrdersBySelectedPeriod(List<OrderRow> orders) {
    return orders.where((order) {
      final delivery = _parseDate(order.oDelivery);
      if (delivery == null) {
        return false;
      }

      switch (_selectedGranularity) {
        case _PeriodGranularity.total:
          return true;
        case _PeriodGranularity.month:
          final key = '${delivery.year}-${delivery.month.toString().padLeft(2, '0')}';
          return key == _selectedMonthKey;
        case _PeriodGranularity.quarter:
          final quarter = ((delivery.month - 1) ~/ 3) + 1;
          final key = '${delivery.year}-Q$quarter';
          return key == _selectedQuarterKey;
        case _PeriodGranularity.year:
          final key = delivery.year.toString();
          return key == _selectedYearKey;
      }
    }).toList(growable: false);
  }

  List<String> _availableMonthKeys(List<OrderRow> orders) {
    final keys = <String>{};
    for (final order in orders) {
      final delivery = _parseDate(order.oDelivery);
      if (delivery == null) {
        continue;
      }
      keys.add('${delivery.year}-${delivery.month.toString().padLeft(2, '0')}');
    }
    final list = keys.toList(growable: false)..sort((a, b) => b.compareTo(a));
    return list;
  }

  List<String> _availableQuarterKeys(List<OrderRow> orders) {
    final keys = <String>{};
    for (final order in orders) {
      final delivery = _parseDate(order.oDelivery);
      if (delivery == null) {
        continue;
      }
      final quarter = ((delivery.month - 1) ~/ 3) + 1;
      keys.add('${delivery.year}-Q$quarter');
    }
    final list = keys.toList(growable: false)..sort((a, b) => b.compareTo(a));
    return list;
  }

  List<String> _availableYearKeys(List<OrderRow> orders) {
    final keys = <String>{};
    for (final order in orders) {
      final delivery = _parseDate(order.oDelivery);
      if (delivery == null) {
        continue;
      }
      keys.add(delivery.year.toString());
    }
    final list = keys.toList(growable: false)..sort((a, b) => b.compareTo(a));
    return list;
  }

  DateTime? _parseDate(String raw) {
    final normalized = raw.trim();
    if (normalized.isEmpty || normalized == '-') {
      return null;
    }

    final parsedIso = DateTime.tryParse(normalized);
    if (parsedIso != null) {
      return DateTime(parsedIso.year, parsedIso.month, parsedIso.day);
    }

    final dotMatch = RegExp(r'^(\d{2})\.(\d{2})\.(\d{4})$').firstMatch(normalized);
    if (dotMatch == null) {
      return null;
    }

    final day = int.tryParse(dotMatch.group(1) ?? '');
    final month = int.tryParse(dotMatch.group(2) ?? '');
    final year = int.tryParse(dotMatch.group(3) ?? '');
    if (day == null || month == null || year == null) {
      return null;
    }
    return DateTime(year, month, day);
  }

  List<_WareinsatzRow> _buildWareinsatzRows({
    required List<OrderRow> filteredOrders,
    required List<ItemOrderedRow> orderedItems,
    required List<ItemCatalogueRow> catalogueItems,
    required List<ItemBomRow> bomItems,
  }) {
    final filteredOrderIds = filteredOrders.map((order) => order.oId).toSet();
    final filteredItems = orderedItems
        .where((item) => filteredOrderIds.contains(item.ioOrderId) && item.ioItemId > 0)
        .toList(growable: false);

    final catalogueById = {for (final item in catalogueItems) item.icId: item};
    final childrenByParentId = <int, List<ItemBomRow>>{};
    final rootByArticleId = <int, List<ItemBomRow>>{};

    for (final bom in bomItems) {
      final parentId = bom.ibParentId;
      final id = bom.ibId;
      if (parentId == null) {
        if (id != null) {
          rootByArticleId.putIfAbsent(bom.ibItemId, () => <ItemBomRow>[]).add(bom);
        }
        continue;
      }
      childrenByParentId.putIfAbsent(parentId, () => <ItemBomRow>[]).add(bom);
    }

    final aggregateByItemId = <int, _WareinsatzMutable>{};

    void addSold(int itemId, double quantity, {ItemOrderedRow? ordered}) {
      if (itemId <= 0 || quantity <= 0) {
        return;
      }
      final catalogue = catalogueById[itemId];
      final aggregate = aggregateByItemId.putIfAbsent(itemId, () {
        return _WareinsatzMutable(
          itemId: itemId,
          idi: catalogue?.icIdi ?? ordered?.ioIdi ?? 'Artikel #$itemId',
          description: catalogue?.icDescriptionDeLong ?? ordered?.ioDescriptionDeLong ?? '-',
          purchasePriceEur: catalogue?.icPurchasePriceNet ?? 0,
          netSalePricePerUnit: catalogue?.icPriceNet ?? 0,
        );
      });
      aggregate.soldQuantity += quantity;
    }

    void addBom(int itemId, double quantity) {
      if (itemId <= 0 || quantity <= 0) {
        return;
      }
      final catalogue = catalogueById[itemId];
      final aggregate = aggregateByItemId.putIfAbsent(itemId, () {
        return _WareinsatzMutable(
          itemId: itemId,
          idi: catalogue?.icIdi ?? 'Artikel #$itemId',
          description: catalogue?.icDescriptionDeLong ?? '-',
          purchasePriceEur: catalogue?.icPurchasePriceNet ?? 0,
          netSalePricePerUnit: catalogue?.icPriceNet ?? 0,
        );
      });
      aggregate.bomQuantity += quantity;
    }

    void accumulateBomChildren(
      int parentBomId,
      double baseQuantity,
      Set<int> visiting,
    ) {
      if (visiting.contains(parentBomId)) {
        return;
      }

      final children = childrenByParentId[parentBomId] ?? const <ItemBomRow>[];
      if (children.isEmpty) {
        return;
      }

      final nextVisiting = {...visiting, parentBomId};
      for (final child in children) {
        final componentQuantity = baseQuantity * child.ibQuantity;
        addBom(child.ibItemId, componentQuantity);
        final childBomId = child.ibId;
        if (childBomId != null) {
          accumulateBomChildren(childBomId, componentQuantity, nextVisiting);
        }
      }
    }

    for (final item in filteredItems) {
      final soldQuantity = item.ioQuantity.toDouble();
      addSold(item.ioItemId, soldQuantity, ordered: item);

      final roots = rootByArticleId[item.ioItemId] ?? const <ItemBomRow>[];
      for (final root in roots) {
        final rootBomId = root.ibId;
        if (rootBomId == null) {
          continue;
        }
        accumulateBomChildren(rootBomId, soldQuantity, <int>{});
      }
    }

    final rows = aggregateByItemId.values
        .map((entry) => entry.toRow())
        .toList(growable: false)
      ..sort((a, b) {
        final valueCompare = b.totalValueEur.compareTo(a.totalValueEur);
        if (valueCompare != 0) {
          return valueCompare;
        }
        return a.itemId.compareTo(b.itemId);
      });

    return rows;
  }

  Future<void> _exportWareinsatzCsv(List<_WareinsatzRow> rows) async {
    setState(() => _loading = true);
    try {
      final showMengeOhneBomColumn = _selectedScope != WareinsatzScope.bomOnly;
      final showBomMengeColumn = _selectedScope != WareinsatzScope.withoutBom;
      final showGesamtmengeColumn = _selectedScope == WareinsatzScope.all;
      final showFinancialColumns = _selectedScope == WareinsatzScope.withoutBom;
      final headers = wareinsatzExportHeaders(_selectedScope);
      final buffer = StringBuffer();
      buffer.writeln(headers.map(_csvEscape).join(';'));

      for (final row in rows) {
        final cells = <String>[
          _csvEscape(row.bezeichnung),
          _csvEscape(row.beschreibung),
          if (showMengeOhneBomColumn) _csvEscape(_formatQuantity(_displayMengeOhneBom(row))),
          if (showBomMengeColumn) _csvEscape(_formatQuantity(_displayBomMenge(row))),
          if (showGesamtmengeColumn) _csvEscape(_formatQuantity(row.totalQuantity)),
          if (showFinancialColumns) ...[
            _csvEscape(_formatMoney(row.purchasePriceEur)),
            _csvEscape(_formatMoney(row.totalValueEur)),
            _csvEscape(_formatMoney(row.soldNetValueEur)),
            _csvEscape(
              _selectedMarginDisplay == _MarginDisplay.percent
                  ? _formatPercent(row.marginPercent)
                  : _formatMoney(row.marginEur),
            ),
          ],
        ];
        buffer.writeln(cells.join(';'));
      }

      final fileName = 'wareneinsatz_versanddatum_${_periodLabelForExport()}_${_buildFileTimestamp(DateTime.now())}.csv';
      final targetPath = await _pickExportTargetPath(
        dialogTitle: 'Wareneinsatz als CSV exportieren',
        fileName: fileName,
        allowedExtensions: const ['csv'],
      );
      if (targetPath == null || targetPath.trim().isEmpty) {
        return;
      }

      final csvWithBom = '\uFEFF${buffer.toString()}';
      await File(targetPath).writeAsString(csvWithBom, encoding: utf8);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Wareneinsatz-CSV exportiert nach: $targetPath')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Wareneinsatz-CSV-Export fehlgeschlagen: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _exportWareinsatzPdf(List<_WareinsatzRow> rows) async {
    setState(() => _loading = true);
    try {
      final document = pw.Document();
      final fonts = await _loadPdfFonts();
      final showMengeOhneBomColumn = _selectedScope != WareinsatzScope.bomOnly;
      final showBomMengeColumn = _selectedScope != WareinsatzScope.withoutBom;
      final showGesamtmengeColumn = _selectedScope == WareinsatzScope.all;
      final showFinancialColumns = _selectedScope == WareinsatzScope.withoutBom;
      final headers = wareinsatzExportHeaders(_selectedScope);
      final tableData = rows
          .map(
            (row) => <String>[
              row.bezeichnung,
              row.beschreibung,
              if (showMengeOhneBomColumn) _formatQuantity(_displayMengeOhneBom(row)),
              if (showBomMengeColumn) _formatQuantity(_displayBomMenge(row)),
              if (showGesamtmengeColumn) _formatQuantity(row.totalQuantity),
              if (showFinancialColumns) ...[
                _formatMoney(row.purchasePriceEur),
                _formatMoney(row.totalValueEur),
                _formatMoney(row.soldNetValueEur),
                _selectedMarginDisplay == _MarginDisplay.percent
                    ? _formatPercent(row.marginPercent)
                    : _formatMoney(row.marginEur),
              ],
            ],
          )
          .toList(growable: false);

      document.addPage(
        pw.MultiPage(
          theme: pw.ThemeData.withFont(base: fonts.base, bold: fonts.bold),
          pageFormat: PdfPageFormat.a3.landscape,
          build: (context) => [
            pw.Text(
              'Wareneinsatz nach Versand-Datum (${_periodLabelForExportUi()})',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headers: headers,
              data: tableData,
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
              headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 7),
              cellAlignment: pw.Alignment.centerLeft,
              cellPadding: const pw.EdgeInsets.all(3),
              columnWidths: {
                0: const pw.FlexColumnWidth(0.9),
                1: const pw.FlexColumnWidth(3.4),
                if (showMengeOhneBomColumn) 2: const pw.FlexColumnWidth(1.0),
                if (showBomMengeColumn) ...{
                  if (showMengeOhneBomColumn) 3: const pw.FlexColumnWidth(1.0),
                  if (!showMengeOhneBomColumn) 2: const pw.FlexColumnWidth(1.0),
                },
                if (showGesamtmengeColumn) ...{
                  if (showMengeOhneBomColumn && showBomMengeColumn) 4: const pw.FlexColumnWidth(1.0),
                  if (!showMengeOhneBomColumn && showBomMengeColumn) 3: const pw.FlexColumnWidth(1.0),
                },
                if (showFinancialColumns) ...{
                  if (showGesamtmengeColumn) ...{
                    5: const pw.FlexColumnWidth(1.1),
                    6: const pw.FlexColumnWidth(1.2),
                    7: const pw.FlexColumnWidth(1.2),
                    8: const pw.FlexColumnWidth(1.1),
                  } else ...{
                    4: const pw.FlexColumnWidth(1.1),
                    5: const pw.FlexColumnWidth(1.2),
                    6: const pw.FlexColumnWidth(1.2),
                    7: const pw.FlexColumnWidth(1.1),
                  },
                },
              },
            ),
          ],
        ),
      );

      final fileName = 'wareneinsatz_${_periodLabelForExport()}_${_buildFileTimestamp(DateTime.now())}.pdf';
      final targetPath = await _pickExportTargetPath(
        dialogTitle: 'Wareneinsatz als PDF exportieren',
        fileName: fileName,
        allowedExtensions: const ['pdf'],
      );
      if (targetPath == null || targetPath.trim().isEmpty) {
        return;
      }

      await File(targetPath).writeAsBytes(await document.save());
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Wareneinsatz-PDF exportiert nach: $targetPath')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Wareneinsatz-PDF-Export fehlgeschlagen: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<String?> _pickExportTargetPath({
    required String dialogTitle,
    required String fileName,
    required List<String> allowedExtensions,
  }) async {
    final initialDirectory = (await getApplicationDocumentsDirectory()).path;
    try {
      return await FilePicker.saveFile(
        dialogTitle: dialogTitle,
        fileName: fileName,
        initialDirectory: initialDirectory,
        type: FileType.custom,
        allowedExtensions: allowedExtensions,
      );
    } catch (_) {
      return null;
    }
  }

  Future<_PdfFonts> _loadPdfFonts() async {
    final baseData = await rootBundle.load('lib/fonts/Roboto-Regular.ttf');
    final boldData = await rootBundle.load('lib/fonts/Roboto-Bold.ttf');
    return _PdfFonts(
      base: pw.Font.ttf(baseData),
      bold: pw.Font.ttf(boldData),
    );
  }

  String _csvEscape(String value) {
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }

  String _buildFileTimestamp(DateTime value) {
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    final year = value.year.toString().padLeft(4, '0');
    final month = twoDigits(value.month);
    final day = twoDigits(value.day);
    final hour = twoDigits(value.hour);
    final minute = twoDigits(value.minute);
    final second = twoDigits(value.second);
    return '$year$month${day}_$hour$minute$second';
  }

  String _periodLabelForExport() {
    final scope = switch (_selectedScope) {
      WareinsatzScope.all => 'all',
      WareinsatzScope.bomOnly => 'bom',
      WareinsatzScope.withoutBom => 'without_bom',
    };
    switch (_selectedGranularity) {
      case _PeriodGranularity.month:
        return 'monat_${_selectedMonthKey ?? 'na'}_$scope';
      case _PeriodGranularity.quarter:
        return 'quartal_${_selectedQuarterKey ?? 'na'}_$scope';
      case _PeriodGranularity.year:
        return 'jahr_${_selectedYearKey ?? 'na'}_$scope';
      case _PeriodGranularity.total:
        return 'gesamt_$scope';
    }
  }

  String _periodLabelForExportUi() {
    final scopeLabel = switch (_selectedScope) {
      WareinsatzScope.all => ' | Alle Positionen',
      WareinsatzScope.bomOnly => ' | nur BOM-Komponenten',
      WareinsatzScope.withoutBom => ' | nur ohne BOM',
    };
    switch (_selectedGranularity) {
      case _PeriodGranularity.month:
        return 'Monat ${_selectedMonthKey ?? '-'}$scopeLabel';
      case _PeriodGranularity.quarter:
        return 'Quartal ${_selectedQuarterKey ?? '-'}$scopeLabel';
      case _PeriodGranularity.year:
        return 'Jahr ${_selectedYearKey ?? '-'}$scopeLabel';
      case _PeriodGranularity.total:
        return 'Gesamt$scopeLabel';
    }
  }

  List<_WareinsatzRow> _filterRowsByScope(List<_WareinsatzRow> rows) {
    switch (_selectedScope) {
      case WareinsatzScope.all:
        return rows;
      case WareinsatzScope.bomOnly:
        return rows.where((row) => row.bomQuantity > 0).toList(growable: false);
      case WareinsatzScope.withoutBom:
        return rows.where((row) => row.soldQuantity > 0 && row.bomQuantity <= 0).toList(growable: false);
    }
  }

  List<_WareinsatzRow> _filterRowsBySearch(List<_WareinsatzRow> rows) {
    if (_searchQuery.isEmpty) {
      return rows;
    }

    final wildcardPattern = _buildWildcardRegexPattern(_searchQuery);
    final wildcardRegex = wildcardPattern == null
        ? null
        : RegExp(wildcardPattern, caseSensitive: false);

    return rows.where((row) {
      final bezeichnung = row.bezeichnung.toLowerCase();
      final beschreibung = row.beschreibung.toLowerCase();

      if (wildcardRegex != null) {
        return wildcardRegex.hasMatch(bezeichnung) || wildcardRegex.hasMatch(beschreibung);
      }

      return bezeichnung.contains(_searchQuery) || beschreibung.contains(_searchQuery);
    }).toList(growable: false);
  }

  String? _buildWildcardRegexPattern(String query) {
    if (!query.contains('*') && !query.contains('?')) {
      return null;
    }

    final pattern = StringBuffer();
    for (final rune in query.runes) {
      final char = String.fromCharCode(rune);
      switch (char) {
        case '*':
          pattern.write('.*');
        case '?':
          pattern.write('.');
        default:
          pattern.write(RegExp.escape(char));
      }
    }

    return pattern.toString();
  }

  void _onWareneinsatzSortChanged(int columnIndex, bool ascending) {
    setState(() {
      _tableSortColumnIndex = columnIndex;
      _tableSortAscending = ascending;
    });
  }

  List<_WareinsatzRow> _sortWareinsatzRows(List<_WareinsatzRow> rows) {
    final sorted = List<_WareinsatzRow>.from(rows);
    final isAllScope = _selectedScope == WareinsatzScope.all;
    final visibleColumnCount = isAllScope ? 5 : 3;
    final effectiveSortColumnIndex =
        _tableSortColumnIndex < visibleColumnCount ? _tableSortColumnIndex : 0;
    int compare(_WareinsatzRow a, _WareinsatzRow b) {
      switch (effectiveSortColumnIndex) {
        case 0:
          return a.bezeichnung.toLowerCase().compareTo(b.bezeichnung.toLowerCase());
        case 1:
          return a.beschreibung.toLowerCase().compareTo(b.beschreibung.toLowerCase());
        case 2:
          return _displayMengeOhneBom(a).compareTo(_displayMengeOhneBom(b));
        case 3:
          return isAllScope
              ? _displayBomMenge(a).compareTo(_displayBomMenge(b))
              : a.purchasePriceEur.compareTo(b.purchasePriceEur);
        case 4:
          return isAllScope
              ? a.totalQuantity.compareTo(b.totalQuantity)
              : a.totalValueEur.compareTo(b.totalValueEur);
        case 5:
          return isAllScope
              ? a.totalValueEur.compareTo(b.totalValueEur)
              : a.soldNetValueEur.compareTo(b.soldNetValueEur);
        case 6:
          return isAllScope
              ? a.soldNetValueEur.compareTo(b.soldNetValueEur)
              : (_selectedMarginDisplay == _MarginDisplay.percent
                  ? a.marginPercent.compareTo(b.marginPercent)
                  : a.marginEur.compareTo(b.marginEur));
        case 7:
          return _selectedMarginDisplay == _MarginDisplay.percent
              ? a.marginPercent.compareTo(b.marginPercent)
              : a.marginEur.compareTo(b.marginEur);
        default:
          return a.itemId.compareTo(b.itemId);
      }
    }

    sorted.sort((a, b) {
      final result = compare(a, b);
      if (result == 0) {
        return a.itemId.compareTo(b.itemId);
      }
      return _tableSortAscending ? result : -result;
    });
    return sorted;
  }

  String _truncateBeschreibung(String value, {int maxChars = 60}) {
    final flat = value.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    if (flat.length <= maxChars) {
      return flat;
    }
    return '${flat.substring(0, maxChars - 1)}\u2026';
  }

  String _formatQuantity(double value) {
    final rounded = value.roundToDouble();
    if ((value - rounded).abs() < 0.0000001) {
      return rounded.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2).replaceAll('.', ',');
  }

  String _formatMoney(double value) {
    return value.toStringAsFixed(2).replaceAll('.', ',');
  }

  String _formatPercent(double value) {
    return '${value.toStringAsFixed(2).replaceAll('.', ',')} %';
  }

  double _displayMengeOhneBom(_WareinsatzRow row) {
    return _selectedScope == WareinsatzScope.bomOnly ? 0 : row.soldQuantity;
  }

  double _displayBomMenge(_WareinsatzRow row) {
    return _selectedScope == WareinsatzScope.withoutBom ? 0 : row.bomQuantity;
  }
}

class _WareinsatzMutable {
  _WareinsatzMutable({
    required this.itemId,
    required this.idi,
    required this.description,
    required this.purchasePriceEur,
    required this.netSalePricePerUnit,
  });

  final int itemId;
  final String idi;
  final String description;
  final double purchasePriceEur;
  final double netSalePricePerUnit;

  double soldQuantity = 0;
  double bomQuantity = 0;

  _WareinsatzRow toRow() {
    final normalizedBeschreibung = _stripBezeichnungFromBeschreibung(
      bezeichnung: idi,
      beschreibung: description,
    );
    return _WareinsatzRow(
      itemId: itemId,
      bezeichnung: idi,
      beschreibung: normalizedBeschreibung,
      soldQuantity: soldQuantity,
      bomQuantity: bomQuantity,
      purchasePriceEur: purchasePriceEur,
      netSalePricePerUnit: netSalePricePerUnit,
    );
  }
}

class _WareinsatzRow {
  const _WareinsatzRow({
    required this.itemId,
    required this.bezeichnung,
    required this.beschreibung,
    required this.soldQuantity,
    required this.bomQuantity,
    required this.purchasePriceEur,
    required this.netSalePricePerUnit,
  });

  final int itemId;
  final String bezeichnung;
  final String beschreibung;
  final double soldQuantity;
  final double bomQuantity;
  final double purchasePriceEur;
  final double netSalePricePerUnit;

  double get totalValueEur => totalQuantity * purchasePriceEur;
  double get soldNetValueEur => netSalePricePerUnit * totalQuantity;
  double get marginEur => soldNetValueEur <= 0 ? 0 : soldNetValueEur - totalValueEur;
  double get marginPercent => (soldNetValueEur <= 0 || totalValueEur <= 0) ? 0 : (marginEur / totalValueEur) * 100;

  double get totalQuantity => soldQuantity + bomQuantity;
}

class _PdfFonts {
  const _PdfFonts({required this.base, required this.bold});

  final pw.Font base;
  final pw.Font bold;
}

String _stripBezeichnungFromBeschreibung({
  required String bezeichnung,
  required String beschreibung,
}) {
  final normalizedBezeichnung = bezeichnung.trim();
  final normalizedBeschreibung = beschreibung.trim();
  if (normalizedBezeichnung.isEmpty || normalizedBeschreibung.isEmpty) {
    return normalizedBeschreibung.isEmpty ? '-' : normalizedBeschreibung;
  }

  final bezeichnungLower = normalizedBezeichnung.toLowerCase();
  final beschreibungLower = normalizedBeschreibung.toLowerCase();

  if (beschreibungLower == bezeichnungLower) {
    return '-';
  }

  if (beschreibungLower.startsWith(bezeichnungLower)) {
    var remainder = normalizedBeschreibung.substring(normalizedBezeichnung.length).trimLeft();
    const separators = ['|', '-', ':', ';', ',', '/'];
    while (remainder.isNotEmpty && separators.contains(remainder[0])) {
      remainder = remainder.substring(1).trimLeft();
    }
    return remainder.isEmpty ? '-' : remainder;
  }

  return normalizedBeschreibung;
}
