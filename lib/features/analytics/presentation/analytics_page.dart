import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:data_table_2/data_table_2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'import_export_page.dart';
import '../../customer/data/customer_repository.dart';
import '../../item/data/item_repository.dart';
import '../../item/domain/item_models.dart';
import '../../order/data/order_repository.dart';
import '../../order/domain/order_models.dart';

enum _AnalyticsSubPage { chartNetValueOverTime, wareinsatz, importExport }

enum _PeriodGranularity { month, quarter, year, total }

enum WareinsatzScope { all, bomOnly, withoutBom }

enum _MarginDisplay { absolute, percent }

enum WareinsatzPuttFilter { all, onlyPutt, withoutPutt }

enum _NetValueSeriesFilter { revenue, cogs, grossProfit }

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
  return orders
      .where((order) {
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
      })
      .toList(growable: false);
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
    if (showFinancialColumns) ...[1.1, 1.2, 1.2, 1.1],
  ];
}

double wareinsatzOrderedItemNetSales(ItemOrderedRow? item) =>
    item?.ioTotalPrice ?? 0;

double wareinsatzSumOrderedItemNetSales(Iterable<ItemOrderedRow> items) => items
    .fold<double>(0, (sum, item) => sum + wareinsatzOrderedItemNetSales(item));

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

  final dotMatch = RegExp(
    r'^(\d{2})\.(\d{2})\.(\d{4})$',
  ).firstMatch(normalized);
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

bool wareinsatzMatchesDeliveryMonths(OrderRow order, Set<String> monthKeys) {
  if (monthKeys.isEmpty) {
    return true;
  }
  final delivery = wareinsatzParseDeliveryDate(order.oDelivery);
  if (delivery == null) {
    return false;
  }
  final key = '${delivery.year}-${delivery.month.toString().padLeft(2, '0')}';
  return monthKeys.contains(key);
}

List<String> wareinsatzExtractCategorySearchTerms(String query) {
  final terms = <String>[];
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) {
    return terms;
  }
  for (final token in normalized.split(RegExp(r'\s+'))) {
    if (token.startsWith('kat:') ||
        token.startsWith('kategorie:') ||
        token.startsWith('cat:')) {
      final index = token.indexOf(':');
      if (index < 0 || index >= token.length - 1) {
        continue;
      }
      final term = token.substring(index + 1).trim();
      if (term.isNotEmpty) {
        terms.add(term);
      }
    }
  }
  return terms;
}

String wareinsatzStripCategorySearchTerms(String query) {
  return query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where(
        (token) =>
            !token.startsWith('kat:') &&
            !token.startsWith('kategorie:') &&
            !token.startsWith('cat:'),
      )
      .join(' ')
      .trim();
}

String? wareinsatzBuildWildcardRegexPattern(String query) {
  if (!query.contains('*') && !query.contains('?')) {
    return null;
  }

  final pattern = StringBuffer();
  for (final rune in query.runes) {
    final char = String.fromCharCode(rune);
    if (char == '*') {
      pattern.write('.*');
    } else if (char == '?') {
      pattern.write('.');
    } else {
      pattern.write(RegExp.escape(char));
    }
  }

  return pattern.toString();
}

bool wareinsatzTextMatchesQuery({required String text, required String query}) {
  if (query.isEmpty) {
    return true;
  }
  final wildcardPattern = wareinsatzBuildWildcardRegexPattern(query);
  if (wildcardPattern == null) {
    return text.contains(query);
  }
  return RegExp('^$wildcardPattern\$', caseSensitive: false).hasMatch(text);
}

