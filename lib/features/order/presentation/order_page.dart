import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../customer/data/customer_repository.dart';
import '../../item/data/item_image_storage_service.dart';
import '../../customer/domain/customer.dart';
import '../../item/domain/item_models.dart';
import '../data/order_repository.dart';
import '../domain/order_models.dart';
import 'widgets/item_ordered_form_dialog.dart';
import 'widgets/order_form_dialog.dart';

class OrderPage extends StatefulWidget {
  const OrderPage({super.key});

  @override
  State<OrderPage> createState() => _OrderPageState();
}

class _OrderPageState extends State<OrderPage> {
  final _orderRepo = const OrderRepository();
  final _customerRepo = const CustomerRepository();
  final _imageStorage = const ItemImageStorageService();

  List<OrderRow> _orders = [];
  List<ItemOrderedRow> _items = [];
  List<Customer> _allCustomers = [];
  Map<String, Customer> _customerById = {};

  bool _loading = true;
  String? _loadError;
  String? _selectedOrderId;
  int? _selectedItemOrderedId;

  int _orderSortColumnIndex = 0;
  bool _orderSortAscending = false;
  final TextEditingController _orderSearchController = TextEditingController();
  String _orderSearchQuery = '';
  double _splitterRatio = 0.55;
  bool _isDragging = false;

  static const double _splitterHeight = 28.0;
  static const double _minTopHeight = 200.0;
  static const double _minBottomHeight = 140.0;

