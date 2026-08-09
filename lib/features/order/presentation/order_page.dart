import 'dart:io';

import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../customer/data/customer_repository.dart';
import '../../item/data/item_image_storage_service.dart';
import '../../customer/domain/customer.dart';
import '../../customer/domain/country_tld.dart';
import '../../customer/presentation/customer_page.dart';
import '../../item/domain/item_models.dart';
import '../data/order_repository.dart';
import '../domain/order_models.dart';
import 'widgets/item_ordered_form_dialog.dart';
import 'widgets/order_form_dialog.dart';

class HtsCodeCellContent extends StatelessWidget {
  const HtsCodeCellContent({
    super.key,
    required this.code,
    required this.onOpen,
    this.onDoubleTap,
  });

  final String code;
  final VoidCallback onOpen;
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onDoubleTap: onDoubleTap,
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              code,
              maxLines: 1,
              style: const TextStyle(
                color: Colors.blue,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
          Tooltip(
            message: 'HTS im Browser oeffnen',
            child: IconButton(
              visualDensity: VisualDensity.compact,
              splashRadius: 16,
              iconSize: 16,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              onPressed: onOpen,
              icon: const Icon(Icons.open_in_new),
            ),
          ),
        ],
      ),
    );
  }
}

class OrderPage extends StatefulWidget {
  const OrderPage({super.key, this.initialOrderId});

  final String? initialOrderId;

  @override
  State<OrderPage> createState() => _OrderPageState();
}

@visibleForTesting
String buildItemSelectionKey(ItemOrderedRow item) {
  final id = item.ioId;
  if (id != null) {
    return 'id:$id';
  }
  return 'fallback:${item.ioOrderId}|${item.ioPos}|${item.ioItemId}|${item.ioIdi}';
}

@visibleForTesting
int resolveEffectivePaymentCode({
  required int plannedPaymentCode,
  required int? actualPaymentCode,
}) {
  return actualPaymentCode ?? plannedPaymentCode;
}

@visibleForTesting
bool hasPaymentOverride({
  required int plannedPaymentCode,
  required int? actualPaymentCode,
}) {
  return actualPaymentCode != null && actualPaymentCode != plannedPaymentCode;
}

@visibleForTesting
String buildPaymentDisplayLabel({
  required int plannedPaymentCode,
  required int? actualPaymentCode,
}) {
  final plannedLabel = _paymentLabelFromCode(plannedPaymentCode);
  final actualCode = actualPaymentCode;
  if (actualCode == null || actualCode == plannedPaymentCode) {
    return plannedLabel;
  }
  final actualLabel = _paymentLabelFromCode(actualCode);
  return '$plannedLabel -> $actualLabel';
}

String _paymentLabelFromCode(int code) {
  const labels = ['Sonstiges', 'PayPal', 'Banküberweisung', 'Kreditkarte', 'Bar'];
  if (code < 0 || code >= labels.length) return code.toString();
  return labels[code];
}

enum _OrderStatusQuickFilter {
  all,
  paidNotShipped,
  shippedNotPaid,
}

class _OrderPageState extends State<OrderPage> {
  final _orderRepo = const OrderRepository();
  final _customerRepo = const CustomerRepository();
  final _imageStorage = const ItemImageStorageService();

  List<OrderRow> _orders = [];
  List<ItemOrderedRow> _items = [];
  List<Customer> _allCustomers = [];
  List<CountryTld> _allCountries = [];
  Map<String, Customer> _customerById = {};

  bool _loading = true;
  String? _loadError;
  String? _selectedOrderId;
  String? _selectedItemOrderedKey;

  int _orderSortColumnIndex = 0;
  bool _orderSortAscending = false;
  _OrderStatusQuickFilter _orderStatusQuickFilter = _OrderStatusQuickFilter.all;
  final TextEditingController _orderSearchController = TextEditingController();
  String _orderSearchQuery = '';
  final ScrollController _ordersVerticalController = ScrollController();
  final ScrollController _ordersHorizontalController = ScrollController();
  final ScrollController _itemsVerticalController = ScrollController();
  final ScrollController _itemsHorizontalController = ScrollController();
  double _splitterRatio = 0.55;
  bool _isDragging = false;
  String? _pendingInitialOrderId;

  static const double _splitterHeight = 28.0;
  static const double _minTopHeight = 200.0;
  static const double _minBottomHeight = 140.0;
  static const int _cashPaymentCode = 4;

