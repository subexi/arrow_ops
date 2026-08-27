import 'dart:convert';
import 'dart:io';

import 'package:data_table_2/data_table_2.dart';
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

enum WareinsatzPuttFilter { all, onlyPutt, withoutPutt }

List<String> wareinsatzAvailableTradeShowOptions(List<OrderRow> orders) {
  final values = <String>{};
  for (final order in orders) {
    final tradeShow = order.oTradeShow.trim();
    if (tradeShow.isEmpty || tradeShow == '-') {
      continue;
    }
    values.add(tradeShow);
  }
  final list = values.toList(growable: false)
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return list;
}

List<OrderRow> wareinsatzFilterOrdersByTradeShowAndPutt({
  required List<OrderRow> orders,
  required Set<String> selectedTradeShows,
  required WareinsatzPuttFilter puttFilter,
}) {
  return orders.where((order) {
    if (selectedTradeShows.isNotEmpty) {
      final tradeShow = order.oTradeShow.trim();
      if (!selectedTradeShows.contains(tradeShow)) {
        return false;
      }
    }

    switch (puttFilter) {
      case WareinsatzPuttFilter.all:
        return true;
      case WareinsatzPuttFilter.onlyPutt:
        return order.oPutt != 0;
      case WareinsatzPuttFilter.withoutPutt:
        return order.oPutt == 0;
    }
  }).toList(growable: false);
}

bool wareinsatzRowMatchesScope({
  required WareinsatzScope scope,
  required double soldQuantity,
  required double bomQuantity,
}) {
  switch (scope) {
    case WareinsatzScope.all:
      return true;
    case WareinsatzScope.bomOnly:
      return bomQuantity > 0;
    case WareinsatzScope.withoutBom:
      // Keep all sold rows. A sold item can also appear as BOM component in
      // other rows/orders and must still count towards sales diagnostics.
      return soldQuantity > 0;
  }
}

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
        'Σ EK netto (EUR)',
        'Σ Verkauf netto (EUR)',
        'Marge EUR',
      ],
  };
}

List<double> wareinsatzPdfColumnFlexes({
  required bool showMengeOhneBomColumn,
  required bool showBomMengeColumn,
  required bool showGesamtmengeColumn,
  required bool showFinancialColumns,
}) {
  return <double>[
    0.9,
    3.4,
    if (showMengeOhneBomColumn) 1.0,
    if (showBomMengeColumn) 1.0,
    if (showGesamtmengeColumn) 1.0,
    if (showFinancialColumns) ...[
      1.1,
      1.2,
      1.2,
      1.1,
    ],
  ];
}

double wareinsatzOrderedItemNetSales(ItemOrderedRow? item) =>
    item?.ioTotalPrice ?? 0;

double wareinsatzSumOrderedItemNetSales(Iterable<ItemOrderedRow> items) =>
    items.fold<double>(0, (sum, item) => sum + wareinsatzOrderedItemNetSales(item));

double wareinsatzOrderedItemNetSalesForOrder({
  required ItemOrderedRow item,
  required OrderRow? order,
}) {
  final grossOrNet = wareinsatzOrderedItemNetSales(item);
  if (order == null) {
    return grossOrNet;
  }

  final isGrossBasis = order.oPriceBasis.trim().toLowerCase() == 'gross';
  const cashPaymentCode = 4;
  final cashSpecial = order.oPutt != 0 && order.oPayment == cashPaymentCode;

  double normalizedNet = grossOrNet;
  if (isGrossBasis && !cashSpecial) {
    final divisor = 1 + (order.oVatRate / 100);
    if (divisor > 0) {
      normalizedNet = grossOrNet / divisor;
    }
  }

  final currency = order.oCurrency.trim().toUpperCase();
  if (currency == 'USD') {
    final fxToEur = order.oFxToEur;
    if (fxToEur <= 0) {
      return 0;
    }
    return normalizedNet * fxToEur;
  }

  return normalizedNet;
}

