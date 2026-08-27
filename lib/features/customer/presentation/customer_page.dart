import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_path_config.dart';
import '../../../core/ui/transient_feedback.dart';
import '../data/country_csv_service.dart';
import '../data/customer_csv_service.dart';
import '../data/customer_repository.dart';
import '../domain/country_tld.dart';
import '../domain/customer.dart';
import '../../item/presentation/item_catalogue_page.dart';
import '../../order/data/order_repository.dart';
import '../../order/domain/order_models.dart';
import '../../order/presentation/order_page.dart';
import 'customer_country_display.dart';
import 'widgets/csv_import_preview_dialog.dart';
import 'widgets/customer_detail_dialog.dart';
import 'widgets/customer_form_dialog.dart';
import 'widgets/customer_page_actions.dart';
import 'widgets/customer_paginated_table.dart';
import 'widgets/customer_results_header.dart';

export 'widgets/customer_paginated_table.dart' show CustomerDataTableSource;

@visibleForTesting
double computeEffectiveOrderNetGoods(OrderRow order) {
  final effectivePaypalFee =
      order.oPaypalFeeActual ??
      ((order.oPaymentActual != null && order.oPaymentActual != 1)
          ? 0
          : order.oPaypalFee);

  final hasActualSettlementOverride =
      order.oPaymentActual != null || order.oPaypalFeeActual != null;

  if (order.oValueGoods != 0 && !hasActualSettlementOverride) {
    return order.oValueGoods;
  }

  // Fallback for legacy/unsynchronized orders and adjustments with actual
  // settlement values.
  return order.oTotalPrice - order.oShipping - effectivePaypalFee - order.oVat;
}

class CustomerPage extends StatefulWidget {
  const CustomerPage({
    super.key,
    this.initialCustomerId,
    this.openInitialCustomerDetails = false,
    this.showModuleNavigation = true,
    this.enableBackgroundNormalization = true,
    this.reloadOnVisibilityChange = true,
    this.initializeDatabasePath = true,
    this.customerRepository = const CustomerRepository(),
    this.orderRepository = const OrderRepository(),
  });

  final String? initialCustomerId;
  final bool openInitialCustomerDetails;
  final bool showModuleNavigation;
  final bool enableBackgroundNormalization;
  final bool reloadOnVisibilityChange;
  final bool initializeDatabasePath;
  final CustomerRepository customerRepository;
  final OrderRepository orderRepository;

  @override
  State<CustomerPage> createState() => _CustomerPageState();
}

class _CustomerPageState extends State<CustomerPage> {
  late final CustomerRepository _repository;
  late final OrderRepository _orderRepository;
  final CustomerCsvService _csvService = CustomerCsvService();
  final CountryCsvService _countryCsvService = CountryCsvService();

  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;
  late final ScrollController _customerOrdersScrollController;
  late final ScrollController _orderItemsScrollController;
  Timer? _searchDebounce;

  bool _loading = false;
  List<Customer> _customers = const [];
  List<Customer> _filteredCustomers = const [];
  List<String> _customerSearchIndex = const [];
  Map<String, String> _countryNameByCode = const {};
  String _databasePath = 'wird geladen...';
  bool _databasePathFallbackActive = false;
  String? _preferredDatabasePath;
  String? _databaseStatusMessage;
  int _sortColumnIndex = 0;
  bool _sortAscending = false;
  int _rowsPerPage = 25;
  String _lastFilterQuery = '';
  List<int> _lastFilteredIndices = const [];
  int _perfOpCounter = 0;
  bool _adminUnitNormalizationRunning = false;
  Map<String, double> _customerNetById = const {};
  String? _selectedCustomerId;
  String? _selectedOrderId;
  List<OrderRow> _selectedCustomerOrders = const [];
  List<ItemOrderedRow> _selectedOrderItems = const [];
  Map<String, int> _selectedOrderItemCountByOrderId = const {};
  bool _wasVisibleInBuild = false;
  String? _pendingInitialCustomerId;
  bool _pendingOpenInitialCustomerDetails = false;
  double _customerTopSectionRatio = 0.5;
  double _customerMiddleSectionRatio = 0.5;
  bool _isTopSectionSplitterDragging = false;
  bool _isMiddleSectionSplitterDragging = false;

  static const double _customerSectionSplitterHeight = 24.0;
  static const double _customerTopSectionMinHeight = 220.0;
  static const double _customerMiddleSectionMinHeight = 140.0;
  static const double _customerBottomSectionMinHeight = 140.0;
    static const String _customerTopSectionRatioPrefKey =
      'customer_page.top_section_ratio';
    static const String _customerMiddleSectionRatioPrefKey =
      'customer_page.middle_section_ratio';

  String _normalizeCustomerId(String? value) {
    return (value ?? '').trim().toLowerCase();
  }

  bool _isSameCustomerId(String? a, String? b) {
    return _normalizeCustomerId(a) == _normalizeCustomerId(b);
  }

  Future<void> _loadCustomerSectionLayoutPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final topRatio = prefs.getDouble(_customerTopSectionRatioPrefKey);
    final middleRatio = prefs.getDouble(_customerMiddleSectionRatioPrefKey);

    if (!mounted) {
      return;
    }

