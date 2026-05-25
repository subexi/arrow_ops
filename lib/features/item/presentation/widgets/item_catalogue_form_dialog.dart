import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/ui/transient_feedback.dart';
import '../../domain/item_models.dart';

class ItemCatalogueFormDialog extends StatefulWidget {
  const ItemCatalogueFormDialog({
    super.key,
    required this.nextId,
    this.initialValue,
    this.readOnly = false,
  });

  final int nextId;
  final ItemCatalogueRow? initialValue;
  final bool readOnly;

  @override
  State<ItemCatalogueFormDialog> createState() => _ItemCatalogueFormDialogState();
}

class _ItemCatalogueFormDialogState extends State<ItemCatalogueFormDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  bool get _isWide => MediaQuery.of(context).size.width >= 760;

  late final TextEditingController _idController;
  late final TextEditingController _idiController;
  late final TextEditingController _ideController;
  late final TextEditingController _idvController;
  late final TextEditingController _descriptionDeController;
  late final TextEditingController _descriptionEnController;
  late final TextEditingController _colorCodeController;
  late final TextEditingController _priceNetController;
  late final TextEditingController _priceWholesaleNetController;
  late final TextEditingController _purchasePriceNetController;
  late final TextEditingController _weightController;
  late final TextEditingController _sourceOfSupplyController;
  late final TextEditingController _htsController;
  late final TextEditingController _imagePathController;
  late final TextEditingController _noteController;
  late final TextEditingController _stockController;
  late bool _isIcComponent;
  bool _expandDescriptionDe = false;
  bool _expandDescriptionEn = false;

  @override
  void initState() {
    super.initState();
    final initialValue = widget.initialValue;
    _idController = TextEditingController(text: (initialValue?.icId ?? widget.nextId).toString());
    _idiController = TextEditingController(text: initialValue?.icIdi ?? '');
    _ideController = TextEditingController(text: initialValue?.icIde ?? '');
    _idvController = TextEditingController(text: initialValue?.icIdv ?? '');
    _descriptionDeController = TextEditingController(text: initialValue?.icDescriptionDeLong ?? '');
    _descriptionEnController = TextEditingController(text: initialValue?.icDescriptionEnLong ?? '');
    _colorCodeController = TextEditingController(text: initialValue?.icColorCode ?? '');
    _priceNetController = TextEditingController(text: _decimalText(initialValue?.icPriceNet, 2));
    _priceWholesaleNetController = TextEditingController(text: _decimalText(initialValue?.icPriceWholesaleNet, 2));
    _purchasePriceNetController = TextEditingController(text: _decimalText(initialValue?.icPurchasePriceNet, 2));
    _weightController = TextEditingController(text: _decimalText(initialValue?.icWeight, 1));
    _sourceOfSupplyController = TextEditingController(text: initialValue?.icSourceOfSupply ?? '');
    _htsController = TextEditingController(text: initialValue?.icHts ?? '');
    _imagePathController = TextEditingController(text: initialValue?.icImagePath ?? '');
    _noteController = TextEditingController(text: initialValue?.icNote ?? '');
    _stockController = TextEditingController(text: (initialValue?.icStock ?? 0).toString());
    _isIcComponent = (initialValue?.icIc ?? 0) != 0;
  }

  @override
  void dispose() {
    _idController.dispose();
    _idiController.dispose();
    _ideController.dispose();
    _idvController.dispose();
    _descriptionDeController.dispose();
    _descriptionEnController.dispose();
    _colorCodeController.dispose();
    _priceNetController.dispose();
    _priceWholesaleNetController.dispose();
    _purchasePriceNetController.dispose();
    _weightController.dispose();
    _sourceOfSupplyController.dispose();
    _htsController.dispose();
    _imagePathController.dispose();
    _noteController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  static String _decimalText(double? value, int fractionDigits) {
    if (value == null) {
      return '';
    }
    return value.toStringAsFixed(fractionDigits).replaceAll('.', ',');
  }

  String _text(TextEditingController controller) => controller.text.trim();

  int _parseInt(TextEditingController controller) => int.tryParse(_text(controller)) ?? 0;

  double _parseDouble(TextEditingController controller) =>
      double.tryParse(_text(controller).replaceAll(',', '.')) ?? 0;

  Widget _field(
    TextEditingController controller,
    String label, {
    int? maxLines = 1,
    TextInputType? keyboardType,
    bool enabled = true,
    bool readOnly = false,
    VoidCallback? onTap,
  }) {
    return TextFormField(
      controller: controller,
      enabled: enabled || readOnly,
      readOnly: readOnly,
      enableInteractiveSelection: true,
      maxLines: maxLines,
      onTap: onTap,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      validator: (value) {
        if (label == 'Artikel-ID' && (value == null || value.trim().isEmpty)) {
          return 'Bitte eine ID angeben.';
        }
        if (label == 'Artikel-ID' && int.tryParse(value!.trim()) == null) {
          return 'Bitte eine gueltige Zahl angeben.';
        }
        return null;
      },
    );
  }

  Widget _compactRow(List<Widget> children) {
    if (!_isWide) {
      return Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1) const SizedBox(height: 12),
          ],
        ],
      );
    }

    return Row(
      children: [
        for (int i = 0; i < children.length; i++) ...[
          Expanded(child: children[i]),
          if (i != children.length - 1) const SizedBox(width: 12),
        ],
      ],
    );
  }

  Future<void> _pickImagePath() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'gif', 'heic', 'heif'],
      allowMultiple: false,
    );
    if (!mounted) {
      return;
    }

    final pickedPath = result?.files.single.path;
    if (pickedPath == null || pickedPath.trim().isEmpty) {
      TransientFeedback.show(
        context,
        message: 'Kein gueltiger Bildpfad ausgewaehlt.',
      );
      return;
    }

    setState(() {
      _imagePathController.text = pickedPath;
    });
  }

  Widget _imagePathField() {
    final readOnly = widget.readOnly;
    final imagePath = _imagePathController.text.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _imagePathController,
          enabled: true,
          readOnly: readOnly,
          enableInteractiveSelection: true,
          decoration: InputDecoration(
            labelText: 'Bild',
            border: const OutlineInputBorder(),
            helperText: 'Beim Speichern wird der Pfad app-intern normalisiert.',
            suffixIcon: readOnly
                ? null
                : IconButton(
                    tooltip: 'Datei waehlen',
                    onPressed: _pickImagePath,
                    icon: const Icon(Icons.folder_open),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        if (!readOnly)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton.icon(
                onPressed: () => setState(() => _imagePathController.clear()),
                icon: const Icon(Icons.clear),
                label: const Text('Pfad leeren'),
              ),
            ],
          ),
        if (imagePath.isNotEmpty) ...[
          const SizedBox(height: 8),
          _imagePreview(imagePath),
        ],
      ],
    );
  }

  Widget _imagePreview(String imagePath) {
    final file = File(imagePath);
    if (!file.existsSync()) {
      return const SizedBox.shrink();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        children: [
          SizedBox(
            height: 140,
            width: double.infinity,
            child: InkWell(
              onTap: () => _showFullImagePreview(file),
              child: Image.file(
                file,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    alignment: Alignment.center,
                    child: const Text('Vorschau nicht verfuegbar'),
                  );
                },
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Material(
              color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(999),
              child: IconButton(
                tooltip: 'Vollansicht',
                onPressed: () => _showFullImagePreview(file),
                icon: const Icon(Icons.zoom_in),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showFullImagePreview(File file) async {
    final transformController = TransformationController();
    var currentScale = 1.0;
    var showShortcutHint = true;

    void setScale(double nextScale) {
      currentScale = nextScale.clamp(0.6, 5.0);
      transformController.value = Matrix4.diagonal3Values(currentScale, currentScale, 1.0);
    }

    await showDialog<void>(
      context: context,
      builder: (context) {
        return Shortcuts(
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
            SingleActivator(LogicalKeyboardKey.equal, shift: true): _ZoomInIntent(),
            SingleActivator(LogicalKeyboardKey.numpadAdd): _ZoomInIntent(),
            SingleActivator(LogicalKeyboardKey.minus): _ZoomOutIntent(),
            SingleActivator(LogicalKeyboardKey.numpadSubtract): _ZoomOutIntent(),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              DismissIntent: CallbackAction<DismissIntent>(
                onInvoke: (intent) {
                  Navigator.of(context).pop();
                  return null;
                },
              ),
              _ZoomInIntent: CallbackAction<_ZoomInIntent>(
                onInvoke: (intent) {
                  setScale(currentScale * 1.2);
                  return null;
                },
              ),
              _ZoomOutIntent: CallbackAction<_ZoomOutIntent>(
                onInvoke: (intent) {
                  setScale(currentScale / 1.2);
                  return null;
                },
              ),
            },
            child: Focus(
              autofocus: true,
              child: StatefulBuilder(
                builder: (context, setDialogState) {
                  return Dialog(
                    insetPadding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: 900,
                      height: 620,
                      child: Stack(
                        children: [
                          Positioned.fill(
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
                          Positioned(
                            top: 8,
                            left: 8,
                            child: FilledButton.tonalIcon(
                              onPressed: () => setDialogState(() => showShortcutHint = !showShortcutHint),
                              icon: Icon(showShortcutHint ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                              label: Text(showShortcutHint ? 'Hilfe ausblenden' : 'Hilfe einblenden'),
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
                          if (showShortcutHint)
                            Positioned(
                              left: 12,
                              bottom: 12,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.86),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Theme.of(context).dividerColor.withValues(alpha: 0.25),
                                  ),
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  child: Text('Shortcuts: Esc schliessen • + hineinzoomen • - herauszoomen'),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );

    transformController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialValue != null;
    final readOnly = widget.readOnly;
    final canEdit = !readOnly;

    return AlertDialog(
      title: Text(readOnly ? 'Katalogeintrag ansehen' : (isEditing ? 'Katalogeintrag bearbeiten' : 'Katalogeintrag anlegen')),
      content: SizedBox(
        width: _isWide ? 760 : 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _compactRow([
                  _field(_idController, 'Artikel-ID', enabled: !isEditing && canEdit, readOnly: readOnly),
                  _field(_idiController, 'Bezeichnung', enabled: canEdit, readOnly: readOnly),
                ]),
                const SizedBox(height: 12),
                _compactRow([
                  _field(_ideController, 'Bezeichnung extern', enabled: canEdit, readOnly: readOnly),
                  _field(_idvController, 'ID-Version', enabled: canEdit, readOnly: readOnly),
                ]),
                const SizedBox(height: 12),
                _field(
                  _descriptionDeController,
                  'Beschreibung',
                  maxLines: _expandDescriptionDe ? null : 4,
                  enabled: canEdit,
                  readOnly: readOnly,
                  onTap: () {
                    if (_expandDescriptionDe) {
                      return;
                    }
                    setState(() => _expandDescriptionDe = true);
                  },
                ),
                const SizedBox(height: 12),
                _field(
                  _descriptionEnController,
                  'Description',
                  maxLines: _expandDescriptionEn ? null : 4,
                  enabled: canEdit,
                  readOnly: readOnly,
                  onTap: () {
                    if (_expandDescriptionEn) {
                      return;
                    }
                    setState(() => _expandDescriptionEn = true);
                  },
                ),
                const SizedBox(height: 12),
                _compactRow([
                  _field(_colorCodeController, 'Farbe', enabled: canEdit, readOnly: readOnly),
                  _field(_sourceOfSupplyController, 'Lieferant', enabled: canEdit, readOnly: readOnly),
                ]),
                const SizedBox(height: 12),
                _compactRow([
                  _field(
                    _priceNetController,
                    'Nettopreis',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    enabled: canEdit,
                    readOnly: readOnly,
                  ),
                  _field(
                    _priceWholesaleNetController,
                    'Netto-Haendlerpreis',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    enabled: canEdit,
                    readOnly: readOnly,
                  ),
                ]),
                const SizedBox(height: 12),
                _compactRow([
                  _field(
                    _purchasePriceNetController,
                    'Netto-Einkaufspreis',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    enabled: canEdit,
                    readOnly: readOnly,
                  ),
                  _field(
                    _weightController,
                    'Gewicht in g',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    enabled: canEdit,
                    readOnly: readOnly,
                  ),
                ]),
                const SizedBox(height: 12),
                _compactRow([
                  _field(_htsController, 'HTS Code', enabled: canEdit, readOnly: readOnly),
                  _imagePathField(),
                ]),
                const SizedBox(height: 12),
                _field(_noteController, 'Notiz', maxLines: 4, enabled: canEdit, readOnly: readOnly),
                const SizedBox(height: 12),
                _compactRow([
                  _field(
                    _stockController,
                    'Lagerbestand',
                    keyboardType: TextInputType.number,
                    enabled: canEdit,
                    readOnly: readOnly,
                  ),
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'ZB Komponente',
                      border: OutlineInputBorder(),
                    ),
                    child: Row(
                      children: [
                        CupertinoSwitch(
                          value: _isIcComponent,
                          onChanged: canEdit ? (value) => setState(() => _isIcComponent = value) : null,
                        ),
                      ],
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(readOnly ? 'Schliessen' : 'Abbrechen'),
        ),
        if (!readOnly)
          FilledButton(
            onPressed: () {
              if (!_formKey.currentState!.validate()) {
                return;
              }

              final result = ItemCatalogueRow(
                icId: _parseInt(_idController),
                icIdi: _text(_idiController),
                icIde: _text(_ideController),
                icIdv: _text(_idvController),
                icDescriptionDeLong: _text(_descriptionDeController),
                icDescriptionEnLong: _text(_descriptionEnController),
                icColorCode: _text(_colorCodeController),
                icPriceNet: _parseDouble(_priceNetController),
                icPriceWholesaleNet: _parseDouble(_priceWholesaleNetController),
                icPurchasePriceNet: _parseDouble(_purchasePriceNetController),
                icWeight: _parseDouble(_weightController),
                icSourceOfSupply: _text(_sourceOfSupplyController),
                icHts: _text(_htsController),
                icImagePath: _text(_imagePathController),
                icNote: _text(_noteController),
                icStock: _parseInt(_stockController),
                icIc: _isIcComponent ? 1 : 0,
              );
              Navigator.of(context).pop(result);
            },
            child: const Text('Speichern'),
          ),
      ],
    );
  }
}

class _ZoomInIntent extends Intent {
  const _ZoomInIntent();
}

class _ZoomOutIntent extends Intent {
  const _ZoomOutIntent();
}