bool wareinsatzMatchesSearchQuery({
  required String query,
  required String bezeichnung,
  required String beschreibung,
  required String category,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) {
    return true;
  }

  final categoryTerms = wareinsatzExtractCategorySearchTerms(normalizedQuery);
  final normalizedCategory = category.trim().toLowerCase();
  for (final term in categoryTerms) {
    if (!wareinsatzTextMatchesQuery(text: normalizedCategory, query: term)) {
      return false;
    }
  }

  final freeQuery = wareinsatzStripCategorySearchTerms(normalizedQuery);
  if (freeQuery.isEmpty) {
    return true;
  }

  final searchTokens = freeQuery
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty);
  final normalizedBezeichnung = bezeichnung.toLowerCase();
  final normalizedBeschreibung = beschreibung.toLowerCase();
  for (final rawToken in searchTokens) {
    final isNegated = rawToken.startsWith('!') && rawToken.length > 1;
    final token = isNegated ? rawToken.substring(1) : rawToken;
    if (token.isEmpty) {
      continue;
    }
    final matchesToken =
        wareinsatzTextMatchesQuery(text: normalizedBezeichnung, query: token) ||
        wareinsatzTextMatchesQuery(
          text: normalizedBeschreibung,
          query: token,
        ) ||
        wareinsatzTextMatchesQuery(text: normalizedCategory, query: token);
    if (isNegated) {
      if (matchesToken) {
        return false;
      }
      continue;
    }
    if (!matchesToken) {
      return false;
    }
  }

  return true;
}

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  final OrderRepository _orderRepository = const OrderRepository();
  final CustomerRepository _customerRepository = const CustomerRepository();
  final ItemRepository _itemRepository = const ItemRepository();
  final TextEditingController _searchController = TextEditingController();
  static const List<Color> _countryPiePalette = [
    Color(0xFF0072B2),
    Color(0xFFE69F00),
    Color(0xFF009E73),
    Color(0xFFD55E00),
    Color(0xFFCC79A7),
    Color(0xFFF0E442),
    Color(0xFF56B4E9),
    Color(0xFF000000),
    Color(0xFF6C4A8B),
    Color(0xFF7A7A7A),
  ];

  _AnalyticsSubPage _selectedSubPage = _AnalyticsSubPage.chartNetValueOverTime;
  _PeriodGranularity _selectedChartGranularity = _PeriodGranularity.month;
  Set<String> _selectedChartQuarterKeys = const <String>{};
  Set<String> _selectedChartYearKeys = const <String>{};
  WareinsatzPuttFilter _selectedChartPuttFilter = WareinsatzPuttFilter.all;
  _PeriodGranularity _selectedGranularity = _PeriodGranularity.total;
  bool _isSideNavigationVisible = true;
  WareinsatzScope _selectedScope = WareinsatzScope.all;
  _MarginDisplay _selectedMarginDisplay = _MarginDisplay.absolute;
  WareinsatzPuttFilter _selectedPuttFilter = WareinsatzPuttFilter.all;
  _NetValueSeriesFilter? _selectedNetValueSeriesFilter;
  double _netValueTopRatio = 0.52;
  double _netValueMiddleRatio = 0.45;
  bool _isNetValueTopSplitterDragging = false;
  bool _isNetValueMiddleSplitterDragging = false;
  static const double _netValueSplitterHeight = 28.0;
  static const double _netValueTopMinHeight = 180.0;
  static const double _netValueMiddleMinHeight = 140.0;
  static const double _netValueBottomMinHeight = 140.0;
  int _tableSortColumnIndex = 6;
  bool _tableSortAscending = false;

  bool _loading = true;
  String? _error;
  String _searchQuery = '';

  List<OrderRow> _orders = const [];
  List<ItemOrderedRow> _orderedItems = const [];
  List<ItemCatalogueRow> _catalogueItems = const [];
  List<ItemBomRow> _bomItems = const [];
  Map<String, String> _countryNamesByCode = const {};

  Set<String> _selectedMonthKeys = const <String>{};
  String? _selectedQuarterKey;
  String? _selectedYearKey;
  Set<String> _selectedTradeShows = const <String>{};
  bool _wasVisibleInBuild = false;

  void _handleOrderDataVersionChanged() {
    if (!mounted || _loading) {
      return;
    }
    _loadData();
  }

  @override
  void initState() {
    super.initState();
    OrderRepository.orderDataVersion.addListener(
      _handleOrderDataVersionChanged,
    );
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
    OrderRepository.orderDataVersion.removeListener(
      _handleOrderDataVersionChanged,
    );
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
      final itemFutures = orders.map(
        (order) => _orderRepository.getItemsForOrder(order.oId),
      );
      final itemLists = await Future.wait(itemFutures);
      final orderedItems = itemLists
          .expand((rows) => rows)
          .toList(growable: false);

      final catalogueItems = await _itemRepository.getCatalogueItems();
      final bomItems = await _itemRepository.getBomItems();
      final countries = await _customerRepository.getAllCountries();
      final countryNamesByCode = <String, String>{
        for (final country in countries)
          country.coTld.trim().toUpperCase(): country.coName.trim(),
      };

      if (!mounted) {
        return;
      }

      setState(() {
        _orders = orders;
        _orderedItems = orderedItems;
        _catalogueItems = catalogueItems;
        _bomItems = bomItems;
        _countryNamesByCode = countryNamesByCode;
        _ensurePeriodDefaults();
        _ensureChartPeriodDefaults();
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

    _selectedMonthKeys = _selectedMonthKeys.where(monthKeys.contains).toSet();
    if (_selectedMonthKeys.isEmpty && monthKeys.isNotEmpty) {
      _selectedMonthKeys = {monthKeys.first};
    }
    if (_selectedQuarterKey == null ||
        !quarterKeys.contains(_selectedQuarterKey)) {
      _selectedQuarterKey = quarterKeys.isEmpty ? null : quarterKeys.first;
    }
    if (_selectedYearKey == null || !yearKeys.contains(_selectedYearKey)) {
      _selectedYearKey = yearKeys.isEmpty ? null : yearKeys.first;
    }

    if (_selectedGranularity == _PeriodGranularity.month && monthKeys.isEmpty) {
      _selectedGranularity = _PeriodGranularity.total;
    }
    if (_selectedGranularity == _PeriodGranularity.quarter &&
        _selectedQuarterKey == null) {
      _selectedGranularity = _PeriodGranularity.total;
    }
    if (_selectedGranularity == _PeriodGranularity.year &&
        _selectedYearKey == null) {
      _selectedGranularity = _PeriodGranularity.total;
    }

    final availableTradeShows = wareinsatzAvailableTradeShowOptions(
      _orders,
    ).toSet();
    _selectedTradeShows = _selectedTradeShows
        .where(availableTradeShows.contains)
        .toSet();
  }

  void _ensureChartPeriodDefaults() {
    final yearKeys = _availableYearKeys(_orders);
    _selectedChartYearKeys = _selectedChartYearKeys
        .where(yearKeys.contains)
        .toSet();
    final quarterKeysForYear = _availableQuarterKeysForChartYear(
      _orders,
      _selectedChartYearKeys,
    );
    _selectedChartQuarterKeys = _selectedChartQuarterKeys
        .where(quarterKeysForYear.contains)
        .toSet();
  }

  @override
  Widget build(BuildContext context) {
    final tickerMode = TickerMode.valuesOf(context);
    final isVisibleInShell = tickerMode.enabled;
    if (isVisibleInShell && !_wasVisibleInBuild && !_loading) {
      _loadData();
    }
    _wasVisibleInBuild = isVisibleInShell;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Auswertung'),
        actions: [
          IconButton(
            tooltip: _isSideNavigationVisible
                ? 'Menue ausblenden'
                : 'Menue einblenden',
            onPressed: () {
              setState(() {
                _isSideNavigationVisible = !_isSideNavigationVisible;
              });
            },
            icon: Icon(_isSideNavigationVisible ? Icons.menu_open : Icons.menu),
          ),
          IconButton(
            tooltip: 'Neu laden',
            onPressed: _loading ? null : _loadData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Row(
        children: [
          if (_isSideNavigationVisible) ...[
            _buildSideNavigation(context),
            const VerticalDivider(width: 1),
          ],
          Expanded(
            child: switch (_selectedSubPage) {
              _AnalyticsSubPage.chartNetValueOverTime =>
                _buildNetValueChartView(context),
              _AnalyticsSubPage.wareinsatz => _buildWareneinsatzView(context),
              _AnalyticsSubPage.importExport => const ImportExportPage(),
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSideNavigation(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 300,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(
              'Auswertungen',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          Card(
            color: colorScheme.surfaceContainerLow,
            child: ExpansionTile(
              initiallyExpanded: true,
              shape: const Border(),
              collapsedShape: const Border(),
              leading: const Icon(Icons.bar_chart_outlined),
              title: const Text('Grafik'),
              childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              children: [
                _buildNavigationEntry(
                  icon: Icons.bar_chart,
                  label: 'Rohertrag / Zeit',
                  subPage: _AnalyticsSubPage.chartNetValueOverTime,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _buildNavigationEntry(
            icon: Icons.inventory_2,
            label: 'Wareneinsatz',
            subPage: _AnalyticsSubPage.wareinsatz,
          ),
          const SizedBox(height: 8),
          _buildNavigationEntry(
            icon: Icons.import_export,
            label: 'Import / Export',
            subPage: _AnalyticsSubPage.importExport,
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationEntry({
    required IconData icon,
    required String label,
    required _AnalyticsSubPage subPage,
  }) {
    final selected = _selectedSubPage == subPage;
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      leading: Icon(icon),
      title: Text(label),
      selected: selected,
      onTap: () {
        if (selected) {
          return;
        }
        setState(() {
          _selectedSubPage = subPage;
        });
      },
    );
  }

  Widget _buildNetValueSplitter({
    required bool isDragging,
    required VoidCallback onDragStart,
    required VoidCallback onDragEnd,
    required ValueChanged<DragUpdateDetails> onDragUpdate,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: (_) => onDragStart(),
        onVerticalDragEnd: (_) => onDragEnd(),
        onVerticalDragCancel: onDragEnd,
        onVerticalDragUpdate: onDragUpdate,
        child: Container(
          height: _netValueSplitterHeight,
          color: isDragging
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
              : Theme.of(context).dividerColor.withValues(alpha: 0.15),
          child: const Center(child: Icon(Icons.drag_handle, size: 18)),
        ),
      ),
    );
  }

  Widget _buildNetValueChartView(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }

    final chartFilterContext = _buildChartFilterContext(
      orders: _orders,
      orderedItems: _orderedItems,
      catalogueItems: _catalogueItems,
      puttFilter: _selectedChartPuttFilter,
      granularity: _selectedChartGranularity,
      selectedQuarterKeys: _selectedChartQuarterKeys,
      selectedYearKeys: _selectedChartYearKeys,
    );

    final buckets = _buildNetValueBuckets(
      context: chartFilterContext,
      granularity: _selectedChartGranularity,
    );
    final yearMonthTableData = _buildNetValueYearMonthTableData(
      context: chartFilterContext,
      granularity: _selectedChartGranularity,
      seriesFilter: _selectedNetValueSeriesFilter,
    );
    final countryShareBuckets = _buildCountryShareBuckets(
      context: chartFilterContext,
    );
    final totalNetRevenue = buckets.fold<double>(
      0,
      (sum, bucket) => sum + bucket.netRevenueEur,
    );
    final totalNetCogs = buckets.fold<double>(
      0,
      (sum, bucket) => sum + bucket.netCogsEur,
    );
    final totalGrossProfit = buckets.fold<double>(
      0,
      (sum, bucket) => sum + bucket.grossProfitEur,
    );
    final netValueFxHint = _buildNetValueFxHint(context: chartFilterContext);

    return LayoutBuilder(
      builder: (context, viewportConstraints) {
        final minChartSectionHeight =
            _netValueTopMinHeight +
            _netValueMiddleMinHeight +
            _netValueBottomMinHeight +
            (_netValueSplitterHeight * 2);
        final chartSectionHeight = math.max(
          minChartSectionHeight,
          viewportConstraints.maxHeight * 0.72,
        );

        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rohertrag / Zeit',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Vergleich je Zeitraum: Umsatz netto, EK-netto Wareneinsatz und Rohertrag (Umsatz netto - EK-netto).',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  netValueFxHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      SegmentedButton<_PeriodGranularity>(
                        segments: const [
                          ButtonSegment(
                            value: _PeriodGranularity.month,
                            label: Text('Monat'),
                          ),
                          ButtonSegment(
                            value: _PeriodGranularity.quarter,
                            label: Text('Quartal'),
                          ),
                          ButtonSegment(
                            value: _PeriodGranularity.year,
                            label: Text('Jahr'),
                          ),
                          ButtonSegment(
                            value: _PeriodGranularity.total,
                            label: Text('Gesamt'),
                          ),
                        ],
                        selected: {_selectedChartGranularity},
                        onSelectionChanged: (selection) {
                          setState(() {
                            _selectedChartGranularity = selection.first;
                            _ensureChartPeriodDefaults();
                          });
                        },
                      ),
                      const SizedBox(width: 12),
                      SegmentedButton<WareinsatzPuttFilter>(
                        segments: const [
                          ButtonSegment(
                            value: WareinsatzPuttFilter.all,
                            label: Text('incl. PUTT'),
                          ),
                          ButtonSegment(
                            value: WareinsatzPuttFilter.withoutPutt,
                            label: Text('excl. PUTT'),
                          ),
                          ButtonSegment(
                            value: WareinsatzPuttFilter.onlyPutt,
                            label: Text('nur PUTT'),
                          ),
                        ],
                        selected: {_selectedChartPuttFilter},
                        onSelectionChanged: (selection) {
                          setState(() {
                            _selectedChartPuttFilter = selection.first;
                          });
                        },
                      ),
                      if (_selectedChartGranularity !=
                          _PeriodGranularity.total) ...[
                        const SizedBox(width: 12),
                        _chartYearFilterButton(_availableYearKeys(_orders)),
                      ],
                      if (_selectedChartGranularity ==
                          _PeriodGranularity.quarter) ...[
                        const SizedBox(width: 12),
                        _chartQuarterFilterButton(
                          _availableQuarterKeysForChartYear(
                            _orders,
                            _selectedChartYearKeys,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    _summaryChip(
                      'Gefilterte Auftraege',
                      '${chartFilterContext.orderById.length}',
                    ),
                    _summaryChip(
                      'Gefilterte Positionen',
                      '${chartFilterContext.filteredItems.length}',
                    ),
                    _summaryChip('Zeitraeume', '${buckets.length}'),
                    if (_selectedNetValueSeriesFilter == null ||
                        _selectedNetValueSeriesFilter ==
                            _NetValueSeriesFilter.revenue)
                      _summaryChip(
                        'Σ Umsatz netto',
                        _formatMoneyEur(totalNetRevenue),
                      ),
                    if (_selectedNetValueSeriesFilter == null ||
                        _selectedNetValueSeriesFilter ==
                            _NetValueSeriesFilter.cogs)
                      _summaryChip(
                        'Σ EK-netto',
                        _formatMoneyEur(totalNetCogs),
                      ),
                    if (_selectedNetValueSeriesFilter == null ||
                        _selectedNetValueSeriesFilter ==
                            _NetValueSeriesFilter.grossProfit)
                      _summaryChip(
                        'Σ Rohertrag',
                        _formatMoneyEur(totalGrossProfit),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: chartSectionHeight,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final splitterTotal = _netValueSplitterHeight * 2;
                      final availableHeight = (constraints.maxHeight - splitterTotal)
                          .clamp(0.0, double.infinity);

                      final topAndLowerMin =
                          _netValueTopMinHeight + _netValueMiddleMinHeight + _netValueBottomMinHeight;

                      late final double topHeight;
                      if (availableHeight <= topAndLowerMin) {
                        topHeight = availableHeight * _netValueTopRatio;
                      } else {
                        topHeight = (availableHeight * _netValueTopRatio).clamp(
                          _netValueTopMinHeight,
                          availableHeight - (_netValueMiddleMinHeight + _netValueBottomMinHeight),
                        );
                      }

                      final lowerAvailable = (availableHeight - topHeight)
                          .clamp(0.0, double.infinity);
                      final lowerMinCombined =
                          _netValueMiddleMinHeight + _netValueBottomMinHeight;

                      late final double middleHeight;
                      if (lowerAvailable <= lowerMinCombined) {
                        middleHeight = lowerAvailable * _netValueMiddleRatio;
                      } else {
                        middleHeight = (lowerAvailable * _netValueMiddleRatio).clamp(
                          _netValueMiddleMinHeight,
                          lowerAvailable - _netValueBottomMinHeight,
                        );
                      }

                      final bottomHeight =
                          (lowerAvailable - middleHeight).clamp(0.0, double.infinity);

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            height: topHeight,
                            child: _buildNetValueBarChart(
                              buckets,
                              granularity: _selectedChartGranularity,
                            ),
                          ),
                          _buildNetValueSplitter(
                            isDragging: _isNetValueTopSplitterDragging,
                            onDragStart: () {
                              setState(() => _isNetValueTopSplitterDragging = true);
                            },
                            onDragEnd: () {
                              setState(() => _isNetValueTopSplitterDragging = false);
                            },
                            onDragUpdate: (details) {
                              if (availableHeight <= 0) {
                                return;
                              }
                              final baseTop = _netValueTopRatio * availableHeight;
                              final targetTop = baseTop + details.delta.dy;
                              final minCombined =
                                  _netValueTopMinHeight + _netValueMiddleMinHeight + _netValueBottomMinHeight;

                              late final double newTopHeight;
                              if (availableHeight <= minCombined) {
                                newTopHeight = targetTop.clamp(0.0, availableHeight);
                              } else {
                                newTopHeight = targetTop.clamp(
                                  _netValueTopMinHeight,
                                  availableHeight - (_netValueMiddleMinHeight + _netValueBottomMinHeight),
                                );
                              }

                              setState(() {
                                _netValueTopRatio = availableHeight <= 0
                                    ? _netValueTopRatio
                                    : (newTopHeight / availableHeight).clamp(0.05, 0.9);
                              });
                            },
                          ),
                          SizedBox(
                            height: middleHeight,
                            child: _buildNetValueYearMonthTable(
                              yearMonthTableData,
                              granularity: _selectedChartGranularity,
                              seriesFilter: _selectedNetValueSeriesFilter,
                            ),
                          ),
                          _buildNetValueSplitter(
                            isDragging: _isNetValueMiddleSplitterDragging,
                            onDragStart: () {
                              setState(() => _isNetValueMiddleSplitterDragging = true);
                            },
                            onDragEnd: () {
                              setState(() => _isNetValueMiddleSplitterDragging = false);
                            },
                            onDragUpdate: (details) {
                              if (lowerAvailable <= 0) {
                                return;
                              }
                              final baseMiddle = _netValueMiddleRatio * lowerAvailable;
                              final targetMiddle = baseMiddle + details.delta.dy;
                              final minCombined =
                                  _netValueMiddleMinHeight + _netValueBottomMinHeight;

                              late final double newMiddleHeight;
                              if (lowerAvailable <= minCombined) {
                                newMiddleHeight = targetMiddle.clamp(0.0, lowerAvailable);
                              } else {
                                newMiddleHeight = targetMiddle.clamp(
                                  _netValueMiddleMinHeight,
                                  lowerAvailable - _netValueBottomMinHeight,
                                );
                              }

                              setState(() {
                                _netValueMiddleRatio = lowerAvailable <= 0
                                    ? _netValueMiddleRatio
                                    : (newMiddleHeight / lowerAvailable).clamp(0.05, 0.95);
                              });
                            },
                          ),
                          SizedBox(
                            height: bottomHeight,
                            child: _buildCountrySharePieSection(
                              countryShareBuckets,
                              granularity: _selectedChartGranularity,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<_NetValueBucket> _buildNetValueBuckets({
    required _ChartFilterContext context,
    required _PeriodGranularity granularity,
  }) {
    final orderById = context.orderById;
    final revenueByPeriod = <String, double>{};
    final cogsByPeriod = <String, double>{};
    final labelByPeriod = <String, String>{};

    for (final item in context.filteredItems) {
      final order = orderById[item.ioOrderId];
      if (order == null) {
        continue;
      }
      final delivery = wareinsatzParseDeliveryDate(order.oDelivery);
      if (delivery == null) {
        continue;
      }

      late final String periodKey;
      late final String periodLabel;
      switch (granularity) {
        case _PeriodGranularity.month:
          periodKey =
              '${delivery.year}-${delivery.month.toString().padLeft(2, '0')}';
          periodLabel =
              '${delivery.month.toString().padLeft(2, '0')}/${delivery.year}';
        case _PeriodGranularity.quarter:
          final quarter = ((delivery.month - 1) ~/ 3) + 1;
          periodKey = '${delivery.year}-Q$quarter';
          periodLabel = 'Q$quarter ${delivery.year}';
        case _PeriodGranularity.year:
          periodKey = delivery.year.toString();
          periodLabel = periodKey;
        case _PeriodGranularity.total:
          // In chart view, "Gesamt" should still show the yearly distribution.
          periodKey = delivery.year.toString();
          periodLabel = periodKey;
      }

      final netRevenueEur = wareinsatzOrderedItemNetSalesForOrder(
        item: item,
        order: order,
      );
      final purchasePriceNet =
          context.catalogueById[item.ioItemId]?.icPurchasePriceNet ?? 0;
      final netCogsEur = item.ioQuantity * purchasePriceNet;

      revenueByPeriod.update(
        periodKey,
        (value) => value + netRevenueEur,
        ifAbsent: () => netRevenueEur,
      );
      cogsByPeriod.update(
        periodKey,
        (value) => value + netCogsEur,
        ifAbsent: () => netCogsEur,
      );
      labelByPeriod.putIfAbsent(periodKey, () => periodLabel);
    }

    if (revenueByPeriod.isEmpty) {
      return const [];
    }

    final keys = revenueByPeriod.keys.toList(growable: false)
      ..sort((a, b) => a.compareTo(b));

    return keys
        .map(
          (key) => _NetValueBucket(
            periodLabel: labelByPeriod[key] ?? key,
            netRevenueEur: revenueByPeriod[key] ?? 0,
            netCogsEur: cogsByPeriod[key] ?? 0,
          ),
        )
        .toList(growable: false);
  }

  String _buildNetValueFxHint({required _ChartFilterContext context}) {
    final filteredOrders = context.orderById.values;
    final usdOrders = filteredOrders
        .where((order) => order.oCurrency.trim().toUpperCase() == 'USD')
        .toList(growable: false);
    final usdOrderCount = usdOrders.length;
    final usdOrdersWithoutFxCount = usdOrders
        .where((order) => order.oFxToEur <= 0)
        .length;

    if (usdOrderCount == 0) {
      return 'Hinweis: Umsatz netto wird in EUR ausgewiesen.';
    }

    if (usdOrdersWithoutFxCount == 0) {
      return 'Hinweis: $usdOrderCount USD-Auftraege wurden mit dem jeweiligen USD→EUR-Kurs in den Umsatz netto eingerechnet.';
    }

    return 'Hinweis: $usdOrderCount USD-Auftraege werden per USD→EUR-Kurs umgerechnet; $usdOrdersWithoutFxCount ohne gueltigen Kurs sind im Umsatz netto nicht beruecksichtigt.';
  }

  Widget _buildNetValueBarChart(
    List<_NetValueBucket> buckets, {
    required _PeriodGranularity granularity,
  }) {
    if (buckets.isEmpty) {
      return const Card(
        child: Center(
          child: Text('Keine Daten mit gueltigem Versanddatum vorhanden.'),
        ),
      );
    }

    final showRevenue =
        _selectedNetValueSeriesFilter == null ||
        _selectedNetValueSeriesFilter == _NetValueSeriesFilter.revenue;
    final showCogs =
        _selectedNetValueSeriesFilter == null ||
        _selectedNetValueSeriesFilter == _NetValueSeriesFilter.cogs;
    final showGrossProfit =
        _selectedNetValueSeriesFilter == null ||
        _selectedNetValueSeriesFilter == _NetValueSeriesFilter.grossProfit;
    final visibleSeriesCount =
        (showRevenue ? 1 : 0) + (showCogs ? 1 : 0) + (showGrossProfit ? 1 : 0);
    final isSingleSeriesView = visibleSeriesCount == 1;

    final visibleValues = <double>[];
    for (final bucket in buckets) {
      if (showRevenue) {
        visibleValues.add(bucket.netRevenueEur);
      }
      if (showCogs) {
        visibleValues.add(bucket.netCogsEur);
      }
      if (showGrossProfit) {
        visibleValues.add(bucket.grossProfitEur);
      }
    }

    final maxPositiveValue = visibleValues.fold<double>(
      0,
      (currentMax, value) => math.max(currentMax, value),
    );
    final minNegativeValue = visibleValues.fold<double>(
      0,
      (currentMin, value) => math.min(currentMin, value),
    );
    final safePositiveMax = maxPositiveValue <= 0 ? 1.0 : maxPositiveValue;
    final safeNegativeAbs = minNegativeValue >= 0 ? 0.0 : minNegativeValue.abs();
    final hasNegativeValues = safeNegativeAbs > 0;
    final totalRange = safePositiveMax + safeNegativeAbs;
    final positiveAreaFactor = hasNegativeValues
        ? (safePositiveMax / totalRange)
        : 1.0;
    final minColumnWidth = isSingleSeriesView ? 130.0 : 200.0;
    const revenueColor = Color(0xFF42A5F5);
    const cogsColor = Color(0xFFFFB74D);
    const grossProfitPositiveColor = Color(0xFF66BB6A);
    const grossProfitNegativeColor = Color(0xFFEF5350);
    const allSeriesColor = Color(0xFF78909C);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isCompactViewport = constraints.maxWidth < 1100;
                  final isCompactHeight = constraints.maxHeight < 230;
                  final isUltraCompactHeight = constraints.maxHeight < 190;
                  final showLegend = !isUltraCompactHeight;
                  const estimatedLegendBlockHeight = 52.0;
                  final availableChartHeight = math.max(
                    0.0,
                    constraints.maxHeight -
                        (showLegend ? estimatedLegendBlockHeight : 0.0),
                  );
                  final labelWidth = isCompactViewport ? 48.0 : 56.0;
                  final barWidth = isCompactViewport ? 30.0 : 34.0;
                  final innerBarSpacing = isCompactViewport ? 6.0 : 8.0;
                  final monthSeparatorColor = Color.alphaBlend(
                    Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
                    Theme.of(context).dividerColor,
                  );
                  final showMonthSeparators =
                      granularity == _PeriodGranularity.month;
                  const monthSeparatorWidth = 10.0;
                  final separatorsTotalWidth = showMonthSeparators
                      ? math.max(0, buckets.length - 1) * monthSeparatorWidth
                      : 0.0;
                  final contentWidth =
                      buckets.length * minColumnWidth + separatorsTotalWidth;
                  final chartWidth = isSingleSeriesView
                      ? contentWidth
                      : math.max(constraints.maxWidth, contentWidth);
                    final reservedChromeHeight = isCompactHeight ? 12.0 : 56.0;
                  final sharedMaxBarHeight =
                      (availableChartHeight - reservedChromeHeight)
                          .clamp(0.0, 220.0);
                  const valueLabelHeight = 16.0;
                  const valueLabelSpacing = 4.0;

                  Widget bar({
                    required double value,
                    required Color color,
                    required double maxHeight,
                  }) {
                    final drawableHeight = math.max(0.0, maxHeight);
                    final positiveAreaHeight = drawableHeight * positiveAreaFactor;
                    final negativeAreaHeight = drawableHeight - positiveAreaHeight;
                    final positiveBarHeight = value <= 0
                        ? 0.0
                        : ((value / safePositiveMax) * positiveAreaHeight).clamp(
                            0.0,
                            positiveAreaHeight,
                          );
                    final negativeBarHeight = value >= 0 || !hasNegativeValues
                        ? 0.0
                        : ((value.abs() / safeNegativeAbs) * negativeAreaHeight)
                              .clamp(0.0, negativeAreaHeight);

                    final barRadius = value >= 0
                        ? const BorderRadius.vertical(top: Radius.circular(6))
                        : const BorderRadius.vertical(bottom: Radius.circular(6));

                    return Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (!isCompactHeight) ...[
                          SizedBox(
                            width: labelWidth,
                            height: valueLabelHeight,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(_formatMoneyEur(value)),
                            ),
                          ),
                          const SizedBox(height: valueLabelSpacing),
                        ],
                        SizedBox(
                          width: barWidth,
                          height: maxHeight,
                          child: Column(
                            children: [
                              SizedBox(
                                height: positiveAreaHeight,
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Container(
                                    width: barWidth,
                                    height: positiveBarHeight,
                                    decoration: BoxDecoration(
                                      color: color,
                                      borderRadius: barRadius,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                height: negativeAreaHeight,
                                child: Align(
                                  alignment: Alignment.topCenter,
                                  child: Container(
                                    width: barWidth,
                                    height: negativeBarHeight,
                                    decoration: BoxDecoration(
                                      color: color,
                                      borderRadius: barRadius,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showLegend) ...[
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _ChartLegendChip(
                              label: 'Alle',
                              color: allSeriesColor,
                              selected: _selectedNetValueSeriesFilter == null,
                              onTap: () {
                                setState(() {
                                  _selectedNetValueSeriesFilter = null;
                                });
                              },
                            ),
                            const SizedBox(width: 12),
                            _ChartLegendChip(
                              label: 'Umsatz netto',
                              color: revenueColor,
                              selected:
                                  _selectedNetValueSeriesFilter ==
                                  _NetValueSeriesFilter.revenue,
                              onTap: () {
                                setState(() {
                                  _selectedNetValueSeriesFilter =
                                      _selectedNetValueSeriesFilter ==
                                          _NetValueSeriesFilter.revenue
                                      ? null
                                      : _NetValueSeriesFilter.revenue;
                                });
                              },
                            ),
                            const SizedBox(width: 12),
                            _ChartLegendChip(
                              label: 'EK-netto',
                              color: cogsColor,
                              selected:
                                  _selectedNetValueSeriesFilter ==
                                  _NetValueSeriesFilter.cogs,
                              onTap: () {
                                setState(() {
                                  _selectedNetValueSeriesFilter =
                                      _selectedNetValueSeriesFilter ==
                                          _NetValueSeriesFilter.cogs
                                      ? null
                                      : _NetValueSeriesFilter.cogs;
                                });
                              },
                            ),
                            const SizedBox(width: 12),
                            _ChartLegendChip(
                              label: 'Rohertrag',
                              color: grossProfitPositiveColor,
                              selected:
                                  _selectedNetValueSeriesFilter ==
                                  _NetValueSeriesFilter.grossProfit,
                              onTap: () {
                                setState(() {
                                  _selectedNetValueSeriesFilter =
                                      _selectedNetValueSeriesFilter ==
                                          _NetValueSeriesFilter.grossProfit
                                      ? null
                                      : _NetValueSeriesFilter.grossProfit;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      ],
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: chartWidth,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (var index = 0; index < buckets.length; index++) ...[
                                  SizedBox(
                                    width: minColumnWidth,
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: isSingleSeriesView ? 2 : 6,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Expanded(
                                            child: Align(
                                              alignment: Alignment.bottomLeft,
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.start,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.end,
                                                children: [
                                                  if (showRevenue)
                                                    bar(
                                                      value: buckets[index]
                                                          .netRevenueEur,
                                                      color: revenueColor,
                                                      maxHeight: sharedMaxBarHeight,
                                                    ),
                                                  if (showRevenue &&
                                                      (showCogs ||
                                                          showGrossProfit))
                                                    SizedBox(
                                                      width: innerBarSpacing,
                                                    ),
                                                  if (showCogs)
                                                    bar(
                                                      value: buckets[index]
                                                          .netCogsEur,
                                                      color: cogsColor,
                                                      maxHeight: sharedMaxBarHeight,
                                                    ),
                                                  if (showCogs && showGrossProfit)
                                                    SizedBox(
                                                      width: innerBarSpacing,
                                                    ),
                                                  if (showGrossProfit)
                                                    bar(
                                                      value: buckets[index]
                                                          .grossProfitEur,
                                                      color: buckets[index]
                                                                  .grossProfitEur >=
                                                              0
                                                          ? grossProfitPositiveColor
                                                          : grossProfitNegativeColor,
                                                      maxHeight: sharedMaxBarHeight,
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          if (!isCompactHeight) ...[
                                            const SizedBox(height: 12),
                                            Text(
                                              buckets[index].periodLabel,
                                              textAlign: TextAlign.center,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelMedium,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (showMonthSeparators &&
                                      index < buckets.length - 1)
                                    SizedBox(
                                      width: monthSeparatorWidth,
                                      child: Center(
                                        child: Container(
                                          width: 1,
                                          height: 42,
                                          color: monthSeparatorColor,
                                        ),
                                      ),
                                    ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_CountryShareBucket> _buildCountryShareBuckets({
    required _ChartFilterContext context,
  }) {
    final orderById = context.orderById;
    final valueByCountry = <String, double>{};

    for (final item in context.filteredItems) {
      final order = orderById[item.ioOrderId];
      if (order == null) {
        continue;
      }
      final delivery = wareinsatzParseDeliveryDate(order.oDelivery);
      if (delivery == null) {
        continue;
      }

        final countryRaw = order.oDeliveryCountryId.trim().toUpperCase();
        final countryKey = _normalizeCountryBucketKey(countryRaw);
      final valueEur = wareinsatzOrderedItemNetSalesForOrder(
        item: item,
        order: order,
      );
      valueByCountry.update(
        countryKey,
        (value) => value + valueEur,
        ifAbsent: () => valueEur,
      );
    }

    final total = valueByCountry.values.fold<double>(
      0,
      (sum, value) => sum + value,
    );
    if (total <= 0) {
      return const [];
    }

    final entries = valueByCountry.entries.toList(growable: false)
      ..sort((a, b) => b.value.compareTo(a.value));

    return entries
        .map(
          (entry) => _CountryShareBucket(
            countryLabel: entry.key,
            valueEur: entry.value,
            share: entry.value / total,
          ),
        )
        .toList(growable: false);
  }

  String _normalizeCountryBucketKey(String rawCountry) {
    if (rawCountry.isEmpty || rawCountry == '-') {
      return 'UNBEKANNT';
    }

    // Schreibweisen fuer die USA werden bewusst in einem Bucket zusammengefasst.
    if (rawCountry == 'US' ||
        rawCountry == 'USA' ||
        rawCountry == 'UNITED STATES' ||
        rawCountry == 'UNITED STATES OF AMERICA') {
      return 'USA';
    }

    return rawCountry;
  }

  String _countryLegendLabel(String countryCode) {
    final normalized = countryCode.trim().toUpperCase();
    if (normalized.isEmpty || normalized == 'UNBEKANNT') {
      return 'UNBEKANNT - Unbekannt';
    }

    if (normalized == 'FL' || normalized == 'LI' || normalized == 'LIECHTENSTEIN') {
      final displayCode = normalized == 'LIECHTENSTEIN' ? 'LI' : normalized;
      return '$displayCode - Liechtenstein';
    }

    String? name = _countryNamesByCode[normalized];
    if (name != null && name.trim().isEmpty) {
      name = null;
    }

    if (name == null && normalized == 'USA') {
      name = _countryNamesByCode['US'];
      if (name != null && name.trim().isEmpty) {
        name = null;
      }
    }

    if (name == null && normalized == 'FL') {
      name = _countryNamesByCode['LI'];
      if (name != null && name.trim().isEmpty) {
        name = null;
      }
    }

    if (name == null && normalized == 'FL') {
      name = 'Liechtenstein';
    }

    final resolvedName =
        (name == null || name.trim().isEmpty) ? normalized : name.trim();
    return '$normalized - $resolvedName';
  }

  Widget _buildCountrySharePieSection(
    List<_CountryShareBucket> buckets, {
    required _PeriodGranularity granularity,
  }) {
    if (buckets.isEmpty) {
      return const Card(
        child: Center(
          child: Text('Keine Daten fuer die Laenderverteilung vorhanden.'),
        ),
      );
    }

    final totalValue = buckets.fold<double>(
      0,
      (sum, bucket) => sum + bucket.valueEur,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 1000;
                  final pieWidget = Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: 220,
                      height: 220,
                      child: CustomPaint(
                        painter: _CountrySharePiePainter(
                          buckets: buckets,
                          colors: _countryPiePalette,
                        ),
                      ),
                    ),
                  );

                  final legendWidget = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Verteilung Netto-Umsatz nach Land (${_chartGranularityLabel(granularity)})',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Σ ${_formatMoneyEur(totalValue)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView.builder(
                          itemCount: buckets.length,
                          itemBuilder: (context, index) {
                            final bucket = buckets[index];
                            final color = _countryPiePalette[index % _countryPiePalette.length];
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                children: [
                                  Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: color,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          _countryLegendLabel(bucket.countryLabel),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context).textTheme.bodySmall,
                                        ),
                                        Text(
                                          '${_formatMoneyEur(bucket.valueEur)} (${_formatPercent(bucket.share * 100)})',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context).textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  );

                  if (isNarrow) {
                    return Column(
                      children: [
                        pieWidget,
                        const SizedBox(height: 10),
                        Expanded(child: legendWidget),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      SizedBox(
                        width: 260,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: pieWidget,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(child: legendWidget),
                    ],
                  );
          },
        ),
      ),
    );
  }

  _NetValueYearMonthTableData _buildNetValueYearMonthTableData({
    required _ChartFilterContext context,
    required _PeriodGranularity granularity,
    required _NetValueSeriesFilter? seriesFilter,
  }) {
    final totalColumnLabel = switch (seriesFilter) {
      _NetValueSeriesFilter.revenue => 'Umsatz netto',
      _NetValueSeriesFilter.cogs => 'EK-netto',
      _NetValueSeriesFilter.grossProfit => 'Rohertrag',
      null => 'Umsatz netto',
    };

    final orderById = context.orderById;
    final columnLabels = switch (granularity) {
      _PeriodGranularity.month => const <String>[
        'Jan',
        'Feb',
        'Mrz',
        'Apr',
        'Mai',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Okt',
        'Nov',
        'Dez',
      ],
      _PeriodGranularity.quarter => const <String>['Q1', 'Q2', 'Q3', 'Q4'],
      _PeriodGranularity.year => const <String>['Jahr'],
      _PeriodGranularity.total => <String>[totalColumnLabel],
    };
    final valuesByRow = <String, List<double>>{};

    for (final item in context.filteredItems) {
      final order = orderById[item.ioOrderId];
      if (order == null) {
        continue;
      }
      final delivery = wareinsatzParseDeliveryDate(order.oDelivery);
      if (delivery == null) {
        continue;
      }

        final rowLabel = delivery.year.toString();
      final columnIndex = switch (granularity) {
        _PeriodGranularity.month => delivery.month - 1,
        _PeriodGranularity.quarter => ((delivery.month - 1) ~/ 3),
        _PeriodGranularity.year => 0,
        _PeriodGranularity.total => 0,
      };

      final rowValues = valuesByRow.putIfAbsent(
        rowLabel,
        () => List<double>.filled(columnLabels.length, 0),
      );
      final netRevenueEur = wareinsatzOrderedItemNetSalesForOrder(
        item: item,
        order: order,
      );
      final purchasePriceNet =
          context.catalogueById[item.ioItemId]?.icPurchasePriceNet ?? 0;
      final netCogsEur = item.ioQuantity * purchasePriceNet;
      final grossProfitEur = netRevenueEur - netCogsEur;

      // The table values always follow the active chart series filter.
      final valueForTable = switch (seriesFilter) {
        _NetValueSeriesFilter.revenue => netRevenueEur,
        _NetValueSeriesFilter.cogs => netCogsEur,
        _NetValueSeriesFilter.grossProfit => grossProfitEur,
        null => netRevenueEur,
      };
      rowValues[columnIndex] += valueForTable;
    }

    final rowLabels = valuesByRow.keys.toList(growable: false)
      ..sort((a, b) {
        final aInt = int.tryParse(a);
        final bInt = int.tryParse(b);
        if (aInt != null && bInt != null) {
          return aInt.compareTo(bInt);
        }
        return a.compareTo(b);
      });

    final columnTotals = List<double>.filled(columnLabels.length, 0);
    var grandTotal = 0.0;

    for (final rowLabel in rowLabels) {
      final rowValues = valuesByRow[rowLabel] ?? const <double>[];
      for (
        var columnIndex = 0;
        columnIndex < columnLabels.length;
        columnIndex++
      ) {
        final value = rowValues[columnIndex];
        columnTotals[columnIndex] += value;
        grandTotal += value;
      }
    }

    return _NetValueYearMonthTableData(
      rowHeaderLabel: 'Jahr',
      rowLabels: rowLabels,
      columnLabels: columnLabels,
      valuesByRow: valuesByRow,
      columnTotals: columnTotals,
      grandTotal: grandTotal,
    );
  }

  _ChartFilterContext _buildChartFilterContext({
    required List<OrderRow> orders,
    required List<ItemOrderedRow> orderedItems,
    required List<ItemCatalogueRow> catalogueItems,
    required WareinsatzPuttFilter puttFilter,
    required _PeriodGranularity granularity,
    required Set<String> selectedQuarterKeys,
    required Set<String> selectedYearKeys,
  }) {
    final filteredOrders = <OrderRow>[];
    for (final order in orders) {
      final delivery = wareinsatzParseDeliveryDate(order.oDelivery);
      if (delivery == null) {
        continue;
      }
      if (granularity != _PeriodGranularity.total) {
        final yearKey = delivery.year.toString();
        if (selectedYearKeys.isNotEmpty &&
            !selectedYearKeys.contains(yearKey)) {
          continue;
        }
      }
      if (granularity == _PeriodGranularity.quarter) {
        final quarter = ((delivery.month - 1) ~/ 3) + 1;
        final quarterKey = '${delivery.year}-Q$quarter';
        if (selectedQuarterKeys.isNotEmpty &&
            !selectedQuarterKeys.contains(quarterKey)) {
          continue;
        }
      }
      if (_matchesPuttFilter(order: order, puttFilter: puttFilter)) {
        filteredOrders.add(order);
      }
    }

    final orderById = {for (final order in filteredOrders) order.oId: order};
    final filteredItems = orderedItems
        .where((item) => orderById.containsKey(item.ioOrderId))
        .toList(growable: false);

    final catalogueById = {
      for (final item in catalogueItems) item.icId: item,
    };

    return _ChartFilterContext(
      orderById: orderById,
      filteredItems: filteredItems,
      catalogueById: catalogueById,
    );
  }

  bool _matchesPuttFilter({
    required OrderRow order,
    required WareinsatzPuttFilter puttFilter,
  }) {
    switch (puttFilter) {
      case WareinsatzPuttFilter.all:
        return true;
      case WareinsatzPuttFilter.onlyPutt:
        return order.oPutt != 0;
      case WareinsatzPuttFilter.withoutPutt:
        return order.oPutt == 0;
    }
  }

  Widget _buildNetValueYearMonthTable(
    _NetValueYearMonthTableData data, {
    required _PeriodGranularity granularity,
    required _NetValueSeriesFilter? seriesFilter,
  }) {
    if (data.rowLabels.isEmpty) {
      return const Card(
        child: Center(child: Text('Keine Jahres-/Monatsdaten verfuegbar.')),
      );
    }

    final zeroValueColor = Theme.of(context).colorScheme.error;
    TextStyle? moneyCellStyle(
      double value, {
      FontWeight weight = FontWeight.w400,
    }) {
      final baseStyle = Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(fontSize: 11, fontWeight: weight);
      if (value.abs() < 0.0000001) {
        return (baseStyle ?? const TextStyle()).copyWith(color: zeroValueColor);
      }
      return baseStyle;
    }

    final tableSeriesLabel = switch (seriesFilter) {
      _NetValueSeriesFilter.revenue => 'Umsatz netto',
      _NetValueSeriesFilter.cogs => 'EK-netto',
      _NetValueSeriesFilter.grossProfit => 'Rohertrag',
      null => 'Alle Kennzahlen',
    };
    final periodLabel = switch (granularity) {
      _PeriodGranularity.month => 'Monat',
      _PeriodGranularity.quarter => 'Quartal',
      _PeriodGranularity.year => 'Jahr',
      _PeriodGranularity.total => 'Gesamt (Jahre)',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tabelle: $tableSeriesLabel nach $periodLabel',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: DataTable(
                    headingRowHeight: 36,
                    dataRowMinHeight: 34,
                    dataRowMaxHeight: 38,
                    horizontalMargin: 10,
                    columnSpacing: 12,
                    headingTextStyle: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(fontSize: 11, fontWeight: FontWeight.w700),
                    dataTextStyle: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(fontSize: 11),
                    columns: [
                      DataColumn(label: Text(data.rowHeaderLabel)),
                      for (final columnLabel in data.columnLabels)
                        DataColumn(numeric: true, label: Text(columnLabel)),
                      DataColumn(
                        numeric: true,
                        label: Text(
                          granularity == _PeriodGranularity.total
                              ? 'Summe ${data.columnLabels.first}'
                              : 'Summe Jahr',
                        ),
                      ),
                    ],
                    rows: [
                      for (final rowLabel in data.rowLabels)
                        DataRow(
                          cells: [
                            DataCell(Text(rowLabel)),
                            for (
                              var columnIndex = 0;
                              columnIndex < data.columnLabels.length;
                              columnIndex++
                            )
                              DataCell(
                                // Nullwerte werden bewusst visuell hervorgehoben.
                                Text(
                                  _formatMoneyEur(
                                    (data.valuesByRow[rowLabel] ??
                                        const <double>[])[columnIndex],
                                  ),
                                  style: moneyCellStyle(
                                    (data.valuesByRow[rowLabel] ??
                                        const <double>[])[columnIndex],
                                  ),
                                ),
                              ),
                            DataCell(
                              // Jahressumme ebenfalls rot, falls exakt 0.
                              Text(
                                _formatMoneyEur(
                                  (data.valuesByRow[rowLabel] ?? const <double>[])
                                      .fold<double>(0, (sum, value) => sum + value),
                                ),
                                style: moneyCellStyle(
                                  (data.valuesByRow[rowLabel] ?? const <double>[])
                                      .fold<double>(0, (sum, value) => sum + value),
                                  weight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      DataRow(
                        cells: [
                          const DataCell(
                            Text(
                              'Summe',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          for (final columnTotal in data.columnTotals)
                            DataCell(
                              // Monatssummen werden konsistent eingefaerbt.
                              Text(
                                _formatMoneyEur(columnTotal),
                                style: moneyCellStyle(
                                  columnTotal,
                                  weight: FontWeight.w700,
                                ),
                              ),
                            ),
                          DataCell(
                            // Gesamtsumme in starker Gewichtung, bei 0 ebenfalls rot.
                            Text(
                              _formatMoneyEur(data.grandTotal),
                              style: moneyCellStyle(
                                data.grandTotal,
                                weight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _chartGranularityLabel(_PeriodGranularity granularity) {
    switch (granularity) {
      case _PeriodGranularity.month:
        return 'Monat';
      case _PeriodGranularity.quarter:
        return 'Quartal';
      case _PeriodGranularity.year:
        return 'Jahr';
      case _PeriodGranularity.total:
        return 'Gesamt';
    }
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
    final rows = _sortWareinsatzRows(
      _filterRowsBySearch(_filterRowsByScope(allRows)),
    );
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
    final effectiveSortColumnIndex = _tableSortColumnIndex < visibleColumnCount
        ? _tableSortColumnIndex
        : 0;

    final totalMengeOhneBom = rows.fold<double>(
      0,
      (sum, row) => sum + _displayMengeOhneBom(row),
    );
    final totalBomQty = rows.fold<double>(
      0,
      (sum, row) => sum + _displayBomMenge(row),
    );
    final totalGesamtmenge = rows.fold<double>(
      0,
      (sum, row) => sum + row.totalQuantity,
    );
    final totalValue = rows.fold<double>(
      0,
      (sum, row) => sum + row.soldValueEur,
    );
    final totalSalesNet = rows.fold<double>(
      0,
      (sum, row) => sum + row.soldNetValueEur,
    );
    final totalMargin = rows.fold<double>(
      0,
      (sum, row) => sum + row.soldMarginEur,
    );
    final totalMarginPercent = totalValue <= 0
        ? 0.0
        : (totalMargin / totalValue) * 100;
    final debugEkNettoFromRows = rows.fold<double>(
      0,
      (sum, row) => sum + row.soldValueEur,
    );
    final diagnosticsTableMaxHeight = (MediaQuery.sizeOf(context).height * 0.34)
        .clamp(220.0, 420.0)
        .toDouble();

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
                  ButtonSegment(
                    value: _PeriodGranularity.month,
                    label: Text('Monat'),
                  ),
                  ButtonSegment(
                    value: _PeriodGranularity.quarter,
                    label: Text('Quartal'),
                  ),
                  ButtonSegment(
                    value: _PeriodGranularity.year,
                    label: Text('Jahr'),
                  ),
                  ButtonSegment(
                    value: _PeriodGranularity.total,
                    label: Text('Gesamt'),
                  ),
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
                  ButtonSegment(
                    value: WareinsatzScope.all,
                    label: Text('Alle Positionen'),
                  ),
                  ButtonSegment(
                    value: WareinsatzScope.bomOnly,
                    label: Text('nur BOM-Komponenten'),
                  ),
                  ButtonSegment(
                    value: WareinsatzScope.withoutBom,
                    label: Text('nur ohne BOM'),
                  ),
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
                    ButtonSegment(
                      value: _MarginDisplay.absolute,
                      label: Text('Marge EUR'),
                    ),
                    ButtonSegment(
                      value: _MarginDisplay.percent,
                      label: Text('Marge % auf EK'),
                    ),
                  ],
                  selected: {_selectedMarginDisplay},
                  onSelectionChanged: (selection) {
                    setState(() {
                      _selectedMarginDisplay = selection.first;
                    });
                  },
                ),
              if (_selectedGranularity == _PeriodGranularity.month)
                _monthFilterButton(monthKeys),
              if (_selectedGranularity == _PeriodGranularity.quarter)
                _periodDropdown(
                  label: 'Quartal',
                  value: _selectedQuarterKey,
                  values: quarterKeys,
                  onChanged: (value) =>
                      setState(() => _selectedQuarterKey = value),
                ),
              if (_selectedGranularity == _PeriodGranularity.year)
                _periodDropdown(
                  label: 'Jahr',
                  value: _selectedYearKey,
                  values: yearKeys,
                  onChanged: (value) =>
                      setState(() => _selectedYearKey = value),
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
                onPressed: rows.isEmpty
                    ? null
                    : () => _exportWareinsatzCsv(rows),
                icon: const Icon(Icons.table_chart_outlined),
                label: const Text('CSV exportieren'),
              ),
              FilledButton.tonalIcon(
                onPressed: rows.isEmpty
                    ? null
                    : () => _exportWareinsatzPdf(rows),
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
              if (_selectedGranularity == _PeriodGranularity.month &&
                  _selectedMonthKeys.isNotEmpty)
                _summaryChip(
                  'Monate',
                  (() {
                    final sorted = _selectedMonthKeys.toList(growable: false)
                      ..sort();
                    if (sorted.length == 1) {
                      return sorted.first;
                    }
                    return '${sorted.first} bis ${sorted.last} (${sorted.length})';
                  })(),
                ),
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
                _summaryChip(
                  'Menge ohne BOM',
                  _formatQuantity(totalMengeOhneBom),
                ),
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
                title: const Text(
                  'Diagnose: Auftragsbeitraege zu Σ Verkauf (netto, scope-konsistent)',
                ),
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
                            : () => _exportOrderNetContributionsCsv(
                                orderNetContributions,
                              ),
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
                      headingTextStyle: Theme.of(context).textTheme.labelMedium
                          ?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            height: 1.2,
                          ),
                      headingRowColor: WidgetStateProperty.resolveWith(
                        (_) => Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                      ),
                      columns: [
                        DataColumn2(
                          label: const Text(
                            'Auftrag',
                            maxLines: 2,
                            softWrap: true,
                            overflow: TextOverflow.visible,
                          ),
                          fixedWidth: 130,
                        ),
                        DataColumn2(
                          label: const Text(
                            'Versanddatum',
                            maxLines: 2,
                            softWrap: true,
                            overflow: TextOverflow.visible,
                          ),
                          fixedWidth: 150,
                        ),
                        DataColumn2(
                          label: const Text(
                            'Auftragsdatum',
                            maxLines: 2,
                            softWrap: true,
                            overflow: TextOverflow.visible,
                          ),
                          fixedWidth: 150,
                        ),
                        DataColumn2(
                          label: const Text(
                            'Waehrung',
                            maxLines: 2,
                            softWrap: true,
                            overflow: TextOverflow.visible,
                          ),
                          fixedWidth: 95,
                        ),
                        DataColumn2(
                          label: const Text(
                            'USD→EUR',
                            maxLines: 2,
                            softWrap: true,
                            overflow: TextOverflow.visible,
                          ),
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
                          label: const Text(
                            'MwSt %',
                            maxLines: 2,
                            softWrap: true,
                            overflow: TextOverflow.visible,
                          ),
                          numeric: true,
                          fixedWidth: 95,
                        ),
                        DataColumn2(
                          label: const Text(
                            'Pos.',
                            maxLines: 2,
                            softWrap: true,
                            overflow: TextOverflow.visible,
                          ),
                          numeric: true,
                          fixedWidth: 70,
                        ),
                        DataColumn2(
                          label: const Text(
                            'Netto (EUR)',
                            maxLines: 2,
                            softWrap: true,
                            overflow: TextOverflow.visible,
                          ),
                          numeric: true,
                          fixedWidth: 145,
                        ),
                        DataColumn2(
                          label: const Text(
                            'Hinweis',
                            maxLines: 2,
                            softWrap: true,
                            overflow: TextOverflow.visible,
                          ),
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
                              DataCell(
                                Text(_formatMoney(contribution.fxToEur)),
                              ),
                              DataCell(
                                Text(
                                  _formatMoney(contribution.priceBasisValue),
                                ),
                              ),
                              DataCell(
                                Text(_formatMoney(contribution.vatRate)),
                              ),
                              DataCell(Text(contribution.itemCount.toString())),
                              DataCell(
                                Text(_formatMoney(contribution.netSalesEur)),
                              ),
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
              labelText: 'Suchen in Bezeichnung, Beschreibung und Kategorie',
              hintText:
                  'Teiltext; kat:spitz; * fuer beliebig, ? fuer ein Zeichen, ! zum Ausschliessen',
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
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _summaryChip('Trefferzeilen', '${rows.length}'),
              _summaryChip(
                'Σ Menge ohne BOM',
                _formatQuantity(totalMengeOhneBom),
              ),
              _summaryChip(
                'Σ EK netto (Treffer)',
                _formatMoney(debugEkNettoFromRows),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: rows.isEmpty
                ? const Center(
                    child: Text('Keine Daten fuer den ausgewaehlten Zeitraum.'),
                  )
                : DataTable2(
                    minWidth: showFinancialColumns ? 1450 : 1050,
                    fixedTopRows: 1,
                    headingRowHeight: 68,
                    headingRowColor: WidgetStateProperty.resolveWith(
                      (_) =>
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                    columnSpacing: 14,
                    horizontalMargin: 10,
                    headingTextStyle: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(
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
                              _onWareneinsatzSortChanged(
                                columnIndex,
                                ascending,
                              ),
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
                              _onWareneinsatzSortChanged(
                                columnIndex,
                                ascending,
                              ),
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
                              _onWareneinsatzSortChanged(
                                columnIndex,
                                ascending,
                              ),
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
                              _onWareneinsatzSortChanged(
                                columnIndex,
                                ascending,
                              ),
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
                              _onWareneinsatzSortChanged(
                                columnIndex,
                                ascending,
                              ),
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
                              _onWareneinsatzSortChanged(
                                columnIndex,
                                ascending,
                              ),
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
                              _onWareneinsatzSortChanged(
                                columnIndex,
                                ascending,
                              ),
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
                              DataCell(
                                Text(
                                  _formatQuantity(_displayMengeOhneBom(row)),
                                ),
                              ),
                            if (showBomMengeColumn)
                              DataCell(
                                Text(_formatQuantity(_displayBomMenge(row))),
                              ),
                            if (showGesamtmengeColumn)
                              DataCell(
                                Text(_formatQuantity(row.totalQuantity)),
                              ),
                            if (showFinancialColumns) ...[
                              DataCell(
                                Text(_formatMoney(row.purchasePriceEur)),
                              ),
                              DataCell(Text(_formatMoney(row.soldValueEur))),
                              DataCell(Text(_formatMoney(row.soldNetValueEur))),
                              DataCell(
                                Text(
                                  _selectedMarginDisplay ==
                                          _MarginDisplay.percent
                                      ? _formatPercent(row.soldMarginPercent)
                                      : _formatMoney(row.soldMarginEur),
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
            .map(
              (entry) =>
                  DropdownMenuItem<String>(value: entry, child: Text(entry)),
            )
            .toList(growable: false),
        onChanged: values.isEmpty ? null : onChanged,
      ),
    );
  }

  Widget _monthFilterButton(List<String> values) {
    final hasSelection = _selectedMonthKeys.isNotEmpty;
    final label = hasSelection
        ? 'Monate (${_selectedMonthKeys.length})'
        : 'Monate (alle)';

    return OutlinedButton.icon(
      onPressed: values.isEmpty ? null : () => _showMonthFilterDialog(values),
      icon: const Icon(Icons.calendar_month_outlined),
      label: Text(label),
    );
  }

  Widget _chartQuarterFilterButton(List<String> values) {
    final hasSelection = _selectedChartQuarterKeys.isNotEmpty;
    final label = hasSelection
        ? 'Quartale (${_selectedChartQuarterKeys.length})'
        : 'Quartale (alle)';

    return OutlinedButton.icon(
      onPressed: values.isEmpty
          ? null
          : () => _showChartQuarterFilterDialog(values),
      icon: const Icon(Icons.view_module_outlined),
      label: Text(label),
    );
  }

  Widget _chartYearFilterButton(List<String> values) {
    final hasSelection = _selectedChartYearKeys.isNotEmpty;
    final allSelected =
      hasSelection &&
      values.isNotEmpty &&
      _selectedChartYearKeys.length == values.length &&
      _selectedChartYearKeys.containsAll(values);
    final label = hasSelection
      ? (allSelected
          ? 'Jahre (alle)'
          : 'Jahre (${_selectedChartYearKeys.length})')
      : 'Jahre (alle)';

    return OutlinedButton.icon(
      onPressed: values.isEmpty ? null : () => _showChartYearFilterDialog(values),
      icon: const Icon(Icons.calendar_today_outlined),
      label: Text(label),
    );
  }

  Future<void> _showChartQuarterFilterDialog(List<String> values) async {
    final workingSelection = Set<String>.from(_selectedChartQuarterKeys);

    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Quartale filtern'),
              content: SizedBox(
                width: 420,
                child: values.isEmpty
                    ? const Text('Keine Quartale vorhanden.')
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final quarter in values)
                            CheckboxListTile(
                              value: workingSelection.contains(quarter),
                              title: Text(quarter),
                              controlAffinity: ListTileControlAffinity.leading,
                              onChanged: (checked) {
                                setDialogState(() {
                                  if (checked == true) {
                                    workingSelection.add(quarter);
                                  } else {
                                    workingSelection.remove(quarter);
                                  }
                                });
                              },
                            ),
                        ],
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () =>
                      Navigator.of(context).pop(_selectedChartQuarterKeys),
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
      _selectedChartQuarterKeys = result;
      _ensureChartPeriodDefaults();
    });
  }

  Future<void> _showChartYearFilterDialog(List<String> values) async {
    final workingSelection = Set<String>.from(_selectedChartYearKeys);

    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Jahre filtern'),
              content: SizedBox(
                width: 420,
                child: values.isEmpty
                    ? const Text('Keine Jahre vorhanden.')
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final year in values)
                            CheckboxListTile(
                              value: workingSelection.contains(year),
                              title: Text(year),
                              controlAffinity: ListTileControlAffinity.leading,
                              onChanged: (checked) {
                                setDialogState(() {
                                  if (checked == true) {
                                    workingSelection.add(year);
                                  } else {
                                    workingSelection.remove(year);
                                  }
                                });
                              },
                            ),
                        ],
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () =>
                      Navigator.of(context).pop(_selectedChartYearKeys),
                  child: const Text('Abbrechen'),
                ),
                TextButton(
                  onPressed: () {
                    setDialogState(() {
                      workingSelection
                        ..clear()
                        ..addAll(values);
                    });
                  },
                  child: const Text('Alle auswaehlen'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(<String>{}),
                  child: const Text('Alle abwaehlen'),
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
      _selectedChartYearKeys = result;
      _ensureChartPeriodDefaults();
    });
  }

  Future<void> _showMonthFilterDialog(List<String> values) async {
    final workingSelection = Set<String>.from(_selectedMonthKeys);
    if (workingSelection.isEmpty && values.isNotEmpty) {
      workingSelection.add(values.first);
    }

    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Monate filtern'),
              content: SizedBox(
                width: 420,
                child: values.isEmpty
                    ? const Text('Keine Monate vorhanden.')
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final month in values)
                            CheckboxListTile(
                              value: workingSelection.contains(month),
                              title: Text(month),
                              controlAffinity: ListTileControlAffinity.leading,
                              onChanged: (checked) {
                                setDialogState(() {
                                  if (checked == true) {
                                    workingSelection.add(month);
                                  } else {
                                    workingSelection.remove(month);
                                  }
                                });
                              },
                            ),
                        ],
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () =>
                      Navigator.of(context).pop(_selectedMonthKeys),
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
      _selectedMonthKeys = result;
      _ensurePeriodDefaults();
    });
  }

  Widget _summaryChip(String label, String value) {
    return Chip(label: Text('$label: $value'));
  }

  List<OrderRow> _filterOrders(List<OrderRow> orders) {
    final ordersByTradeShowAndPutt = wareinsatzFilterOrdersByTradeShowAndPutt(
      orders: orders,
      selectedTradeShows: _selectedTradeShows,
      puttFilter: _selectedPuttFilter,
    );

    return ordersByTradeShowAndPutt
        .where((order) {
          if (order.oCanceled != 0 && order.oReturned != 0) {
            return false;
          }

          final delivery = wareinsatzParseDeliveryDate(order.oDelivery);
          if (delivery == null) {
            return false;
          }

          switch (_selectedGranularity) {
            case _PeriodGranularity.total:
              return true;
            case _PeriodGranularity.month:
              return wareinsatzMatchesDeliveryMonths(order, _selectedMonthKeys);
            case _PeriodGranularity.quarter:
              final quarter = ((delivery.month - 1) ~/ 3) + 1;
              final key = '${delivery.year}-Q$quarter';
              return key == _selectedQuarterKey;
            case _PeriodGranularity.year:
              final key = delivery.year.toString();
              return key == _selectedYearKey;
          }
        })
        .toList(growable: false);
  }

  Widget _tradeShowFilterButton(List<String> options) {
    final hasSelection = _selectedTradeShows.isNotEmpty;
    final label = hasSelection
        ? 'Trade Show (${_selectedTradeShows.length})'
        : 'Trade Show (alle)';

    return OutlinedButton.icon(
      onPressed: options.isEmpty
          ? null
          : () => _showTradeShowFilterDialog(options),
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
                  onPressed: () =>
                      Navigator.of(context).pop(_selectedTradeShows),
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

  List<String> _availableQuarterKeysForChartYear(
    List<OrderRow> orders,
    Set<String> yearKeys,
  ) {
    final allQuarterKeys = _availableQuarterKeys(orders);
    if (yearKeys.isEmpty) {
      return allQuarterKeys;
    }

    return allQuarterKeys
        .where(
          (quarterKey) => yearKeys.any(
            (yearKey) => quarterKey.startsWith('$yearKey-'),
          ),
        )
        .toList(growable: false);
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
    final orderById = {for (final order in filteredOrders) order.oId: order};
    final filteredItems = orderedItems
        .where(
          (item) =>
              filteredOrderIds.contains(item.ioOrderId) && item.ioItemId > 0,
        )
        .toList(growable: false);

    final catalogueById = {for (final item in catalogueItems) item.icId: item};
    final childrenByParentId = <int, List<ItemBomRow>>{};
    final rootByArticleId = <int, List<ItemBomRow>>{};

    for (final bom in bomItems) {
      final parentId = bom.ibParentId;
      final id = bom.ibId;
      if (parentId == null) {
        if (id != null) {
          rootByArticleId
              .putIfAbsent(bom.ibItemId, () => <ItemBomRow>[])
              .add(bom);
        }
        continue;
      }
      childrenByParentId.putIfAbsent(parentId, () => <ItemBomRow>[]).add(bom);
    }

    final aggregateByItemId = <int, _WareinsatzMutable>{};

    _WareinsatzMutable? addSold(
      int itemId,
      double quantity, {
      ItemOrderedRow? ordered,
    }) {
      if (itemId <= 0 || quantity <= 0) {
        return null;
      }
      final catalogue = catalogueById[itemId];
      final aggregate = aggregateByItemId.putIfAbsent(itemId, () {
        return _WareinsatzMutable(
          itemId: itemId,
          idi: catalogue?.icIdi ?? ordered?.ioIdi ?? 'Artikel #$itemId',
          description:
              catalogue?.icDescriptionDeLong ??
              ordered?.ioDescriptionDeLong ??
              '-',
          category: catalogue?.category ?? '',
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
      return aggregate;
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
          category: catalogue?.category ?? '',
          purchasePriceEur: catalogue?.icPurchasePriceNet ?? 0,
        );
      });
      aggregate.bomQuantity += quantity;
    }

    double accumulateBomChildren(
      int parentBomId,
      double baseQuantity,
      Set<int> visiting,
    ) {
      if (visiting.contains(parentBomId)) {
        return 0;
      }

      final children = childrenByParentId[parentBomId] ?? const <ItemBomRow>[];
      if (children.isEmpty) {
        return 0;
      }

      final nextVisiting = {...visiting, parentBomId};
      var totalChildrenQuantity = 0.0;
      for (final child in children) {
        final componentQuantity = baseQuantity * child.ibQuantity;
        addBom(child.ibItemId, componentQuantity);
        totalChildrenQuantity += componentQuantity;
        final childBomId = child.ibId;
        if (childBomId != null) {
          totalChildrenQuantity += accumulateBomChildren(
            childBomId,
            componentQuantity,
            nextVisiting,
          );
        }
      }
      return totalChildrenQuantity;
    }

    for (final item in filteredItems) {
      final soldQuantity = item.ioQuantity.toDouble();
      final soldAggregate = addSold(item.ioItemId, soldQuantity, ordered: item);

      final roots = rootByArticleId[item.ioItemId] ?? const <ItemBomRow>[];
      var ownBomQuantity = 0.0;
      for (final root in roots) {
        final rootBomId = root.ibId;
        if (rootBomId == null) {
          continue;
        }
        ownBomQuantity += accumulateBomChildren(
          rootBomId,
          soldQuantity,
          <int>{},
        );
      }
      if (soldAggregate != null && ownBomQuantity > 0) {
        soldAggregate.ownBomQuantity += ownBomQuantity;
      }
    }

    final rows =
        aggregateByItemId.values
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
    final orderById = {for (final order in filteredOrders) order.oId: order};
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
          deliveryDate: order.oDelivery.trim().isEmpty
              ? '-'
              : order.oDelivery.trim(),
          orderDate: order.oDate.trim().isEmpty ? '-' : order.oDate.trim(),
          currency: order.oCurrency.trim().isEmpty
              ? 'EUR'
              : order.oCurrency.trim().toUpperCase(),
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

    final rows =
        grouped.values.map((entry) => entry.toRow()).toList(growable: false)
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

      final totalNet = rows.fold<double>(
        0,
        (sum, row) => sum + row.netSalesEur,
      );
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
        SnackBar(
          content: Text(
            'Wareneinsatz-Diagnose-CSV exportiert nach: $targetPath',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Wareneinsatz-Diagnose-CSV-Export fehlgeschlagen: $error',
          ),
        ),
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
          if (showMengeOhneBomColumn)
            _csvEscape(_formatQuantity(_displayMengeOhneBom(row))),
          if (showBomMengeColumn)
            _csvEscape(_formatQuantity(_displayBomMenge(row))),
          if (showGesamtmengeColumn)
            _csvEscape(_formatQuantity(row.totalQuantity)),
          if (showFinancialColumns) ...[
            _csvEscape(_formatMoney(row.purchasePriceEur)),
            _csvEscape(_formatMoney(row.soldValueEur)),
            _csvEscape(_formatMoney(row.soldNetValueEur)),
            _csvEscape(
              _selectedMarginDisplay == _MarginDisplay.percent
                  ? _formatPercent(row.soldMarginPercent)
                  : _formatMoney(row.soldMarginEur),
            ),
          ],
        ];
        buffer.writeln(cells.join(';'));
      }

      final fileName =
          'wareneinsatz_versanddatum_${_periodLabelForExport()}_${_buildFileTimestamp(DateTime.now())}.csv';
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
        SnackBar(
          content: Text('Wareneinsatz-CSV exportiert nach: $targetPath'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Wareneinsatz-CSV-Export fehlgeschlagen: $error'),
        ),
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
        for (var i = 0; i < columnFlexes.length; i++)
          i: pw.FlexColumnWidth(columnFlexes[i]),
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
        (sum, row) => sum + row.soldValueEur,
      );
      final totalVerkaufNetto = rows.fold<double>(
        0,
        (sum, row) => sum + row.soldNetValueEur,
      );
      final totalMargeEur = rows.fold<double>(
        0,
        (sum, row) => sum + row.soldMarginEur,
      );
      final totalMargePercent = totalEkWert > 0
          ? (totalMargeEur / totalEkWert) * 100
          : 0.0;

      final tableData = rows
          .map(
            (row) => <String>[
              row.bezeichnung,
              row.beschreibung,
              if (showMengeOhneBomColumn)
                _formatQuantity(_displayMengeOhneBom(row)),
              if (showBomMengeColumn) _formatQuantity(_displayBomMenge(row)),
              if (showGesamtmengeColumn) _formatQuantity(row.totalQuantity),
              if (showFinancialColumns) ...[
                _formatMoney(row.purchasePriceEur),
                _formatMoney(row.soldValueEur),
                _formatMoney(row.soldNetValueEur),
                _selectedMarginDisplay == _MarginDisplay.percent
                    ? _formatPercent(row.soldMarginPercent)
                    : _formatMoney(row.soldMarginEur),
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
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey300,
              ),
              headerStyle: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              ),
              cellStyle: const pw.TextStyle(fontSize: 7),
              cellAlignment: pw.Alignment.centerLeft,
              cellPadding: const pw.EdgeInsets.all(3),
              columnWidths: columnWidths,
            ),
            pw.Table(
              columnWidths: columnWidths,
              border: pw.TableBorder(
                left: const pw.BorderSide(color: PdfColors.grey500, width: 0.5),
                right: const pw.BorderSide(
                  color: PdfColors.grey500,
                  width: 0.5,
                ),
                bottom: const pw.BorderSide(
                  color: PdfColors.grey500,
                  width: 0.5,
                ),
                horizontalInside: const pw.BorderSide(
                  color: PdfColors.grey500,
                  width: 0.5,
                ),
                verticalInside: const pw.BorderSide(
                  color: PdfColors.grey500,
                  width: 0.5,
                ),
              ),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                  children: [
                    for (var index = 0; index < summaryRow.length; index++)
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(3),
                        child: pw.Align(
                          alignment:
                              index >= quantityColumnStart &&
                                  (index <
                                          quantityColumnStart +
                                              quantityColumnCount ||
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

      final fileName =
          'wareneinsatz_${_periodLabelForExport()}_${_buildFileTimestamp(DateTime.now())}.pdf';
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
        SnackBar(
          content: Text('Wareneinsatz-PDF exportiert nach: $targetPath'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Wareneinsatz-PDF-Export fehlgeschlagen: $error'),
        ),
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
    return _PdfFonts(base: pw.Font.ttf(baseData), bold: pw.Font.ttf(boldData));
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
        if (_selectedMonthKeys.isEmpty) {
          return 'monat_na_$scope';
        }
        final sorted = _selectedMonthKeys.toList(growable: false)..sort();
        final first = sorted.first;
        final last = sorted.last;
        if (sorted.length == 1) {
          return 'monat_${sorted.first}_$scope';
        }
        return 'monat_${first}_bis_${last}_${sorted.length}m_$scope';
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
        if (_selectedMonthKeys.isEmpty) {
          return 'Monat -$scopeLabel';
        }
        final sorted = _selectedMonthKeys.toList(growable: false)..sort();
        if (sorted.length == 1) {
          return 'Monat ${sorted.first}$scopeLabel';
        }
        return 'Monate ${sorted.first} bis ${sorted.last} (${sorted.length})$scopeLabel';
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
            bomQuantity: row.totalBomQuantity,
          ),
        )
        .toList(growable: false);
  }

  List<_WareinsatzRow> _filterRowsBySearch(List<_WareinsatzRow> rows) {
    if (_searchQuery.isEmpty) {
      return rows;
    }

    return rows
        .where((row) {
          return wareinsatzMatchesSearchQuery(
            query: _searchQuery,
            bezeichnung: row.bezeichnung,
            beschreibung: row.beschreibung,
            category: row.category,
          );
        })
        .toList(growable: false);
  }

  String _diagnosticsPriceBasisCurrencyLabel(List<_OrderNetContribution> rows) {
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
    final visibleColumnCount = switch (_selectedScope) {
      WareinsatzScope.all => 5,
      WareinsatzScope.bomOnly => 3,
      WareinsatzScope.withoutBom => 7,
    };
    final effectiveSortColumnIndex = _tableSortColumnIndex < visibleColumnCount
        ? _tableSortColumnIndex
        : 0;
    int compare(_WareinsatzRow a, _WareinsatzRow b) {
      switch (effectiveSortColumnIndex) {
        case 0:
          return a.bezeichnung.toLowerCase().compareTo(
            b.bezeichnung.toLowerCase(),
          );
        case 1:
          return a.beschreibung.toLowerCase().compareTo(
            b.beschreibung.toLowerCase(),
          );
        case 2:
          return _displayMengeOhneBom(a).compareTo(_displayMengeOhneBom(b));
        case 3:
          return isAllScope
              ? _displayBomMenge(a).compareTo(_displayBomMenge(b))
              : a.purchasePriceEur.compareTo(b.purchasePriceEur);
        case 4:
          return isAllScope
              ? a.totalQuantity.compareTo(b.totalQuantity)
              : a.soldValueEur.compareTo(b.soldValueEur);
        case 5:
          return isAllScope
              ? a.totalValueEur.compareTo(b.totalValueEur)
              : a.soldNetValueEur.compareTo(b.soldNetValueEur);
        case 6:
          return isAllScope
              ? a.soldNetValueEur.compareTo(b.soldNetValueEur)
              : (_selectedMarginDisplay == _MarginDisplay.percent
                    ? a.soldMarginPercent.compareTo(b.soldMarginPercent)
                    : a.soldMarginEur.compareTo(b.soldMarginEur));
        case 7:
          return _selectedMarginDisplay == _MarginDisplay.percent
              ? a.soldMarginPercent.compareTo(b.soldMarginPercent)
              : a.soldMarginEur.compareTo(b.soldMarginEur);
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
      _PeriodGranularity.month => wareinsatzMatchesDeliveryMonths(
        order.copyWith(oDelivery: order.oDate),
        _selectedMonthKeys,
      ),
      _PeriodGranularity.quarter =>
        _selectedQuarterKey != null &&
            '${orderDate.year}-Q${((orderDate.month - 1) ~/ 3) + 1}' ==
                _selectedQuarterKey,
      _PeriodGranularity.year =>
        _selectedYearKey != null &&
            orderDate.year.toString() == _selectedYearKey,
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

  String _formatMoneyEur(double value) {
    final absolute = value.abs();
    final fixed = absolute.toStringAsFixed(2);
    final parts = fixed.split('.');
    final integerPart = parts.first;
    final decimalPart = parts.last;
    final grouped = StringBuffer();

    for (var index = 0; index < integerPart.length; index++) {
      final reverseIndex = integerPart.length - index;
      grouped.write(integerPart[index]);
      if (reverseIndex > 1 && reverseIndex % 3 == 1) {
        grouped.write('.');
      }
    }

    final sign = value < 0 ? '-' : '';
    return '$sign${grouped.toString()},$decimalPart EUR';
  }

  String _formatPercent(double value) {
    return '${value.toStringAsFixed(2).replaceAll('.', ',')} %';
  }

  double _displayMengeOhneBom(_WareinsatzRow row) {
    return _selectedScope == WareinsatzScope.bomOnly ? 0 : row.soldQuantity;
  }

  double _displayBomMenge(_WareinsatzRow row) {
    return _selectedScope == WareinsatzScope.withoutBom
        ? 0
        : row.totalBomQuantity;
  }
}

class _NetValueBucket {
  const _NetValueBucket({
    required this.periodLabel,
    required this.netRevenueEur,
    required this.netCogsEur,
  });

  final String periodLabel;
  final double netRevenueEur;
  final double netCogsEur;
  double get grossProfitEur => netRevenueEur - netCogsEur;
}

class _ChartLegendChip extends StatelessWidget {
  const _ChartLegendChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Opacity(
        opacity: selected ? 1 : 0.8,
        child: Chip(
          visualDensity: VisualDensity.compact,
          backgroundColor: selected
              ? color.withValues(alpha: 0.2)
              : Theme.of(context).chipTheme.backgroundColor,
          avatar: CircleAvatar(backgroundColor: color, radius: 6),
          label: Text(label),
        ),
      ),
    );
  }
}

class _NetValueYearMonthTableData {
  const _NetValueYearMonthTableData({
    required this.rowHeaderLabel,
    required this.rowLabels,
    required this.columnLabels,
    required this.valuesByRow,
    required this.columnTotals,
    required this.grandTotal,
  });

  final String rowHeaderLabel;
  final List<String> rowLabels;
  final List<String> columnLabels;
  final Map<String, List<double>> valuesByRow;
  final List<double> columnTotals;
  final double grandTotal;
}

class _CountryShareBucket {
  const _CountryShareBucket({
    required this.countryLabel,
    required this.valueEur,
    required this.share,
  });

  final String countryLabel;
  final double valueEur;
  final double share;
}

class _ChartFilterContext {
  const _ChartFilterContext({
    required this.orderById,
    required this.filteredItems,
    required this.catalogueById,
  });

  final Map<String, OrderRow> orderById;
  final List<ItemOrderedRow> filteredItems;
  final Map<int, ItemCatalogueRow> catalogueById;
}

class _CountrySharePiePainter extends CustomPainter {
  _CountrySharePiePainter({required this.buckets, required this.colors});

  final List<_CountryShareBucket> buckets;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (buckets.isEmpty) {
      return;
    }

    final total = buckets.fold<double>(0, (sum, entry) => sum + entry.valueEur);
    if (total <= 0) {
      return;
    }

    final radius = size.shortestSide / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: center, radius: radius);

    final basePaint = Paint()..style = PaintingStyle.fill;
    final separatorPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.6, radius * 0.02)
      ..strokeCap = StrokeCap.butt
      ..color = Colors.white;

    var startAngle = -math.pi / 2;
    for (var index = 0; index < buckets.length; index++) {
      final bucket = buckets[index];
      final sweepAngle = (bucket.valueEur / total) * math.pi * 2;
      final paint = basePaint..color = colors[index % colors.length];

      canvas.drawArc(rect, startAngle, sweepAngle, true, paint);

      final boundary = Offset(
        center.dx + math.cos(startAngle) * radius,
        center.dy + math.sin(startAngle) * radius,
      );
      canvas.drawLine(center, boundary, separatorPaint);

      startAngle += sweepAngle;
    }

    final finalBoundary = Offset(
      center.dx + math.cos(startAngle) * radius,
      center.dy + math.sin(startAngle) * radius,
    );
    canvas.drawLine(center, finalBoundary, separatorPaint);
  }

  @override
  bool shouldRepaint(covariant _CountrySharePiePainter oldDelegate) {
    if (oldDelegate.buckets.length != buckets.length) {
      return true;
    }
    for (var i = 0; i < buckets.length; i++) {
      if (oldDelegate.buckets[i].countryLabel != buckets[i].countryLabel ||
          oldDelegate.buckets[i].valueEur != buckets[i].valueEur) {
        return true;
      }
    }
    return false;
  }
}

class _WareinsatzMutable {
  _WareinsatzMutable({
    required this.itemId,
    required this.idi,
    required this.description,
    required this.category,
    required this.purchasePriceEur,
  });

  final int itemId;
  final String idi;
  final String description;
  final String category;
  final double purchasePriceEur;

  double soldQuantity = 0;
  double bomQuantity = 0;
  double ownBomQuantity = 0;
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
      category: category,
      soldQuantity: soldQuantity,
      bomQuantity: bomQuantity,
      ownBomQuantity: ownBomQuantity,
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
    required this.category,
    required this.soldQuantity,
    required this.bomQuantity,
    required this.ownBomQuantity,
    required this.purchasePriceEur,
    required this.soldNetValueEur,
  });

  final int itemId;
  final String bezeichnung;
  final String beschreibung;
  final String category;
  final double soldQuantity;
  final double bomQuantity;
  final double ownBomQuantity;
  final double purchasePriceEur;
  final double soldNetValueEur;

  double get totalBomQuantity => bomQuantity + ownBomQuantity;

  double get totalValueEur => totalQuantity * purchasePriceEur;
  double get marginEur =>
      soldNetValueEur <= 0 ? 0 : soldNetValueEur - totalValueEur;
  double get marginPercent => (soldNetValueEur <= 0 || totalValueEur <= 0)
      ? 0
      : (marginEur / totalValueEur) * 100;
  double get soldValueEur => soldQuantity * purchasePriceEur;
  double get soldMarginEur =>
      soldNetValueEur <= 0 ? 0 : soldNetValueEur - soldValueEur;
  double get soldMarginPercent => (soldNetValueEur <= 0 || soldValueEur <= 0)
      ? 0
      : (soldMarginEur / soldValueEur) * 100;

  double get totalQuantity {
    if (ownBomQuantity > 0) {
      return totalBomQuantity;
    }
    return soldQuantity + bomQuantity;
  }
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
    var remainder = normalizedBeschreibung
        .substring(normalizedBezeichnung.length)
        .trimLeft();
    const separators = ['|', '-', ':', ';', ',', '/'];
    while (remainder.isNotEmpty && separators.contains(remainder[0])) {
      remainder = remainder.substring(1).trimLeft();
    }
    return remainder.isEmpty ? '-' : remainder;
  }

  return normalizedBeschreibung;
}
