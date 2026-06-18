import 'dart:convert';
import 'dart:io';

import 'package:data_table_2/data_table_2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/sync/icloud_sync_service.dart';
import '../data/item_image_storage_service.dart';
import '../data/item_repository.dart';
import '../domain/item_models.dart';
import '../domain/item_purchase_price_calculator.dart';
import 'widgets/item_bom_form_dialog.dart';
import 'widgets/item_catalogue_form_dialog.dart';

const Set<String> cataloguePdfHardNoWrapFieldKeys = {
  'ic_id',
  'ic_ide',
  'ic_idv',
  'ic_hts',
  'ic_source_of_supply',
  'ic_price_net',
  'ic_price_gross_19',
  'ic_price_wholesale_net',
  'ic_purchase_price_net',
};

double cataloguePdfCellFontSizeForFieldKeys(Iterable<String> selectedFieldKeys) {
  final keys = selectedFieldKeys.toSet();
  final hasHardNoWrap = keys.any(cataloguePdfHardNoWrapFieldKeys.contains);
  if (!hasHardNoWrap) {
    return 6.5;
  }
  if (keys.length >= 12) {
    return 5.8;
  }
  if (keys.length >= 9) {
    return 6.1;
  }
  return 6.3;
}

double cataloguePdfColumnFlexForFieldKey(String fieldKey) {
  switch (fieldKey) {
    // Short technical keys / numeric columns - very compact.
    case 'ic_id':
    case 'ic_ic':
    case 'ic_stock':
      return 0.5;
    case 'ic_weight':
    case 'ic_hts':
      return 0.6;

    // Price columns - compact.
    case 'ic_price_net':
    case 'ic_price_gross_19':
    case 'ic_price_wholesale_net':
    case 'ic_purchase_price_net':
      return 0.7;

    // German description heavily prioritized: maximum width.
    case 'ic_description_de_long':
      return 1.8;

    // Text columns - moderately compact.
    case 'ic_description_en_long':
    case 'ic_note':
    case 'ic_image_path':
    case 'ic_source_of_supply':
      return 1.2;

    // Typical short text identifiers - compact.
    case 'ic_idi':
    case 'ic_ide':
    case 'ic_idv':
      return 0.9;

    default:
      return 0.85;
  }
}

class ItemCataloguePage extends StatefulWidget {
  const ItemCataloguePage({
    super.key,
    this.loadOnInit = true,
    this.initialCatalogueItems = const [],
    this.initialBomItems = const [],
  });

  final bool loadOnInit;
  final List<ItemCatalogueRow> initialCatalogueItems;
  final List<ItemBomRow> initialBomItems;

  @override
  State<ItemCataloguePage> createState() => _ItemCataloguePageState();
}

class _ItemCataloguePageState extends State<ItemCataloguePage> {
  final ItemRepository _repository = const ItemRepository();
  final ItemImageStorageService _imageStorage = const ItemImageStorageService();
  final ICloudSyncService _icloudSync = const ICloudSyncService();

  late final TextEditingController _searchController;
  late final ScrollController _catalogueVerticalController;
  late final ScrollController _catalogueHorizontalController;
  late final ScrollController _bomVerticalController;
  late final ScrollController _bomHorizontalController;

  List<ItemCatalogueRow> _catalogueItems = const [];
  List<ItemBomRow> _bomItems = const [];
  Map<int, ItemCatalogueRow> _catalogueById = const {};
  Map<int, double> _derivedWeightByArticleId = const {};
  String _searchQuery = '';
  bool _loading = true;
  Set<String> _catalogueExportFieldSelection = const {};
  List<String> _catalogueExportFieldOrder = const [];
  Set<String> _bomExportFieldSelection = const {};
  List<String> _bomExportFieldOrder = const [];

  int? _selectedCatalogueId;
  int? _selectedBomId;
  _CatalogueFilter _catalogueFilter = _CatalogueFilter.all;
  _VariantFilter _variantFilter = _VariantFilter.all;
  int _catalogueSortColumnIndex = 0;
  bool _catalogueSortAscending = true;
  int _bomSortColumnIndex = 0;
  bool _bomSortAscending = true;
  double _cataloguePaneRatio = 0.72;
  bool _isDraggingSplitter = false;

  static const double _splitterHeight = 28.0;
  static const double _minCataloguePaneHeight = 300.0;
  static const double _minBomPaneHeight = 160.0;

  static const List<String> _catalogueSortLabels = [
    'Artikel-ID',
    'Bezeichnung',
    'Variante',
    'Bruttopreis',
    'Nettopreis',
    'Netto Haendlerpreis',
    'Netto Einkaufspreis',
    'Gewicht in g',
    'HTS Code',
    'Bestand',
  ];
  static const List<String> _bomSortLabels = [
    'ID',
    'Artikel-ID',
    'Eltern Artikel (Katalog)',
    'Menge',
    'Bezeichnung',
    'Netto-Einkaufspreis',
  ];
  static const String _catalogueExportFieldPrefsKey = 'item_catalogue_export_fields';
  static const String _catalogueExportFieldOrderPrefsKey = 'item_catalogue_export_field_order';
  static const String _bomExportFieldPrefsKey = 'item_bom_export_fields';
  static const String _bomExportFieldOrderPrefsKey = 'item_bom_export_field_order';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _catalogueVerticalController = ScrollController();
    _catalogueHorizontalController = ScrollController();
    _bomVerticalController = ScrollController();
    _bomHorizontalController = ScrollController();
    _searchController.addListener(() {
      final nextQuery = _searchController.text.trim().toLowerCase();
      if (nextQuery == _searchQuery) {
        return;
      }
      setState(() => _searchQuery = nextQuery);
    });

    if (!widget.loadOnInit) {
      _catalogueItems = List<ItemCatalogueRow>.unmodifiable(widget.initialCatalogueItems);
      _bomItems = List<ItemBomRow>.unmodifiable(widget.initialBomItems);
      _catalogueById = {
        for (final item in _catalogueItems) item.icId: item,
      };
      _derivedWeightByArticleId = calculateDerivedWeights(
        catalogueRows: _catalogueItems,
        bomRows: _bomItems,
      );
      _selectedCatalogueId = _catalogueItems.isEmpty ? null : _catalogueItems.first.icId;
      _selectedBomId = null;
      _loading = false;
      return;
    }