    setState(() {
      if (topRatio != null) {
        _customerTopSectionRatio = topRatio.clamp(0.0, 1.0);
      }
      if (middleRatio != null) {
        _customerMiddleSectionRatio = middleRatio.clamp(0.0, 1.0);
      }
    });
  }

  Future<void> _saveCustomerSectionLayoutPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(
      _customerTopSectionRatioPrefKey,
      _customerTopSectionRatio,
    );
    await prefs.setDouble(
      _customerMiddleSectionRatioPrefKey,
      _customerMiddleSectionRatio,
    );
  }

  Future<void> _resetCustomerSectionLayout() async {
    setState(() {
      _customerTopSectionRatio = 0.5;
      _customerMiddleSectionRatio = 0.5;
    });
    await _saveCustomerSectionLayoutPrefs();
  }

  double _resolvedTopSectionHeight(double availableHeight) {
    if (availableHeight <= 0) {
      return 0;
    }

    final minCombined =
        _customerTopSectionMinHeight +
        _customerMiddleSectionMinHeight +
        _customerBottomSectionMinHeight;
    final desired = availableHeight * _customerTopSectionRatio;

    if (availableHeight <= minCombined) {
      return desired.clamp(0.0, availableHeight);
    }

    return desired.clamp(
      _customerTopSectionMinHeight,
      availableHeight -
          (_customerMiddleSectionMinHeight + _customerBottomSectionMinHeight),
    );
  }

  double _resolvedMiddleSectionHeight(
    double lowerAvailableHeight,
  ) {
    if (lowerAvailableHeight <= 0) {
      return 0;
    }

    final minCombined =
        _customerMiddleSectionMinHeight + _customerBottomSectionMinHeight;
    final desired = lowerAvailableHeight * _customerMiddleSectionRatio;

    if (lowerAvailableHeight <= minCombined) {
      return desired.clamp(0.0, lowerAvailableHeight);
    }

    return desired.clamp(
      _customerMiddleSectionMinHeight,
      lowerAvailableHeight - _customerBottomSectionMinHeight,
    );
  }

  Widget _buildVerticalSectionSplitter({
    required bool isDragging,
    required VoidCallback onDragStart,
    required VoidCallback onDragEnd,
    required ValueChanged<DragUpdateDetails> onDragUpdate,
    required VoidCallback onDoubleTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: onDoubleTap,
      onVerticalDragStart: (_) => onDragStart(),
      onVerticalDragEnd: (_) => onDragEnd(),
      onVerticalDragCancel: () => onDragEnd(),
      onVerticalDragUpdate: onDragUpdate,
      child: Container(
        height: _customerSectionSplitterHeight,
        color: isDragging
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
            : Theme.of(context).dividerColor.withValues(alpha: 0.15),
        child: const Center(
          child: Icon(Icons.drag_handle, size: 18),
        ),
      ),
    );
  }

  Widget _buildDesktopCustomerLayout(BoxConstraints constraints) {
    final splitterTotalHeight = _customerSectionSplitterHeight * 2;
    final availableHeight =
        (constraints.maxHeight - splitterTotalHeight).clamp(0.0, double.infinity);
    final topHeight = _resolvedTopSectionHeight(availableHeight);
    final lowerAvailableHeight =
        (availableHeight - topHeight).clamp(0.0, double.infinity);
    final middleHeight = _resolvedMiddleSectionHeight(lowerAvailableHeight);
    final bottomHeight =
        (lowerAvailableHeight - middleHeight).clamp(0.0, double.infinity);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: topHeight,
          child: CustomerPaginatedTable(
            customers: _filteredCustomers,
            countryNameByCode: _countryNameByCode,
            loading: _loading,
            sortColumnIndex: _sortColumnIndex,
            sortAscending: _sortAscending,
            rowsPerPage: _rowsPerPage,
            onRowsPerPageChanged: (value) =>
                setState(() => _rowsPerPage = value),
            onSort: _sortFilteredCustomers,
            onEditCustomer: _editCustomer,
            onDeleteCustomer: _deleteCustomer,
            onOpenMap: _showMapDialog,
            selectedCustomerId: _selectedCustomerId,
            onSelectCustomer: _selectCustomer,
            customerNetById: _customerNetById,
          ),
        ),
        _buildVerticalSectionSplitter(
          isDragging: _isTopSectionSplitterDragging,
          onDragStart: () {
            setState(() => _isTopSectionSplitterDragging = true);
          },
          onDragEnd: () {
            setState(() => _isTopSectionSplitterDragging = false);
            unawaited(_saveCustomerSectionLayoutPrefs());
          },
          onDoubleTap: () => unawaited(_resetCustomerSectionLayout()),
          onDragUpdate: (details) {
            final nextTopHeight = _resolvedTopSectionHeight(availableHeight) +
                details.delta.dy;
            final clampedTopHeight = _resolvedTopSectionHeight(availableHeight)
                .clamp(0.0, availableHeight);

            final minCombined =
                _customerTopSectionMinHeight +
                _customerMiddleSectionMinHeight +
                _customerBottomSectionMinHeight;
            final normalizedTopHeight = availableHeight <= minCombined
                ? nextTopHeight.clamp(0.0, availableHeight)
                : nextTopHeight.clamp(
                    _customerTopSectionMinHeight,
                    availableHeight -
                        (_customerMiddleSectionMinHeight +
                            _customerBottomSectionMinHeight),
                  );

            if (availableHeight <= 0) {
              return;
            }

            setState(() {
              _customerTopSectionRatio =
                  (normalizedTopHeight / availableHeight).clamp(0.0, 1.0);
              if (clampedTopHeight <= 0) {
                _customerTopSectionRatio = 0.5;
              }
            });
          },
        ),
        SizedBox(
          height: middleHeight,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final showHeader = constraints.maxHeight >= 48;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (showHeader) ...[
                        Text(
                          'Aufträge zum Kunden',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                      ],
                      Expanded(child: _buildCustomerOrdersTable()),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        _buildVerticalSectionSplitter(
          isDragging: _isMiddleSectionSplitterDragging,
          onDragStart: () {
            setState(() => _isMiddleSectionSplitterDragging = true);
          },
          onDragEnd: () {
            setState(() => _isMiddleSectionSplitterDragging = false);
            unawaited(_saveCustomerSectionLayoutPrefs());
          },
          onDoubleTap: () => unawaited(_resetCustomerSectionLayout()),
          onDragUpdate: (details) {
            final currentTopHeight = _resolvedTopSectionHeight(availableHeight);
            final currentLowerAvailableHeight =
                (availableHeight - currentTopHeight).clamp(0.0, double.infinity);
            if (currentLowerAvailableHeight <= 0) {
              return;
            }

            final nextMiddleHeight =
                _resolvedMiddleSectionHeight(currentLowerAvailableHeight) +
                    details.delta.dy;
            final minCombined =
                _customerMiddleSectionMinHeight + _customerBottomSectionMinHeight;
            final normalizedMiddleHeight = currentLowerAvailableHeight <= minCombined
                ? nextMiddleHeight.clamp(0.0, currentLowerAvailableHeight)
                : nextMiddleHeight.clamp(
                    _customerMiddleSectionMinHeight,
                    currentLowerAvailableHeight - _customerBottomSectionMinHeight,
                  );

            setState(() {
              _customerMiddleSectionRatio =
                  (normalizedMiddleHeight / currentLowerAvailableHeight)
                      .clamp(0.0, 1.0);
            });
          },
        ),
        SizedBox(
          height: bottomHeight,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final showHeader = constraints.maxHeight >= 48;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (showHeader) ...[
                        Text(
                          'Positionen zum Auftrag',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                      ],
                      Expanded(child: _buildOrderItemsTable()),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  static final RegExp _validCountryCodePattern = RegExp(r'^[a-z]{2,}$');

  bool get _perfLoggingEnabled => kDebugMode && Platform.isMacOS;

  String _nextPerfTraceTag(String scope) {
    _perfOpCounter += 1;
    return '$scope#$_perfOpCounter';
  }

  void _logPerf(
    String operation,
    Stopwatch stopwatch, {
    String? details,
    String? traceTag,
  }) {
    if (!_perfLoggingEnabled) {
      return;
    }
    final tag = traceTag == null || traceTag.isEmpty ? '' : '[$traceTag]';
    final suffix = details == null || details.isEmpty ? '' : ' | $details';
    debugPrint(
      '⏱️ [perf]$tag $operation: ${stopwatch.elapsedMilliseconds} ms$suffix',
    );
  }

  void _showFeedback(String message) {
    if (!mounted) {
      return;
    }
    TransientFeedback.show(context, message: message);
  }

  Future<bool> _openUrlWithPlatformCommand(Uri uri) async {
    final url = uri.toString();
    try {
      if (Platform.isMacOS) {
        await Process.start('/usr/bin/open', [
          url,
        ], mode: ProcessStartMode.detached);
        return true;
      }
      if (Platform.isLinux) {
        await Process.start('xdg-open', [url], mode: ProcessStartMode.detached);
        return true;
      }
      if (Platform.isWindows) {
        await Process.start('cmd', [
          '/c',
          'start',
          '',
          url,
        ], mode: ProcessStartMode.detached);
        return true;
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  Future<bool> _copyTextWithPlatformFallback(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      final check = await Clipboard.getData('text/plain');
      if (check?.text == text) {
        return true;
      }
    } catch (_) {
      // continue with platform fallback
    }

    try {
      Future<bool> writeToCommand(String command, List<String> args) async {
        final process = await Process.start(command, args);
        process.stdin.write(text);
        await process.stdin.close();
        final exitCode = await process.exitCode;
        return exitCode == 0;
      }

      if (Platform.isMacOS) {
        return await writeToCommand('/usr/bin/pbcopy', const []);
      }
      if (Platform.isLinux) {
        final wlCopyOk = await writeToCommand('wl-copy', const []);
        if (wlCopyOk) {
          return true;
        }
        return await writeToCommand('xclip', const ['-selection', 'clipboard']);
      }
      if (Platform.isWindows) {
        return await writeToCommand('cmd', const ['/c', 'clip']);
      }
    } catch (_) {
      return false;
    }

    return false;
  }

  Future<bool> _openMapInBrowser(String mapUrl) async {
    final uri = Uri.tryParse(mapUrl);

    if (uri == null) {
      _showFeedback('Kartenlink ist ungueltig.');
      return false;
    }

    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }

    if (!opened) {
      try {
        opened = await launchUrl(uri, mode: LaunchMode.platformDefault);
      } catch (_) {
        opened = false;
      }
    }

    if (!opened) {
      opened = await _openUrlWithPlatformCommand(uri);
    }

    if (!opened && mounted) {
      _showFeedback('Kartenlink konnte nicht im Browser geoeffnet werden.');
      return false;
    }

    return opened;
  }

  Future<bool> _copyMapLink(String mapUrl) async {
    final copied = await _copyTextWithPlatformFallback(mapUrl);
    if (!mounted) {
      return copied;
    }
    _showFeedback(
      copied
          ? 'Kartenlink wurde in die Zwischenablage kopiert.'
          : 'Kartenlink konnte nicht kopiert werden.',
    );
    return copied;
  }

  @override
  void initState() {
    super.initState();
    final initialCustomerId = widget.initialCustomerId?.trim();
    _pendingInitialCustomerId =
      (initialCustomerId == null || initialCustomerId.isEmpty)
        ? null
        : initialCustomerId;
    _pendingOpenInitialCustomerDetails = widget.openInitialCustomerDetails;
    _repository = widget.customerRepository;
    _orderRepository = widget.orderRepository;
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode(debugLabel: 'customerSearch');
    _customerOrdersScrollController = ScrollController();
    _orderItemsScrollController = ScrollController();
    _searchController.addListener(_onSearchChanged);
    unawaited(_loadCustomerSectionLayoutPrefs());
    if (widget.initializeDatabasePath) {
      _loadDatabasePath();
    }
    _loadCustomers();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchFocusNode.dispose();
    _searchController.dispose();
    _customerOrdersScrollController.dispose();
    _orderItemsScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadDatabasePath() async {
    try {
      // Initialisiert die DB (inkl. Migration in den Zielordner),
      // die UI zeigt danach den konfigurierten Pfad an.
      await AppDatabase.instance.database;
      if (!mounted) {
        return;
      }
      final activePath = AppDatabase.instance.activeDatabasePath;
      final preferredPath = DatabasePathConfig.preferredDatabasePath;
      final resolvedPath =
          (activePath == null || activePath.trim().isEmpty)
              ? (preferredPath ?? 'Pfad unbekannt')
              : activePath;
      final fallbackActive =
          preferredPath != null &&
          preferredPath.trim().isNotEmpty &&
          resolvedPath.trim().isNotEmpty &&
          resolvedPath != preferredPath;
      setState(() {
        _databasePath = resolvedPath;
        _preferredDatabasePath = preferredPath;
        _databasePathFallbackActive = fallbackActive;
        _databaseStatusMessage = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      final preferredPath = DatabasePathConfig.preferredDatabasePath;
      setState(() {
        _databasePath = 'Pfad konnte nicht geladen werden';
        _databasePathFallbackActive = false;
        _preferredDatabasePath = preferredPath;
        _databaseStatusMessage =
            'SQLite-Initialisierung fehlgeschlagen: $error'
            '${preferredPath == null ? '' : '\nBevorzugter Pfad: $preferredPath'}';
      });
      // Continue with loading, even if DB init failed
      await _loadCustomers();
    }
  }

  Future<void> _loadCustomers({bool runBackgroundNormalization = true}) async {
    final traceTag = _nextPerfTraceTag('load');
    final totalStopwatch = Stopwatch()..start();
    setState(() => _loading = true);
    try {
      final fetchStopwatch = Stopwatch()..start();
      final customers = await _repository.getAll();
      final countries = await _repository.getAllCountries();
      List<OrderRow> orders = [];
      try {
        orders = await _orderRepository.getOrders();
      } catch (orderError) {
        if (_perfLoggingEnabled) {
          debugPrint('⚠️ [perf][$traceTag] orders for netto-sum failed: $orderError');
        }
      }
      fetchStopwatch.stop();

      final customerNetById = <String, double>{};
      for (final order in orders) {
        final customerId = order.oCustomerId.trim();
        if (customerId.isEmpty) {
          continue;
        }
        final orderNet = computeEffectiveOrderNetGoods(order);
        customerNetById.update(
          customerId,
          (value) => value + orderNet,
          ifAbsent: () => orderNet,
        );
      }

      final indexStopwatch = Stopwatch()..start();
      final countryNameByCode = <String, String>{
        for (final country in countries)
          country.coTld.toLowerCase(): country.coName,
      };
      final customerSearchIndex = customers
          .map(_buildSearchIndex)
          .toList(growable: false);
      indexStopwatch.stop();

      if (!mounted) {
        return;
      }
      setState(() {
        _customers = customers;
        _customerNetById = customerNetById;
        _customerSearchIndex = customerSearchIndex;
        _countryNameByCode = countryNameByCode;
        _lastFilterQuery = '';
        _lastFilteredIndices = List<int>.generate(
          customers.length,
          (index) => index,
        );
      });

      final pendingInitialCustomerId = _pendingInitialCustomerId;
      if (pendingInitialCustomerId != null) {
        final initialCustomer = customers.cast<Customer?>().firstWhere(
              (customer) => _isSameCustomerId(
                customer?.cId,
                pendingInitialCustomerId,
              ),
              orElse: () => null,
            );
        _pendingInitialCustomerId = null;
        if (initialCustomer != null) {
          await _selectCustomer(initialCustomer);
          if (_pendingOpenInitialCustomerDetails && mounted) {
            _pendingOpenInitialCustomerDetails = false;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) {
                return;
              }
              _showCustomerDetails(initialCustomer);
            });
          }
        }
      }

      _filterCustomers(traceTag: traceTag);

      _logPerf(
        'load/fetch',
        fetchStopwatch,
        details:
            'customers=${customers.length}, countries=${countries.length}, orders=${orders.length}',
        traceTag: traceTag,
      );
      _logPerf(
        'load/index',
        indexStopwatch,
        details: 'searchEntries=${customerSearchIndex.length}',
        traceTag: traceTag,
      );

      if (runBackgroundNormalization && widget.enableBackgroundNormalization) {
        unawaited(
          _runAdministrativeUnitNormalizationInBackground(
            traceTag: traceTag,
          ),
        );
      }
    } catch (error) {
      if (_perfLoggingEnabled) {
        debugPrint('⚠️ [perf][$traceTag] load failed: $error');
      }
      if (!mounted) {
        return;
      }
      _showFeedback('Kunden konnten nicht geladen werden: $error');
    } finally {
      totalStopwatch.stop();
      _logPerf('load/total', totalStopwatch, traceTag: traceTag);
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _runAdministrativeUnitNormalizationInBackground({
    String? traceTag,
  }) async {
    if (_adminUnitNormalizationRunning) {
      return;
    }

    _adminUnitNormalizationRunning = true;
    final stopwatch = Stopwatch()..start();
    try {
      final normalizedCount = await _repository.normalizeItalianAdministrativeUnits();

      if (_perfLoggingEnabled) {
        debugPrint(
          '⏱️ [perf]${traceTag == null ? '' : '[$traceTag]'} normalize/background: $normalizedCount updates',
        );
      }

      if (normalizedCount > 0 && mounted) {
        await _loadCustomers(runBackgroundNormalization: false);
      }
    } catch (error) {
      if (_perfLoggingEnabled) {
        debugPrint(
          '⚠️ [perf]${traceTag == null ? '' : '[$traceTag]'} normalize/background failed: $error',
        );
      }
    } finally {
      stopwatch.stop();
      _logPerf('normalize/background', stopwatch, traceTag: traceTag);
      _adminUnitNormalizationRunning = false;
    }
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    final traceTag = _nextPerfTraceTag('search');
    _searchDebounce = Timer(
      const Duration(milliseconds: 260),
      () => _filterCustomers(traceTag: traceTag),
    );
  }

  String _buildSearchIndex(Customer c) {
    return [
      c.cId,
      c.cLastName,
      c.cFirstName,
      c.cCompany,
      c.cCityB,
      c.cCityD,
      c.cMail,
      c.cPhone,
      c.cStreetB,
      c.cStreetD,
      c.cPostalCodeB,
      c.cPostalCodeD,
      c.cCountryBId ?? '',
      c.cCountryDId ?? '',
    ].join('|').toLowerCase();
  }

  void _filterCustomers({String? traceTag}) {
    final stopwatch = Stopwatch()..start();
    final query = _searchController.text.toLowerCase().trim();

    final maxLength = _customers.length < _customerSearchIndex.length
        ? _customers.length
        : _customerSearchIndex.length;

    List<int> candidateIndices;
    if (query.isNotEmpty &&
        _lastFilterQuery.isNotEmpty &&
        query.startsWith(_lastFilterQuery)) {
      candidateIndices = _lastFilteredIndices;
    } else {
      candidateIndices = List<int>.generate(maxLength, (index) => index);
    }

    List<int> filteredIndices;
    if (query.isEmpty) {
      filteredIndices = List<int>.generate(maxLength, (index) => index);
    } else {
      final results = <int>[];
      for (final index in candidateIndices) {
        if (index < maxLength && _customerSearchIndex[index].contains(query)) {
          results.add(index);
        }
      }
      filteredIndices = results;
    }

    final filtered = filteredIndices
        .map((index) => _customers[index])
        .toList(growable: false);

    _applyCurrentSort(filtered);

    if (!mounted) return;
    setState(() {
      _filteredCustomers = filtered;
      _lastFilterQuery = query;
      _lastFilteredIndices = filteredIndices;
    });

    stopwatch.stop();
    _logPerf(
      'search/filter',
      stopwatch,
      details:
          'queryLen=${query.length}, candidates=${candidateIndices.length}, matches=${filtered.length}',
      traceTag: traceTag,
    );
  }

  void _applyLocalCustomerChange(
    Customer customer, {
    required bool remove,
    String? traceTag,
  }) {
    final stopwatch = Stopwatch()..start();
    final updatedCustomers = List<Customer>.from(_customers);
    if (remove) {
      updatedCustomers.removeWhere((item) => item.cId == customer.cId);
    } else {
      final existingIndex = updatedCustomers.indexWhere(
        (item) => item.cId == customer.cId,
      );
      if (existingIndex >= 0) {
        updatedCustomers[existingIndex] = customer;
      } else {
        updatedCustomers.add(customer);
      }
    }

    final updatedCountryMap = Map<String, String>.from(_countryNameByCode);
    void ensureCountry(String? code) {
      final normalized = code?.trim().toLowerCase();
      if (normalized == null || normalized.isEmpty || normalized == '-') {
        return;
      }
      updatedCountryMap.putIfAbsent(normalized, () => normalized.toUpperCase());
    }

    if (!remove) {
      ensureCountry(customer.cCountryBId);
      ensureCountry(customer.cCountryDId);
    }

    setState(() {
      _customers = updatedCustomers;
      _countryNameByCode = updatedCountryMap;
      _customerSearchIndex = updatedCustomers
          .map(_buildSearchIndex)
          .toList(growable: false);
      _lastFilterQuery = '';
      _lastFilteredIndices = List<int>.generate(
        updatedCustomers.length,
        (index) => index,
      );
    });

    _filterCustomers(traceTag: traceTag);
    stopwatch.stop();
    _logPerf(
      'local/update',
      stopwatch,
      details:
          'remove=$remove, total=${updatedCustomers.length}, id=${customer.cId}',
      traceTag: traceTag,
    );
  }

  void _sortFilteredCustomers(
    int columnIndex,
    bool ascending,
  ) {
    final sorted = List<Customer>.from(_filteredCustomers);
    _sortColumnIndex = columnIndex;
    _sortAscending = ascending;
    _applyCurrentSort(sorted);

    setState(() {
      _filteredCustomers = sorted;
    });
  }

  String _formatMoney(double value) {
    return value.toStringAsFixed(2).replaceAll('.', ',');
  }

  String _formatDate(String raw) {
    final value = raw.trim();
    return value.isEmpty ? '-' : value;
  }

  String _customerNameForOrder(String customerId) {
    final normalized = customerId.trim();
    if (normalized.isEmpty) {
      return '-';
    }

    final customer = _customers.cast<Customer?>().firstWhere(
          (candidate) => _isSameCustomerId(candidate?.cId, normalized),
          orElse: () => null,
        );
    if (customer == null) {
      return normalized;
    }

    final fullName = '${customer.cLastName}, ${customer.cFirstName}'.trim();
    return fullName.isEmpty || fullName == ',' ? normalized : fullName;
  }

  double _itemNetTotal(ItemOrderedRow item) {
    final selectedOrderId = _selectedOrderId;
    if (selectedOrderId == null) {
      return item.ioTotalPrice;
    }

    OrderRow? order;
    for (final candidate in _selectedCustomerOrders) {
      if (candidate.oId == selectedOrderId) {
        order = candidate;
        break;
      }
    }

    if (order == null) {
      return item.ioTotalPrice;
    }

    final isGrossBasis = order.oPriceBasis.trim().toLowerCase() == 'gross';
    if (!isGrossBasis) {
      return item.ioTotalPrice;
    }

    final divisor = 1 + (order.oVatRate / 100);
    if (divisor <= 0) {
      return item.ioTotalPrice;
    }

    return item.ioTotalPrice / divisor;
  }

  Future<void> _selectCustomer(Customer customer) async {
    setState(() {
      _selectedCustomerId = customer.cId;
      _selectedOrderId = null;
      _selectedCustomerOrders = const [];
      _selectedOrderItems = const [];
      _selectedOrderItemCountByOrderId = const {};
    });

    try {
      final orders = await _orderRepository.getOrders();
      final customerOrders = orders
          .where((order) => order.oCustomerId == customer.cId)
          .toList(growable: false)
        ..sort((a, b) => b.oId.compareTo(a.oId));
      final itemCountsByOrderId = await _orderRepository.getItemCountsByOrderIds(
        customerOrders.map((order) => order.oId),
      );

      if (!mounted || !_isSameCustomerId(_selectedCustomerId, customer.cId)) {
        return;
      }

      setState(() {
        _selectedCustomerOrders = customerOrders;
        _selectedOrderItemCountByOrderId = itemCountsByOrderId;
      });
    } catch (error) {
      if (!mounted || !_isSameCustomerId(_selectedCustomerId, customer.cId)) {
        return;
      }
      _showFeedback('Aufträge konnten nicht geladen werden: $error');
    }
  }

  Future<void> _selectOrder(OrderRow order) async {
    setState(() {
      _selectedOrderId = order.oId;
      _selectedOrderItems = const [];
    });

    try {
      final items = await _orderRepository.getItemsForOrder(order.oId);
      if (!mounted || _selectedOrderId != order.oId) {
        return;
      }
      setState(() {
        _selectedOrderItems = items;
        final updatedCounts = Map<String, int>.from(_selectedOrderItemCountByOrderId);
        updatedCounts[order.oId] = items.length;
        _selectedOrderItemCountByOrderId = updatedCounts;
      });
    } catch (error) {
      if (!mounted || _selectedOrderId != order.oId) {
        return;
      }
      _showFeedback('Auftragspositionen konnten nicht geladen werden: $error');
    }
  }

  Future<void> _jumpToCustomerOrder(OrderRow order) async {
    if (!mounted) {
      return;
    }

    final currentCustomerId = _selectedCustomerId ?? order.oCustomerId;
    final currentOrderId = _selectedOrderId ?? order.oId;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OrderPage(initialOrderId: order.oId),
      ),
    );

    if (!mounted) {
      return;
    }

    await _loadCustomers(runBackgroundNormalization: false);
    if (!mounted) {
      return;
    }

    final refreshedCustomer = _customers.cast<Customer?>().firstWhere(
          (customer) => _isSameCustomerId(customer?.cId, currentCustomerId),
          orElse: () => null,
        );
    if (refreshedCustomer == null) {
      return;
    }

    await _selectCustomer(refreshedCustomer);
    if (!mounted) {
      return;
    }

    final refreshedOrder = _selectedCustomerOrders.cast<OrderRow?>().firstWhere(
          (candidate) => candidate?.oId == currentOrderId,
          orElse: () => null,
        );
    if (refreshedOrder == null) {
      return;
    }

    await _selectOrder(refreshedOrder);
  }

  Future<void> _showCustomerDetails(Customer customer) {
    return showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CustomerDetailDialog(
        customer: customer,
        countryNameByCode: _countryNameByCode,
        onEdit: () => _editCustomer(customer),
        onDelete: () => _deleteCustomer(customer),
      ),
    );
  }

  Widget _buildCustomerOrdersTable() {
    if (_selectedCustomerId == null) {
      return const Center(child: Text('Kunde auswählen, um Aufträge zu sehen.'));
    }
    if (_selectedCustomerOrders.isEmpty) {
      return const Center(child: Text('Keine Aufträge für diesen Kunden vorhanden.'));
    }

    return Scrollbar(
      controller: _customerOrdersScrollController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _customerOrdersScrollController,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            showCheckboxColumn: false,
            columns: const [
              DataColumn(label: Text('ID')),
              DataColumn(label: Text('Kunde')),
              DataColumn(label: Text('Datum')),
              DataColumn(label: Text('Netto €'), numeric: true),
              DataColumn(label: Text('Pos.'), numeric: true),
              DataColumn(label: Text('Go')),
            ],
            rows: _selectedCustomerOrders.map((order) {
              final isSelected = _selectedOrderId == order.oId;
              final itemCount = _selectedOrderItemCountByOrderId[order.oId] ?? 0;
              return DataRow(
                selected: isSelected,
                onSelectChanged: (_) => _selectOrder(order),
                cells: [
                  DataCell(Text(order.oId)),
                  DataCell(Text(_customerNameForOrder(order.oCustomerId))),
                  DataCell(Text(_formatDate(order.oDate))),
                  DataCell(Text(_formatMoney(computeEffectiveOrderNetGoods(order)))),
                  DataCell(Text(itemCount.toString())),
                  DataCell(
                    IconButton(
                      tooltip: 'Zu diesem Auftrag springen',
                      icon: const Icon(CupertinoIcons.arrow_turn_down_right),
                      onPressed: () => _jumpToCustomerOrder(order),
                    ),
                  ),
                ],
              );
            }).toList(growable: false),
          ),
        ),
      ),
    );
  }

  Widget _buildOrderItemsTable() {
    if (_selectedOrderId == null) {
      return const Center(child: Text('Auftrag auswählen, um Positionen zu sehen.'));
    }
    if (_selectedOrderItems.isEmpty) {
      return const Center(child: Text('Keine Positionen für diesen Auftrag vorhanden.'));
    }

    return Scrollbar(
      controller: _orderItemsScrollController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _orderItemsScrollController,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Auftrags-ID')),
              DataColumn(label: Text('Pos.')),
              DataColumn(label: Text('Art.-ID')),
              DataColumn(label: Text('Bez.')),
              DataColumn(label: Text('Menge'), numeric: true),
              DataColumn(label: Text('∑ Netto €'), numeric: true),
            ],
            rows: _selectedOrderItems.map((item) {
              return DataRow(
                cells: [
                  DataCell(Text(item.ioOrderId)),
                  DataCell(Text(item.ioPos.toString().padLeft(2, '0'))),
                  DataCell(Text(item.ioItemId.toString())),
                  DataCell(Text(item.ioIdi)),
                  DataCell(Text(item.ioQuantity.toString())),
                  DataCell(Text(_formatMoney(_itemNetTotal(item)))),
                ],
              );
            }).toList(growable: false),
          ),
        ),
      ),
    );
  }

  void _applyCurrentSort(List<Customer> customers) {
    switch (_sortColumnIndex) {
      case 0:
        customers.sort(
          (a, b) => _sortAscending
              ? a.cId.toLowerCase().compareTo(b.cId.toLowerCase())
              : b.cId.toLowerCase().compareTo(a.cId.toLowerCase()),
        );
        break;
      case 1:
        customers.sort((a, b) => _sortAscending
            ? (_customerNetById[a.cId.trim()] ?? a.cTotalValueEur).compareTo(
                _customerNetById[b.cId.trim()] ?? b.cTotalValueEur,
              )
            : (_customerNetById[b.cId.trim()] ?? b.cTotalValueEur).compareTo(
                _customerNetById[a.cId.trim()] ?? a.cTotalValueEur,
              ));
        break;
      case 2:
        customers.sort(
          (a, b) => _sortAscending
              ? a.cLastName.toLowerCase().compareTo(b.cLastName.toLowerCase())
              : b.cLastName.toLowerCase().compareTo(a.cLastName.toLowerCase()),
        );
        break;
      case 3:
        customers.sort(
          (a, b) => _sortAscending
              ? a.cFirstName.toLowerCase().compareTo(b.cFirstName.toLowerCase())
              : b.cFirstName.toLowerCase().compareTo(
                  a.cFirstName.toLowerCase(),
                ),
        );
        break;
      case 4:
        customers.sort(
          (a, b) => _sortAscending
              ? a.cCompany.toLowerCase().compareTo(b.cCompany.toLowerCase())
              : b.cCompany.toLowerCase().compareTo(a.cCompany.toLowerCase()),
        );
        break;
      case 5:
        customers.sort(
          (a, b) => _sortAscending
              ? a.cCityB.toLowerCase().compareTo(b.cCityB.toLowerCase())
              : b.cCityB.toLowerCase().compareTo(a.cCityB.toLowerCase()),
        );
        break;
      case 6:
        customers.sort((a, b) {
          final aVal = resolveDisplayCountry(
            customer: a,
            countryNameByCode: _countryNameByCode,
          ).toLowerCase();
          final bVal = resolveDisplayCountry(
            customer: b,
            countryNameByCode: _countryNameByCode,
          ).toLowerCase();
          return _sortAscending ? aVal.compareTo(bVal) : bVal.compareTo(aVal);
        });
        break;
      case 7:
        customers.sort(
          (a, b) => _sortAscending
              ? a.cMail.toLowerCase().compareTo(b.cMail.toLowerCase())
              : b.cMail.toLowerCase().compareTo(a.cMail.toLowerCase()),
        );
        break;
      default:
        break;
    }
  }

  Widget _buildMobileCustomerList() {
    return ListView.separated(
      itemCount: _filteredCustomers.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final c = _filteredCustomers[index];
        final countryName = resolveDisplayCountry(
          customer: c,
          countryNameByCode: _countryNameByCode,
        );
        final subtitle = [
          if (c.cCompany.isNotEmpty && c.cCompany != '-') c.cCompany,
          if (c.cCityB.isNotEmpty) c.cCityB,
          if (countryName.isNotEmpty) countryName,
        ].join(' · ');
        return CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => _showCustomerDetails(c),
          child: Container(
            decoration: BoxDecoration(
              color: CupertinoColors.secondarySystemGroupedBackground
                  .resolveFrom(context),
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${c.cLastName}, ${c.cFirstName}',
                        style: CupertinoTheme.of(context).textTheme.textStyle
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                      if (subtitle.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: CupertinoTheme.of(
                              context,
                            ).textTheme.tabLabelTextStyle,
                          ),
                        ),
                    ],
                  ),
                ),
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  minimumSize: const Size(28, 28),
                  onPressed: () => _showMapDialog(c),
                  child: const Icon(CupertinoIcons.map_pin_ellipse),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showDataActionsSheet() async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Datenaktionen'),
        message: const Text('Import, Export und Bereinigung auswaehlen.'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              if (_loading) {
                return;
              }
              Navigator.of(sheetContext).pop();
              _exportCsv();
            },
            child: const Text('Customers exportieren'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              if (_loading) {
                return;
              }
              Navigator.of(sheetContext).pop();
              _exportLocationsCsv();
            },
            child: const Text('Customers locations exportieren'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              if (_loading) {
                return;
              }
              Navigator.of(sheetContext).pop();
              _importCsv();
            },
            child: const Text('Customers als CSV importieren'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              if (_loading) {
                return;
              }
              Navigator.of(sheetContext).pop();
              _importCsvWithReplacement();
            },
            child: const Text('Customers importieren (Bestand loeschen)'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              if (_loading) {
                return;
              }
              Navigator.of(sheetContext).pop();
              _exportCountryCsv();
            },
            child: const Text('Laender exportieren'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              if (_loading) {
                return;
              }
              Navigator.of(sheetContext).pop();
              _importCountryCsv();
            },
            child: const Text('Laender importieren'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              if (_loading) {
                return;
              }
              Navigator.of(sheetContext).pop();
              _cleanupInvalidCountriesWithPreview();
            },
            child: const Text('Ungueltige Laender bereinigen'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('Abbrechen'),
        ),
      ),
    );
  }

  void _showAllLocationsDialog() {
    final validCustomers = _filteredCustomers
        .where(
          (c) =>
              !((c.cLat == 0 && c.cLon == 0) || c.cLat.isNaN || c.cLon.isNaN),
        )
        .toList();

    if (validCustomers.isEmpty) {
      _showFeedback(
        'Keine gueltigen Koordinaten in der aktuellen Liste vorhanden.',
      );
      return;
    }

    final markers = validCustomers
        .map(
          (c) => Marker(
            width: 36,
            height: 36,
            point: LatLng(c.cLat, c.cLon),
            child: Tooltip(
              message: '${c.cLastName}, ${c.cFirstName}',
              child: const Icon(
                Icons.location_pin,
                color: Colors.red,
                size: 34,
              ),
            ),
          ),
        )
        .toList();

    final lats = validCustomers.map((c) => c.cLat);
    final lons = validCustomers.map((c) => c.cLon);
    final minLat = lats.reduce((a, b) => a < b ? a : b);
    final maxLat = lats.reduce((a, b) => a > b ? a : b);
    final minLon = lons.reduce((a, b) => a < b ? a : b);
    final maxLon = lons.reduce((a, b) => a > b ? a : b);
    final center = LatLng((minLat + maxLat) / 2, (minLon + maxLon) / 2);
    final geojsonFeatures = validCustomers
        .map((c) {
          final name = '${c.cLastName}, ${c.cFirstName}'.replaceAll('"', '\\"');
          return '{"type":"Feature","geometry":{"type":"Point","coordinates":[${c.cLon},${c.cLat}]},"properties":{"name":"$name"}}';
        })
        .join(',');
    final geojson =
        '{"type":"FeatureCollection","features":[$geojsonFeatures]}';
    final mapUrl =
        'https://geojson.io/#data=data:application/json,${Uri.encodeComponent(geojson)}';

    final mapController = MapController();
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = (screenSize.width * 0.90).clamp(320.0, 1000.0);
    final mapHeight = (screenSize.height * 0.50).clamp(250.0, 400.0);

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Alle Locations (${validCustomers.length})'),
        content: SizedBox(
          width: dialogWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: mapHeight,
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: mapController,
                        options: MapOptions(
                          initialCenter: center,
                          initialZoom: validCustomers.length == 1 ? 14 : 4,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.example.arrow_ops',
                            errorTileCallback: (tile, error, stackTrace) {
                              debugPrint(
                                'Tile konnte nicht geladen werden (${tile.coordinates}): $error',
                              );
                            },
                          ),
                          MarkerLayer(markers: markers),
                        ],
                      ),
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Material(
                              color: Colors.white,
                              elevation: 2,
                              borderRadius: BorderRadius.circular(4),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(4),
                                onTap: () => mapController.move(
                                  mapController.camera.center,
                                  mapController.camera.zoom + 1,
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.all(6),
                                  child: Icon(Icons.add, size: 20),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Material(
                              color: Colors.white,
                              elevation: 2,
                              borderRadius: BorderRadius.circular(4),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(4),
                                onTap: () => mapController.move(
                                  mapController.camera.center,
                                  mapController.camera.zoom - 1,
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.all(6),
                                  child: Icon(Icons.remove, size: 20),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await _copyMapLink(mapUrl);
            },
            icon: const Icon(Icons.copy),
            label: const Text('Link kopieren'),
          ),
          TextButton.icon(
            onPressed: () async {
              final opened = await _openMapInBrowser(mapUrl);
              if (opened && dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
            icon: const Icon(Icons.open_in_new),
            label: const Text('Im Browser öffnen'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  }

  void _showMapDialog(Customer customer) {
    final lat = customer.cLat;
    final lon = customer.cLon;

    if ((lat == 0 && lon == 0) || lat.isNaN || lon.isNaN) {
      _showFeedback('Keine gueltigen Koordinaten vorhanden.');
      return;
    }

    final mapUrl =
        'https://www.openstreetmap.org/?mlat=$lat&mlon=$lon#map=17/$lat/$lon';
    final location = LatLng(lat, lon);
    final mapController = MapController();
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = (screenSize.width * 0.85).clamp(300.0, 760.0);
    final mapHeight = (screenSize.height * 0.40).clamp(180.0, 320.0);

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Location: ${customer.cLastName}, ${customer.cFirstName}'),
        content: SizedBox(
          width: dialogWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: mapHeight,
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: mapController,
                        options: MapOptions(
                          initialCenter: location,
                          initialZoom: 16,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.example.arrow_ops',
                            errorTileCallback: (tile, error, stackTrace) {
                              debugPrint(
                                'Tile konnte nicht geladen werden (${tile.coordinates}): $error',
                              );
                            },
                          ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                width: 42,
                                height: 42,
                                point: location,
                                child: const Icon(
                                  Icons.location_pin,
                                  color: Colors.red,
                                  size: 40,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Material(
                              color: Colors.white,
                              elevation: 2,
                              borderRadius: BorderRadius.circular(4),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(4),
                                onTap: () => mapController.move(
                                  mapController.camera.center,
                                  mapController.camera.zoom + 1,
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.all(6),
                                  child: Icon(Icons.add, size: 20),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Material(
                              color: Colors.white,
                              elevation: 2,
                              borderRadius: BorderRadius.circular(4),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(4),
                                onTap: () => mapController.move(
                                  mapController.camera.center,
                                  mapController.camera.zoom - 1,
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.all(6),
                                  child: Icon(Icons.remove, size: 20),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SelectableText('Lat: $lat, Lon: $lon'),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: SelectableText(
                  mapUrl,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await _copyMapLink(mapUrl);
            },
            icon: const Icon(Icons.copy),
            label: const Text('Link kopieren'),
          ),
          TextButton.icon(
            onPressed: () async {
              final opened = await _openMapInBrowser(mapUrl);
              if (opened && dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
            icon: const Icon(Icons.open_in_new),
            label: const Text('Im Browser oeffnen'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Schliessen'),
          ),
        ],
      ),
    );
  }

  Future<String?> _defaultPickerDirectory() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      if (await docs.exists()) {
        return docs.path;
      }
    } catch (_) {
      // Fallback to platform default dialog location.
    }
    return null;
  }

  Future<void> _importCsv({bool replaceExisting = false}) async {
    setState(() => _loading = true);
    try {
      debugPrint('📂 Öffne FilePicker...');
      final initialDirectory = await _defaultPickerDirectory();
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        withData: true,
        dialogTitle: 'CSV-Datei zum Importieren auswählen',
        initialDirectory: initialDirectory,
      );

      if (result.isEmpty) {
        debugPrint('⊘ FilePicker: Keine Datei ausgewählt');
        return;
      }

      final file = result.single;
      debugPrint('✅ Datei ausgewählt: ${file.name}');

      final content = file.path != null
          ? await File(file.path!).readAsString()
          : utf8.decode(await file.readAsBytes());

      debugPrint('📖 Datei gelesen: ${content.length} Zeichen');
      await _processImport(content, replaceExisting: replaceExisting);
    } catch (error, stackTrace) {
      debugPrint('❌ FilePicker-Fehler: $error');
      debugPrint('📍 Stack: $stackTrace');
      if (!mounted) {
        return;
      }
      _showFeedback('Dateiauswahl fehlgeschlagen: $error');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _importCsvWithReplacement() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Bestand vor Import löschen?'),
        content: const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'Der bestehende Kundenbestand wird vor dem Import vollständig gelöscht. Fortfahren?',
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Abbrechen'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Löschen und importieren'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    await _importCsv(replaceExisting: true);
  }

  Future<void> _processImport(
    String content, {
    bool replaceExisting = false,
  }) async {
    final customers = _csvService.importCustomers(content);

    if (!mounted) {
      return;
    }

    if (customers.isEmpty) {
      _showFeedback('Keine gültigen Kundendaten in der Datei gefunden.');
      return;
    }

    // Validiere Kundendaten
    final validCustomers = <Customer>[];
    final invalidRows = <int>[];

    for (int i = 0; i < customers.length; i++) {
      final c = customers[i];
      if (c.cId.isEmpty || c.cLastName.isEmpty || c.cFirstName.isEmpty) {
        invalidRows.add(i);
      } else {
        validCustomers.add(c);
      }
    }

    if (invalidRows.isNotEmpty) {
      debugPrint('⚠️ ${invalidRows.length} ungültige Reihen: $invalidRows');
    }

    if (validCustomers.isEmpty) {
      if (!mounted) {
        return;
      }
      _showFeedback('Keine gültigen Kundendaten nach Validierung gefunden.');
      return;
    }

    // Zeige Vorschau
    if (!mounted) {
      return;
    }

    await showCupertinoDialog(
      context: context,
      builder: (context) => CsvImportPreviewDialog(
        customers: validCustomers,
        replaceExisting: replaceExisting,
        onConfirm: () async {
          await _performImport(
            validCustomers,
            replaceExisting: replaceExisting,
          );
        },
      ),
    );
  }

  Future<void> _performImport(
    List<Customer> customers, {
    bool replaceExisting = false,
  }) async {
    setState(() => _loading = true);
    try {
      debugPrint(
        '🔄 Starte Import von ${customers.length} Kundendatensätzen...',
      );
      debugPrint(
        '📋 Erste Kundin: ${customers.isNotEmpty ? customers.first.cLastName : "keine"}',
      );

      var deleted = 0;
      if (replaceExisting) {
        deleted = await _repository.deleteAllCustomers();
        debugPrint(
          '🗑️ Vor Import wurden $deleted bestehende Kundendatensätze gelöscht',
        );
      }

      final inserted = await _repository.bulkUpsert(customers);

      debugPrint('✅ Import erfolgreich: $inserted Datensätze');

      await _loadCustomers();

      if (!mounted) {
        return;
      }
      _showFeedback(
        replaceExisting
            ? '$inserted Kundendatensätze importiert, $deleted alte Datensätze gelöscht.'
            : '$inserted Kundendatensätze importiert.',
      );
    } catch (error, stackTrace) {
      debugPrint('⚠️ Import-Fehler: $error');
      debugPrint('📍 Stack: $stackTrace');
      debugPrint('Type: ${error.runtimeType}');
      if (!mounted) {
        return;
      }
      _showFeedback('Import fehlgeschlagen: $error');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _exportCsv() async {
    setState(() => _loading = true);
    try {
      final customers = await _repository.getAll();
      final csv = _csvService.exportCustomers(customers);
      final initialDirectory = await _defaultPickerDirectory();

      final fileName =
          'customer_export_${DateTime.now().toIso8601String().replaceAll(':', '-')}.csv';

      String? targetPath;

      if (Platform.isMacOS) {
        targetPath = (await FilePicker.saveFile(
          dialogTitle: 'CSV exportieren',
          fileName: fileName,
          initialDirectory: initialDirectory,
          type: FileType.custom,
          allowedExtensions: const ['csv'],
          bytes: Uint8List(0),
        ))?.toFilePath();
      }

      targetPath ??= p.join(
        (await getApplicationDocumentsDirectory()).path,
        fileName,
      );

      await File(targetPath).writeAsString(csv);

      if (!mounted) {
        return;
      }
      _showFeedback('CSV exportiert nach: $targetPath');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showFeedback('Export fehlgeschlagen: $error');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _csvEscape(String value) {
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }

  String _countryNameFromDeliveryCode(
    String? countryCode,
    Map<String, String> countryNameByCode,
  ) {
    final normalized = countryCode?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty || normalized == '-') {
      return '';
    }
    return countryNameByCode[normalized] ?? normalized.toUpperCase();
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

  Future<void> _exportLocationsCsv() async {
    setState(() => _loading = true);
    try {
      final customers = await _repository.getAll();
      final countries = await _repository.getAllCountries();
      final countryNameByCode = <String, String>{
        for (final country in countries)
          country.coTld.toLowerCase(): country.coName,
      };

      final buffer = StringBuffer('street,zip,city,country,lat,lon\n');
      for (final customer in customers) {
        final street = customer.cStreetD.trim();
        final zip = customer.cPostalCodeD.trim();
        final city = customer.cCityD.trim();
        final country = _countryNameFromDeliveryCode(
          customer.cCountryDId,
          countryNameByCode,
        );
        final lat = customer.cLat.toString();
        final lon = customer.cLon.toString();

        buffer.writeln(
          '${_csvEscape(street)},${_csvEscape(zip)},${_csvEscape(city)},${_csvEscape(country)},${_csvEscape(lat)},${_csvEscape(lon)}',
        );
      }

      final initialDirectory = await _defaultPickerDirectory();
      final fileName =
          'af_locations_${_buildFileTimestamp(DateTime.now())}.csv';

      String? targetPath;
      if (Platform.isMacOS) {
        targetPath = (await FilePicker.saveFile(
          dialogTitle: 'Customers locations als CSV exportieren',
          fileName: fileName,
          initialDirectory: initialDirectory,
          type: FileType.custom,
          allowedExtensions: const ['csv'],
          bytes: Uint8List(0),
        ))?.toFilePath();
      }

      targetPath ??= p.join(
        (await getApplicationDocumentsDirectory()).path,
        fileName,
      );
      await File(targetPath).writeAsString(buffer.toString());

      if (!mounted) {
        return;
      }
      _showFeedback('Locations-CSV exportiert nach: $targetPath');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showFeedback('Locations-Export fehlgeschlagen: $error');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _exportCountryCsv() async {
    setState(() => _loading = true);
    try {
      final countries = await _repository.getAllCountries();
      final exportedCodes = <String>{};
      final buffer = StringBuffer('co_tld,co_name\n');
      for (final country in countries) {
        final tld = country.coTld.trim().toLowerCase();
        if (!_validCountryCodePattern.hasMatch(tld)) {
          continue;
        }
        if (!exportedCodes.add(tld)) {
          continue;
        }
        final name = country.coName.trim();
        buffer.writeln('${_csvEscape(tld)},${_csvEscape(name)}');
      }

      final fileName =
          'country_tld_export_${DateTime.now().toIso8601String().replaceAll(':', '-')}.csv';
      final initialDirectory = await _defaultPickerDirectory();

      String? targetPath;
      if (Platform.isMacOS) {
        targetPath = (await FilePicker.saveFile(
          dialogTitle: 'Länder als CSV exportieren',
          fileName: fileName,
          initialDirectory: initialDirectory,
          type: FileType.custom,
          allowedExtensions: const ['csv'],
          bytes: Uint8List(0),
        ))?.toFilePath();
      }

      targetPath ??= p.join(
        (await getApplicationDocumentsDirectory()).path,
        fileName,
      );
      await File(targetPath).writeAsString(buffer.toString());

      if (!mounted) {
        return;
      }
      _showFeedback('Länder-CSV exportiert nach: $targetPath');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showFeedback('Länder-Export fehlgeschlagen: $error');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _cleanupInvalidCountriesWithPreview() async {
    setState(() => _loading = true);
    try {
      final countries = await _repository.getAllCountries();
      final customers = await _repository.getAll();

      final referencedCodes = <String>{
        for (final c in customers)
          ...[
            c.cCountryBId?.trim().toLowerCase() ?? '',
            c.cCountryDId?.trim().toLowerCase() ?? '',
          ].where((code) => code.isNotEmpty),
      };

      final invalidCountries =
          countries.where((country) {
            final code = country.coTld.trim().toLowerCase();
            return !_validCountryCodePattern.hasMatch(code);
          }).toList()..sort(
            (a, b) => a.coTld.toLowerCase().compareTo(b.coTld.toLowerCase()),
          );

      if (!mounted) {
        return;
      }

      if (invalidCountries.isEmpty) {
        _showFeedback('Keine ungültigen Länder-Codes gefunden.');
        return;
      }

      final deletable = <CountryTld>[];
      final blocked = <CountryTld>[];

      for (final country in invalidCountries) {
        final code = country.coTld.trim().toLowerCase();
        if (referencedCodes.contains(code)) {
          blocked.add(country);
        } else {
          deletable.add(country);
        }
      }

      String formatCountries(List<CountryTld> entries) {
        if (entries.isEmpty) {
          return '-';
        }
        return entries
            .map(
              (entry) =>
                  '${entry.coTld.trim().toLowerCase()} (${entry.coName.trim()})',
            )
            .join('\n');
      }

      final confirmed = await showCupertinoDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return CupertinoAlertDialog(
            title: const Text('Ungültige Länder-Codes bereinigen'),
            content: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Gefunden: ${invalidCountries.length} ungültige Einträge',
                    ),
                    const SizedBox(height: 10),
                    Text('Werden gelöscht (${deletable.length}):'),
                    const SizedBox(height: 4),
                    Text(
                      formatCountries(deletable),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Nicht löschbar wegen Kundenreferenzen (${blocked.length}):',
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatCountries(blocked),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Abbrechen'),
              ),
              CupertinoDialogAction(
                isDestructiveAction: true,
                onPressed: () {
                  if (deletable.isEmpty) {
                    return;
                  }
                  Navigator.of(dialogContext).pop(true);
                },
                child: const Text('Löschen'),
              ),
            ],
          );
        },
      );

      if (confirmed != true) {
        return;
      }

      final deleted = await _repository.deleteCountriesByCodes(
        deletable.map((entry) => entry.coTld).toList(),
      );
      await _loadCustomers();

      if (!mounted) {
        return;
      }
      _showFeedback(
        '$deleted ungültige Länder gelöscht. ${blocked.length} waren referenziert und wurden übersprungen.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showFeedback('Bereinigung fehlgeschlagen: $error');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _importCountryCsv() async {
    setState(() => _loading = true);
    try {
      final initialDirectory = await _defaultPickerDirectory();
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        dialogTitle: 'country_tld.csv auswählen',
        initialDirectory: initialDirectory,
      );

      if (result.isEmpty) {
        return;
      }

      final file = result.single;
      final path = file.path;
      if (path == null || path.isEmpty) {
        throw Exception('Dateipfad konnte nicht gelesen werden.');
      }

      final content = await File(path).readAsString();
      final countries = _countryCsvService.importCountries(content);

      if (countries.isEmpty) {
        if (!mounted) {
          return;
        }
        _showFeedback('Keine gültigen Länder in country_tld.csv gefunden.');
        return;
      }

      final inserted = await _repository.bulkUpsertCountries(countries);

      if (!mounted) {
        return;
      }
      _showFeedback('$inserted Länder importiert.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showFeedback('country_tld Import fehlgeschlagen: $error');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _createCustomer() async {
    final countries = await _repository.getAllCountries();
    if (!mounted) return;

    final result = await showCupertinoDialog<Customer>(
      context: context,
      builder: (context) => CustomerFormDialog(countries: countries),
    );

    if (result == null) {
      return;
    }

    setState(() => _loading = true);
    final traceTag = _nextPerfTraceTag('save/create');
    final totalStopwatch = Stopwatch()..start();
    try {
      debugPrint('➕ Erstelle neuen Kundendatensatz: ${result.cId}');

      final dbStopwatch = Stopwatch()..start();
      await _repository.upsert(result);
      dbStopwatch.stop();

      debugPrint('✅ Kunde erstellt: ${result.cLastName}, ${result.cFirstName}');
      _applyLocalCustomerChange(result, remove: false, traceTag: traceTag);
      _logPerf(
        'save/create-db',
        dbStopwatch,
        details: 'id=${result.cId}',
        traceTag: traceTag,
      );

      if (!mounted) {
        return;
      }
      _showFeedback(
        'Kunde erstellt: ${result.cLastName}, ${result.cFirstName}',
      );
    } catch (error) {
      debugPrint('❌ Fehler beim Erstellen: $error');
      if (!mounted) {
        return;
      }
      _showFeedback('Fehler beim Erstellen: $error');
    } finally {
      totalStopwatch.stop();
      _logPerf(
        'save/create-total',
        totalStopwatch,
        details: 'id=${result.cId}',
        traceTag: traceTag,
      );
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _editCustomer(Customer customer) async {
    final countries = await _repository.getAllCountries();
    if (!mounted) return;

    final result = await showCupertinoDialog<Customer>(
      context: context,
      builder: (context) =>
          CustomerFormDialog(customer: customer, countries: countries),
    );

    if (result == null) {
      return;
    }

    setState(() => _loading = true);
    final traceTag = _nextPerfTraceTag('save/edit');
    final totalStopwatch = Stopwatch()..start();
    try {
      debugPrint('✏️ Aktualisiere Kundendatensatz: ${result.cId}');

      final dbStopwatch = Stopwatch()..start();
      await _repository.update(result);
      dbStopwatch.stop();

      debugPrint(
        '✅ Kunde aktualisiert: ${result.cLastName}, ${result.cFirstName}',
      );
      _applyLocalCustomerChange(result, remove: false, traceTag: traceTag);
      _logPerf(
        'save/edit-db',
        dbStopwatch,
        details: 'id=${result.cId}',
        traceTag: traceTag,
      );

      if (!mounted) {
        return;
      }
      _showFeedback(
        'Kunde aktualisiert: ${result.cLastName}, ${result.cFirstName}',
      );
    } catch (error) {
      debugPrint('❌ Fehler beim Aktualisieren: $error');
      if (!mounted) {
        return;
      }
      _showFeedback('Fehler beim Aktualisieren: $error');
    } finally {
      totalStopwatch.stop();
      _logPerf(
        'save/edit-total',
        totalStopwatch,
        details: 'id=${result.cId}',
        traceTag: traceTag,
      );
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _deleteCustomer(Customer customer) async {
    setState(() => _loading = true);
    final traceTag = _nextPerfTraceTag('save/delete');
    final totalStopwatch = Stopwatch()..start();
    try {
      debugPrint('🗑️ Lösche Kundendatensatz: ${customer.cId}');

      final dbStopwatch = Stopwatch()..start();
      await _repository.delete(customer.cId);
      dbStopwatch.stop();

      debugPrint(
        '✅ Kunde gelöscht: ${customer.cLastName}, ${customer.cFirstName}',
      );
      _applyLocalCustomerChange(customer, remove: true, traceTag: traceTag);
      _logPerf(
        'save/delete-db',
        dbStopwatch,
        details: 'id=${customer.cId}',
        traceTag: traceTag,
      );

      if (!mounted) {
        return;
      }
      _showFeedback(
        'Kunde gelöscht: ${customer.cLastName}, ${customer.cFirstName}',
      );
    } catch (error) {
      debugPrint('❌ Fehler beim Löschen: $error');
      if (!mounted) {
        return;
      }
      _showFeedback('Fehler beim Löschen: $error');
    } finally {
      totalStopwatch.stop();
      _logPerf(
        'save/delete-total',
        totalStopwatch,
        details: 'id=${customer.cId}',
        traceTag: traceTag,
      );
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tickerMode = TickerMode.valuesOf(context);
    final isVisibleInShell = tickerMode.enabled;
    if (
        widget.reloadOnVisibilityChange &&
        isVisibleInShell &&
        !_wasVisibleInBuild &&
        !_loading) {
      unawaited(_loadCustomers(runBackgroundNormalization: false));
    }
    _wasVisibleInBuild = isVisibleInShell;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Arrow Ops'),
        centerTitle: false,
        actions: [
          if (widget.showModuleNavigation)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              onPressed: _loading
                  ? null
                  : () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ItemCataloguePage(),
                        ),
                      );
                    },
              child: const Row(
                children: [
                  Icon(CupertinoIcons.cube_box, size: 20),
                  SizedBox(width: 6),
                  Text('Artikel'),
                ],
              ),
            ),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            onPressed: _showDataActionsSheet,
            child: const Row(
              children: [
                Icon(CupertinoIcons.ellipsis_circle, size: 20),
                SizedBox(width: 6),
                Text('Daten'),
              ],
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CustomerPageActions(
              loading: _loading,
              databasePath: _databasePath,
              databasePathFallbackActive: _databasePathFallbackActive,
              preferredDatabasePath: _preferredDatabasePath,
              databaseStatusMessage: _databaseStatusMessage,
              searchController: _searchController,
              searchFocusNode: _searchFocusNode,
              onSearchChanged: (_) => _onSearchChanged(),
              onCreateCustomer: _createCustomer,
              onRefresh: _loadCustomers,
            ),
            const SizedBox(height: 16),
            CustomerResultsHeader(
              searchText: _searchController.text,
              totalCount: _customers.length,
              filteredCount: _filteredCustomers.length,
              onShowAllLocations: _filteredCustomers.isEmpty
                  ? null
                  : _showAllLocationsDialog,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CupertinoActivityIndicator(radius: 14))
                  : _customers.isEmpty
                  ? const Center(
                      child: Text('Noch keine Kundendaten vorhanden.'),
                    )
                  : _filteredCustomers.isEmpty
                  ? const Center(
                      child: Text(
                        'Keine Kunden gefunden, die dem Suchbegriff entsprechen.',
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        if (constraints.maxWidth < 600) {
                          return _buildMobileCustomerList();
                        }
                        return _buildDesktopCustomerLayout(constraints);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
