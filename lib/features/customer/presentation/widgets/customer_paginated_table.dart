import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

import '../../domain/customer.dart';
import '../customer_country_display.dart';
import 'customer_detail_dialog.dart';

typedef CustomerSortCallback = void Function(int columnIndex, bool ascending);

class CustomerPaginatedTable extends StatefulWidget {
  const CustomerPaginatedTable({
    super.key,
    required this.customers,
    required this.countryNameByCode,
    required this.loading,
    required this.sortColumnIndex,
    required this.sortAscending,
    required this.rowsPerPage,
    required this.onRowsPerPageChanged,
    required this.onSort,
    required this.onEditCustomer,
    required this.onDeleteCustomer,
    required this.onOpenMap,
    required this.selectedCustomerId,
    required this.onSelectCustomer,
    required this.customerNetById,
  });

  final List<Customer> customers;
  final Map<String, String> countryNameByCode;
  final bool loading;
  final int sortColumnIndex;
  final bool sortAscending;
  final int rowsPerPage;
  final ValueChanged<int> onRowsPerPageChanged;
  final CustomerSortCallback onSort;
  final ValueChanged<Customer> onEditCustomer;
  final ValueChanged<Customer> onDeleteCustomer;
  final ValueChanged<Customer> onOpenMap;
  final String? selectedCustomerId;
  final ValueChanged<Customer> onSelectCustomer;
  final Map<String, double> customerNetById;

  @override
  State<CustomerPaginatedTable> createState() => _CustomerPaginatedTableState();
}

class _CustomerPaginatedTableState extends State<CustomerPaginatedTable> {
  late final ScrollController _verticalScrollController;
  late final ScrollController _horizontalScrollController;

  @override
  void initState() {
    super.initState();
    _verticalScrollController = ScrollController();
    _horizontalScrollController = ScrollController();
  }

  @override
  void dispose() {
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PaginatedDataTable2(
      sortColumnIndex: widget.sortColumnIndex,
      sortAscending: widget.sortAscending,
      rowsPerPage: widget.rowsPerPage,
      scrollController: _verticalScrollController,
      horizontalScrollController: _horizontalScrollController,
      isVerticalScrollBarVisible: true,
      isHorizontalScrollBarVisible: true,
      availableRowsPerPage: const [10, 25, 50],
      onRowsPerPageChanged: (value) {
        if (value != null) {
          widget.onRowsPerPageChanged(value);
        }
      },
      showFirstLastButtons: true,
      showCheckboxColumn: false,
      minWidth: 1200,
      columns: [
        DataColumn(
          label: const Text('ID'),
          onSort: widget.onSort,
        ),
        DataColumn(
          label: const Text('∑ Netto €'),
          numeric: true,
          onSort: widget.onSort,
        ),
        DataColumn2(
          fixedWidth: 190,
          label: const Text('Nachname'),
          onSort: widget.onSort,
        ),
        DataColumn(
          label: const Text('Vorname'),
          onSort: widget.onSort,
        ),
        DataColumn(
          label: const Text('Firma'),
          onSort: widget.onSort,
        ),
        DataColumn(
          label: const Text('Stadt'),
          onSort: widget.onSort,
        ),
        DataColumn(
          label: const Text('Land'),
          onSort: widget.onSort,
        ),
        DataColumn(
          label: const Text('E-Mail'),
          onSort: widget.onSort,
        ),
        const DataColumn(label: Text('Details')),
        const DataColumn(label: Text('Maps')),
      ],
      source: CustomerDataTableSource(
        customers: widget.customers,
        countryNameByCode: widget.countryNameByCode,
        loading: widget.loading,
        selectedCustomerId: widget.selectedCustomerId,
        onSelectCustomer: widget.onSelectCustomer,
        customerNetById: widget.customerNetById,
        onOpenDetails: (customer) {
          showCupertinoDialog<void>(
            context: context,
            builder: (context) => CustomerDetailDialog(
              customer: customer,
              countryNameByCode: widget.countryNameByCode,
              onEdit: () => widget.onEditCustomer(customer),
              onDelete: () => widget.onDeleteCustomer(customer),
            ),
          );
        },
        onOpenMap: widget.onOpenMap,
      ),
    );
  }
}

class CustomerDataTableSource extends DataTableSource {
  CustomerDataTableSource({
    required this.customers,
    required this.countryNameByCode,
    required this.loading,
    required this.selectedCustomerId,
    required this.onSelectCustomer,
    required this.customerNetById,
    required this.onOpenDetails,
    required this.onOpenMap,
  });

  final List<Customer> customers;
  final Map<String, String> countryNameByCode;
  final bool loading;
  final String? selectedCustomerId;
  final ValueChanged<Customer> onSelectCustomer;
  final Map<String, double> customerNetById;
  final ValueChanged<Customer> onOpenDetails;
  final ValueChanged<Customer> onOpenMap;

  Widget _buildSelectableCopyCell({
    required String value,
    required String copyTooltip,
  }) {
    return Row(
      children: [
        Expanded(
          child: SelectableText(
            value,
            maxLines: 1,
            enableInteractiveSelection: true,
          ),
        ),
        Tooltip(
          message: copyTooltip,
          child: IconButton(
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            tooltip: copyTooltip,
            icon: const Icon(CupertinoIcons.doc_on_doc),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
            },
          ),
        ),
      ],
    );
  }

  String _formatMoney(double value) {
    return value.toStringAsFixed(2).replaceAll('.', ',');
  }

  double _customerNetValue(Customer customer) {
    final customerId = customer.cId.trim();
    return customerNetById[customerId] ?? customer.cTotalValueEur;
  }

  @override
  DataRow? getRow(int index) {
    if (index < 0 || index >= customers.length) {
      return null;
    }

    final customer = customers[index];
    final countryName = resolveDisplayCountry(
      customer: customer,
      countryNameByCode: countryNameByCode,
      fallbackWhenMissing: '-',
    );

    return DataRow.byIndex(
      index: index,
      selected: selectedCustomerId != null && selectedCustomerId == customer.cId,
      onSelectChanged: loading ? null : (_) => onSelectCustomer(customer),
      cells: [
        DataCell(
          _buildSelectableCopyCell(
            value: customer.cId,
            copyTooltip: 'ID kopieren',
          ),
        ),
        DataCell(
          Text(
            _formatMoney(_customerNetValue(customer)),
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        DataCell(
          Text(
            customer.cLastName,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        DataCell(
          Text(
            customer.cFirstName,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        DataCell(
          Text(
            customer.cCompany,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        DataCell(
          Text(
            customer.cCityB,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        DataCell(
          Text(countryName, softWrap: false, overflow: TextOverflow.ellipsis),
        ),
        DataCell(
          _buildSelectableCopyCell(
            value: customer.cMail,
            copyTooltip: 'E-Mail kopieren',
          ),
        ),
        DataCell(
          IconButton(
            tooltip: 'Details anzeigen',
            icon: const Icon(CupertinoIcons.info),
            onPressed: loading ? null : () => onOpenDetails(customer),
          ),
        ),
        DataCell(
          IconButton(
            tooltip: 'Karte anzeigen',
            icon: const Icon(CupertinoIcons.map_pin_ellipse),
            onPressed: loading ? null : () => onOpenMap(customer),
          ),
        ),
      ],
    );
  }

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => customers.length;

  @override
  int get selectedRowCount => 0;
}