DateTime? wareinsatzParseDeliveryDate(String raw) {
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

bool wareinsatzMatchesDeliveryMonth(OrderRow order, String monthKey) {
  final delivery = wareinsatzParseDeliveryDate(order.oDelivery);
  if (delivery == null) {
    return false;
  }
  final key = '${delivery.year}-${delivery.month.toString().padLeft(2, '0')}';
  return key == monthKey;
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
  WareinsatzPuttFilter _selectedPuttFilter = WareinsatzPuttFilter.all;
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
  Set<String> _selectedTradeShows = const <String>{};
  bool _wasVisibleInBuild = false;

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

    final availableTradeShows = wareinsatzAvailableTradeShowOptions(_orders).toSet();
    _selectedTradeShows = _selectedTradeShows
        .where(availableTradeShows.contains)
        .toSet();
  }

  @override
  Widget build(BuildContext context) {
    final offstageAncestor = context.findAncestorWidgetOfExactType<Offstage>();
    final isVisibleInShell = offstageAncestor?.offstage != true;
    if (isVisibleInShell && !_wasVisibleInBuild && !_loading) {
      _loadData();
    }
    _wasVisibleInBuild = isVisibleInShell;

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
    final tradeShowOptions = wareinsatzAvailableTradeShowOptions(_orders);
    final filteredOrders = _filterOrders(_orders);
    final allRows = _buildWareinsatzRows(
      filteredOrders: filteredOrders,
      orderedItems: _orderedItems,
      catalogueItems: _catalogueItems,
      bomItems: _bomItems,
    );
    final scopeRows = _filterRowsByScope(allRows);
    final scopedItemIds = scopeRows.map((row) => row.itemId).toSet();
    final orderNetContributions = _buildOrderNetContributions(
      filteredOrders: filteredOrders,
      orderedItems: _orderedItems,
      allowedItemIds: scopedItemIds,
    );
    final rows = _sortWareinsatzRows(_filterRowsBySearch(_filterRowsByScope(allRows)));
    final priceBasisCurrencyLabel = _diagnosticsPriceBasisCurrencyLabel(
      orderNetContributions,
    );
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
    final diagnosticsTableMaxHeight =
      (MediaQuery.sizeOf(context).height * 0.34).clamp(220.0, 420.0).toDouble();

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
            'Aggregation nach Versand-Datum. Σ Verkauf netto basiert auf den tatsaechlichen Positionswerten (io_total_price); BOM-Komponenten werden mengenmaessig beruecksichtigt.',
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
              _tradeShowFilterButton(tradeShowOptions),
              SegmentedButton<WareinsatzPuttFilter>(
                segments: const [
                  ButtonSegment(
                    value: WareinsatzPuttFilter.all,
                    label: Text('PUTT: alle'),
                  ),
                  ButtonSegment(
                    value: WareinsatzPuttFilter.onlyPutt,
                    label: Text('nur PUTT'),
                  ),
                  ButtonSegment(
                    value: WareinsatzPuttFilter.withoutPutt,
                    label: Text('ohne PUTT'),
                  ),
                ],
                selected: {_selectedPuttFilter},
                onSelectionChanged: (selection) {
                  setState(() {
                    _selectedPuttFilter = selection.first;
                  });
                },
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
              if (_selectedTradeShows.isNotEmpty)
                _summaryChip('Trade Show', _selectedTradeShows.join(', ')),
              if (_selectedPuttFilter != WareinsatzPuttFilter.all)
                _summaryChip(
                  'PUTT',
                  _selectedPuttFilter == WareinsatzPuttFilter.onlyPutt
                      ? 'nur PUTT'
                      : 'ohne PUTT',
                ),
              if (showMengeOhneBomColumn)
                _summaryChip('Menge ohne BOM', _formatQuantity(totalMengeOhneBom)),
              if (showBomMengeColumn)
                _summaryChip('BOM-Menge', _formatQuantity(totalBomQty)),
              if (showGesamtmengeColumn)
                _summaryChip('Gesamtmenge', _formatQuantity(totalGesamtmenge)),
              if (showFinancialColumns) ...[
                _summaryChip('Σ Wert EK (EUR)', _formatMoney(totalValue)),
                _summaryChip('Σ Verkauf (EUR)', _formatMoney(totalSalesNet)),
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
          if (showFinancialColumns) ...[
            const SizedBox(height: 12),
            Card(
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                title: const Text('Diagnose: Auftragsbeitraege zu Σ Verkauf (netto, scope-konsistent)'),
                subtitle: Text(
                  '${orderNetContributions.length} Auftraege • Summe ${_formatMoney(orderNetContributions.fold<double>(0, (sum, row) => sum + row.netSalesEur))} EUR',
                ),
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: FilledButton.tonalIcon(
                        onPressed: orderNetContributions.isEmpty
                            ? null
                            : () => _exportOrderNetContributionsCsv(orderNetContributions),
                        icon: const Icon(Icons.table_chart_outlined),
                        label: const Text('Diagnose-CSV exportieren'),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: diagnosticsTableMaxHeight,
                    child: DataTable2(
                      minWidth: 1250,
                      fixedTopRows: 1,
                      headingRowHeight: 68,
                      columnSpacing: 14,
                      horizontalMargin: 10,
                      headingTextStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        height: 1.2,
                      ),
                      headingRowColor: WidgetStateProperty.resolveWith(
                        (_) => Theme.of(context).colorScheme.surfaceContainerHighest,
                      ),
                      columns: [
                        DataColumn2(
                          label: const Text('Auftrag', maxLines: 2, softWrap: true, overflow: TextOverflow.visible),
                          fixedWidth: 130,
                        ),
                        DataColumn2(
                          label: const Text('Versanddatum', maxLines: 2, softWrap: true, overflow: TextOverflow.visible),
                          fixedWidth: 150,
                        ),
                        DataColumn2(
                          label: const Text('Auftragsdatum', maxLines: 2, softWrap: true, overflow: TextOverflow.visible),
                          fixedWidth: 150,
                        ),
                        DataColumn2(
                          label: const Text('Waehrung', maxLines: 2, softWrap: true, overflow: TextOverflow.visible),
                          fixedWidth: 95,
                        ),
                        DataColumn2(
                          label: const Text('USD→EUR', maxLines: 2, softWrap: true, overflow: TextOverflow.visible),
                          numeric: true,
                          fixedWidth: 125,
                        ),
                        DataColumn2(
                          label: Text(
                            'Berechnungsbasis\n($priceBasisCurrencyLabel)',
                            maxLines: 2,
                            softWrap: true,
                            overflow: TextOverflow.visible,
                          ),
                          numeric: true,
                          fixedWidth: 200,
                        ),
                        DataColumn2(
                          label: const Text('MwSt %', maxLines: 2, softWrap: true, overflow: TextOverflow.visible),
                          numeric: true,
                          fixedWidth: 95,
                        ),
                        DataColumn2(
                          label: const Text('Pos.', maxLines: 2, softWrap: true, overflow: TextOverflow.visible),
                          numeric: true,
                          fixedWidth: 70,
                        ),
                        DataColumn2(
                          label: const Text('Netto (EUR)', maxLines: 2, softWrap: true, overflow: TextOverflow.visible),
                          numeric: true,
                          fixedWidth: 145,
                        ),
                        DataColumn2(
                          label: const Text('Hinweis', maxLines: 2, softWrap: true, overflow: TextOverflow.visible),
                          size: ColumnSize.L,
                        ),
                      ],
                      rows: [
                        for (final contribution in orderNetContributions)
                          DataRow(
                            cells: [
                              DataCell(Text(contribution.orderId)),
                              DataCell(Text(contribution.deliveryDate)),
                              DataCell(Text(contribution.orderDate)),
                              DataCell(Text(contribution.currency)),
                              DataCell(Text(_formatMoney(contribution.fxToEur))),
                              DataCell(Text(_formatMoney(contribution.priceBasisValue))),
                              DataCell(Text(_formatMoney(contribution.vatRate))),
                              DataCell(Text(contribution.itemCount.toString())),
                              DataCell(Text(_formatMoney(contribution.netSalesEur))),
                              DataCell(Text(contribution.hint)),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
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
                : DataTable2(
                    minWidth: showFinancialColumns ? 1450 : 1050,
                    fixedTopRows: 1,
                    headingRowHeight: 68,
                    headingRowColor: WidgetStateProperty.resolveWith(
                      (_) => Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                    columnSpacing: 14,
                    horizontalMargin: 10,
                    headingTextStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      height: 1.2,
                    ),
                    sortColumnIndex: effectiveSortColumnIndex,
                    sortAscending: _tableSortAscending,
                    columns: [
                      DataColumn2(
                        label: const Text(
                          'Bezeichnung',
                          maxLines: 2,
                          softWrap: true,
                          overflow: TextOverflow.visible,
                        ),
                        fixedWidth: 160,
                        onSort: (columnIndex, ascending) =>
                            _onWareneinsatzSortChanged(columnIndex, ascending),
                      ),
                      DataColumn2(
                        label: const Text(
                          'Beschreibung',
                          maxLines: 2,
                          softWrap: true,
                          overflow: TextOverflow.visible,
                        ),
                        size: ColumnSize.L,
                        onSort: (columnIndex, ascending) =>
                            _onWareneinsatzSortChanged(columnIndex, ascending),
                      ),
                      if (showMengeOhneBomColumn)
                        DataColumn2(
                          numeric: true,
                          label: const Text(
                            'Menge ohne BOM',
                            maxLines: 2,
                            softWrap: true,
                            overflow: TextOverflow.visible,
                          ),
                          fixedWidth: 140,
                          onSort: (columnIndex, ascending) =>
                              _onWareneinsatzSortChanged(columnIndex, ascending),
                        ),
                      if (showBomMengeColumn)
                        DataColumn2(
                          numeric: true,
                          label: const Text(
                            'BOM-Menge',
                            maxLines: 2,
                            softWrap: true,
                            overflow: TextOverflow.visible,
                          ),
                          fixedWidth: 120,
                          onSort: (columnIndex, ascending) =>
                              _onWareneinsatzSortChanged(columnIndex, ascending),
                        ),
                      if (showGesamtmengeColumn)
                        DataColumn2(
                          numeric: true,
                          label: const Text(
                            'Gesamtmenge',
                            maxLines: 2,
                            softWrap: true,
                            overflow: TextOverflow.visible,
                          ),
                          fixedWidth: 130,
                          onSort: (columnIndex, ascending) =>
                              _onWareneinsatzSortChanged(columnIndex, ascending),
                        ),
                      if (showFinancialColumns) ...[
                        DataColumn2(
                          numeric: true,
                          label: const Text(
                            'EK netto\n(EUR)',
                            maxLines: 2,
                            softWrap: true,
                            overflow: TextOverflow.visible,
                          ),
                          fixedWidth: 130,
                          onSort: (columnIndex, ascending) =>
                              _onWareneinsatzSortChanged(columnIndex, ascending),
                        ),
                        DataColumn2(
                          numeric: true,
                          label: const Text(
                            'Σ EK netto\n(EUR)',
                            maxLines: 2,
                            softWrap: true,
                            overflow: TextOverflow.visible,
                          ),
                          fixedWidth: 145,
                          onSort: (columnIndex, ascending) =>
                              _onWareneinsatzSortChanged(columnIndex, ascending),
                        ),
                        DataColumn2(
                          numeric: true,
                          label: const Text(
                            'Σ Verkauf netto\n(EUR)',
                            maxLines: 2,
                            softWrap: true,
                            overflow: TextOverflow.visible,
                          ),
                          fixedWidth: 165,
                          onSort: (columnIndex, ascending) =>
                              _onWareneinsatzSortChanged(columnIndex, ascending),
                        ),
                        DataColumn2(
                          numeric: true,
                          label: Text(
                            _selectedMarginDisplay == _MarginDisplay.percent
                                ? 'Marge % auf EK'
                                : 'Marge EUR',
                            maxLines: 2,
                            softWrap: true,
                            overflow: TextOverflow.visible,
                          ),
                          fixedWidth: 130,
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

  List<OrderRow> _filterOrders(List<OrderRow> orders) {
    final ordersByTradeShowAndPutt = wareinsatzFilterOrdersByTradeShowAndPutt(
      orders: orders,
      selectedTradeShows: _selectedTradeShows,
      puttFilter: _selectedPuttFilter,
    );

    return ordersByTradeShowAndPutt.where((order) {

      final delivery = wareinsatzParseDeliveryDate(order.oDelivery);
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

  Widget _tradeShowFilterButton(List<String> options) {
    final hasSelection = _selectedTradeShows.isNotEmpty;
    final label = hasSelection
        ? 'Trade Show (${_selectedTradeShows.length})'
        : 'Trade Show (alle)';

    return OutlinedButton.icon(
      onPressed: options.isEmpty ? null : () => _showTradeShowFilterDialog(options),
      icon: const Icon(Icons.event_available_outlined),
      label: Text(label),
    );
  }

  Future<void> _showTradeShowFilterDialog(List<String> options) async {
    final workingSelection = Set<String>.from(_selectedTradeShows);

    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Trade Show filtern'),
              content: SizedBox(
                width: 420,
                child: options.isEmpty
                    ? const Text('Keine Trade Shows vorhanden.')
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final option in options)
                            CheckboxListTile(
                              value: workingSelection.contains(option),
                              title: Text(option),
                              controlAffinity: ListTileControlAffinity.leading,
                              onChanged: (checked) {
                                setDialogState(() {
                                  if (checked == true) {
                                    workingSelection.add(option);
                                  } else {
                                    workingSelection.remove(option);
                                  }
                                });
                              },
                            ),
                        ],
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(_selectedTradeShows),
                  child: const Text('Abbrechen'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(<String>{}),
                  child: const Text('Alle'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(workingSelection),
                  child: const Text('Uebernehmen'),
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted || result == null) {
      return;
    }

    setState(() {
      _selectedTradeShows = result;
    });
  }

  List<String> _availableMonthKeys(List<OrderRow> orders) {
    final keys = <String>{};
    for (final order in orders) {
      final delivery = wareinsatzParseDeliveryDate(order.oDelivery);
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
      final delivery = wareinsatzParseDeliveryDate(order.oDelivery);
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
      final delivery = wareinsatzParseDeliveryDate(order.oDelivery);
      if (delivery == null) {
        continue;
      }
      keys.add(delivery.year.toString());
    }
    final list = keys.toList(growable: false)..sort((a, b) => b.compareTo(a));
    return list;
  }

  List<_WareinsatzRow> _buildWareinsatzRows({
    required List<OrderRow> filteredOrders,
    required List<ItemOrderedRow> orderedItems,
    required List<ItemCatalogueRow> catalogueItems,
    required List<ItemBomRow> bomItems,
  }) {
    final filteredOrderIds = filteredOrders.map((order) => order.oId).toSet();
    final orderById = {
      for (final order in filteredOrders) order.oId: order,
    };
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
        );
      });
      aggregate.soldQuantity += quantity;
      if (ordered != null) {
        aggregate.soldNetValueEur += wareinsatzOrderedItemNetSalesForOrder(
          item: ordered,
          order: orderById[ordered.ioOrderId],
        );
      }
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

  List<_OrderNetContribution> _buildOrderNetContributions({
    required List<OrderRow> filteredOrders,
    required List<ItemOrderedRow> orderedItems,
    required Set<int> allowedItemIds,
  }) {
    final orderById = {
      for (final order in filteredOrders) order.oId: order,
    };
    final grouped = <String, _OrderNetContributionMutable>{};

    for (final item in orderedItems) {
      final order = orderById[item.ioOrderId];
      if (order == null) {
        continue;
      }
      if (!allowedItemIds.contains(item.ioItemId)) {
        continue;
      }

      final entry = grouped.putIfAbsent(item.ioOrderId, () {
        final hint = _orderDatePeriodHint(order);
        return _OrderNetContributionMutable(
          orderId: order.oId,
          deliveryDate: order.oDelivery.trim().isEmpty ? '-' : order.oDelivery.trim(),
          orderDate: order.oDate.trim().isEmpty ? '-' : order.oDate.trim(),
          currency: order.oCurrency.trim().isEmpty ? 'EUR' : order.oCurrency.trim().toUpperCase(),
          fxToEur: order.oFxToEur,
          priceBasisValue: 0,
          vatRate: order.oVatRate,
          hint: hint,
        );
      });

      entry.itemCount += 1;
      entry.priceBasisValue += wareinsatzOrderedItemNetSales(item);
      entry.netSalesEur += wareinsatzOrderedItemNetSalesForOrder(
        item: item,
        order: order,
      );
    }

    final rows = grouped.values
        .map((entry) => entry.toRow())
        .toList(growable: false)
      ..sort((a, b) => a.orderId.compareTo(b.orderId));

    return rows;
  }

  Future<void> _exportOrderNetContributionsCsv(
    List<_OrderNetContribution> rows,
  ) async {
    setState(() => _loading = true);
    try {
      final headers = [
        'Auftrag',
        'Versanddatum',
        'Auftragsdatum',
        'Waehrung',
        'USD→EUR',
        'Berechnungsbasis (${_diagnosticsPriceBasisCurrencyLabel(rows)})',
        'MwSt %',
        'Positionen',
        'Netto (EUR)',
        'Hinweis',
      ];

      final buffer = StringBuffer();
      buffer.writeln(headers.map(_csvEscape).join(';'));

      for (final row in rows) {
        final cells = <String>[
          _csvEscape(row.orderId),
          _csvEscape(row.deliveryDate),
          _csvEscape(row.orderDate),
          _csvEscape(row.currency),
          _csvEscape(_formatMoney(row.fxToEur)),
          _csvEscape(_formatMoney(row.priceBasisValue)),
          _csvEscape(_formatMoney(row.vatRate)),
          _csvEscape(row.itemCount.toString()),
          _csvEscape(_formatMoney(row.netSalesEur)),
          _csvEscape(row.hint),
        ];
        buffer.writeln(cells.join(';'));
      }

      final totalNet = rows.fold<double>(0, (sum, row) => sum + row.netSalesEur);
      buffer.writeln(
        [
          _csvEscape('SUMME'),
          _csvEscape('-'),
          _csvEscape('-'),
          _csvEscape('-'),
          _csvEscape('-'),
          _csvEscape('-'),
          _csvEscape('-'),
          _csvEscape('-'),
          _csvEscape(_formatMoney(totalNet)),
          _csvEscape('-'),
        ].join(';'),
      );

      final fileName =
          'wareneinsatz_diagnose_auftraege_${_periodLabelForExport()}_${_buildFileTimestamp(DateTime.now())}.csv';
      final targetPath = await _pickExportTargetPath(
        dialogTitle: 'Wareneinsatz-Diagnose als CSV exportieren',
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
        SnackBar(content: Text('Wareneinsatz-Diagnose-CSV exportiert nach: $targetPath')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Wareneinsatz-Diagnose-CSV-Export fehlgeschlagen: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
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
      final columnFlexes = wareinsatzPdfColumnFlexes(
        showMengeOhneBomColumn: showMengeOhneBomColumn,
        showBomMengeColumn: showBomMengeColumn,
        showGesamtmengeColumn: showGesamtmengeColumn,
        showFinancialColumns: showFinancialColumns,
      );
      final columnWidths = <int, pw.TableColumnWidth>{
        for (var i = 0; i < columnFlexes.length; i++) i: pw.FlexColumnWidth(columnFlexes[i]),
      };
      final totalMengeOhneBom = rows.fold<double>(
        0,
        (sum, row) => sum + _displayMengeOhneBom(row),
      );
      final totalBomMenge = rows.fold<double>(
        0,
        (sum, row) => sum + _displayBomMenge(row),
      );
      final totalGesamtmenge = rows.fold<double>(
        0,
        (sum, row) => sum + row.totalQuantity,
      );
      final totalEkNetto = rows.fold<double>(
        0,
        (sum, row) => sum + row.purchasePriceEur,
      );
      final totalEkWert = rows.fold<double>(
        0,
        (sum, row) => sum + row.totalValueEur,
      );
      final totalVerkaufNetto = rows.fold<double>(
        0,
        (sum, row) => sum + row.soldNetValueEur,
      );
      final totalMargeEur = rows.fold<double>(
        0,
        (sum, row) => sum + row.marginEur,
      );
      final totalMargePercent = totalEkWert > 0 ? (totalMargeEur / totalEkWert) * 100 : 0.0;

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
      final summaryRow = <String>[
        'SUMME',
        'Aufsummierung',
        if (showMengeOhneBomColumn) _formatQuantity(totalMengeOhneBom),
        if (showBomMengeColumn) _formatQuantity(totalBomMenge),
        if (showGesamtmengeColumn) _formatQuantity(totalGesamtmenge),
        if (showFinancialColumns) ...[
          _formatMoney(totalEkNetto),
          _formatMoney(totalEkWert),
          _formatMoney(totalVerkaufNetto),
          _selectedMarginDisplay == _MarginDisplay.percent
              ? _formatPercent(totalMargePercent)
              : _formatMoney(totalMargeEur),
        ],
      ];
      final quantityColumnStart = 2;
      final quantityColumnCount =
          (showMengeOhneBomColumn ? 1 : 0) +
          (showBomMengeColumn ? 1 : 0) +
          (showGesamtmengeColumn ? 1 : 0);
      final financialColumnStart = quantityColumnStart + quantityColumnCount;

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
              columnWidths: columnWidths,
            ),
            pw.Table(
              columnWidths: columnWidths,
              border: pw.TableBorder(
                left: const pw.BorderSide(color: PdfColors.grey500, width: 0.5),
                right: const pw.BorderSide(color: PdfColors.grey500, width: 0.5),
                bottom: const pw.BorderSide(color: PdfColors.grey500, width: 0.5),
                horizontalInside: const pw.BorderSide(color: PdfColors.grey500, width: 0.5),
                verticalInside: const pw.BorderSide(color: PdfColors.grey500, width: 0.5),
              ),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                  children: [
                    for (var index = 0; index < summaryRow.length; index++)
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(3),
                        child: pw.Align(
                          alignment: index >= quantityColumnStart &&
                                  (index < quantityColumnStart + quantityColumnCount ||
                                      index >= financialColumnStart)
                              ? pw.Alignment.centerRight
                              : pw.Alignment.centerLeft,
                          child: pw.Text(
                            summaryRow[index],
                            style: pw.TextStyle(
                              fontSize: 7,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
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
      final uri = await FilePicker.saveFile(
        dialogTitle: dialogTitle,
        fileName: fileName,
        bytes: Uint8List(0),
        initialDirectory: initialDirectory,
        type: FileType.custom,
        allowedExtensions: allowedExtensions,
      );
      return uri?.toFilePath();
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
    return rows
        .where(
          (row) => wareinsatzRowMatchesScope(
            scope: _selectedScope,
            soldQuantity: row.soldQuantity,
            bomQuantity: row.bomQuantity,
          ),
        )
        .toList(growable: false);
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

  String _diagnosticsPriceBasisCurrencyLabel(
    List<_OrderNetContribution> rows,
  ) {
    if (rows.isNotEmpty && rows.every((row) => row.currency == 'USD')) {
      return 'USD';
    }
    return 'EUR';
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

  String _orderDatePeriodHint(OrderRow order) {
    final orderDate = wareinsatzParseDeliveryDate(order.oDate);
    if (orderDate == null) {
      return 'Auftragsdatum fehlt/ungueltig';
    }

    final inPeriod = switch (_selectedGranularity) {
      _PeriodGranularity.total => true,
      _PeriodGranularity.month =>
        _selectedMonthKey != null &&
        '${orderDate.year}-${orderDate.month.toString().padLeft(2, '0')}' == _selectedMonthKey,
      _PeriodGranularity.quarter =>
        _selectedQuarterKey != null &&
        '${orderDate.year}-Q${((orderDate.month - 1) ~/ 3) + 1}' == _selectedQuarterKey,
      _PeriodGranularity.year =>
        _selectedYearKey != null && orderDate.year.toString() == _selectedYearKey,
    };

    return inPeriod ? '-' : 'Auftragsdatum ausserhalb Zeitraum';
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
  });

  final int itemId;
  final String idi;
  final String description;
  final double purchasePriceEur;

  double soldQuantity = 0;
  double bomQuantity = 0;
  double soldNetValueEur = 0;

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
      soldNetValueEur: soldNetValueEur,
    );
  }
}

class _OrderNetContributionMutable {
  _OrderNetContributionMutable({
    required this.orderId,
    required this.deliveryDate,
    required this.orderDate,
    required this.currency,
    required this.fxToEur,
    required this.priceBasisValue,
    required this.vatRate,
    required this.hint,
  });

  final String orderId;
  final String deliveryDate;
  final String orderDate;
  final String currency;
  final double fxToEur;
  double priceBasisValue;
  final double vatRate;
  final String hint;

  int itemCount = 0;
  double netSalesEur = 0;

  _OrderNetContribution toRow() {
    return _OrderNetContribution(
      orderId: orderId,
      deliveryDate: deliveryDate,
      orderDate: orderDate,
      currency: currency,
      fxToEur: fxToEur,
      priceBasisValue: priceBasisValue,
      vatRate: vatRate,
      itemCount: itemCount,
      netSalesEur: netSalesEur,
      hint: hint,
    );
  }
}

class _OrderNetContribution {
  const _OrderNetContribution({
    required this.orderId,
    required this.deliveryDate,
    required this.orderDate,
    required this.currency,
    required this.fxToEur,
    required this.priceBasisValue,
    required this.vatRate,
    required this.itemCount,
    required this.netSalesEur,
    required this.hint,
  });

  final String orderId;
  final String deliveryDate;
  final String orderDate;
  final String currency;
  final double fxToEur;
  final double priceBasisValue;
  final double vatRate;
  final int itemCount;
  final double netSalesEur;
  final String hint;
}

class _WareinsatzRow {
  const _WareinsatzRow({
    required this.itemId,
    required this.bezeichnung,
    required this.beschreibung,
    required this.soldQuantity,
    required this.bomQuantity,
    required this.purchasePriceEur,
    required this.soldNetValueEur,
  });

  final int itemId;
  final String bezeichnung;
  final String beschreibung;
  final double soldQuantity;
  final double bomQuantity;
  final double purchasePriceEur;
  final double soldNetValueEur;

  double get totalValueEur => totalQuantity * purchasePriceEur;
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