    _loadCatalogueExportPreferences();
    _loadBomExportPreferences();
    _loadData();
  }

  @override
  void dispose() {
    _catalogueVerticalController.dispose();
    _catalogueHorizontalController.dispose();
    _bomVerticalController.dispose();
    _bomHorizontalController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final catalogueItems = await _repository.getCatalogueItems();
      await _repository.deleteOrphanBomItems(
        validCatalogueIds: catalogueItems.map((item) => item.icId).toSet(),
      );
      var bomItems = await _repository.getBomItems();
      final removedRootOnlyAnchors = await _repository.deleteRootOnlyBomAnchors();
      if (removedRootOnlyAnchors > 0) {
        if (kDebugMode) {
          debugPrint('🧹 Entfernte Root-Only BOM-Anker: $removedRootOnlyAnchors');
        }
        bomItems = await _repository.getBomItems();
      }
      await _syncManagedCatalogueImages(catalogueItems);
      if (!mounted) {
        return;
      }

      final catalogueById = {
        for (final item in catalogueItems) item.icId: item,
      };

      var nextSelectedCatalogueId = _selectedCatalogueId;
      if (nextSelectedCatalogueId == null || !catalogueById.containsKey(nextSelectedCatalogueId)) {
        nextSelectedCatalogueId = catalogueItems.isEmpty ? null : catalogueItems.first.icId;
      }

      final visibleBom = _buildVisibleBomRows(
        selectedCatalogueId: nextSelectedCatalogueId,
        allBomRows: bomItems,
        includeRoots: true,
      );

      var nextSelectedBomId = _selectedBomId;
      if (nextSelectedBomId == null || !visibleBom.any((row) => row.ibId == nextSelectedBomId)) {
        nextSelectedBomId = visibleBom.isEmpty ? null : visibleBom.first.ibId;
      }

      setState(() {
        _catalogueItems = catalogueItems;
        _bomItems = bomItems;
        _catalogueById = catalogueById;
        _derivedWeightByArticleId = calculateDerivedWeights(
          catalogueRows: catalogueItems,
          bomRows: bomItems,
        );
        _selectedCatalogueId = nextSelectedCatalogueId;
        _selectedBomId = nextSelectedBomId;
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _syncManagedCatalogueImages(List<ItemCatalogueRow> catalogueItems) async {
    final managedPaths = catalogueItems
        .map((item) => item.icImagePath.trim())
        .where((path) => path.isNotEmpty && !p.isAbsolute(path))
        .toSet();

    for (final path in managedPaths) {
      try {
        await _icloudSync.syncManagedImage(path);
      } catch (error) {
        if (kDebugMode) {
          debugPrint('⚠️ Konnte Bild nicht synchronisieren ($path): $error');
        }
      }
    }
  }

  int _nextCatalogueId() => _catalogueItems.isEmpty
      ? 1
      : _catalogueItems.map((item) => item.icId).reduce((a, b) => a > b ? a : b) + 1;

  int _nextBomId() => _bomItems.isEmpty
      ? 1
      : _bomItems.map((item) => item.ibId ?? 0).reduce((a, b) => a > b ? a : b) + 1;

  String _formatDecimal(double value, int fractionDigits) {
    return value.toStringAsFixed(fractionDigits).replaceAll('.', ',');
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

  Widget _buildHtsLink(String htsCode) {
    final normalized = htsCode.trim();
    if (normalized.isEmpty || normalized == '-') {
      return const Text('-');
    }

    return InkWell(
      onTap: () => _openHtsUrl(normalized),
      child: Text(
        normalized,
        style: const TextStyle(
          color: Colors.blue,
          decoration: TextDecoration.underline,
        ),
      ),
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

  Set<String> _normalizeCatalogueExportFieldSelection(Iterable<String> selectedKeys) {
    final availableKeys = _catalogueExportFields().map((field) => field.key).toSet();
    final normalized = selectedKeys.where(availableKeys.contains).toSet();
    return normalized.isEmpty ? availableKeys : normalized;
  }

  List<String> _normalizeCatalogueExportFieldOrder(Iterable<String> orderedKeys) {
    final availableKeys = _catalogueExportFields().map((field) => field.key).toList(growable: false);
    final availableSet = availableKeys.toSet();

    final normalized = <String>[];
    for (final key in orderedKeys) {
      if (availableSet.contains(key) && !normalized.contains(key)) {
        normalized.add(key);
      }
    }

    for (final key in availableKeys) {
      if (!normalized.contains(key)) {
        normalized.add(key);
      }
    }

    return normalized;
  }

  Future<void> _loadCatalogueExportPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    final storedSelectedKeys = preferences.getStringList(_catalogueExportFieldPrefsKey) ?? const <String>[];
    final storedOrderKeys = preferences.getStringList(_catalogueExportFieldOrderPrefsKey) ?? const <String>[];
    final normalizedSelection = _normalizeCatalogueExportFieldSelection(storedSelectedKeys);
    final normalizedOrder = _normalizeCatalogueExportFieldOrder(storedOrderKeys);
    if (!mounted) {
      return;
    }
    setState(() {
      _catalogueExportFieldSelection = normalizedSelection;
      _catalogueExportFieldOrder = normalizedOrder;
    });
  }

  Future<void> _saveCatalogueExportPreferences({
    required Set<String> selectedKeys,
    required List<String> orderedKeys,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      _catalogueExportFieldPrefsKey,
      selectedKeys.toList(growable: false),
    );
    await preferences.setStringList(
      _catalogueExportFieldOrderPrefsKey,
      orderedKeys,
    );
  }

  Set<String> _normalizeBomExportFieldSelection(Iterable<String> selectedKeys) {
    final availableKeys = _bomExportFields().map((field) => field.key).toSet();
    final normalized = selectedKeys.where(availableKeys.contains).toSet();
    return normalized.isEmpty ? availableKeys : normalized;
  }

  List<String> _normalizeBomExportFieldOrder(Iterable<String> orderedKeys) {
    final availableKeys = _bomExportFields().map((field) => field.key).toList(growable: false);
    final availableSet = availableKeys.toSet();

    final normalized = <String>[];
    for (final key in orderedKeys) {
      if (availableSet.contains(key) && !normalized.contains(key)) {
        normalized.add(key);
      }
    }

    for (final key in availableKeys) {
      if (!normalized.contains(key)) {
        normalized.add(key);
      }
    }

    return normalized;
  }

  Future<void> _loadBomExportPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    final storedSelectedKeys = preferences.getStringList(_bomExportFieldPrefsKey) ?? const <String>[];
    final storedOrderKeys = preferences.getStringList(_bomExportFieldOrderPrefsKey) ?? const <String>[];
    final normalizedSelection = _normalizeBomExportFieldSelection(storedSelectedKeys);
    final normalizedOrder = _normalizeBomExportFieldOrder(storedOrderKeys);
    if (!mounted) {
      return;
    }
    setState(() {
      _bomExportFieldSelection = normalizedSelection;
      _bomExportFieldOrder = normalizedOrder;
    });
  }

  Future<void> _saveBomExportPreferences({
    required Set<String> selectedKeys,
    required List<String> orderedKeys,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      _bomExportFieldPrefsKey,
      selectedKeys.toList(growable: false),
    );
    await preferences.setStringList(
      _bomExportFieldOrderPrefsKey,
      orderedKeys,
    );
  }

  List<_CatalogueExportField> _catalogueExportFields() {
    return [
      _CatalogueExportField(
        key: 'ic_id',
        label: 'Artikel-ID',
        csvHeader: 'ic_id',
        value: (row) => row.icId.toString(),
      ),
      _CatalogueExportField(
        key: 'ic_idi',
        label: 'Bezeichnung',
        csvHeader: 'ic_idi',
        value: (row) => row.icIdi,
      ),
      _CatalogueExportField(
        key: 'ic_ide',
        label: 'ic_ide',
        csvHeader: 'ic_ide',
        value: (row) => row.icIde,
      ),
      _CatalogueExportField(
        key: 'ic_idv',
        label: 'Variante',
        csvHeader: 'ic_idv',
        value: (row) => row.icIdv,
      ),
      _CatalogueExportField(
        key: 'ic_description_de_long',
        label: 'Beschreibung DE',
        csvHeader: 'ic_description_de_long',
        value: (row) => row.icDescriptionDeLong,
      ),
      _CatalogueExportField(
        key: 'ic_description_en_long',
        label: 'Beschreibung EN',
        csvHeader: 'ic_description_en_long',
        value: (row) => row.icDescriptionEnLong,
      ),
      _CatalogueExportField(
        key: 'ic_price_net',
        label: 'Nettopreis',
        csvHeader: 'ic_price_net',
        value: (row) => row.icPriceNet.toString(),
      ),
      _CatalogueExportField(
        key: 'ic_price_gross_19',
        label: 'Bruttopreis inkl. 19%',
        csvHeader: 'ic_price_gross_19',
        value: (row) => _grossPrice(row.icPriceNet).toStringAsFixed(2),
      ),
      _CatalogueExportField(
        key: 'ic_price_wholesale_net',
        label: 'Netto Händlerpreis',
        csvHeader: 'ic_price_wholesale_net',
        value: (row) => row.icPriceWholesaleNet.toString(),
      ),
      _CatalogueExportField(
        key: 'ic_purchase_price_net',
        label: 'Netto Einkaufspreis',
        csvHeader: 'ic_purchase_price_net',
        value: (row) => row.icPurchasePriceNet.toString(),
      ),
      _CatalogueExportField(
        key: 'ic_weight',
        label: 'Gewicht in g',
        csvHeader: 'ic_weight',
        value: (row) => row.icWeight.toString(),
      ),
      _CatalogueExportField(
        key: 'ic_source_of_supply',
        label: 'Lieferquelle',
        csvHeader: 'ic_source_of_supply',
        value: (row) => row.icSourceOfSupply,
      ),
      _CatalogueExportField(
        key: 'ic_hts',
        label: 'HTS Code',
        csvHeader: 'ic_hts',
        value: (row) => row.icHts,
      ),
      _CatalogueExportField(
        key: 'ic_image_path',
        label: 'Bildpfad',
        csvHeader: 'ic_image_path',
        value: (row) => row.icImagePath,
      ),
      _CatalogueExportField(
        key: 'ic_note',
        label: 'Notiz',
        csvHeader: 'ic_note',
        value: (row) => row.icNote,
      ),
      _CatalogueExportField(
        key: 'ic_stock',
        label: 'Bestand',
        csvHeader: 'ic_stock',
        value: (row) => row.icStock.toString(),
      ),
      _CatalogueExportField(
        key: 'ic_ic',
        label: 'ZB Komponenten',
        csvHeader: 'ic_ic',
        value: (row) => row.icIc.toString(),
      ),
    ];
  }

  List<_BomExportField> _bomExportFields() {
    return [
      _BomExportField(
        key: 'root_catalogue_id',
        label: 'BOM zu Artikel-ID',
        csvHeader: 'root_catalogue_id',
        value: (row) => row.rootCatalogueId.toString(),
      ),
      _BomExportField(
        key: 'root_catalogue_name',
        label: 'BOM zu Artikel',
        csvHeader: 'root_catalogue_name',
        value: (row) => row.rootCatalogueName,
      ),
      _BomExportField(
        key: 'ib_id',
        label: 'BOM-ID',
        csvHeader: 'ib_id',
        value: (row) => row.bomId.toString(),
      ),
      _BomExportField(
        key: 'ib_item_id',
        label: 'Artikel-ID',
        csvHeader: 'ib_item_id',
        value: (row) => row.articleId.toString(),
      ),
      _BomExportField(
        key: 'item_name',
        label: 'Bezeichnung',
        csvHeader: 'Bezeichnung',
        value: (row) => row.articleName,
      ),
      _BomExportField(
        key: 'net_purchase_total',
        label: 'Netto-Einkaufspreis',
        csvHeader: 'Netto-Einkaufspreis',
        value: (row) => row.netPurchaseTotal.toString(),
      ),
      _BomExportField(
        key: 'ib_parent_id',
        label: 'Parent BOM-ID',
        csvHeader: 'ib_parent_id',
        value: (row) => row.parentBomId?.toString() ?? '',
      ),
      _BomExportField(
        key: 'parent_article_label',
        label: 'Eltern_Artikel',
        csvHeader: 'Eltern_Artikel',
        value: (row) => row.parentArticleLabel,
      ),
      _BomExportField(
        key: 'ib_order',
        label: 'Reihenfolge',
        csvHeader: 'ib_order',
        value: (row) => row.order.toString(),
      ),
      _BomExportField(
        key: 'ib_quantity',
        label: 'Menge',
        csvHeader: 'Menge',
        value: (row) => row.quantity.toString(),
      ),
    ];
  }

  Future<List<_CatalogueExportField>?> _showCatalogueExportFieldDialog() async {
    final fields = _catalogueExportFields();
    final fieldsByKey = {
      for (final field in fields) field.key: field,
    };
    final selectedKeys = _normalizeCatalogueExportFieldSelection(_catalogueExportFieldSelection);
    final orderedFieldKeys = _normalizeCatalogueExportFieldOrder(
      _catalogueExportFieldOrder.isEmpty
          ? fields.map((field) => field.key)
          : _catalogueExportFieldOrder,
    );

    return showDialog<List<_CatalogueExportField>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Exportfelder auswaehlen'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text('Ausgewaehlt: ${selectedKeys.length}/${fields.length}'),
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            setDialogState(() {
                              selectedKeys
                                ..clear()
                                ..addAll(orderedFieldKeys);
                            });
                          },
                          child: const Text('Alle'),
                        ),
                        TextButton(
                          onPressed: () {
                            setDialogState(selectedKeys.clear);
                          },
                          child: const Text('Keine'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 360,
                      child: ReorderableListView.builder(
                        buildDefaultDragHandles: false,
                        itemCount: orderedFieldKeys.length,
                        onReorderItem: (oldIndex, newIndex) {
                          setDialogState(() {
                            final moved = orderedFieldKeys.removeAt(oldIndex);
                            orderedFieldKeys.insert(newIndex, moved);
                          });
                        },
                        itemBuilder: (context, index) {
                          final key = orderedFieldKeys[index];
                          final field = fieldsByKey[key];
                          if (field == null) {
                            return const SizedBox.shrink();
                          }
                          return CheckboxListTile(
                            key: ValueKey(field.key),
                            dense: true,
                            value: selectedKeys.contains(field.key),
                            title: Text(field.label),
                            subtitle: Text(field.csvHeader),
                            secondary: ReorderableDragStartListener(
                              index: index,
                              child: const Icon(Icons.drag_handle),
                            ),
                            onChanged: (checked) {
                              setDialogState(() {
                                if (checked == true) {
                                  selectedKeys.add(field.key);
                                } else {
                                  selectedKeys.remove(field.key);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Abbrechen'),
                ),
                FilledButton(
                  onPressed: selectedKeys.isEmpty
                      ? null
                      : () {
                        final selectedFields = orderedFieldKeys
                          .map((key) => fieldsByKey[key])
                          .whereType<_CatalogueExportField>()
                          .where((field) => selectedKeys.contains(field.key))
                              .toList(growable: false);
                          Navigator.of(context).pop(selectedFields);
                        },
                  child: const Text('Exportieren'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<List<_CatalogueExportField>?> _promptCatalogueExportFields() async {
    final selectedFields = await _showCatalogueExportFieldDialog();
    if (selectedFields == null || selectedFields.isEmpty) {
      return null;
    }

    final selectedKeys = selectedFields.map((field) => field.key).toSet();
    final orderedKeys = selectedFields.map((field) => field.key).toList(growable: false);
    if (mounted) {
      setState(() {
        _catalogueExportFieldSelection = selectedKeys;
        _catalogueExportFieldOrder = orderedKeys;
      });
    }
    await _saveCatalogueExportPreferences(
      selectedKeys: selectedKeys,
      orderedKeys: orderedKeys,
    );
    return selectedFields;
  }

  Future<Set<int>?> _showBomTargetSelectionDialog() async {
    final targets = _catalogueItems
        .map((item) {
          final rows = _buildVisibleBomRows(
            selectedCatalogueId: item.icId,
            allBomRows: _bomItems,
            includeRoots: false,
          );
          return _BomExportTarget(
            catalogueId: item.icId,
            catalogueName: item.icIdi,
            rowCount: rows.length,
          );
        })
        .where((target) => target.rowCount > 0)
        .toList(growable: false)
      ..sort((a, b) => a.catalogueId.compareTo(b.catalogueId));

    if (targets.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Keine BOM-Daten zum Export vorhanden.')),
        );
      }
      return null;
    }

    final selectedIds = targets.map((target) => target.catalogueId).toSet();

    return showDialog<Set<int>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Zu exportierende BOMs auswählen'),
              content: SizedBox(
                width: 560,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text('Ausgewählt: ${selectedIds.length}/${targets.length}'),
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            setDialogState(() {
                              selectedIds
                                ..clear()
                                ..addAll(targets.map((target) => target.catalogueId));
                            });
                          },
                          child: const Text('Alle'),
                        ),
                        TextButton(
                          onPressed: () {
                            setDialogState(selectedIds.clear);
                          },
                          child: const Text('Keine'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 320,
                      child: ListView.builder(
                        itemCount: targets.length,
                        itemBuilder: (context, index) {
                          final target = targets[index];
                          final name = target.catalogueName.trim().isEmpty
                              ? '#${target.catalogueId}'
                              : '#${target.catalogueId} • ${target.catalogueName}';
                          return CheckboxListTile(
                            dense: true,
                            value: selectedIds.contains(target.catalogueId),
                            title: Text(name),
                            subtitle: Text('${target.rowCount} BOM-Zeilen'),
                            onChanged: (checked) {
                              setDialogState(() {
                                if (checked == true) {
                                  selectedIds.add(target.catalogueId);
                                } else {
                                  selectedIds.remove(target.catalogueId);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Abbrechen'),
                ),
                FilledButton(
                  onPressed: selectedIds.isEmpty
                      ? null
                      : () => Navigator.of(context).pop(Set<int>.from(selectedIds)),
                  child: const Text('Weiter'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  List<_BomExportRow> _buildBomExportRows(Set<int> selectedCatalogueIds) {
    final rows = <_BomExportRow>[];
    for (final catalogueId in selectedCatalogueIds) {
      final rootItem = _catalogueById[catalogueId];
      final rootName = rootItem?.icIdi.trim() ?? '';
      final bomRows = _buildVisibleBomRows(
        selectedCatalogueId: catalogueId,
        allBomRows: _bomItems,
        includeRoots: false,
      );

      for (final row in bomRows) {
        final article = _catalogueById[row.ibItemId];
        final netPurchaseTotal = (article?.icPurchasePriceNet ?? 0) * row.ibQuantity;
        rows.add(
          _BomExportRow(
            rootCatalogueId: catalogueId,
            rootCatalogueName: rootName,
            bomId: row.ibId ?? 0,
            articleId: row.ibItemId,
            articleName: _catalogueById[row.ibItemId]?.icIdi ?? '',
            parentBomId: row.ibParentId,
            parentArticleLabel: _parentArticleLabelOf(row),
            order: row.ibOrder,
            quantity: row.ibQuantity,
            netPurchaseTotal: netPurchaseTotal,
          ),
        );
      }
    }
    return rows;
  }

  Future<List<_BomExportField>?> _showBomExportFieldDialog() async {
    final fields = _bomExportFields();
    final fieldsByKey = {for (final field in fields) field.key: field};
    final selectedKeys = _normalizeBomExportFieldSelection(_bomExportFieldSelection);
    final orderedFieldKeys = _normalizeBomExportFieldOrder(
      _bomExportFieldOrder.isEmpty ? fields.map((field) => field.key) : _bomExportFieldOrder,
    );

    return showDialog<List<_BomExportField>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('BOM-Exportfelder auswählen'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text('Ausgewählt: ${selectedKeys.length}/${fields.length}'),
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            setDialogState(() {
                              selectedKeys
                                ..clear()
                                ..addAll(orderedFieldKeys);
                            });
                          },
                          child: const Text('Alle'),
                        ),
                        TextButton(
                          onPressed: () {
                            setDialogState(selectedKeys.clear);
                          },
                          child: const Text('Keine'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 360,
                      child: ReorderableListView.builder(
                        buildDefaultDragHandles: false,
                        itemCount: orderedFieldKeys.length,
                        onReorderItem: (oldIndex, newIndex) {
                          setDialogState(() {
                            final moved = orderedFieldKeys.removeAt(oldIndex);
                            orderedFieldKeys.insert(newIndex, moved);
                          });
                        },
                        itemBuilder: (context, index) {
                          final key = orderedFieldKeys[index];
                          final field = fieldsByKey[key];
                          if (field == null) {
                            return const SizedBox.shrink();
                          }
                          return CheckboxListTile(
                            key: ValueKey(field.key),
                            dense: true,
                            value: selectedKeys.contains(field.key),
                            title: Text(field.label),
                            subtitle: Text(field.csvHeader),
                            secondary: ReorderableDragStartListener(
                              index: index,
                              child: const Icon(Icons.drag_handle),
                            ),
                            onChanged: (checked) {
                              setDialogState(() {
                                if (checked == true) {
                                  selectedKeys.add(field.key);
                                } else {
                                  selectedKeys.remove(field.key);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Abbrechen'),
                ),
                FilledButton(
                  onPressed: selectedKeys.isEmpty
                      ? null
                      : () {
                          final selectedFields = orderedFieldKeys
                              .map((key) => fieldsByKey[key])
                              .whereType<_BomExportField>()
                              .where((field) => selectedKeys.contains(field.key))
                              .toList(growable: false);
                          Navigator.of(context).pop(selectedFields);
                        },
                  child: const Text('Weiter'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<List<_BomExportField>?> _promptBomExportFields() async {
    final selectedFields = await _showBomExportFieldDialog();
    if (selectedFields == null || selectedFields.isEmpty) {
      return null;
    }

    final selectedKeys = selectedFields.map((field) => field.key).toSet();
    final orderedKeys = selectedFields.map((field) => field.key).toList(growable: false);
    if (mounted) {
      setState(() {
        _bomExportFieldSelection = selectedKeys;
        _bomExportFieldOrder = orderedKeys;
      });
    }
    await _saveBomExportPreferences(selectedKeys: selectedKeys, orderedKeys: orderedKeys);
    return selectedFields;
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

  Future<void> _onCatalogueExportSelected(_CatalogueExportFormat format) async {
    final selectedFields = await _promptCatalogueExportFields();
    if (selectedFields == null) {
      return;
    }

    switch (format) {
      case _CatalogueExportFormat.csv:
        await _exportCatalogueCsv(selectedFields);
      case _CatalogueExportFormat.pdf:
        final sortSelection = await _showPdfSortDialog(selectedFields);
        if (sortSelection == null) {
          return;
        }
        await _exportCataloguePdf(selectedFields, sortSelection: sortSelection);
    }
  }

  Future<void> _onBomExportSelected(_BomExportFormat format) async {
    final selectedBomCatalogueIds = await _showBomTargetSelectionDialog();
    if (selectedBomCatalogueIds == null || selectedBomCatalogueIds.isEmpty) {
      return;
    }

    final exportRows = _buildBomExportRows(selectedBomCatalogueIds);
    if (exportRows.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Keine BOM-Zeilen für die Auswahl gefunden.')),
        );
      }
      return;
    }

    final selectedFields = await _promptBomExportFields();
    if (selectedFields == null) {
      return;
    }

    switch (format) {
      case _BomExportFormat.csv:
        await _exportBomCsv(exportRows, selectedFields);
      case _BomExportFormat.pdf:
        final sortSelection = await _showBomPdfSortDialog(selectedFields);
        if (sortSelection == null) {
          return;
        }
        await _exportBomPdf(
          exportRows,
          selectedFields,
          sortSelection: sortSelection,
        );
    }
  }

  Future<_BomPdfSortSelection?> _showBomPdfSortDialog(
    List<_BomExportField> selectedFields,
  ) async {
    const noneKey = '__none__';
    var selectedKey = noneKey;
    var ascending = true;

    return showDialog<_BomPdfSortSelection>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('BOM PDF-Sortierung wählen'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedKey,
                    decoration: const InputDecoration(
                      labelText: 'Sortierfeld',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: noneKey,
                        child: Text('Keine Sortierung'),
                      ),
                      ...selectedFields.map(
                        (field) => DropdownMenuItem<String>(
                          value: field.key,
                          child: Text(field.label),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setDialogState(() {
                        selectedKey = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: ascending,
                    title: const Text('Aufsteigend'),
                    contentPadding: EdgeInsets.zero,
                    onChanged: selectedKey == noneKey
                        ? null
                        : (value) {
                            setDialogState(() {
                              ascending = value;
                            });
                          },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Abbrechen'),
                ),
                FilledButton(
                  onPressed: () {
                    final fieldKey = selectedKey == noneKey ? null : selectedKey;
                    Navigator.of(context).pop(
                      _BomPdfSortSelection(
                        fieldKey: fieldKey,
                        ascending: ascending,
                      ),
                    );
                  },
                  child: const Text('Weiter'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<_CataloguePdfSortSelection?> _showPdfSortDialog(
    List<_CatalogueExportField> selectedFields,
  ) async {
    const noneKey = '__none__';
    var selectedKey = noneKey;
    var ascending = true;

    return showDialog<_CataloguePdfSortSelection>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('PDF-Sortierung waehlen'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedKey,
                    decoration: const InputDecoration(
                      labelText: 'Sortierfeld',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: noneKey,
                        child: Text('Keine Sortierung'),
                      ),
                      ...selectedFields.map(
                        (field) => DropdownMenuItem<String>(
                          value: field.key,
                          child: Text(field.label),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setDialogState(() {
                        selectedKey = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: ascending,
                    title: const Text('Aufsteigend'),
                    contentPadding: EdgeInsets.zero,
                    onChanged: selectedKey == noneKey
                        ? null
                        : (value) {
                            setDialogState(() {
                              ascending = value;
                            });
                          },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Abbrechen'),
                ),
                FilledButton(
                  onPressed: () {
                    final fieldKey = selectedKey == noneKey ? null : selectedKey;
                    Navigator.of(context).pop(
                      _CataloguePdfSortSelection(
                        fieldKey: fieldKey,
                        ascending: ascending,
                      ),
                    );
                  },
                  child: const Text('Weiter'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  int _compareExportValues(String a, String b) {
    final normalizedA = a.trim().replaceAll(',', '.');
    final normalizedB = b.trim().replaceAll(',', '.');
    final numericA = double.tryParse(normalizedA);
    final numericB = double.tryParse(normalizedB);
    if (numericA != null && numericB != null) {
      return numericA.compareTo(numericB);
    }
    return a.toLowerCase().compareTo(b.toLowerCase());
  }

  String _formatPdfFieldValue(
    _CatalogueExportField field,
    ItemCatalogueRow row, {
    Map<int, double>? derivedWeightByArticleId,
  }) {
    final rawValue = _catalogueExportFieldValue(
      field,
      row,
      derivedWeightByArticleId: derivedWeightByArticleId,
    );

    String toGermanFixed(String value, int fractionDigits) {
      final parsed = double.tryParse(value.trim().replaceAll(',', '.'));
      if (parsed == null) {
        return value;
      }
      return parsed.toStringAsFixed(fractionDigits).replaceAll('.', ',');
    }

    String formatted;
    switch (field.key) {
      case 'ic_price_net':
      case 'ic_price_gross_19':
      case 'ic_price_wholesale_net':
      case 'ic_purchase_price_net':
        formatted = toGermanFixed(rawValue, 2);
        break;
      case 'ic_weight':
        formatted = toGermanFixed(rawValue, 1);
        break;
      default:
        formatted = rawValue;
    }

    // Sanitize symbols for PDF compatibility
    return _sanitizeSymbols(formatted);
  }

  String _truncateCataloguePdfValue(
    String fieldKey,
    String value, {
    int? maxCharsOverride,
  }) {
    final trimmed = value.trim();
    final maxChars = maxCharsOverride ?? _cataloguePdfMaxChars(fieldKey);
    if (maxChars <= 0 || trimmed.length <= maxChars) {
      return trimmed;
    }
    final hardNoWrap = cataloguePdfHardNoWrapFieldKeys.contains(fieldKey);
    if (maxChars <= 1) {
      return hardNoWrap ? trimmed.substring(0, 1) : '…';
    }
    if (hardNoWrap) {
      return trimmed.substring(0, maxChars);
    }
    return '${trimmed.substring(0, maxChars - 1)}…';
  }

  Map<String, int> _buildCataloguePdfDynamicMaxChars(
    List<_CatalogueExportField> selectedFields,
    List<ItemCatalogueRow> rows, {
    required Map<int, double> derivedWeightByArticleId,
  }) {
    if (selectedFields.isEmpty) {
      return const {};
    }

    const rowCharBudget = 260.0;
    final totalFlex = selectedFields
        .map((field) => _cataloguePdfColumnFlex(field.key))
        .fold<double>(0, (sum, value) => sum + value);

    final result = <String, int>{};

    for (final field in selectedFields) {
      final flex = _cataloguePdfColumnFlex(field.key);
      final proportionalCap = ((rowCharBudget * (flex / totalFlex)).round())
          .clamp(6, 64);

      final lengths = rows
          .map(
            (row) => _formatPdfFieldValue(
              field,
              row,
              derivedWeightByArticleId: derivedWeightByArticleId,
            ).trim().length,
          )
          .where((length) => length > 0)
          .toList(growable: false)
        ..sort();

      final percentileLength = lengths.isEmpty
          ? _cataloguePdfMaxChars(field.key)
          : lengths[((lengths.length - 1) * 0.85).floor()];

      final baselineMin = _cataloguePdfBaselineMinChars(field.key);
        final adjustedCap = cataloguePdfHardNoWrapFieldKeys.contains(field.key)
          ? (proportionalCap - 2).clamp(6, 64)
          : proportionalCap;
      result[field.key] = percentileLength.clamp(baselineMin, adjustedCap);
    }

    return result;
  }

  int _cataloguePdfBaselineMinChars(String fieldKey) {
    switch (fieldKey) {
      case 'ic_description_de_long':
        return 18;
      case 'ic_description_en_long':
      case 'ic_note':
      case 'ic_image_path':
      case 'ic_source_of_supply':
        return 20;
      case 'ic_idi':
      case 'ic_ide':
      case 'ic_idv':
        return 14;
      default:
        return 6;
    }
  }

  int _cataloguePdfMaxChars(String fieldKey) {
    switch (fieldKey) {
      case 'ic_id':
        return 8;
      case 'ic_ic':
      case 'ic_stock':
      case 'ic_weight':
        return 6;
      case 'ic_hts':
        return 16;
      case 'ic_price_net':
      case 'ic_price_gross_19':
      case 'ic_price_wholesale_net':
      case 'ic_purchase_price_net':
        return 14;
      case 'ic_idi':
      case 'ic_ide':
      case 'ic_idv':
        return 28;
      case 'ic_description_de_long':
        return 26;
      case 'ic_description_en_long':
      case 'ic_note':
      case 'ic_image_path':
      case 'ic_source_of_supply':
        return 42;
      default:
        return 32;
    }
  }

  double _cataloguePdfCellFontSize(List<_CatalogueExportField> selectedFields) {
    return cataloguePdfCellFontSizeForFieldKeys(
      selectedFields.map((field) => field.key),
    );
  }

  String _formatBomPdfFieldValue(_BomExportField field, _BomExportRow row) {
    final rawValue = field.value(row);

    String toGermanFixed(String value, int fractionDigits) {
      final parsed = double.tryParse(value.trim().replaceAll(',', '.'));
      if (parsed == null) {
        return value;
      }
      return parsed.toStringAsFixed(fractionDigits).replaceAll('.', ',');
    }

    String formatted;
    switch (field.key) {
      case 'ib_quantity':
      case 'ib_order':
        formatted = toGermanFixed(rawValue, 0);
        break;
      case 'net_purchase_total':
        formatted = toGermanFixed(rawValue, 2);
        break;
      default:
        formatted = rawValue;
    }

    // Sanitize symbols for PDF compatibility
    return _sanitizeSymbols(formatted);
  }

  Future<void> _exportCatalogueCsv(List<_CatalogueExportField> selectedFields) async {

    setState(() => _loading = true);
    try {
      final rows = await _repository.getCatalogueItems();
      final bomRows = await _repository.getBomItems();
      final derivedWeightByArticleId = calculateDerivedWeights(
        catalogueRows: rows,
        bomRows: bomRows,
      );
      final buffer = StringBuffer();
      buffer.writeln(
        selectedFields.map((field) => _csvEscape(field.csvHeader)).join(';'),
      );

      for (final row in rows) {
        final values = selectedFields
            .map(
              (field) => _csvEscape(
                _catalogueExportFieldValue(
                  field,
                  row,
                  derivedWeightByArticleId: derivedWeightByArticleId,
                ),
              ),
            )
            .join(';');
        buffer.writeln(values);
      }

      final fileName = 'item_catalogue_export_${_buildFileTimestamp(DateTime.now())}.csv';
      final targetPath = await _pickExportTargetPath(
        dialogTitle: 'Artikelkatalog als CSV exportieren',
        fileName: fileName,
        allowedExtensions: const ['csv'],
      );
      if (targetPath == null || targetPath.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Export abgebrochen: Kein Speicherort ausgewaehlt.')),
          );
        }
        return;
      }
      final csvWithBom = '\uFEFF${buffer.toString()}';
      await File(targetPath).writeAsString(csvWithBom, encoding: utf8);

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Artikelkatalog-CSV exportiert nach: $targetPath')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Artikelkatalog-Export fehlgeschlagen: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _exportCataloguePdf(
    List<_CatalogueExportField> selectedFields, {
    required _CataloguePdfSortSelection sortSelection,
  }) async {
    setState(() => _loading = true);
    try {
      final rows = await _repository.getCatalogueItems();
      final bomRows = await _repository.getBomItems();
      final derivedWeightByArticleId = calculateDerivedWeights(
        catalogueRows: rows,
        bomRows: bomRows,
      );
      final sortedRows = List<ItemCatalogueRow>.from(rows);
      final sortFieldKey = sortSelection.fieldKey;
      if (sortFieldKey != null) {
        final sortField = selectedFields
            .where((field) => field.key == sortFieldKey)
            .cast<_CatalogueExportField?>()
            .firstWhere((field) => field != null, orElse: () => null);
        if (sortField != null) {
          sortedRows.sort((a, b) {
            final compare = _compareExportValues(
              _catalogueExportFieldValue(
                sortField,
                a,
                derivedWeightByArticleId: derivedWeightByArticleId,
              ),
              _catalogueExportFieldValue(
                sortField,
                b,
                derivedWeightByArticleId: derivedWeightByArticleId,
              ),
            );
            return sortSelection.ascending ? compare : -compare;
          });
        }
      }

      final document = pw.Document();
      final fonts = await _loadPdfFonts();

      final headers = selectedFields.map((field) => field.label).toList(growable: false);
      final cellFontSize = _cataloguePdfCellFontSize(selectedFields);
      final columnWidths = <int, pw.TableColumnWidth>{
        for (var index = 0; index < selectedFields.length; index++)
          index: pw.FlexColumnWidth(
            _cataloguePdfColumnFlex(selectedFields[index].key),
          ),
      };
      final dynamicMaxCharsByField = _buildCataloguePdfDynamicMaxChars(
        selectedFields,
        sortedRows,
        derivedWeightByArticleId: derivedWeightByArticleId,
      );
      final tableData = sortedRows
          .map(
            (row) => selectedFields
                .map(
                  (field) {
                    final rawValue = _formatPdfFieldValue(
                      field,
                      row,
                      derivedWeightByArticleId: derivedWeightByArticleId,
                    );
                    return _truncateCataloguePdfValue(
                      field.key,
                      rawValue,
                      maxCharsOverride: dynamicMaxCharsByField[field.key],
                    );
                  },
                )
                .toList(growable: false),
          )
          .toList(growable: false);

      document.addPage(
        pw.MultiPage(
          theme: pw.ThemeData.withFont(
            base: fonts.base,
            bold: fonts.bold,
          ),
          pageFormat: PdfPageFormat.a3.landscape,
          build: (context) => [
            pw.Text(
              'Artikelkatalog Export',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headers: headers,
              data: tableData,
              columnWidths: columnWidths,
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
              headerStyle: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              ),
              cellStyle: pw.TextStyle(fontSize: cellFontSize),
              cellAlignment: pw.Alignment.centerLeft,
              cellPadding: const pw.EdgeInsets.all(3),
            ),
          ],
        ),
      );

      final fileName = 'item_catalogue_export_${_buildFileTimestamp(DateTime.now())}.pdf';
      final targetPath = await _pickExportTargetPath(
        dialogTitle: 'Artikelkatalog als PDF exportieren',
        fileName: fileName,
        allowedExtensions: const ['pdf'],
      );
      if (targetPath == null || targetPath.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Export abgebrochen: Kein Speicherort ausgewaehlt.')),
          );
        }
        return;
      }
      await File(targetPath).writeAsBytes(await document.save());

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Artikelkatalog-PDF exportiert nach: $targetPath')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Artikelkatalog-PDF-Export fehlgeschlagen: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _catalogueExportFieldValue(
    _CatalogueExportField field,
    ItemCatalogueRow row, {
    Map<int, double>? derivedWeightByArticleId,
  }) {
    if (field.key == 'ic_weight') {
      final weight = derivedWeightByArticleId?[row.icId] ?? _displayWeight(row);
      return weight.toStringAsFixed(1);
    }
    return field.value(row);
  }

  Future<void> _exportBomCsv(
    List<_BomExportRow> exportRows,
    List<_BomExportField> selectedFields,
  ) async {
    setState(() => _loading = true);
    try {
      final buffer = StringBuffer();
      buffer.writeln(selectedFields.map((field) => _csvEscape(field.csvHeader)).join(';'));

      for (final row in exportRows) {
        final values = selectedFields.map((field) => _csvEscape(field.value(row))).join(';');
        buffer.writeln(values);
      }

      final fileName = 'item_bom_export_${_buildFileTimestamp(DateTime.now())}.csv';
      final targetPath = await _pickExportTargetPath(
        dialogTitle: 'BOM als CSV exportieren',
        fileName: fileName,
        allowedExtensions: const ['csv'],
      );
      if (targetPath == null || targetPath.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Export abgebrochen: Kein Speicherort ausgewählt.')),
          );
        }
        return;
      }
      final csvWithBom = '\uFEFF${buffer.toString()}';
      await File(targetPath).writeAsString(csvWithBom, encoding: utf8);

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('BOM-CSV exportiert nach: $targetPath')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('BOM-CSV-Export fehlgeschlagen: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _exportBomPdf(
    List<_BomExportRow> exportRows,
    List<_BomExportField> selectedFields, {
    required _BomPdfSortSelection sortSelection,
  }) async {
    setState(() => _loading = true);
    try {
      final sortedRows = List<_BomExportRow>.from(exportRows);
      final sortFieldKey = sortSelection.fieldKey;
      if (sortFieldKey != null) {
        final sortField = selectedFields
            .where((field) => field.key == sortFieldKey)
            .cast<_BomExportField?>()
            .firstWhere((field) => field != null, orElse: () => null);
        if (sortField != null) {
          sortedRows.sort((a, b) {
            final compare = _compareExportValues(
              sortField.value(a),
              sortField.value(b),
            );
            return sortSelection.ascending ? compare : -compare;
          });
        }
      }

      final document = pw.Document();
      final fonts = await _loadPdfFonts();
      final headers = selectedFields.map((field) => field.label).toList(growable: false);
      final tableData = sortedRows
          .map(
          (row) => selectedFields
            .map((field) => _formatBomPdfFieldValue(field, row))
            .toList(growable: false),
          )
          .toList(growable: false);

      document.addPage(
        pw.MultiPage(
          theme: pw.ThemeData.withFont(base: fonts.base, bold: fonts.bold),
          pageFormat: PdfPageFormat.a3.landscape,
          build: (context) => [
            pw.Text(
              'BOM Export',
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
            ),
          ],
        ),
      );

      final fileName = 'item_bom_export_${_buildFileTimestamp(DateTime.now())}.pdf';
      final targetPath = await _pickExportTargetPath(
        dialogTitle: 'BOM als PDF exportieren',
        fileName: fileName,
        allowedExtensions: const ['pdf'],
      );
      if (targetPath == null || targetPath.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Export abgebrochen: Kein Speicherort ausgewählt.')),
          );
        }
        return;
      }
      await File(targetPath).writeAsBytes(await document.save());

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('BOM-PDF exportiert nach: $targetPath')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('BOM-PDF-Export fehlgeschlagen: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _onExportMenuSelected(_ExportMenuAction action) async {
    switch (action) {
      case _ExportMenuAction.catalogueCsv:
        await _onCatalogueExportSelected(_CatalogueExportFormat.csv);
      case _ExportMenuAction.cataloguePdf:
        await _onCatalogueExportSelected(_CatalogueExportFormat.pdf);
      case _ExportMenuAction.bomCsv:
        await _onBomExportSelected(_BomExportFormat.csv);
      case _ExportMenuAction.bomPdf:
        await _onBomExportSelected(_BomExportFormat.pdf);
    }
  }

  Future<_PdfFonts> _loadPdfFonts() async {
    try {
      // Try to load Noto Sans (better symbol support)
      try {
        final notoData = await rootBundle.load('lib/fonts/NotoSans-Regular.ttf');
        final notoBoldData = await rootBundle.load('lib/fonts/NotoSans-Bold.ttf');
        return _PdfFonts(
          base: pw.Font.ttf(notoData),
          bold: pw.Font.ttf(notoBoldData),
        );
      } catch (_) {
        // Fallback to Roboto if Noto Sans not found
      }

      final baseData = await rootBundle.load('lib/fonts/Roboto-Regular.ttf');
      final boldData = await rootBundle.load('lib/fonts/Roboto-Bold.ttf');
      return _PdfFonts(
        base: pw.Font.ttf(baseData),
        bold: pw.Font.ttf(boldData),
      );
    } catch (e) {
      // Ultimate fallback to built-in font
      return _PdfFonts(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
      );
    }
  }

  String _sanitizeSymbols(String text) {
    // Common symbol mappings for better PDF compatibility
    return text
        .replaceAll('→', '->')
        .replaceAll('←', '<-')
        .replaceAll('↔', '<->')
        .replaceAll('•', '•')
        .replaceAll('°', 'deg')
        .replaceAll('×', 'x')
        .replaceAll('÷', '/')
        .replaceAll('√', 'sqrt')
        .replaceAll('±', '+/-')
        .replaceAll('™', '(TM)')
        .replaceAll('®', '(R)')
        .replaceAll('©', '(C)');
  }

  double _cataloguePdfColumnFlex(String fieldKey) {
    return cataloguePdfColumnFlexForFieldKey(fieldKey);
  }

  double _grossPrice(double netPrice) => netPrice * 1.19;

  double _displayWeight(ItemCatalogueRow item) {
    return _derivedWeightByArticleId[item.icId] ?? item.icWeight;
  }

  Widget _leftAlignedHeader(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(text, textAlign: TextAlign.left),
    );
  }

  DataCell _catalogueDetailCell(Widget child, ItemCatalogueRow item) {
    return DataCell(
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: () => _showCatalogueReadOnly(item),
        child: Align(
          alignment: Alignment.centerLeft,
          child: child,
        ),
      ),
    );
  }

  bool _matchesCatalogueQuery(ItemCatalogueRow item) {
    if (_searchQuery.isEmpty) {
      return true;
    }
    final text = [
      item.icIdi,
      item.icIdv,
      item.icDescriptionDeLong,
      item.icDescriptionEnLong,
      item.icNote,
    ].join(' | ').toLowerCase();
    return text.contains(_searchQuery);
  }

  bool _matchesCatalogueFilter(ItemCatalogueRow item) {
    switch (_catalogueFilter) {
      case _CatalogueFilter.all:
        return true;
      case _CatalogueFilter.zbOnly:
        return item.icIc != 0;
      case _CatalogueFilter.withoutZb:
        return item.icIc == 0;
    }
  }

  bool _matchesVariantFilter(ItemCatalogueRow item) {
    final variantValue = item.icIdv.trim();
    switch (_variantFilter) {
      case _VariantFilter.all:
        return true;
      case _VariantFilter.withVariants:
        return variantValue != '-';
      case _VariantFilter.withoutVariants:
        return variantValue == '-';
    }
  }

  List<ItemCatalogueRow> _visibleCatalogueRows() {
    final result = _catalogueItems
        .where((item) => _matchesCatalogueQuery(item) && _matchesCatalogueFilter(item) && _matchesVariantFilter(item))
        .toList();
    result.sort((a, b) {
      final compare = _compareCatalogueByColumn(a, b, _catalogueSortColumnIndex);
      return _catalogueSortAscending ? compare : -compare;
    });
    return result;
  }

  List<ItemBomRow> _visibleBomRows() {
    final result = List<ItemBomRow>.from(
      _buildVisibleBomRows(
        selectedCatalogueId: _selectedCatalogueId,
        allBomRows: _bomItems,
        includeRoots: false,
      ),
    ).where((row) => _catalogueById.containsKey(row.ibItemId)).toList(growable: false);
    result.sort((a, b) {
      final compare = _compareBomByColumn(a, b, _bomSortColumnIndex);
      return _bomSortAscending ? compare : -compare;
    });
    return result;
  }

  int _compareCatalogueByColumn(ItemCatalogueRow a, ItemCatalogueRow b, int columnIndex) {
    switch (columnIndex) {
      case 0:
        return a.icId.compareTo(b.icId);
      case 1:
        return a.icIdi.toLowerCase().compareTo(b.icIdi.toLowerCase());
      case 2:
        return a.icIdv.toLowerCase().compareTo(b.icIdv.toLowerCase());
      case 3:
        return _grossPrice(a.icPriceNet).compareTo(_grossPrice(b.icPriceNet));
      case 4:
        return a.icPriceNet.compareTo(b.icPriceNet);
      case 5:
        return a.icPriceWholesaleNet.compareTo(b.icPriceWholesaleNet);
      case 6:
        return a.icPurchasePriceNet.compareTo(b.icPurchasePriceNet);
      case 7:
        return _displayWeight(a).compareTo(_displayWeight(b));
      case 8:
        return a.icHts.toLowerCase().compareTo(b.icHts.toLowerCase());
      case 9:
        return a.icStock.compareTo(b.icStock);
      default:
        return a.icId.compareTo(b.icId);
    }
  }

  int? _parentArticleIdOf(ItemBomRow row) {
    final parentBomId = row.ibParentId;
    if (parentBomId == null) {
      return null;
    }

    for (final candidate in _bomItems) {
      if (candidate.ibId == parentBomId) {
        return candidate.ibItemId;
      }
    }
    return null;
  }

  String _parentArticleLabelOf(ItemBomRow row) {
    final parentArticleId = _parentArticleIdOf(row);
    if (parentArticleId == null) {
      return 'Root / kein Parent';
    }

    final parentItem = _catalogueById[parentArticleId];
    final name = parentItem?.icIdi.trim() ?? '';
    return name.isEmpty ? parentArticleId.toString() : '$parentArticleId • $name';
  }

  double _bomNetPurchaseTotalOf(ItemBomRow row) {
    final item = _catalogueById[row.ibItemId];
    if (item == null) {
      return 0;
    }
    return item.icPurchasePriceNet * row.ibQuantity;
  }

  int _compareBomByColumn(ItemBomRow a, ItemBomRow b, int columnIndex) {
    switch (columnIndex) {
      case 0:
        return (a.ibId ?? 0).compareTo(b.ibId ?? 0);
      case 1:
        return a.ibItemId.compareTo(b.ibItemId);
      case 2:
        return (_parentArticleIdOf(a) ?? -1).compareTo(_parentArticleIdOf(b) ?? -1);
      case 3:
        return a.ibQuantity.compareTo(b.ibQuantity);
      case 4:
        final aIdi = (_catalogueById[a.ibItemId]?.icIdi ?? '').toLowerCase();
        final bIdi = (_catalogueById[b.ibItemId]?.icIdi ?? '').toLowerCase();
        return aIdi.compareTo(bIdi);
      case 5:
        return _bomNetPurchaseTotalOf(a).compareTo(_bomNetPurchaseTotalOf(b));
      default:
        return (a.ibId ?? 0).compareTo(b.ibId ?? 0);
    }
  }

  void _onCatalogueSort(int columnIndex, bool ascending) {
    setState(() {
      _catalogueSortColumnIndex = columnIndex;
      _catalogueSortAscending = ascending;
    });
  }

  void _onBomSort(int columnIndex, bool ascending) {
    setState(() {
      _bomSortColumnIndex = columnIndex;
      _bomSortAscending = ascending;
    });
  }

  void _resetCatalogueSort() {
    setState(() {
      _catalogueSortColumnIndex = 0;
      _catalogueSortAscending = true;
    });
  }

  void _resetBomSort() {
    setState(() {
      _bomSortColumnIndex = 0;
      _bomSortAscending = true;
    });
  }

  ItemBomRow? _selectedBomFrom(List<ItemBomRow> rows) {
    final selectedId = _selectedBomId;
    if (selectedId == null) {
      return null;
    }
    for (final row in rows) {
      if (row.ibId == selectedId) {
        return row;
      }
    }
    return null;
  }

  String _safeCatalogueSortLabel() {
    if (_catalogueSortColumnIndex < 0 || _catalogueSortColumnIndex >= _catalogueSortLabels.length) {
      return _catalogueSortLabels.first;
    }
    return _catalogueSortLabels[_catalogueSortColumnIndex];
  }

  String _safeBomSortLabel() {
    if (_bomSortColumnIndex < 0 || _bomSortColumnIndex >= _bomSortLabels.length) {
      return _bomSortLabels.first;
    }
    return _bomSortLabels[_bomSortColumnIndex];
  }

  List<ItemBomRow> _buildVisibleBomRows({
    required int? selectedCatalogueId,
    required List<ItemBomRow> allBomRows,
    required bool includeRoots,
  }) {
    if (selectedCatalogueId == null) {
      return const [];
    }

    final roots = allBomRows
      .where((row) => row.ibItemId == selectedCatalogueId && row.ibParentId == null)
        .toList(growable: false);

    if (roots.isEmpty) {
      return const [];
    }

    final byParent = <int, List<ItemBomRow>>{};
    for (final row in allBomRows) {
      final parentId = row.ibParentId;
      if (parentId == null) {
        continue;
      }
      byParent.putIfAbsent(parentId, () => <ItemBomRow>[]).add(row);
    }

    final includedIds = <int>{};
    final result = <ItemBomRow>[];
    final queue = <int>[];

    for (final root in roots) {
      final rootId = root.ibId;
      if (rootId == null) {
        if (includeRoots) {
          result.add(root);
        }
        continue;
      }
      if (includedIds.add(rootId)) {
        if (includeRoots) {
          result.add(root);
        }
        queue.add(rootId);
      }
    }

    while (queue.isNotEmpty) {
      final currentId = queue.removeLast();
      final children = byParent[currentId] ?? const <ItemBomRow>[];
      for (final child in children) {
        final childId = child.ibId;
        if (childId == null) {
          continue;
        }
        if (includedIds.add(childId)) {
          result.add(child);
          queue.add(childId);
        }
      }
    }

    result.sort((a, b) {
      final parentCompare = (a.ibParentId ?? -1).compareTo(b.ibParentId ?? -1);
      if (parentCompare != 0) {
        return parentCompare;
      }
      final orderCompare = a.ibOrder.compareTo(b.ibOrder);
      if (orderCompare != 0) {
        return orderCompare;
      }
      return (a.ibId ?? 0).compareTo(b.ibId ?? 0);
    });

    return result;
  }

  Future<void> _showCatalogueForm({ItemCatalogueRow? initialValue}) async {
    final lockPurchasePriceNet =
        initialValue != null && _isAutoCalculatedPurchasePriceArticle(initialValue.icId);
    final result = await showDialog<ItemCatalogueRow>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ItemCatalogueFormDialog(
        nextId: _nextCatalogueId(),
        initialValue: initialValue,
        lockPurchasePriceNet: lockPurchasePriceNet,
      ),
    );

    if (result == null) {
      return;
    }

    try {
      final normalizedResult = await _normalizeCatalogueItemImagePath(result);
      await _repository.saveCatalogueItem(normalizedResult);

      try {
        await _icloudSync.syncManagedImage(normalizedResult.icImagePath);
      } catch (error) {
        if (kDebugMode) {
          debugPrint('⚠️ iCloud Sync beim Speichern fehlgeschlagen: $error');
        }
      }

      await _loadData();

      if (!mounted) {
        return;
      }
      setState(() {
        _selectedCatalogueId = normalizedResult.icId;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Speichern fehlgeschlagen: $error')),
      );
    }
  }

  Future<void> _showCatalogueReadOnly(ItemCatalogueRow item) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => ItemCatalogueFormDialog(
        nextId: item.icId,
        initialValue: item,
        readOnly: true,
        lockPurchasePriceNet: _isAutoCalculatedPurchasePriceArticle(item.icId),
      ),
    );
  }

  bool _isAutoCalculatedPurchasePriceArticle(int articleId) {
    final validRows = _bomItems.where((row) => _catalogueById.containsKey(row.ibItemId)).toList(growable: false);
    final parentBomIds = validRows.map((row) => row.ibParentId).whereType<int>().toSet();

    final appearsAsChild = validRows.any((row) => row.ibItemId == articleId && row.ibParentId != null);
    if (appearsAsChild) {
      return false;
    }

    for (final row in validRows) {
      final id = row.ibId;
      if (id == null || row.ibItemId != articleId) {
        continue;
      }

      // Preis nur dann sperren, wenn der Artikel als ausgewiesener Root-Elternknoten
      // in der BOM auftritt und mindestens ein Kind hat. Artikel, die irgendwo
      // als Kind vorkommen, bleiben editierbar.
      if (row.ibParentId == null && parentBomIds.contains(id)) {
        return true;
      }
    }

    return false;
  }

  Future<ItemCatalogueRow> _normalizeCatalogueItemImagePath(ItemCatalogueRow item) async {
    final rawPath = item.icImagePath.trim();
    if (rawPath.isEmpty || !p.isAbsolute(rawPath)) {
      return item;
    }

    final normalizedPath = await _imageStorage.normalizeForStorage(
      rawPath: rawPath,
      itemId: item.icId,
    );
    if (normalizedPath == rawPath) {
      return item;
    }
    return item.copyWith(icImagePath: normalizedPath);
  }

  Future<void> _deleteCatalogue(ItemCatalogueRow item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Katalogeintrag loeschen?'),
        content: Text('Eintrag #${item.icId} wird inklusive zugehoeriger BOM-Eintraege geloescht.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Loeschen'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    await _repository.deleteCatalogueItem(item.icId);
    await _loadData();
  }

  Future<void> _duplicateCatalogue(ItemCatalogueRow item) async {
    final duplicateMode = await showDialog<_DuplicateMode>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Artikel duplizieren'),
        content: Text(
          'Waehle aus, ob nur der Artikel oder auch die BOM-Struktur kopiert werden soll.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(_DuplicateMode.articleOnly),
            child: const Text('Nur Artikel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_DuplicateMode.articleWithBom),
            child: const Text('Artikel + BOM'),
          ),
        ],
      ),
    );
    if (duplicateMode == null) {
      return;
    }

    final duplicateResult = await _repository.duplicateCatalogueItemWithBom(
      item.icId,
      includeBom: duplicateMode == _DuplicateMode.articleWithBom,
    );
    await _loadData();

    if (!mounted) {
      return;
    }

    setState(() {
      _selectedCatalogueId = duplicateResult.newCatalogueId;
      _selectedBomId = null;
    });

    final copiedBomRows = duplicateResult.duplicatedBomRows;
    final copiedAnchors = duplicateResult.duplicatedAnchorRows;
    final message = duplicateMode == _DuplicateMode.articleOnly
        ? 'Artikel wurde dupliziert.'
        : 'Artikel wurde mit BOM dupliziert ($copiedBomRows Zeilen).';
    final debugSuffix = kDebugMode && duplicateMode == _DuplicateMode.articleWithBom
        ? ' [Anker: $copiedAnchors, Zeilen: $copiedBomRows]'
        : '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$message$debugSuffix')),
    );
  }

  Future<void> _showBomForm({ItemBomRow? initialValue, int? forcedParentBomId}) async {
    final selectedCatalogueId = _selectedCatalogueId;
    if (selectedCatalogueId == null && _catalogueItems.isEmpty) {
      return;
    }

    var initialParentId = forcedParentBomId ?? initialValue?.ibParentId;
    var initialItemId = initialValue?.ibItemId ?? selectedCatalogueId;

    if (initialValue == null && selectedCatalogueId != null) {
      if (forcedParentBomId != null) {
        final forcedParent = _bomItems.cast<ItemBomRow?>().firstWhere(
              (row) => row?.ibId == forcedParentBomId,
              orElse: () => null,
            );
        initialParentId = forcedParent?.ibId;
      } else {
        final existingRoot = _bomItems.where((row) => row.ibItemId == selectedCatalogueId && row.ibParentId == null).cast<ItemBomRow?>().firstWhere(
              (row) => row != null,
              orElse: () => null,
            );

        ItemBomRow? rootRow = existingRoot;
        if (rootRow == null) {
          rootRow = ItemBomRow(
            ibId: _nextBomId(),
            ibItemId: selectedCatalogueId,
            ibParentId: null,
            ibQuantity: 1,
          );
          if (widget.loadOnInit) {
            await _repository.saveBomItem(rootRow);
          }
          final nextBomItems = List<ItemBomRow>.from(_bomItems);
          nextBomItems.add(rootRow);
          _bomItems = List<ItemBomRow>.unmodifiable(nextBomItems);
        }

        initialParentId = rootRow.ibId;
      }
      initialItemId = null;
    }

    final dialogBomItems = selectedCatalogueId == null
        ? _bomItems
        : (forcedParentBomId != null
              ? _bomItems
              : _buildVisibleBomRows(
                  selectedCatalogueId: selectedCatalogueId,
                  allBomRows: _bomItems,
                  includeRoots: true,
                ));

    final validDialogBomItems = dialogBomItems
        .where((row) => _catalogueById.containsKey(row.ibItemId))
        .toList(growable: false);
    final validDialogParentIds = validDialogBomItems
        .map((row) => row.ibId)
        .whereType<int>()
        .toSet();

    if (initialParentId != null && !validDialogParentIds.contains(initialParentId)) {
      if (initialValue == null && selectedCatalogueId != null) {
        final fallbackRoot = validDialogBomItems.cast<ItemBomRow?>().firstWhere(
              (row) => row?.ibItemId == selectedCatalogueId && row?.ibParentId == null,
              orElse: () => null,
            );
        initialParentId = fallbackRoot?.ibId;
      } else {
        initialParentId = null;
      }
    }

    if (initialParentId == null && initialValue == null && selectedCatalogueId != null) {
      final fallbackRoot = validDialogBomItems.cast<ItemBomRow?>().firstWhere(
            (row) => row?.ibItemId == selectedCatalogueId && row?.ibParentId == null,
            orElse: () => null,
          );
      initialParentId = fallbackRoot?.ibId;
    }

    if (!mounted) {
      return;
    }

    final result = await showDialog<ItemBomRow>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ItemBomFormDialog(
        catalogueItems: _catalogueItems,
        availableBomItems: validDialogBomItems,
        nextId: _nextBomId(),
        initialValue: initialValue,
        initialParentId: initialParentId,
        initialItemId: initialItemId,
      ),
    );

    if (result == null) {
      return;
    }

    await _repository.saveBomItem(result);
    await _loadData();

    if (!mounted) {
      return;
    }
    setState(() {
      _selectedBomId = result.ibId;
    });
  }

  Future<void> _deleteBom(ItemBomRow item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('BOM-Eintrag loeschen?'),
        content: Text('Eintrag #${item.ibId ?? 0} wird inklusive aller Nachkommen geloescht.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Loeschen'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    final id = item.ibId;
    if (id == null) {
      return;
    }

    await _repository.deleteBomItem(id);
    await _loadData();
  }

  Widget _buildCatalogueImagePreview(ItemCatalogueRow item, {double size = 40}) {
    final storedPath = item.icImagePath.trim();
    if (storedPath.isEmpty) {
      return _emptyImagePreview(size: size);
    }

    return FutureBuilder<String?>(
      future: _imageStorage.resolveAbsolutePath(storedPath),
      builder: (context, snapshot) {
        final resolvedPath = snapshot.data?.trim();
        if (resolvedPath == null || resolvedPath.isEmpty) {
          return _emptyImagePreview(size: size);
        }

        final file = File(resolvedPath);
        if (!file.existsSync()) {
          return _emptyImagePreview(size: size);
        }

        return Tooltip(
          message: 'Klicken zum Vergroessern',
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _showCatalogueImageDialog(file),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: size,
                height: size,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Image.file(
                  file,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => _emptyImagePreview(size: size),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showCatalogueImageDialog(File file) async {
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

  Widget _emptyImagePreview({double size = 40}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.image_not_supported_outlined,
        size: size * 0.4,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildCatalogueSection() {
    final visibleItems = _visibleCatalogueRows();
    final selectedItem = _selectedCatalogueId == null ? null : _catalogueById[_selectedCatalogueId!];

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, catalogueConstraints) {
            final compactVerticalSpacing = catalogueConstraints.maxHeight < 460;
            final useCompactControls = catalogueConstraints.maxHeight < 560;
            final useUltraCompactControls = catalogueConstraints.maxHeight < 420;
            final useCompactButtons = catalogueConstraints.maxHeight < 620 || catalogueConstraints.maxWidth < 1100;
            final sectionGap = useUltraCompactControls ? 2.0 : (compactVerticalSpacing ? 4.0 : 10.0);
            final sortGap = useUltraCompactControls ? 0.0 : (compactVerticalSpacing ? 2.0 : 6.0);
            final compactFilledStyle = FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size(0, useUltraCompactControls ? 30 : 34),
              padding: EdgeInsets.symmetric(horizontal: useUltraCompactControls ? 8 : 10, vertical: useUltraCompactControls ? 6 : 8),
            );
            final compactOutlinedStyle = OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size(0, useUltraCompactControls ? 30 : 34),
              padding: EdgeInsets.symmetric(horizontal: useUltraCompactControls ? 8 : 10, vertical: useUltraCompactControls ? 6 : 8),
            );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
            Row(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrow = constraints.maxWidth < 980;

                      if (isNarrow) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _searchQuery.isEmpty
                                  ? 'Artikelkatalog (${_catalogueItems.length})'
                                  : 'Artikelkatalog (${visibleItems.length} von ${_catalogueItems.length})',
                              style: useUltraCompactControls
                                  ? Theme.of(context).textTheme.titleSmall
                                  : Theme.of(context).textTheme.titleMedium,
                            ),
                            SizedBox(height: useUltraCompactControls ? 4 : 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: useUltraCompactControls ? 4 : 8,
                              children: [
                                if (useUltraCompactControls)
                                  IconButton.filledTonal(
                                    tooltip: 'Neu',
                                    onPressed: _loading ? null : () => _showCatalogueForm(),
                                    icon: const Icon(Icons.add),
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.all(6),
                                  )
                                else
                                  FilledButton.icon(
                                    onPressed: _loading ? null : () => _showCatalogueForm(),
                                    style: useCompactButtons ? compactFilledStyle : null,
                                    icon: const Icon(Icons.add),
                                    label: const Text('Neu'),
                                  ),
                                if (useUltraCompactControls)
                                  IconButton.outlined(
                                    tooltip: 'Bearbeiten',
                                    onPressed: _loading || selectedItem == null ? null : () => _showCatalogueForm(initialValue: selectedItem),
                                    icon: const Icon(Icons.edit_outlined),
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.all(6),
                                  )
                                else
                                  OutlinedButton.icon(
                                    onPressed:
                                        _loading || selectedItem == null ? null : () => _showCatalogueForm(initialValue: selectedItem),
                                    style: useCompactButtons ? compactOutlinedStyle : null,
                                    icon: const Icon(Icons.edit_outlined),
                                    label: const Text('Bearbeiten'),
                                  ),
                                if (useUltraCompactControls)
                                  IconButton.outlined(
                                    tooltip: 'Duplizieren',
                                    onPressed: _loading || selectedItem == null ? null : () => _duplicateCatalogue(selectedItem),
                                    icon: const Icon(Icons.copy_outlined),
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.all(6),
                                  )
                                else
                                  OutlinedButton.icon(
                                    onPressed: _loading || selectedItem == null ? null : () => _duplicateCatalogue(selectedItem),
                                    style: useCompactButtons ? compactOutlinedStyle : null,
                                    icon: const Icon(Icons.copy_outlined),
                                    label: const Text('Duplizieren'),
                                  ),
                                if (useUltraCompactControls)
                                  IconButton.outlined(
                                    tooltip: 'Loeschen',
                                    onPressed: _loading || selectedItem == null ? null : () => _deleteCatalogue(selectedItem),
                                    icon: const Icon(Icons.delete_outline),
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.all(6),
                                  )
                                else
                                  OutlinedButton.icon(
                                    onPressed: _loading || selectedItem == null ? null : () => _deleteCatalogue(selectedItem),
                                    style: useCompactButtons ? compactOutlinedStyle : null,
                                    icon: const Icon(Icons.delete_outline),
                                    label: const Text('Loeschen'),
                                  ),
                              ],
                            ),
                          ],
                        );
                      }

                      return Row(
                        children: [
                          Expanded(
                            child: Text(
                              _searchQuery.isEmpty
                                  ? 'Artikelkatalog (${_catalogueItems.length})'
                                  : 'Artikelkatalog (${visibleItems.length} von ${_catalogueItems.length})',
                              style: useUltraCompactControls
                                  ? Theme.of(context).textTheme.titleSmall
                                  : Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          if (useUltraCompactControls)
                            IconButton.filledTonal(
                              tooltip: 'Neu',
                              onPressed: _loading ? null : () => _showCatalogueForm(),
                              icon: const Icon(Icons.add),
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.all(6),
                            )
                          else
                            FilledButton.icon(
                              onPressed: _loading ? null : () => _showCatalogueForm(),
                              style: useCompactButtons ? compactFilledStyle : null,
                              icon: const Icon(Icons.add),
                              label: const Text('Neu'),
                            ),
                          const SizedBox(width: 8),
                          if (useUltraCompactControls)
                            IconButton.outlined(
                              tooltip: 'Bearbeiten',
                              onPressed: _loading || selectedItem == null ? null : () => _showCatalogueForm(initialValue: selectedItem),
                              icon: const Icon(Icons.edit_outlined),
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.all(6),
                            )
                          else
                            OutlinedButton.icon(
                              onPressed: _loading || selectedItem == null ? null : () => _showCatalogueForm(initialValue: selectedItem),
                              style: useCompactButtons ? compactOutlinedStyle : null,
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Bearbeiten'),
                            ),
                          const SizedBox(width: 8),
                          if (useUltraCompactControls)
                            IconButton.outlined(
                              tooltip: 'Duplizieren',
                              onPressed: _loading || selectedItem == null ? null : () => _duplicateCatalogue(selectedItem),
                              icon: const Icon(Icons.copy_outlined),
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.all(6),
                            )
                          else
                            OutlinedButton.icon(
                              onPressed: _loading || selectedItem == null ? null : () => _duplicateCatalogue(selectedItem),
                              style: useCompactButtons ? compactOutlinedStyle : null,
                              icon: const Icon(Icons.copy_outlined),
                              label: const Text('Duplizieren'),
                            ),
                          const SizedBox(width: 8),
                          if (useUltraCompactControls)
                            IconButton.outlined(
                              tooltip: 'Loeschen',
                              onPressed: _loading || selectedItem == null ? null : () => _deleteCatalogue(selectedItem),
                              icon: const Icon(Icons.delete_outline),
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.all(6),
                            )
                          else
                            OutlinedButton.icon(
                              onPressed: _loading || selectedItem == null ? null : () => _deleteCatalogue(selectedItem),
                              style: useCompactButtons ? compactOutlinedStyle : null,
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Loeschen'),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
            SizedBox(height: sectionGap),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Artikel suchen',
                hintText: 'Bezeichnung, Variante, Beschreibung/Description, Notiz ...',
                prefixIcon: const Icon(Icons.search),
                isDense: useCompactControls,
                contentPadding: useCompactControls
                  ? EdgeInsets.symmetric(horizontal: 10, vertical: useUltraCompactControls ? 8 : 10)
                  : null,
                prefixIconConstraints: useCompactControls
                  ? BoxConstraints(minWidth: useUltraCompactControls ? 32 : 36, minHeight: useUltraCompactControls ? 32 : 36)
                  : null,
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Suche loeschen',
                        onPressed: () => _searchController.clear(),
                        icon: const Icon(Icons.clear),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
            SizedBox(height: sectionGap),
            if (useCompactControls)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 4),
                dense: useUltraCompactControls,
                title: Text(
                  'Filter & Sortierung',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Alle Artikel'),
                        selected: _catalogueFilter == _CatalogueFilter.all,
                        onSelected: (_) => setState(() => _catalogueFilter = _CatalogueFilter.all),
                      ),
                      ChoiceChip(
                        label: const Text('ZB-Komponenten'),
                        selected: _catalogueFilter == _CatalogueFilter.zbOnly,
                        onSelected: (_) => setState(() => _catalogueFilter = _CatalogueFilter.zbOnly),
                      ),
                      ChoiceChip(
                        label: const Text('ohne ZB-Komponenten'),
                        selected: _catalogueFilter == _CatalogueFilter.withoutZb,
                        onSelected: (_) => setState(() => _catalogueFilter = _CatalogueFilter.withoutZb),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        key: const ValueKey('variant-filter-all'),
                        label: const Text('Alle Varianten'),
                        selected: _variantFilter == _VariantFilter.all,
                        onSelected: (_) => setState(() => _variantFilter = _VariantFilter.all),
                      ),
                      ChoiceChip(
                        key: const ValueKey('variant-filter-with'),
                        label: const Text('Varianten'),
                        selected: _variantFilter == _VariantFilter.withVariants,
                        onSelected: (_) => setState(() => _variantFilter = _VariantFilter.withVariants),
                      ),
                      ChoiceChip(
                        key: const ValueKey('variant-filter-without'),
                        label: const Text('ohne Varianten'),
                        selected: _variantFilter == _VariantFilter.withoutVariants,
                        onSelected: (_) => setState(() => _variantFilter = _VariantFilter.withoutVariants),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Sortierung: ${_safeCatalogueSortLabel()} '
                        '${_catalogueSortAscending ? 'aufsteigend' : 'absteigend'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      TextButton.icon(
                        onPressed: _resetCatalogueSort,
                        icon: const Icon(Icons.sort),
                        label: const Text('Sortierung zuruecksetzen'),
                      ),
                    ],
                  ),
                ],
              )
            else ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Alle Artikel'),
                    selected: _catalogueFilter == _CatalogueFilter.all,
                    onSelected: (_) => setState(() => _catalogueFilter = _CatalogueFilter.all),
                  ),
                  ChoiceChip(
                    label: const Text('ZB-Komponenten'),
                    selected: _catalogueFilter == _CatalogueFilter.zbOnly,
                    onSelected: (_) => setState(() => _catalogueFilter = _CatalogueFilter.zbOnly),
                  ),
                  ChoiceChip(
                    label: const Text('ohne ZB-Komponenten'),
                    selected: _catalogueFilter == _CatalogueFilter.withoutZb,
                    onSelected: (_) => setState(() => _catalogueFilter = _CatalogueFilter.withoutZb),
                  ),
                ],
              ),
              SizedBox(height: compactVerticalSpacing ? 6 : 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    key: const ValueKey('variant-filter-all'),
                    label: const Text('Alle Varianten'),
                    selected: _variantFilter == _VariantFilter.all,
                    onSelected: (_) => setState(() => _variantFilter = _VariantFilter.all),
                  ),
                  ChoiceChip(
                    key: const ValueKey('variant-filter-with'),
                    label: const Text('Varianten'),
                    selected: _variantFilter == _VariantFilter.withVariants,
                    onSelected: (_) => setState(() => _variantFilter = _VariantFilter.withVariants),
                  ),
                  ChoiceChip(
                    key: const ValueKey('variant-filter-without'),
                    label: const Text('ohne Varianten'),
                    selected: _variantFilter == _VariantFilter.withoutVariants,
                    onSelected: (_) => setState(() => _variantFilter = _VariantFilter.withoutVariants),
                  ),
                ],
              ),
              SizedBox(height: sectionGap),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Sortierung: ${_safeCatalogueSortLabel()} '
                    '${_catalogueSortAscending ? 'aufsteigend' : 'absteigend'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  TextButton.icon(
                    onPressed: _resetCatalogueSort,
                    icon: const Icon(Icons.sort),
                    label: const Text('Sortierung zuruecksetzen'),
                  ),
                ],
              ),
            ],
            SizedBox(height: sortGap),
            Expanded(
              child: visibleItems.isEmpty
                  ? const Center(child: Text('Keine Artikel im Katalog vorhanden.'))
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final isCompact = constraints.maxWidth < 1180;
                        final useExternalScroll = Platform.isIOS;
                        const tableMinWidth = 1260.0;

                        final columns = [
                          DataColumn2(
                            size: ColumnSize.S,
                            label: _leftAlignedHeader('Artikel-ID'),
                            headingRowAlignment: MainAxisAlignment.start,
                            onSort: _onCatalogueSort,
                          ),
                          DataColumn2(
                            size: ColumnSize.L,
                            label: _leftAlignedHeader('Bezeichnung'),
                            headingRowAlignment: MainAxisAlignment.start,
                            onSort: _onCatalogueSort,
                          ),
                          DataColumn2(
                            size: ColumnSize.M,
                            label: _leftAlignedHeader('Variante'),
                            headingRowAlignment: MainAxisAlignment.start,
                            onSort: _onCatalogueSort,
                          ),
                          DataColumn2(
                            size: ColumnSize.M,
                            label: _leftAlignedHeader('Bruttopreis\nincl. 19%'),
                            headingRowAlignment: MainAxisAlignment.start,
                            onSort: _onCatalogueSort,
                          ),
                          DataColumn2(
                            size: ColumnSize.S,
                            label: _leftAlignedHeader('Nettopreis'),
                            headingRowAlignment: MainAxisAlignment.start,
                            onSort: _onCatalogueSort,
                          ),
                          DataColumn2(
                            size: ColumnSize.M,
                            label: _leftAlignedHeader('Netto\nHaendlerpreis'),
                            headingRowAlignment: MainAxisAlignment.start,
                            onSort: _onCatalogueSort,
                          ),
                          DataColumn2(
                            size: ColumnSize.M,
                            label: _leftAlignedHeader('Netto\nEinkaufspreis'),
                            headingRowAlignment: MainAxisAlignment.start,
                            onSort: _onCatalogueSort,
                          ),
                          DataColumn2(
                            size: ColumnSize.S,
                            label: _leftAlignedHeader('Gewicht in g'),
                            headingRowAlignment: MainAxisAlignment.start,
                            onSort: _onCatalogueSort,
                          ),
                          DataColumn2(
                            size: ColumnSize.S,
                            label: _leftAlignedHeader('HTS Code'),
                            headingRowAlignment: MainAxisAlignment.start,
                            onSort: _onCatalogueSort,
                          ),
                          DataColumn2(
                            size: ColumnSize.S,
                            label: _leftAlignedHeader('Bestand'),
                            headingRowAlignment: MainAxisAlignment.start,
                            onSort: _onCatalogueSort,
                          ),
                          DataColumn2(
                            fixedWidth: 56,
                            label: _leftAlignedHeader('Bild'),
                            headingRowAlignment: MainAxisAlignment.start,
                          ),
                        ];

                        final rows = visibleItems
                            .map(
                              (item) => DataRow(
                                selected: item.icId == _selectedCatalogueId,
                                onSelectChanged: (selected) {
                                  if (selected != true) {
                                    return;
                                  }
                                  setState(() {
                                    _selectedCatalogueId = item.icId;
                                    _selectedBomId = null;
                                  });
                                },
                                cells: [
                                  _catalogueDetailCell(Text(item.icId.toString()), item),
                                  _catalogueDetailCell(Text(item.icIdi), item),
                                  _catalogueDetailCell(Text(item.icIdv), item),
                                  _catalogueDetailCell(Text(_formatDecimal(_grossPrice(item.icPriceNet), 2)), item),
                                  _catalogueDetailCell(Text(_formatDecimal(item.icPriceNet, 2)), item),
                                  _catalogueDetailCell(Text(_formatDecimal(item.icPriceWholesaleNet, 2)), item),
                                  _catalogueDetailCell(Text(_formatDecimal(item.icPurchasePriceNet, 2)), item),
                                  _catalogueDetailCell(Text(_formatDecimal(_displayWeight(item), 1)), item),
                                  _catalogueDetailCell(_buildHtsLink(item.icHts), item),
                                  _catalogueDetailCell(Text(item.icStock.toString()), item),
                                  _catalogueDetailCell(_buildCatalogueImagePreview(item, size: 32), item),
                                ],
                              ),
                            )
                            .toList(growable: false);

                        if (useExternalScroll) {
                          const iosHeaders = <String>[
                            'Artikel-ID',
                            'Bezeichnung',
                            'Variante',
                            'Bruttopreis\nincl. 19%',
                            'Nettopreis',
                            'Netto\nHaendlerpreis',
                            'Netto\nEinkaufspreis',
                            'Gewicht in g',
                            'HTS Code',
                            'Bestand',
                            'Bild',
                          ];
                          const iosColumnWidths = <double>[90, 220, 120, 130, 110, 150, 150, 100, 100, 90, 72];
                          final iosColumnsTotalWidth = iosColumnWidths.fold<double>(0, (sum, width) => sum + width);
                          final iosTableWidth = iosColumnsTotalWidth > tableMinWidth ? iosColumnsTotalWidth : tableMinWidth;
                          final hideIosHeader = constraints.maxHeight < 140;

                          Widget buildIosCell(double width, Widget child, {bool center = false, double verticalPadding = 10}) {
                            return SizedBox(
                              width: width,
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8, vertical: verticalPadding),
                                child: Align(
                                  alignment: center ? Alignment.center : Alignment.centerLeft,
                                  child: child,
                                ),
                              ),
                            );
                          }

                          Widget buildHeaderCell(int index) {
                            final label = Text(
                              iosHeaders[index],
                              style: Theme.of(context).textTheme.labelMedium,
                            );
                            if (index == iosHeaders.length - 1) {
                              return buildIosCell(iosColumnWidths[index], label, center: true);
                            }

                            return InkWell(
                              onTap: () {
                                final nextAscending = _catalogueSortColumnIndex == index ? !_catalogueSortAscending : true;
                                _onCatalogueSort(index, nextAscending);
                              },
                              child: buildIosCell(iosColumnWidths[index], label),
                            );
                          }

                          return ExcludeSemantics(
                            child: SingleChildScrollView(
                              controller: _catalogueHorizontalController,
                              scrollDirection: Axis.horizontal,
                              child: SizedBox(
                                width: iosTableWidth,
                                height: constraints.maxHeight,
                                child: Column(
                                  children: [
                                    if (!hideIosHeader)
                                      DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                          border: Border(
                                            top: BorderSide(color: Theme.of(context).dividerColor),
                                            bottom: BorderSide(color: Theme.of(context).dividerColor),
                                          ),
                                        ),
                                        child: Row(
                                          children: List<Widget>.generate(iosHeaders.length, buildHeaderCell),
                                        ),
                                      ),
                                    Expanded(
                                      child: Scrollbar(
                                        controller: _catalogueVerticalController,
                                        thumbVisibility: true,
                                        trackVisibility: true,
                                        child: ListView.builder(
                                          controller: _catalogueVerticalController,
                                          itemCount: visibleItems.length,
                                          itemBuilder: (context, index) {
                                            final item = visibleItems[index];
                                            final selected = item.icId == _selectedCatalogueId;
                                            final rowColor = selected
                                                ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35)
                                                : (index.isEven
                                                    ? Theme.of(context).colorScheme.surface
                                                    : Theme.of(context).colorScheme.surfaceContainerLowest);

                                            return Material(
                                              color: rowColor,
                                              child: InkWell(
                                                onTap: () {
                                                  setState(() {
                                                    _selectedCatalogueId = item.icId;
                                                    _selectedBomId = null;
                                                  });
                                                },
                                                onDoubleTap: () => _showCatalogueReadOnly(item),
                                                child: Row(
                                                  children: [
                                                    buildIosCell(iosColumnWidths[0], Text(item.icId.toString()), verticalPadding: 8),
                                                    buildIosCell(iosColumnWidths[1], Text(item.icIdi), verticalPadding: 8),
                                                    buildIosCell(iosColumnWidths[2], Text(item.icIdv), verticalPadding: 8),
                                                    buildIosCell(iosColumnWidths[3], Text(_formatDecimal(_grossPrice(item.icPriceNet), 2)), verticalPadding: 8),
                                                    buildIosCell(iosColumnWidths[4], Text(_formatDecimal(item.icPriceNet, 2)), verticalPadding: 8),
                                                    buildIosCell(iosColumnWidths[5], Text(_formatDecimal(item.icPriceWholesaleNet, 2)), verticalPadding: 8),
                                                    buildIosCell(iosColumnWidths[6], Text(_formatDecimal(item.icPurchasePriceNet, 2)), verticalPadding: 8),
                                                    buildIosCell(iosColumnWidths[7], Text(_formatDecimal(_displayWeight(item), 1)), verticalPadding: 8),
                                                    buildIosCell(iosColumnWidths[8], _buildHtsLink(item.icHts), verticalPadding: 8),
                                                    buildIosCell(iosColumnWidths[9], Text(item.icStock.toString()), verticalPadding: 8),
                                                    buildIosCell(iosColumnWidths[10], _buildCatalogueImagePreview(item, size: 32), center: true, verticalPadding: 6),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }

                        return DataTable2(
                          showCheckboxColumn: false,
                          sortColumnIndex: _catalogueSortColumnIndex,
                          sortAscending: _catalogueSortAscending,
                          scrollController: _catalogueVerticalController,
                          horizontalScrollController: _catalogueHorizontalController,
                          isVerticalScrollBarVisible: true,
                          isHorizontalScrollBarVisible: true,
                          columnSpacing: isCompact ? 10.0 : 16.0,
                          horizontalMargin: isCompact ? 8.0 : 12.0,
                          minWidth: tableMinWidth,
                          fixedTopRows: 1,
                          columns: columns,
                          rows: rows,
                        );
                      },
                    ),
            ),
          ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBomSection() {
    final selectedCatalogueId = _selectedCatalogueId;
    final selectedCatalogue = selectedCatalogueId == null ? null : _catalogueById[selectedCatalogueId];
    final visibleBomRows = _visibleBomRows();
    final selectableParentBomRows = _buildVisibleBomRows(
      selectedCatalogueId: selectedCatalogueId,
      allBomRows: _bomItems,
      includeRoots: true,
    ).where((row) => _catalogueById.containsKey(row.ibItemId)).toList(growable: false);
    final selectedBom = _selectedBomFrom(visibleBomRows);
    final selectedBomParent = _selectedBomFrom(selectableParentBomRows);

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, bomConstraints) {
            final compactVerticalSpacing = bomConstraints.maxHeight < 420;
            final useUltraCompactControls = bomConstraints.maxHeight < 340;
            final useCompactButtons = bomConstraints.maxHeight < 420 || bomConstraints.maxWidth < 980;
            final useActionMenu = bomConstraints.maxHeight < 420 || bomConstraints.maxWidth < 860;
            final sectionGap = compactVerticalSpacing ? 3.0 : 10.0;
            final sortGap = compactVerticalSpacing ? 0.0 : 6.0;
            final compactFilledStyle = FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: const Size(0, 34),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            );
            final compactOutlinedStyle = OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: const Size(0, 34),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
            Row(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrow = constraints.maxWidth < 900;

                      if (isNarrow) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              selectedCatalogue == null
                                  ? 'BOM (kein Artikel ausgewaehlt)'
                                  : 'BOM zu #${selectedCatalogue.icId} • ${selectedCatalogue.icIdi} (${visibleBomRows.length})',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (!useActionMenu)
                                  if (useUltraCompactControls)
                                    IconButton.filledTonal(
                                      tooltip: 'Neu',
                                      onPressed: _loading || selectedCatalogueId == null ? null : () => _showBomForm(),
                                      icon: const Icon(Icons.add),
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.all(6),
                                    )
                                  else
                                    FilledButton.icon(
                                      onPressed: _loading || selectedCatalogueId == null ? null : () => _showBomForm(),
                                      style: useCompactButtons ? compactFilledStyle : null,
                                      icon: const Icon(Icons.add),
                                      label: const Text('Neu'),
                                    ),
                                if (!useActionMenu)
                                  if (useUltraCompactControls)
                                    IconButton.outlined(
                                      tooltip: 'Neu unter markiertem Eintrag',
                                      onPressed: _loading || selectedBomParent == null
                                          ? null
                                          : () => _showBomForm(forcedParentBomId: selectedBomParent.ibId),
                                      icon: const Icon(Icons.subdirectory_arrow_right),
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.all(6),
                                    )
                                  else
                                    OutlinedButton.icon(
                                      onPressed: _loading || selectedBomParent == null
                                          ? null
                                          : () => _showBomForm(forcedParentBomId: selectedBomParent.ibId),
                                      style: useCompactButtons ? compactOutlinedStyle : null,
                                      icon: const Icon(Icons.subdirectory_arrow_right),
                                      label: const Text('Neu unter markiertem'),
                                    ),
                                if (!useActionMenu)
                                  if (useUltraCompactControls)
                                    IconButton.outlined(
                                      tooltip: 'Bearbeiten',
                                      onPressed: _loading || selectedBom == null ? null : () => _showBomForm(initialValue: selectedBom),
                                      icon: const Icon(Icons.edit_outlined),
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.all(6),
                                    )
                                  else
                                    OutlinedButton.icon(
                                      onPressed: _loading || selectedBom == null ? null : () => _showBomForm(initialValue: selectedBom),
                                      style: useCompactButtons ? compactOutlinedStyle : null,
                                      icon: const Icon(Icons.edit_outlined),
                                      label: const Text('Bearbeiten'),
                                    ),
                                if (!useActionMenu)
                                  if (useUltraCompactControls)
                                    IconButton.outlined(
                                      tooltip: 'Loeschen',
                                      onPressed: _loading || selectedBom == null ? null : () => _deleteBom(selectedBom),
                                      icon: const Icon(Icons.delete_outline),
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.all(6),
                                    )
                                  else
                                    OutlinedButton.icon(
                                      onPressed: _loading || selectedBom == null ? null : () => _deleteBom(selectedBom),
                                      style: useCompactButtons ? compactOutlinedStyle : null,
                                      icon: const Icon(Icons.delete_outline),
                                      label: const Text('Loeschen'),
                                    ),
                              ],
                            ),
                            if (useActionMenu)
                              Align(
                                alignment: Alignment.centerRight,
                                child: PopupMenuButton<String>(
                                  tooltip: 'BOM Aktionen',
                                  onSelected: (value) {
                                    switch (value) {
                                      case 'new':
                                        _showBomForm();
                                        break;
                                      case 'new_child':
                                        if (selectedBomParent != null) {
                                          _showBomForm(forcedParentBomId: selectedBomParent.ibId);
                                        }
                                        break;
                                      case 'edit':
                                        if (selectedBom != null) {
                                          _showBomForm(initialValue: selectedBom);
                                        }
                                        break;
                                      case 'delete':
                                        if (selectedBom != null) {
                                          _deleteBom(selectedBom);
                                        }
                                        break;
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    PopupMenuItem<String>(
                                      value: 'new',
                                      enabled: !_loading && selectedCatalogueId != null,
                                      child: const Text('Neu'),
                                    ),
                                    PopupMenuItem<String>(
                                      value: 'edit',
                                      enabled: !_loading && selectedBom != null,
                                      child: const Text('Bearbeiten'),
                                    ),
                                    PopupMenuItem<String>(
                                      value: 'new_child',
                                      enabled: !_loading && selectedBomParent != null,
                                      child: const Text('Neu unter markiertem'),
                                    ),
                                    PopupMenuItem<String>(
                                      value: 'delete',
                                      enabled: !_loading && selectedBom != null,
                                      child: const Text('Loeschen'),
                                    ),
                                  ],
                                  child: const Icon(Icons.more_horiz),
                                ),
                              ),
                          ],
                        );
                      }

                      return Row(
                        children: [
                          Expanded(
                            child: Text(
                              selectedCatalogue == null
                                  ? 'BOM (kein Artikel ausgewaehlt)'
                                  : 'BOM zu #${selectedCatalogue.icId} • ${selectedCatalogue.icIdi} (${visibleBomRows.length})',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          if (useActionMenu)
                            PopupMenuButton<String>(
                              tooltip: 'BOM Aktionen',
                              onSelected: (value) {
                                switch (value) {
                                  case 'new':
                                    _showBomForm();
                                    break;
                                  case 'new_child':
                                    if (selectedBomParent != null) {
                                      _showBomForm(forcedParentBomId: selectedBomParent.ibId);
                                    }
                                    break;
                                  case 'edit':
                                    if (selectedBom != null) {
                                      _showBomForm(initialValue: selectedBom);
                                    }
                                    break;
                                  case 'delete':
                                    if (selectedBom != null) {
                                      _deleteBom(selectedBom);
                                    }
                                    break;
                                }
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem<String>(
                                  value: 'new',
                                  enabled: !_loading && selectedCatalogueId != null,
                                  child: const Text('Neu'),
                                ),
                                PopupMenuItem<String>(
                                  value: 'edit',
                                  enabled: !_loading && selectedBom != null,
                                  child: const Text('Bearbeiten'),
                                ),
                                PopupMenuItem<String>(
                                  value: 'new_child',
                                  enabled: !_loading && selectedBomParent != null,
                                  child: const Text('Neu unter markiertem'),
                                ),
                                PopupMenuItem<String>(
                                  value: 'delete',
                                  enabled: !_loading && selectedBom != null,
                                  child: const Text('Loeschen'),
                                ),
                              ],
                              icon: const Icon(Icons.more_horiz),
                            )
                          else if (useUltraCompactControls)
                            IconButton.filledTonal(
                              tooltip: 'Neu',
                              onPressed: _loading || selectedCatalogueId == null ? null : () => _showBomForm(),
                              icon: const Icon(Icons.add),
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.all(6),
                            )
                          else
                            FilledButton.icon(
                              onPressed: _loading || selectedCatalogueId == null ? null : () => _showBomForm(),
                              style: useCompactButtons ? compactFilledStyle : null,
                              icon: const Icon(Icons.add),
                              label: const Text('Neu'),
                            ),
                          if (!useActionMenu) const SizedBox(width: 8),
                          if (!useActionMenu)
                            if (useUltraCompactControls)
                              IconButton.outlined(
                                tooltip: 'Neu unter markiertem Eintrag',
                                onPressed: _loading || selectedBomParent == null
                                    ? null
                                    : () => _showBomForm(forcedParentBomId: selectedBomParent.ibId),
                                icon: const Icon(Icons.subdirectory_arrow_right),
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.all(6),
                              )
                            else
                              OutlinedButton.icon(
                                onPressed: _loading || selectedBomParent == null
                                    ? null
                                    : () => _showBomForm(forcedParentBomId: selectedBomParent.ibId),
                                style: useCompactButtons ? compactOutlinedStyle : null,
                                icon: const Icon(Icons.subdirectory_arrow_right),
                                label: const Text('Neu unter markiertem'),
                              ),
                          if (!useActionMenu) const SizedBox(width: 8),
                          if (!useActionMenu)
                            if (useUltraCompactControls)
                              IconButton.outlined(
                                tooltip: 'Bearbeiten',
                                onPressed: _loading || selectedBom == null ? null : () => _showBomForm(initialValue: selectedBom),
                                icon: const Icon(Icons.edit_outlined),
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.all(6),
                              )
                            else
                              OutlinedButton.icon(
                                onPressed: _loading || selectedBom == null ? null : () => _showBomForm(initialValue: selectedBom),
                                style: useCompactButtons ? compactOutlinedStyle : null,
                                icon: const Icon(Icons.edit_outlined),
                                label: const Text('Bearbeiten'),
                              ),
                          if (!useActionMenu) const SizedBox(width: 8),
                          if (!useActionMenu)
                            if (useUltraCompactControls)
                              IconButton.outlined(
                                tooltip: 'Loeschen',
                                onPressed: _loading || selectedBom == null ? null : () => _deleteBom(selectedBom),
                                icon: const Icon(Icons.delete_outline),
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.all(6),
                              )
                            else
                              OutlinedButton.icon(
                                onPressed: _loading || selectedBom == null ? null : () => _deleteBom(selectedBom),
                                style: useCompactButtons ? compactOutlinedStyle : null,
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Loeschen'),
                              ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
            SizedBox(height: sectionGap),
            Wrap(
              spacing: useActionMenu ? 8 : 12,
              runSpacing: useActionMenu ? 4 : 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (!useActionMenu)
                  Text(
                    'Sortierung: ${_safeBomSortLabel()} '
                    '${_bomSortAscending ? 'aufsteigend' : 'absteigend'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                TextButton.icon(
                  onPressed: _resetBomSort,
                  icon: const Icon(Icons.sort),
                  label: Text(useActionMenu ? 'Sortierung' : 'Sortierung zuruecksetzen'),
                ),
              ],
            ),
            SizedBox(height: sortGap),
            Expanded(
              child: selectedCatalogueId == null
                  ? const Center(child: Text('Bitte zuerst oben einen Artikel auswaehlen.'))
                  : visibleBomRows.isEmpty
                      ? const Center(child: Text('Keine untergeordneten BOM-Eintraege gefunden.'))
                      : SingleChildScrollView(
                          controller: _bomHorizontalController,
                          scrollDirection: Axis.horizontal,
                          child: SingleChildScrollView(
                            controller: _bomVerticalController,
                            child: DataTable(
                              showCheckboxColumn: false,
                              sortColumnIndex: _bomSortColumnIndex,
                              sortAscending: _bomSortAscending,
                              columns: [
                                DataColumn(label: const Text('ID'), onSort: _onBomSort),
                                DataColumn(label: const Text('Artikel-ID'), onSort: _onBomSort),
                                DataColumn(label: const Text('Eltern Artikel (Katalog)'), onSort: _onBomSort),
                                DataColumn(label: const Text('Menge'), onSort: _onBomSort),
                                DataColumn(label: const Text('Bezeichnung'), onSort: _onBomSort),
                                DataColumn(label: const Text('Netto-Einkaufspreis'), onSort: _onBomSort),
                                const DataColumn(label: Text('Bild')),
                              ],
                              rows: visibleBomRows
                                  .map((row) {
                                    final item = _catalogueById[row.ibItemId];
                                    return DataRow(
                                      selected: row.ibId == _selectedBomId,
                                      onSelectChanged: (_) {
                                        setState(() {
                                          _selectedBomId = row.ibId;
                                        });
                                      },
                                      cells: [
                                        DataCell(Text('${row.ibId ?? 0}')),
                                        DataCell(Text(row.ibItemId.toString())),
                                        DataCell(Text(_parentArticleLabelOf(row))),
                                        DataCell(Text(row.ibQuantity.toString())),
                                        DataCell(Text(item?.icIdi ?? '')),
                                        DataCell(Text(_formatDecimal(_bomNetPurchaseTotalOf(row), 2))),
                                        DataCell(item == null ? _emptyImagePreview() : _buildCatalogueImagePreview(item)),
                                      ],
                                    );
                                  })
                                  .toList(growable: false),
                            ),
                          ),
                        ),
            ),
          ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Artikelkatalog & BOM'),
        actions: [
          PopupMenuButton<_ExportMenuAction>(
            tooltip: 'Exportieren',
            enabled: !_loading,
            onSelected: _onExportMenuSelected,
            itemBuilder: (context) => const [
              PopupMenuItem<_ExportMenuAction>(
                value: _ExportMenuAction.catalogueCsv,
                child: Text('Artikelkatalog als CSV exportieren'),
              ),
              PopupMenuItem<_ExportMenuAction>(
                value: _ExportMenuAction.cataloguePdf,
                child: Text('Artikelkatalog als PDF exportieren'),
              ),
              PopupMenuDivider(),
              PopupMenuItem<_ExportMenuAction>(
                value: _ExportMenuAction.bomCsv,
                child: Text('BOM als CSV exportieren'),
              ),
              PopupMenuItem<_ExportMenuAction>(
                value: _ExportMenuAction.bomPdf,
                child: Text('BOM als PDF exportieren'),
              ),
            ],
            icon: const Icon(Icons.download_outlined),
          ),
          IconButton(
            tooltip: 'Aktualisieren',
            onPressed: _loading ? null : _loadData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final isShortViewport = constraints.maxHeight < 600;
                if (isShortViewport) {
                  final catalogueHeight = constraints.maxHeight * 0.7;
                  final bomHeight = constraints.maxHeight * 0.55;

                  return SingleChildScrollView(
                    child: Column(
                      children: [
                        SizedBox(height: catalogueHeight.clamp(520.0, 900.0), child: _buildCatalogueSection()),
                        Container(
                          height: _splitterHeight,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
                            border: Border(
                              top: BorderSide(color: Theme.of(context).dividerColor),
                              bottom: BorderSide(color: Theme.of(context).dividerColor),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Container(
                            width: 196,
                            height: 20,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primaryContainer,
                              border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4)),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.drag_handle,
                                  size: 16,
                                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Trenner',
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(height: bomHeight.clamp(420.0, 760.0), child: _buildBomSection()),
                      ],
                    ),
                  );
                }

                final availableHeight = constraints.maxHeight - _splitterHeight;
                if (availableHeight <= 0) {
                  return const SizedBox.shrink();
                }

                final minRatio = (_minCataloguePaneHeight / availableHeight).clamp(0.2, 0.9);
                final maxRatio = (1.0 - (_minBomPaneHeight / availableHeight)).clamp(0.1, 0.8);

                double effectiveRatio;
                if (minRatio > maxRatio) {
                  effectiveRatio = 0.62;
                } else {
                  effectiveRatio = _cataloguePaneRatio.clamp(minRatio, maxRatio);
                }

                final topHeight = availableHeight * effectiveRatio;
                final bottomHeight = availableHeight - topHeight;
                final topPercent = (effectiveRatio * 100).round();
                final bottomPercent = (100 - topPercent).clamp(0, 100);

                return Column(
                  children: [
                    SizedBox(height: topHeight, child: _buildCatalogueSection()),
                    MouseRegion(
                      cursor: SystemMouseCursors.resizeUpDown,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragStart: (_) {
                          setState(() {
                            _isDraggingSplitter = true;
                          });
                        },
                        onVerticalDragUpdate: (details) {
                          final nextRatio = _cataloguePaneRatio + (details.delta.dy / availableHeight);
                          final clampedRatio = minRatio > maxRatio ? nextRatio.clamp(0.3, 0.8) : nextRatio.clamp(minRatio, maxRatio);
                          if (clampedRatio == _cataloguePaneRatio) {
                            return;
                          }
                          setState(() {
                            _cataloguePaneRatio = clampedRatio;
                          });
                        },
                        onVerticalDragEnd: (_) {
                          setState(() {
                            _isDraggingSplitter = false;
                          });
                        },
                        onVerticalDragCancel: () {
                          setState(() {
                            _isDraggingSplitter = false;
                          });
                        },
                        child: Container(
                          height: _splitterHeight,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
                            border: Border(
                              top: BorderSide(color: Theme.of(context).dividerColor),
                              bottom: BorderSide(color: Theme.of(context).dividerColor),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Container(
                            width: 196,
                            height: 20,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primaryContainer,
                              border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4)),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.drag_handle,
                                  size: 16,
                                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _isDraggingSplitter ? 'Artikel $topPercent% | BOM $bottomPercent%' : 'Ziehen zum Anpassen',
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: bottomHeight, child: _buildBomSection()),
                  ],
                );
              },
            ),
    );
  }
}

enum _CatalogueFilter {
  all,
  zbOnly,
  withoutZb,
}

enum _VariantFilter {
  all,
  withVariants,
  withoutVariants,
}

enum _DuplicateMode {
  articleOnly,
  articleWithBom,
}

enum _CatalogueExportFormat {
  csv,
  pdf,
}

enum _BomExportFormat {
  csv,
  pdf,
}

enum _ExportMenuAction {
  catalogueCsv,
  cataloguePdf,
  bomCsv,
  bomPdf,
}

class _CatalogueExportField {
  const _CatalogueExportField({
    required this.key,
    required this.label,
    required this.csvHeader,
    required this.value,
  });

  final String key;
  final String label;
  final String csvHeader;
  final String Function(ItemCatalogueRow row) value;
}

class _PdfFonts {
  const _PdfFonts({required this.base, required this.bold});

  final pw.Font base;
  final pw.Font bold;
}

class _CataloguePdfSortSelection {
  const _CataloguePdfSortSelection({
    required this.fieldKey,
    required this.ascending,
  });

  final String? fieldKey;
  final bool ascending;
}

class _BomPdfSortSelection {
  const _BomPdfSortSelection({
    required this.fieldKey,
    required this.ascending,
  });

  final String? fieldKey;
  final bool ascending;
}

class _BomExportTarget {
  const _BomExportTarget({
    required this.catalogueId,
    required this.catalogueName,
    required this.rowCount,
  });

  final int catalogueId;
  final String catalogueName;
  final int rowCount;
}

class _BomExportRow {
  const _BomExportRow({
    required this.rootCatalogueId,
    required this.rootCatalogueName,
    required this.bomId,
    required this.articleId,
    required this.articleName,
    required this.parentBomId,
    required this.parentArticleLabel,
    required this.order,
    required this.quantity,
    required this.netPurchaseTotal,
  });

  final int rootCatalogueId;
  final String rootCatalogueName;
  final int bomId;
  final int articleId;
  final String articleName;
  final int? parentBomId;
  final String parentArticleLabel;
  final int order;
  final int quantity;
  final double netPurchaseTotal;
}

class _BomExportField {
  const _BomExportField({
    required this.key,
    required this.label,
    required this.csvHeader,
    required this.value,
  });

  final String key;
  final String label;
  final String csvHeader;
  final String Function(_BomExportRow row) value;
}
