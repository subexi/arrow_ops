import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../domain/customer.dart';
import '../customer_country_display.dart';
import 'customer_detail_dialog.dart';

typedef CustomerSortCallback = void Function(int columnIndex, bool ascending);

class CustomerPaginatedTable extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return PaginatedDataTable2(
      sortColumnIndex: sortColumnIndex,
      sortAscending: sortAscending,
      rowsPerPage: rowsPerPage,
      availableRowsPerPage: const [10, 25, 50],
      onRowsPerPageChanged: (value) {
        if (value != null) {
          onRowsPerPageChanged(value);
        }
      },
      showFirstLastButtons: true,
      showCheckboxColumn: false,
      minWidth: 1200,
      columns: [
        DataColumn(
          label: const Text('ID'),
          onSort: onSort,
        ),
        DataColumn(
          label: const Text('∑ Netto €'),
          numeric: true,
          onSort: onSort,
        ),
        DataColumn2(
          fixedWidth: 190,
          label: const Text('Nachname'),
          onSort: onSort,
        ),
        DataColumn(
          label: const Text('Vorname'),
          onSort: onSort,
        ),
        DataColumn(
          label: const Text('Firma'),
          onSort: onSort,
        ),
        DataColumn(
          label: const Text('Stadt'),
          onSort: onSort,
        ),
        DataColumn(
          label: const Text('Land'),
          onSort: onSort,
        ),
        DataColumn(
          label: const Text('E-Mail'),
          onSort: onSort,
        ),
        const DataColumn(label: Text('Details')),
        const DataColumn(label: Text('Maps')),
      ],
      source: CustomerDataTableSource(
        customers: customers,
        countryNameByCode: countryNameByCode,
        loading: loading,
        selectedCustomerId: selectedCustomerId,
        onSelectCustomer: onSelectCustomer,
        customerNetById: customerNetById,
        onOpenDetails: (customer) {
          showCupertinoDialog<void>(
            context: context,
            builder: (context) => CustomerDetailDialog(
              customer: customer,
              countryNameByCode: countryNameByCode,
              onEdit: () => onEditCustomer(customer),
              onDelete: () => onDeleteCustomer(customer),
            ),
          );
        },
        onOpenMap: onOpenMap,
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

  String _formatMoney(double value) {
    return value.toStringAsFixed(2).replaceAll('.', ',');
  }

  double _customerNetValue(Customer customer) {
    return customerNetById[customer.cId] ?? customer.cTotalValueEur;
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
          Text(customer.cId, softWrap: false, overflow: TextOverflow.ellipsis),
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
          Text(
            customer.cMail,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
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