  String _itemSelectionKey(ItemOrderedRow item) {
    return buildItemSelectionKey(item);
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initialOrderId?.trim();
    _pendingInitialOrderId = (initial == null || initial.isEmpty)
        ? null
        : initial;
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final orders = await _orderRepo.getOrders();
      final customers = await _customerRepo.getAll();
      final countries = await _customerRepo.getAllCountries();
      final customerMap = {for (final c in customers) c.cId: c};

      String? nextSelectedId = _selectedOrderId;
      final pendingInitialId = _pendingInitialOrderId;
      if (pendingInitialId != null &&
          orders.any((order) => order.oId == pendingInitialId)) {
        nextSelectedId = pendingInitialId;
      }
      if (nextSelectedId == null || !orders.any((o) => o.oId == nextSelectedId)) {
        nextSelectedId = orders.isEmpty ? null : orders.first.oId;
      }
      _pendingInitialOrderId = null;

      List<ItemOrderedRow> items = [];
      if (nextSelectedId != null) {
        items = await _orderRepo.getItemsForOrder(nextSelectedId);
      }

      String? nextSelectedItemKey = _selectedItemOrderedKey;
      if (nextSelectedItemKey == null ||
          !items.any((item) => _itemSelectionKey(item) == nextSelectedItemKey)) {
        nextSelectedItemKey =
            items.isEmpty ? null : _itemSelectionKey(items.first);
      }

      if (!mounted) return;
      setState(() {
        _orders = orders;
        _allCustomers = customers;
        _allCountries = countries;
        _customerById = customerMap;
        _selectedOrderId = nextSelectedId;
        _items = items;
        _selectedItemOrderedKey = nextSelectedItemKey;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Aufträge konnten nicht geladen werden: $error';
        _orders = [];
        _items = [];
        _selectedOrderId = null;
        _selectedItemOrderedKey = null;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _orderSearchController.dispose();
    _ordersVerticalController.dispose();
    _ordersHorizontalController.dispose();
    _itemsVerticalController.dispose();
    _itemsHorizontalController.dispose();
    super.dispose();
  }

  Future<void> _loadItemsForSelected() async {
    final id = _selectedOrderId;
    if (id == null) {
      setState(() => _items = []);
      return;
    }
    try {
      final items = await _orderRepo.getItemsForOrder(id);
      if (!mounted) return;
      setState(() {
        _items = items;
        if (_selectedItemOrderedKey == null ||
            !items.any((item) => _itemSelectionKey(item) == _selectedItemOrderedKey)) {
          _selectedItemOrderedKey =
              items.isEmpty ? null : _itemSelectionKey(items.first);
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _items = [];
        _selectedItemOrderedKey = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Positionen konnten nicht geladen werden: $error')),
      );
    }
  }

  Future<void> _refreshSelectedOrderFromItems() async {
    final order = _selectedOrder;
    if (order == null) {
      return;
    }

    final items = await _orderRepo.getItemsForOrder(order.oId);
    final summedItemsValue = items.fold<double>(
      0,
      (sum, item) => sum + item.ioTotalPrice,
    );
    final summedItemsWeight = items.fold<double>(
      0,
      (sum, item) => sum + item.ioTotalWeight,
    );

    final vatRate = order.oVatRate;
    final isGrossBasis = order.oPriceBasis.trim().toLowerCase() == 'gross';

    final double valueGoods;
    final double vat;
    if (order.oPutt != 0 && order.oPayment == _cashPaymentCode) {
      valueGoods = summedItemsValue;
      vat = 0;
    } else if (isGrossBasis) {
      final divisor = 1 + (vatRate / 100);
      valueGoods = divisor <= 0 ? summedItemsValue : summedItemsValue / divisor;
      vat = summedItemsValue - valueGoods;
    } else {
      valueGoods = summedItemsValue;
      vat = vatRate <= 0 ? 0 : valueGoods * (vatRate / 100);
    }

    final totalPrice = (order.oPutt != 0 && order.oPayment == _cashPaymentCode)
        ? summedItemsValue
        : valueGoods + vat + order.oShipping + order.oPaypalFee;

    final updatedOrder = order.copyWith(
      oValueGoods: valueGoods,
      oVat: vat,
      oTotalWeight: summedItemsWeight,
      oTotalPrice: totalPrice,
    );

    await _orderRepo.saveOrder(updatedOrder);
    await _loadData();
  }

  String _customerName(String customerId) {
    final c = _customerById[customerId];
    if (c == null) return customerId;
    return '${c.cLastName}, ${c.cFirstName}';
  }

  String _customerCompany(String customerId) {
    final c = _customerById[customerId];
    if (c == null) {
      return '';
    }
    final company = c.cCompany.trim();
    if (company.isEmpty || company == '-') {
      return '';
    }
    return company;
  }

  Future<bool> _openMapInBrowser(String mapUrl) async {
    final uri = Uri.tryParse(mapUrl);
    if (uri == null) {
      return false;
    }
    for (final mode in [LaunchMode.externalApplication, LaunchMode.platformDefault]) {
      try {
        if (await launchUrl(uri, mode: mode)) {
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  void _showOrderDeliveryMapDialog(OrderRow order) {
    final lat = order.oDeliveryLat;
    final lon = order.oDeliveryLon;

    if ((lat == 0 && lon == 0) || lat.isNaN || lon.isNaN) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keine gültigen Koordinaten für Lieferadresse vorhanden.')),
      );
      return;
    }

    final mapUrl = 'https://www.openstreetmap.org/?mlat=$lat&mlon=$lon#map=17/$lat/$lon';
    final location = LatLng(lat, lon);
    final mapController = MapController();
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = (screenSize.width * 0.85).clamp(300.0, 760.0);
    final mapHeight = (screenSize.height * 0.40).clamp(180.0, 320.0);
    final label = _endCustomerLabel(order) == 'Dito'
        ? _customerName(order.oCustomerId)
        : _endCustomerLabel(order);

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Location: $label'),
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
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.example.arrow_ops',
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
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await _openMapInBrowser(mapUrl);
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            icon: const Icon(Icons.open_in_new),
            label: const Text('Im Browser öffnen'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Schliessen'),
          ),
        ],
      ),
    );
  }

  String _endCustomerLabel(OrderRow order) {
    if (order.oDeliveryAddressDifferent == 0) {
      return 'Dito';
    }

    final name = order.oDeliveryName.trim();
    final city = order.oDeliveryCity.trim();
    final safeName = (name.isEmpty || name == '-') ? '-' : name;
    final safeCity = (city.isEmpty || city == '-') ? '-' : city;
    return '$safeName, $safeCity';
  }

  String _puttLabel(int value) => value != 0 ? 'Ja' : '-';

  String _formatDate(String raw) => raw.trim().isEmpty ? '-' : raw.trim();

  Uri _trackingUri(String trackingCode) {
    final encodedTrackingCode = Uri.encodeComponent(trackingCode.trim());
    return Uri.parse('https://parcelsapp.com/de/tracking/$encodedTrackingCode');
  }

  String _trackingCodeForLink(String rawTrackingCode) {
    final normalized = rawTrackingCode.trim();
    if (normalized.isEmpty || normalized == '-') {
      return '';
    }

    var candidate = normalized;
    final firstWhitespace = normalized.indexOf(RegExp(r'\s'));
    if (firstWhitespace >= 0 && firstWhitespace + 1 < normalized.length) {
      candidate = normalized.substring(firstWhitespace + 1).trimLeft();
    }

    if (candidate.isEmpty) {
      return '';
    }

    final firstToken = candidate.split(RegExp(r'\s+')).first.trim();
    final alphanumericOnly = firstToken.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    return alphanumericOnly;
  }

  Future<void> _openTrackingCode(String trackingCode) async {
    final normalized = _trackingCodeForLink(trackingCode);
    if (normalized.isEmpty) {
      return;
    }

    final launched = await launchUrl(
      _trackingUri(normalized),
      mode: LaunchMode.externalApplication,
    );

    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tracking-Link konnte nicht geöffnet werden: $normalized')),
      );
    }
  }

  Widget _buildTrackingCodeCell(String trackingCode) {
    final normalized = _trackingCodeForLink(trackingCode);
    if (normalized.isEmpty) {
      return const Text('-');
    }

    return InkWell(
      onTap: () => _openTrackingCode(normalized),
      child: Text(
        normalized,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.blue,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }

  String _formatDecimal(double v, int digits) =>
      v.toStringAsFixed(digits).replaceAll('.', ',');

  bool _isUsdOrder(OrderRow order) {
    return order.oCurrency.trim().toUpperCase() == 'USD';
  }

  double? _orderNetValueEur(OrderRow order) {
    if (_isUsdOrder(order)) {
      if (order.oFxToEur <= 0) {
        return null;
      }
      return order.oValueGoods * order.oFxToEur;
    }
    return order.oValueGoods;
  }

  String _formatOrderNetValueEur(OrderRow order) {
    final value = _orderNetValueEur(order);
    if (value == null) {
      return '-';
    }
    return _formatDecimal(value, 2);
  }

  Uri _htsUri(String htsCode) {
    final encodedHtsCode = Uri.encodeComponent(htsCode.trim());
    return Uri.parse('https://www.zolltarifnummern.de/2026/$encodedHtsCode');
  }

  Future<void> _openHtsUrl(String htsCode) async {
    final normalized = htsCode.trim();
    if (normalized.isEmpty || normalized == '-') {
      return;
    }

    final launched = await launchUrl(
      _htsUri(normalized),
      mode: LaunchMode.externalApplication,
    );

    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('HTS-Link konnte nicht geöffnet werden: $normalized')),
      );
    }
  }