  @override
  void initState() {
    super.initState();
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
      final customerMap = {for (final c in customers) c.cId: c};

      String? nextSelectedId = _selectedOrderId;
      if (nextSelectedId == null || !orders.any((o) => o.oId == nextSelectedId)) {
        nextSelectedId = orders.isEmpty ? null : orders.first.oId;
      }

      List<ItemOrderedRow> items = [];
      if (nextSelectedId != null) {
        items = await _orderRepo.getItemsForOrder(nextSelectedId);
      }

      int? nextSelectedItemId = _selectedItemOrderedId;
      if (nextSelectedItemId == null || !items.any((item) => item.ioId == nextSelectedItemId)) {
        nextSelectedItemId = items.isEmpty ? null : items.first.ioId;
      }

      if (!mounted) return;
      setState(() {
        _orders = orders;
        _allCustomers = customers;
        _customerById = customerMap;
        _selectedOrderId = nextSelectedId;
        _items = items;
        _selectedItemOrderedId = nextSelectedItemId;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Aufträge konnten nicht geladen werden: $error';
        _orders = [];
        _items = [];
        _selectedOrderId = null;
        _selectedItemOrderedId = null;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _orderSearchController.dispose();
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
        if (_selectedItemOrderedId == null ||
            !items.any((item) => item.ioId == _selectedItemOrderedId)) {
          _selectedItemOrderedId = items.isEmpty ? null : items.first.ioId;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _items = [];
        _selectedItemOrderedId = null;
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
    if (isGrossBasis) {
      final divisor = 1 + (vatRate / 100);
      valueGoods = divisor <= 0 ? summedItemsValue : summedItemsValue / divisor;
      vat = summedItemsValue - valueGoods;
    } else {
      valueGoods = summedItemsValue;
      vat = vatRate <= 0 ? 0 : valueGoods * (vatRate / 100);
    }

    final totalPrice = valueGoods + vat + order.oShipping + order.oPaypalFee;

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

  String _formatDate(String raw) => raw.trim().isEmpty ? '-' : raw.trim();

  Uri _trackingUri(String trackingCode) {
    final encodedTrackingCode = Uri.encodeComponent(trackingCode.trim());
    return Uri.parse('https://parcelsapp.com/de/tracking/$encodedTrackingCode');
  }

  Future<void> _openTrackingCode(String trackingCode) async {
    final normalized = trackingCode.trim();
    if (normalized.isEmpty || normalized == '-') {
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
    final normalized = trackingCode.trim();
    if (normalized.isEmpty || normalized == '-') {
      return const Text('-');
    }

    return InkWell(
      onTap: () => _openTrackingCode(normalized),
      child: Text(
        normalized,
        style: const TextStyle(
          color: Colors.blue,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }

  String _formatDecimal(double v, int digits) =>
      v.toStringAsFixed(digits).replaceAll('.', ',');

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
        );
      },
    );
  }

  String _paymentLabel(int code) {
    const labels = ['Sonstiges', 'PayPal', 'Banküberweisung', 'Kreditkarte', 'Bar'];
    if (code < 0 || code >= labels.length) return code.toString();
    return labels[code];
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
      order.oCustomerId,
      order.oTrackingCode,
      _paymentLabel(order.oPayment),
      order.oDate,
      order.oPayDate,
      order.oDelivery,
    ].map((value) => value.trim().toLowerCase()).join(' ');

    return haystack.contains(normalizedQuery);
  }

  List<OrderRow> _sortedOrders() {
    final normalizedQuery = _orderSearchQuery.trim().toLowerCase();
    final result = _orders
        .where((order) => _matchesOrderSearch(order, normalizedQuery))
        .toList(growable: false);
    result.sort((a, b) {
      int cmp;
      switch (_orderSortColumnIndex) {
        case 0:
          cmp = a.oId.compareTo(b.oId);
        case 1:
          cmp = _customerName(a.oCustomerId)
              .compareTo(_customerName(b.oCustomerId));
        case 2:
          cmp = a.oCurrency.compareTo(b.oCurrency);
        case 3:
          cmp = a.oValueGoods.compareTo(b.oValueGoods);
        case 4:
          cmp = a.oVat.compareTo(b.oVat);
        case 5:
          cmp = (a.oValueGoods + a.oVat).compareTo(b.oValueGoods + b.oVat);
        case 6:
          cmp = a.oShipping.compareTo(b.oShipping);
        case 7:
          cmp = a.oTrackingCode.compareTo(b.oTrackingCode);
        case 8:
          cmp = a.oPayment.compareTo(b.oPayment);
        case 9:
          cmp = a.oPaypalFee.compareTo(b.oPaypalFee);
        case 10:
          cmp = a.oTotalPrice.compareTo(b.oTotalPrice);
        case 11:
          cmp = a.oPayDate.compareTo(b.oPayDate);
        case 12:
          cmp = a.oDelivery.compareTo(b.oDelivery);
        default:
          cmp = a.oId.compareTo(b.oId);
      }
      return _orderSortAscending ? cmp : -cmp;
    });
    return result;
  }

  Future<void> _showOrderForm({OrderRow? initialValue}) async {
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
    final id = _selectedItemOrderedId;
    if (id == null) return null;
    return _items.cast<ItemOrderedRow?>().firstWhere(
          (item) => item?.ioId == id,
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
                hintText: 'Auftrags-ID, Kunde, Trackingcode, Zahlart, Datum',
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
            // ── Tabelle
            Expanded(
              child: sorted.isEmpty
                  ? const Center(child: Text('Keine Bestellungen vorhanden.'))
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        child: DataTable(
                          showCheckboxColumn: false,
                          sortColumnIndex: _orderSortColumnIndex,
                          sortAscending: _orderSortAscending,
                          columns: [
                            DataColumn(label: const Text('Auftrags-ID'), onSort: _onOrderSort),
                            DataColumn(label: const Text('Kunde'), onSort: _onOrderSort),
                            DataColumn(label: const Text('Währung'), onSort: _onOrderSort),
                            DataColumn(label: const Text('Netto'), numeric: true, onSort: _onOrderSort),
                            DataColumn(label: const Text('MwSt'), numeric: true, onSort: _onOrderSort),
                            DataColumn(label: const Text('Brutto'), numeric: true, onSort: _onOrderSort),
                            DataColumn(label: const Text('Versand'), numeric: true, onSort: _onOrderSort),
                            DataColumn(label: const Text('Trackingcode'), onSort: _onOrderSort),
                            DataColumn(label: const Text('Zahlart'), onSort: _onOrderSort),
                            DataColumn(label: const Text('PayPal-Gebühr'), numeric: true, onSort: _onOrderSort),
                            DataColumn(label: const Text('Gesamtpreis'), numeric: true, onSort: _onOrderSort),
                            DataColumn(label: const Text('Bezahlt-Datum'), onSort: _onOrderSort),
                            DataColumn(label: const Text('Versand-Datum'), onSort: _onOrderSort),
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
                                DataCell(Text(_customerName(order.oCustomerId)), onTap: () => handleSelectOrder(), onDoubleTap: () => handleOpenEdit()),
                                DataCell(Text(order.oCurrency), onTap: () => handleSelectOrder(), onDoubleTap: () => handleOpenEdit()),
                                DataCell(Text(_formatDecimal(order.oValueGoods, 2)), onTap: () => handleSelectOrder(), onDoubleTap: () => handleOpenEdit()),
                                DataCell(Text(_formatDecimal(order.oVat, 2)), onTap: () => handleSelectOrder(), onDoubleTap: () => handleOpenEdit()),
                                DataCell(Text(_formatDecimal(order.oValueGoods + order.oVat, 2)), onTap: () => handleSelectOrder(), onDoubleTap: () => handleOpenEdit()),
                                DataCell(Text(_formatDecimal(order.oShipping, 2)), onTap: () => handleSelectOrder(), onDoubleTap: () => handleOpenEdit()),
                                DataCell(_buildTrackingCodeCell(order.oTrackingCode), onTap: () => handleSelectOrder(), onDoubleTap: () => handleOpenEdit()),
                                DataCell(Text(_paymentLabel(order.oPayment)), onTap: () => handleSelectOrder(), onDoubleTap: () => handleOpenEdit()),
                                DataCell(Text(_formatDecimal(order.oPaypalFee, 2)), onTap: () => handleSelectOrder(), onDoubleTap: () => handleOpenEdit()),
                                DataCell(Text(_formatDecimal(order.oTotalPrice, 2)), onTap: () => handleSelectOrder(), onDoubleTap: () => handleOpenEdit()),
                                DataCell(
                                  Text(
                                    _formatDate(order.oPayDate),
                                    style: TextStyle(
                                      color: hasDeliveryDate ? Colors.black : Colors.green,
                                    ),
                                  ),
                                  onTap: () => handleSelectOrder(),
                                  onDoubleTap: () => handleOpenEdit(),
                                ),
                                DataCell(
                                  Text(
                                    _formatDate(order.oDelivery),
                                    style: TextStyle(
                                      color: hasPayDate ? Colors.black : Colors.red,
                                    ),
                                  ),
                                  onTap: () => handleSelectOrder(),
                                  onDoubleTap: () => handleOpenEdit(),
                                ),
                              ],
                            );
                          }).toList(growable: false),
                        ),
                      ),
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
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SingleChildScrollView(
                            child: DataTable(
                              showCheckboxColumn: false,
                              columns: const [
                                DataColumn(label: Text('Pos.')),
                                DataColumn(label: Text('Artikel-\nID', textAlign: TextAlign.center)),
                                DataColumn(label: Text('Bezeichnung')),
                                DataColumn(label: Text('Beschreibung')),
                                DataColumn(label: Text('HTS Code')),
                                DataColumn(label: Text('Gesamtgewicht\nin g', textAlign: TextAlign.center), numeric: true),
                                DataColumn(label: Text('Bild')),
                                DataColumn(label: Text('Menge'), numeric: true),
                                DataColumn(label: Text('Einzelpreis'), numeric: true),
                                DataColumn(label: Text('Rabatt %'), numeric: true),
                                DataColumn(label: Text('Gesamt-\npreis', textAlign: TextAlign.center), numeric: true),
                                DataColumn(label: Text('Farbe')),
                              ],
                              rows: _items.map((item) {
                                final isSelected = item.ioId != null && item.ioId == _selectedItemOrderedId;
                                final description = _positionDescription(item, order.oLanguage);
                                void handleOpenEdit() {
                                  setState(() => _selectedItemOrderedId = item.ioId);
                                  _showItemOrderedForm(initialValue: item);
                                }
                                return DataRow(
                                  selected: isSelected,
                                  onSelectChanged: (_) {
                                    setState(() => _selectedItemOrderedId = item.ioId);
                                  },
                                  cells: [
                                    DataCell(Text(item.ioPos.toString().padLeft(2, '0')), onDoubleTap: handleOpenEdit),
                                    DataCell(Text(item.ioItemId.toString()), onDoubleTap: handleOpenEdit),
                                    DataCell(Text(item.ioIdi), onDoubleTap: handleOpenEdit),
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
                                    DataCell(Text(item.ioHts), onDoubleTap: handleOpenEdit),
                                    DataCell(Text(_formatDecimal(item.ioTotalWeight, 1)), onDoubleTap: handleOpenEdit),
                                    DataCell(_buildOrderedItemImageCell(item.ioPhoto), onDoubleTap: handleOpenEdit),
                                    DataCell(Text(item.ioQuantity.toString()), onDoubleTap: handleOpenEdit),
                                    DataCell(Text(_formatDecimal(item.ioUnitPrice, 2)), onDoubleTap: handleOpenEdit),
                                    DataCell(Text(_formatDecimal(item.ioDiscount, 2)), onDoubleTap: handleOpenEdit),
                                    DataCell(Text(_formatDecimal(item.ioTotalPrice, 2)), onDoubleTap: handleOpenEdit),
                                    DataCell(Text(item.ioColor), onDoubleTap: handleOpenEdit),
                                  ],
                                );
                              }).toList(growable: false),
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