  DataCell _numericCell(
    String value, {
    VoidCallback? onTap,
    VoidCallback? onDoubleTap,
  }) {
    return DataCell(
      Align(
        alignment: Alignment.centerRight,
        child: Text(value),
      ),
      onTap: onTap,
      onDoubleTap: onDoubleTap,
    );
  }

  DataCell _selectableNumericCell(String value) {
    return DataCell(
      SelectionArea(
        child: Align(
          alignment: Alignment.centerRight,
          child: SelectableText(value),
        ),
      ),
    );
  }

  DataCell _currencyCell(
    OrderRow order, {
    VoidCallback? onTap,
    VoidCallback? onDoubleTap,
  }) {
    final isUsd = order.oCurrency.trim().toUpperCase() == 'USD';
    final missingFx = isUsd && order.oFxToEur <= 0;

    return DataCell(
      Row(
        children: [
          Text(order.oCurrency),
          if (missingFx) ...[
            const SizedBox(width: 6),
            const Tooltip(
              message: 'USD ohne gueltigen USD→EUR Kurs',
              child: Icon(
                Icons.warning_amber_rounded,
                size: 16,
                color: Colors.orange,
              ),
            ),
          ],
        ],
      ),
      onTap: onTap,
      onDoubleTap: onDoubleTap,
    );
  }

  DataCell _singleLineCell(
    String value, {
    String? tooltip,
    TextStyle? style,
    VoidCallback? onTap,
    VoidCallback? onDoubleTap,
  }) {
    final label = value.trim().isEmpty ? '-' : value;
    final tooltipText = (tooltip ?? value).trim();
    final textWidget = Text(
      label,
      style: style,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
    );

    return DataCell(
      tooltipText.isEmpty || tooltipText == '-'
          ? textWidget
          : Tooltip(message: tooltipText, child: textWidget),
      onTap: onTap,
      onDoubleTap: onDoubleTap,
    );
  }

  DataCell _htsLinkCell(
    String htsCode, {
    VoidCallback? onDoubleTap,
  }) {
    final normalized = htsCode.trim();
    if (normalized.isEmpty || normalized == '-') {
      return _singleLineCell('-', onDoubleTap: onDoubleTap);
    }

    return DataCell(
      HtsCodeCellContent(
        code: normalized,
        onOpen: () => _openHtsUrl(normalized),
        onDoubleTap: onDoubleTap,
      ),
    );
  }

  Widget _buildOrderedItemImageCell(String imagePath) {
    final normalized = imagePath.trim();
    if (normalized.isEmpty || normalized == '-') {
      return const Text('-');
    }

    return FutureBuilder<String?>(
      future: _imageStorage.resolveAbsolutePath(normalized),
      builder: (context, snapshot) {
        final resolvedPath = snapshot.data?.trim();
        if (resolvedPath == null || resolvedPath.isEmpty) {
          return const Icon(Icons.broken_image_outlined, size: 18);
        }

        final file = File(resolvedPath);
        if (!file.existsSync()) {
          return const Icon(Icons.broken_image_outlined, size: 18);
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: InkWell(
            onTap: () => _showOrderedItemImageDialog(file),
            child: Container(
              width: 40,
              height: 40,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Image.file(
                file,
                fit: BoxFit.contain,
                errorBuilder: (_, error, stackTrace) =>
                    const Icon(Icons.broken_image_outlined, size: 18),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showOrderedItemImageDialog(File file) async {
    if (!file.existsSync()) {
      return;
    }

    final transformController = TransformationController();

    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: 900,
          height: 620,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onDoubleTap: () {
                    transformController.value = Matrix4.identity();
                  },
                  child: InteractiveViewer(
                    transformationController: transformController,
                    minScale: 0.6,
                    maxScale: 5,
                    child: Image.file(
                      file,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => const Center(
                        child: Text('Bild konnte nicht geladen werden.'),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: FilledButton.tonalIcon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  label: const Text('Schliessen'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    transformController.dispose();
  }

  String _paymentLabel(int code) {
    return _paymentLabelFromCode(code);
  }

  int _effectivePaymentCode(OrderRow order) {
    return resolveEffectivePaymentCode(
      plannedPaymentCode: order.oPayment,
      actualPaymentCode: order.oPaymentActual,
    );
  }

  String _paymentDisplayLabel(OrderRow order) {
    return buildPaymentDisplayLabel(
      plannedPaymentCode: order.oPayment,
      actualPaymentCode: order.oPaymentActual,
    );
  }

  bool _hasPaymentOverride(OrderRow order) {
    return hasPaymentOverride(
      plannedPaymentCode: order.oPayment,
      actualPaymentCode: order.oPaymentActual,
    );
  }

  String _positionDescription(ItemOrderedRow item, String orderLanguage) {
    final isGerman = orderLanguage.trim().toUpperCase() == 'DE';
    final primary = isGerman ? item.ioDescriptionDeLong.trim() : item.ioDescriptionEnLong.trim();
    if (primary.isNotEmpty) {
      return primary;
    }

    final fallback = isGerman ? item.ioDescriptionEnLong.trim() : item.ioDescriptionDeLong.trim();
    if (fallback.isNotEmpty) {
      return fallback;
    }

    return '-';
  }

  Future<void> _showPositionDescriptionDialog(String description) async {
    final text = description.trim().isEmpty ? '-' : description.trim();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Beschreibung'),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: SelectableText(text),
          ),
        ),
        actions: [
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Schliessen'),
          ),
        ],
      ),
    );
  }

  bool _matchesOrderSearch(OrderRow order, String normalizedQuery) {
    if (normalizedQuery.isEmpty) {
      return true;
    }

    final haystack = <String>[
      order.oId,
      _customerName(order.oCustomerId),
      _endCustomerLabel(order),
      _customerCompany(order.oCustomerId),
      order.oCustomerId,
      order.oTradeShow,
      _puttLabel(order.oPutt),
      order.oTrackingCode,
      _paymentLabel(order.oPayment),
      _paymentLabel(_effectivePaymentCode(order)),
      _paymentDisplayLabel(order),
      order.oDate,
      order.oPayDate,
      order.oDelivery,
    ].map((value) => value.trim().toLowerCase()).join(' ');

    return haystack.contains(normalizedQuery);
  }

  bool _hasPayDate(OrderRow order) {
    final normalized = order.oPayDate.trim();
    return normalized.isNotEmpty && normalized != '-';
  }

  bool _hasDeliveryDate(OrderRow order) {
    final normalized = order.oDelivery.trim();
    return normalized.isNotEmpty && normalized != '-';
  }

  bool _matchesOrderStatusQuickFilter(OrderRow order) {
    final hasPayDate = _hasPayDate(order);
    final hasDeliveryDate = _hasDeliveryDate(order);
    switch (_orderStatusQuickFilter) {
      case _OrderStatusQuickFilter.all:
        return true;
      case _OrderStatusQuickFilter.paidNotShipped:
        return hasPayDate && !hasDeliveryDate;
      case _OrderStatusQuickFilter.shippedNotPaid:
        return hasDeliveryDate && !hasPayDate;
    }
  }

  List<OrderRow> _sortedOrders() {
    final normalizedQuery = _orderSearchQuery.trim().toLowerCase();
    final result = _orders
        .where((order) => _matchesOrderSearch(order, normalizedQuery))
        .where(_matchesOrderStatusQuickFilter)
        .toList(growable: false);

    if (_orderStatusQuickFilter != _OrderStatusQuickFilter.all) {
      result.sort((a, b) => b.oId.compareTo(a.oId));
      return result;
    }

    result.sort((a, b) {
      int cmp;
      switch (_orderSortColumnIndex) {
        case 0:
          cmp = a.oId.compareTo(b.oId);
        case 1:
          cmp = _customerName(a.oCustomerId)
              .compareTo(_customerName(b.oCustomerId));
        case 2:
          cmp = _endCustomerLabel(a).compareTo(_endCustomerLabel(b));
        case 3:
          cmp = a.oTradeShow.compareTo(b.oTradeShow);
        case 4:
          cmp = a.oPutt.compareTo(b.oPutt);
        case 5:
          cmp = a.oCurrency.compareTo(b.oCurrency);
        case 6:
          cmp = a.oValueGoods.compareTo(b.oValueGoods);
        case 7:
          cmp = a.oVat.compareTo(b.oVat);
        case 8:
          cmp = (a.oValueGoods + a.oVat).compareTo(b.oValueGoods + b.oVat);
        case 9:
          cmp = a.oTotalWeight.compareTo(b.oTotalWeight);
        case 10:
          cmp = a.oShipping.compareTo(b.oShipping);
        case 11:
          cmp = a.oTrackingCode.compareTo(b.oTrackingCode);
        case 12:
          cmp = _effectivePaymentCode(a).compareTo(_effectivePaymentCode(b));
        case 13:
          cmp = a.oPaypalFee.compareTo(b.oPaypalFee);
        case 14:
          cmp = a.oTotalPrice.compareTo(b.oTotalPrice);
        case 15:
          cmp = a.oPayDate.compareTo(b.oPayDate);
        case 16:
          cmp = a.oDelivery.compareTo(b.oDelivery);
        default:
          cmp = a.oId.compareTo(b.oId);
      }
      return _orderSortAscending ? cmp : -cmp;
    });
    return result;
  }

  Future<void> _showOrderForm({OrderRow? initialValue}) async {
    final latestCustomers = await _customerRepo.getAll();
    final latestCountries = await _customerRepo.getAllCountries();
    if (!mounted) return;
    setState(() {
      _allCustomers = latestCustomers;
      _allCountries = latestCountries;
      _customerById = {for (final c in latestCustomers) c.cId: c};
    });

    var canEditOrderId = true;
    var assignedItems = const <ItemOrderedRow>[];
    if (initialValue != null) {
      assignedItems = await _orderRepo.getItemsForOrder(initialValue.oId);
      if (!mounted) return;
      canEditOrderId = assignedItems.isEmpty;
    }

    final result = await showDialog<dynamic>(
      context: context,
      barrierDismissible: false,
      builder: (context) => OrderFormDialog(
        allCustomers: _allCustomers,
        allCountries: _allCountries,
        initialValue: initialValue,
        canEditOrderId: canEditOrderId,
        assignedItems: assignedItems,
      ),
    );

    if (result == 'new_customer') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte zuerst den neuen Kunden anlegen.')),
      );
      return;
    }

    if (result is String && result.startsWith('open_customer:')) {
      final customerId = result.substring('open_customer:'.length).trim();
      if (customerId.isNotEmpty && mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CustomerPage(
              showModuleNavigation: false,
              initialCustomerId: customerId,
              openInitialCustomerDetails: true,
            ),
          ),
        );
      }
      return;
    }

    if (result is! OrderRow) return;

    await _orderRepo.saveOrder(result, originalOrderId: initialValue?.oId);
    if (initialValue != null && initialValue.oLanguage != result.oLanguage) {
      await _orderRepo.syncItemDescriptionsFromCatalogueForOrder(result.oId);
    }
    await _loadData();
    if (!mounted) return;
    setState(() => _selectedOrderId = result.oId);
  }

  Future<void> _deleteOrder(OrderRow order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Auftrag löschen?'),
        content: Text('Auftrag ${order.oId} wird inklusive aller Positionen gelöscht.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _orderRepo.deleteOrder(order.oId);
    await _loadData();
  }

  Future<void> _showItemOrderedForm({ItemOrderedRow? initialValue}) async {
    final order = _selectedOrder;
    if (order == null) {
      return;
    }

    late final List<ItemCatalogueRow> latestSelectableItems;
    try {
      latestSelectableItems = await _orderRepo.getSelectableCatalogueItems();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Artikel konnten nicht geladen werden: $error')),
      );
      return;
    }

    final nextPos = initialValue?.ioPos ?? await _orderRepo.nextItemOrderedPos(order.oId);
    if (!mounted) return;

    final result = await showDialog<ItemOrderedRow>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ItemOrderedFormDialog(
        orderId: order.oId,
        orderLanguage: order.oLanguage,
        orderPriceBasis: order.oPriceBasis,
        isDealerCustomer: order.oDealer == 1,
        availableItems: latestSelectableItems,
        initialPos: nextPos,
        initialValue: initialValue,
      ),
    );

    if (result == null) return;
    await _orderRepo.saveItemOrdered(result);
    await _refreshSelectedOrderFromItems();
  }

  ItemOrderedRow? get _selectedItemOrdered {
      final key = _selectedItemOrderedKey;
      if (key == null) return null;
    return _items.cast<ItemOrderedRow?>().firstWhere(
        (item) => item != null && _itemSelectionKey(item) == key,
          orElse: () => null,
        );
  }

  Future<void> _deleteSelectedItemOrdered() async {
    final selected = _selectedItemOrdered;
    if (selected == null || selected.ioId == null) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Position löschen?'),
        content: Text('Position ${selected.ioPos.toString().padLeft(2, '0')} (${selected.ioIdi}) wird gelöscht.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _orderRepo.deleteItemOrdered(selected.ioId!);
    await _refreshSelectedOrderFromItems();
  }

  void _onOrderSort(int columnIndex, bool ascending) {
    setState(() {
      _orderSortColumnIndex = columnIndex;
      _orderSortAscending = ascending;
    });
  }

  OrderRow? get _selectedOrder {
    final id = _selectedOrderId;
    if (id == null) return null;
    return _orders.cast<OrderRow?>().firstWhere(
          (o) => o?.oId == id,
          orElse: () => null,
        );
  }

  @override
  Widget build(BuildContext context) {
    final loadError = _loadError;
    return Scaffold(
      appBar: AppBar(title: const Text('Aufträge')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(loadError, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _loadData,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Erneut laden'),
                        ),
                      ],
                    ),
                  ),
                )
          : LayoutBuilder(
              builder: (context, constraints) {
                final totalH = constraints.maxHeight;
                final availableH = (totalH - _splitterHeight).clamp(0.0, double.infinity);
                final minCombined = _minTopHeight + _minBottomHeight;

                late final double topH;
                if (availableH <= minCombined) {
                  topH = availableH * _splitterRatio;
                } else {
                  topH = (availableH * _splitterRatio)
                      .clamp(_minTopHeight, availableH - _minBottomHeight);
                }
                final bottomH = (availableH - topH).clamp(0.0, double.infinity);

                return Column(
                  children: [
                    SizedBox(height: topH, child: _buildOrderTable()),
                    _buildSplitter(totalH),
                    SizedBox(height: bottomH, child: _buildItemsTable()),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildSplitter(double totalH) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) => setState(() => _isDragging = true),
      onVerticalDragEnd: (_) => setState(() => _isDragging = false),
      onVerticalDragUpdate: (details) {
        final availableH = (totalH - _splitterHeight).clamp(0.0, double.infinity);
        final minCombined = _minTopHeight + _minBottomHeight;

        setState(() {
          final baseTop = _splitterRatio * availableH;
          final targetTop = baseTop + details.delta.dy;

          late final double newTopH;
          if (availableH <= minCombined) {
            newTopH = targetTop.clamp(0.0, availableH);
          } else {
            newTopH = targetTop.clamp(_minTopHeight, availableH - _minBottomHeight);
          }

          _splitterRatio = availableH <= 0 ? _splitterRatio : (newTopH / availableH);
          _splitterRatio = _splitterRatio.clamp(0.1, 0.9);
        });
      },
      child: Container(
        height: _splitterHeight,
        color: _isDragging
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
            : Theme.of(context).dividerColor.withValues(alpha: 0.15),
        child: const Center(child: Icon(Icons.drag_handle, size: 18)),
      ),
    );
  }

  Widget _buildOrderTable() {
    final sorted = _sortedOrders();
    final showNetEurColumn =
        _orderSearchQuery.trim().isNotEmpty && sorted.any(_isUsdOrder);

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Toolbar
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  _orderSearchQuery.trim().isEmpty
                      ? 'Bestellungen (${_orders.length})'
                      : 'Bestellungen (${sorted.length} / ${_orders.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                FilledButton.icon(
                  onPressed: _loading ? null : () => _showOrderForm(),
                  icon: const Icon(Icons.add),
                  label: const Text('Neu'),
                ),
                OutlinedButton.icon(
                  onPressed: _loading || _selectedOrder == null
                      ? null
                      : () => _showOrderForm(initialValue: _selectedOrder),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Bearbeiten'),
                ),
                OutlinedButton.icon(
                  onPressed: _loading || _selectedOrder == null
                      ? null
                      : () => _deleteOrder(_selectedOrder!),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Löschen'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _orderSearchController,
              decoration: InputDecoration(
                labelText: 'Bestellungen suchen',
                hintText: 'Auftrags-ID, Kunde, Endkunde, Firma, Trade Show, Trackingcode, Zahlart, Datum',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _orderSearchQuery.trim().isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Suche löschen',
                        onPressed: () {
                          _orderSearchController.clear();
                          setState(() => _orderSearchQuery = '');
                        },
                        icon: const Icon(Icons.clear),
                      ),
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _orderSearchQuery = value),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Alle'),
                  selected: _orderStatusQuickFilter == _OrderStatusQuickFilter.all,
                  onSelected: (_) {
                    setState(() {
                      _orderStatusQuickFilter = _OrderStatusQuickFilter.all;
                    });
                  },
                ),
                ChoiceChip(
                  label: const Text('Bezahlt und nicht versendet'),
                  selected: _orderStatusQuickFilter == _OrderStatusQuickFilter.paidNotShipped,
                  onSelected: (_) {
                    setState(() {
                      _orderStatusQuickFilter = _OrderStatusQuickFilter.paidNotShipped;
                    });
                  },
                ),
                ChoiceChip(
                  label: const Text('Versendet und nicht bezahlt'),
                  selected: _orderStatusQuickFilter == _OrderStatusQuickFilter.shippedNotPaid,
                  onSelected: (_) {
                    setState(() {
                      _orderStatusQuickFilter = _OrderStatusQuickFilter.shippedNotPaid;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            // ── Tabelle
            Expanded(
              child: sorted.isEmpty
                  ? const Center(child: Text('Keine Bestellungen vorhanden.'))
                  : DataTable2(
                      showCheckboxColumn: false,
                      sortColumnIndex: _orderSortColumnIndex,
                      sortAscending: _orderSortAscending,
                      scrollController: _ordersVerticalController,
                      horizontalScrollController: _ordersHorizontalController,
                      isVerticalScrollBarVisible: true,
                      isHorizontalScrollBarVisible: true,
                      fixedTopRows: 1,
                      fixedLeftColumns: 3,
                      headingRowHeight: 56,
                      headingRowColor: WidgetStateProperty.resolveWith(
                        (_) => Theme.of(context).colorScheme.surfaceContainerHighest,
                      ),
                      headingTextStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      border: TableBorder(
                        horizontalInside: BorderSide(
                          color: Theme.of(context).dividerColor,
                          width: 0.6,
                        ),
                      ),
                      minWidth: showNetEurColumn ? 2900 : 2760,
                      columns: [
                        DataColumn2(label: const Text('Auftrags-ID'), onSort: _onOrderSort, fixedWidth: 140),
                        DataColumn2(label: const Text('Kunde'), onSort: _onOrderSort, size: ColumnSize.L),
                        DataColumn2(label: const Text('Endkunde'), onSort: _onOrderSort, size: ColumnSize.L),
                        const DataColumn2(label: Text('Map'), fixedWidth: 86),
                        DataColumn2(label: const Text('Trade Show'), onSort: _onOrderSort, size: ColumnSize.M),
                        DataColumn2(label: const Text('Putt'), onSort: _onOrderSort, fixedWidth: 112),
                        DataColumn2(label: const Text('Währung'), onSort: _onOrderSort, fixedWidth: 148),
                        DataColumn2(label: const Text('Netto'), numeric: true, onSort: _onOrderSort, fixedWidth: 120),
                        if (showNetEurColumn)
                          const DataColumn2(
                            label: Text('Netto (EUR)'),
                            numeric: true,
                            fixedWidth: 132,
                          ),
                        DataColumn2(label: const Text('MwSt'), numeric: true, onSort: _onOrderSort, fixedWidth: 120),
                        DataColumn2(label: const Text('Brutto'), numeric: true, onSort: _onOrderSort, fixedWidth: 120),
                        DataColumn2(label: const Text('Gesamtgewicht in g'), numeric: true, onSort: _onOrderSort, fixedWidth: 182),
                        DataColumn2(label: const Text('Versand'), numeric: true, onSort: _onOrderSort, fixedWidth: 132),
                        DataColumn2(label: const Text('Trackingcode'), onSort: _onOrderSort, fixedWidth: 200),
                        DataColumn2(label: const Text('Zahlart (Plan -> Ist)'), onSort: _onOrderSort, fixedWidth: 220),
                        DataColumn2(label: const Text('PayPal-Gebühr'), numeric: true, onSort: _onOrderSort, fixedWidth: 166),
                        DataColumn2(
                          label: const Text('Gesamt-\npreis', textAlign: TextAlign.center),
                          numeric: true,
                          onSort: _onOrderSort,
                          fixedWidth: 176,
                        ),
                        DataColumn2(label: const Text('Bezahlt-Datum'), onSort: _onOrderSort, fixedWidth: 182),
                        DataColumn2(label: const Text('Versand-Datum'), onSort: _onOrderSort, fixedWidth: 178),
                      ],
                      rows: sorted.map((order) {
                        final selected = order.oId == _selectedOrderId;
                        final hasDeliveryDate = order.oDelivery.trim().isNotEmpty;
                        final hasPayDate = order.oPayDate.trim().isNotEmpty;
                        Future<void> handleSelectOrder() async {
                          setState(() => _selectedOrderId = order.oId);
                          await _loadItemsForSelected();
                        }
                        Future<void> handleOpenEdit() async {
                          await handleSelectOrder();
                          if (!mounted) return;
                          await _showOrderForm(initialValue: order);
                        }
                        return DataRow(
                          selected: selected,
                          onSelectChanged: (isSelected) async {
                            if (isSelected != true) {
                              return;
                            }
                            await handleSelectOrder();
                          },
                          cells: [
                            DataCell(
                              Text(order.oId),
                              onTap: () => handleSelectOrder(),
                              onDoubleTap: () => handleOpenEdit(),
                            ),
                            _singleLineCell(_customerName(order.oCustomerId), tooltip: _customerName(order.oCustomerId), onTap: () => handleSelectOrder(), onDoubleTap: () => handleOpenEdit()),
                            _singleLineCell(_endCustomerLabel(order), tooltip: _endCustomerLabel(order), onTap: () => handleSelectOrder(), onDoubleTap: () => handleOpenEdit()),
                            DataCell(
                              Builder(
                                builder: (cellContext) {
                                  final hasCoords = !(order.oDeliveryLat == 0 && order.oDeliveryLon == 0) &&
                                      !order.oDeliveryLat.isNaN &&
                                      !order.oDeliveryLon.isNaN;
                                  return Tooltip(
                                    message: hasCoords
                                        ? 'Lieferadresse auf Karte anzeigen'
                                        : 'Keine Koordinaten vorhanden',
                                    child: IconButton(
                                      onPressed: hasCoords
                                          ? () => _showOrderDeliveryMapDialog(order)
                                          : null,
                                      icon: Icon(
                                        Icons.location_on_outlined,
                                        color: hasCoords
                                            ? Theme.of(cellContext).colorScheme.primary
                                            : Theme.of(cellContext).disabledColor,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            DataCell(Text(order.oTradeShow.trim().isEmpty ? '-' : order.oTradeShow), onTap: () => handleSelectOrder(), onDoubleTap: () => handleOpenEdit()),
                            DataCell(Text(_puttLabel(order.oPutt)), onTap: () => handleSelectOrder(), onDoubleTap: () => handleOpenEdit()),
                            _currencyCell(
                              order,
                              onTap: () => handleSelectOrder(),
                              onDoubleTap: () => handleOpenEdit(),
                            ),
                            _numericCell(_formatDecimal(order.oValueGoods, 2), onTap: () => handleSelectOrder(), onDoubleTap: () => handleOpenEdit()),
                            if (showNetEurColumn)
                              _numericCell(
                                _formatOrderNetValueEur(order),
                                onTap: () => handleSelectOrder(),
                                onDoubleTap: () => handleOpenEdit(),
                              ),
                            _numericCell(_formatDecimal(order.oVat, 2), onTap: () => handleSelectOrder(), onDoubleTap: () => handleOpenEdit()),
                            _numericCell(_formatDecimal(order.oValueGoods + order.oVat, 2), onTap: () => handleSelectOrder(), onDoubleTap: () => handleOpenEdit()),
                            _numericCell(_formatDecimal(order.oTotalWeight, 1), onTap: () => handleSelectOrder(), onDoubleTap: () => handleOpenEdit()),
                            _numericCell(_formatDecimal(order.oShipping, 2), onTap: () => handleSelectOrder(), onDoubleTap: () => handleOpenEdit()),
                            DataCell(_buildTrackingCodeCell(order.oTrackingCode), onTap: () => handleSelectOrder(), onDoubleTap: () => handleOpenEdit()),
                            DataCell(
                              Row(
                                children: [
                                  if (_hasPaymentOverride(order)) ...[
                                    Icon(
                                      Icons.swap_horiz,
                                      size: 16,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                  Expanded(
                                    child: Text(
                                      _paymentDisplayLabel(order),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: _hasPaymentOverride(order)
                                          ? TextStyle(
                                              color: Theme.of(context).colorScheme.primary,
                                              fontWeight: FontWeight.w700,
                                            )
                                          : null,
                                    ),
                                  ),
                                ],
                              ),
                              onTap: () => handleSelectOrder(),
                              onDoubleTap: () => handleOpenEdit(),
                            ),
                            _numericCell(_formatDecimal(order.oPaypalFee, 2), onTap: () => handleSelectOrder(), onDoubleTap: () => handleOpenEdit()),
                            _numericCell(_formatDecimal(order.oTotalPrice, 2), onTap: () => handleSelectOrder(), onDoubleTap: () => handleOpenEdit()),
                            _singleLineCell(
                              _formatDate(order.oPayDate),
                              style: TextStyle(
                                color: hasDeliveryDate ? Colors.black : Colors.green,
                              ),
                              onTap: () => handleSelectOrder(),
                              onDoubleTap: () => handleOpenEdit(),
                            ),
                            _singleLineCell(
                              _formatDate(order.oDelivery),
                              style: TextStyle(
                                color: hasPayDate ? Colors.black : Colors.red,
                              ),
                              onTap: () => handleSelectOrder(),
                              onDoubleTap: () => handleOpenEdit(),
                            ),
                          ],
                        );
                      }).toList(growable: false),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemsTable() {
    final order = _selectedOrder;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  order == null
                      ? 'Positionen (kein Auftrag ausgewählt)'
                      : 'Positionen zu ${order.oId} • ${_customerName(order.oCustomerId)} (${_items.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                FilledButton.icon(
                  onPressed: order == null ? null : () => _showItemOrderedForm(),
                  icon: const Icon(Icons.add),
                  label: const Text('Neu'),
                ),
                OutlinedButton.icon(
                  onPressed: order == null || _selectedItemOrdered == null
                      ? null
                      : () => _showItemOrderedForm(initialValue: _selectedItemOrdered),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Bearbeiten'),
                ),
                OutlinedButton.icon(
                  onPressed: order == null || _selectedItemOrdered == null
                      ? null
                      : _deleteSelectedItemOrdered,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Löschen'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: order == null
                  ? const Center(child: Text('Bitte oben einen Auftrag auswählen.'))
                  : _items.isEmpty
                      ? const Center(child: Text('Keine Positionen vorhanden.'))
                      : DataTable2(
                          showCheckboxColumn: false,
                          scrollController: _itemsVerticalController,
                          horizontalScrollController: _itemsHorizontalController,
                          isVerticalScrollBarVisible: true,
                          isHorizontalScrollBarVisible: true,
                          fixedTopRows: 1,
                          headingRowHeight: 56,
                          headingRowColor: WidgetStateProperty.resolveWith(
                            (_) => Theme.of(context).colorScheme.surfaceContainerHighest,
                          ),
                          headingTextStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          border: TableBorder(
                            horizontalInside: BorderSide(
                              color: Theme.of(context).dividerColor,
                              width: 0.6,
                            ),
                          ),
                          minWidth: 1810,
                          columns: const [
                            DataColumn2(label: Text('Pos.'), fixedWidth: 70),
                            DataColumn2(label: Text('Artikel-ID'), fixedWidth: 126),
                            DataColumn2(label: Text('Bezeichnung'), fixedWidth: 170),
                            DataColumn2(label: Text('Beschreibung'), size: ColumnSize.L),
                            DataColumn2(label: Text('Bild'), fixedWidth: 84),
                            DataColumn2(label: Text('HTS Code'), fixedWidth: 126),
                            DataColumn2(label: Text('Menge'), numeric: true, fixedWidth: 108),
                            DataColumn2(
                              label: Text('Gewicht\nin g'),
                              numeric: true,
                              fixedWidth: 120,
                            ),
                            DataColumn2(
                              label: Text('Gesamtgewicht\nin g'),
                              numeric: true,
                              fixedWidth: 170,
                            ),
                            DataColumn2(label: Text('Einzelpreis'), numeric: true, fixedWidth: 136),
                            DataColumn2(label: Text('Rabatt %'), numeric: true, fixedWidth: 96),
                            DataColumn2(
                              label: Text('Gesamt-\npreis', textAlign: TextAlign.center),
                              numeric: true,
                              fixedWidth: 122,
                            ),
                            DataColumn2(label: Text('Farbe'), size: ColumnSize.M),
                          ],
                          rows: _items.map((item) {
                            final itemSelectionKey = _itemSelectionKey(item);
                            final isSelected = itemSelectionKey == _selectedItemOrderedKey;
                            final description = _positionDescription(item, order.oLanguage);
                            void handleOpenEdit() {
                              setState(() => _selectedItemOrderedKey = itemSelectionKey);
                              _showItemOrderedForm(initialValue: item);
                            }
                            return DataRow(
                              selected: isSelected,
                              onSelectChanged: (_) {
                                setState(() => _selectedItemOrderedKey = itemSelectionKey);
                              },
                              cells: [
                                _numericCell(item.ioPos.toString().padLeft(2, '0'), onDoubleTap: handleOpenEdit),
                                _numericCell(item.ioItemId.toString(), onDoubleTap: handleOpenEdit),
                                _singleLineCell(item.ioIdi, tooltip: item.ioIdi, onDoubleTap: handleOpenEdit),
                                DataCell(
                                  Tooltip(
                                    message: 'Klicken zum Vergroessern',
                                    child: Text(
                                      description,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  onTap: () => _showPositionDescriptionDialog(description),
                                  onDoubleTap: handleOpenEdit,
                                ),
                                DataCell(_buildOrderedItemImageCell(item.ioPhoto), onDoubleTap: handleOpenEdit),
                                _htsLinkCell(item.ioHts, onDoubleTap: handleOpenEdit),
                                _numericCell(item.ioQuantity.toString(), onDoubleTap: handleOpenEdit),
                                _selectableNumericCell(_formatDecimal(item.ioItemWeight, 1)),
                                _numericCell(_formatDecimal(item.ioTotalWeight, 1), onDoubleTap: handleOpenEdit),
                                _selectableNumericCell(_formatDecimal(item.ioUnitPrice, 2)),
                                _numericCell(_formatDecimal(item.ioDiscount, 2), onDoubleTap: handleOpenEdit),
                                _numericCell(_formatDecimal(item.ioTotalPrice, 2), onDoubleTap: handleOpenEdit),
                                DataCell(Text(item.ioColor), onDoubleTap: handleOpenEdit),
                              ],
                            );
                          }).toList(growable: false),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
