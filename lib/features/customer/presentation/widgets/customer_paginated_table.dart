import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../domain/customer.dart';
import '../customer_country_display.dart';
import 'customer_detail_dialog.dart';

typedef CustomerSortCallback =
    void Function(
      int columnIndex,
      bool ascending,
      String Function(Customer customer) selector,
    );

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
          onSort: (columnIndex, ascending) =>
              onSort(columnIndex, ascending, (c) => c.cId.toLowerCase()),
        ),
        DataColumn2(
          fixedWidth: 190,
          label: const Text('Nachname'),
          onSort: (columnIndex, ascending) =>
              onSort(columnIndex, ascending, (c) => c.cLastName.toLowerCase()),
        ),
        DataColumn(
          label: const Text('Vorname'),
          onSort: (columnIndex, ascending) =>
              onSort(columnIndex, ascending, (c) => c.cFirstName.toLowerCase()),
        ),
        DataColumn(
          label: const Text('Firma'),
          onSort: (columnIndex, ascending) =>
              onSort(columnIndex, ascending, (c) => c.cCompany.toLowerCase()),
        ),
        DataColumn(
          label: const Text('Stadt'),
          onSort: (columnIndex, ascending) =>
              onSort(columnIndex, ascending, (c) => c.cCityB.toLowerCase()),
        ),
        DataColumn(
          label: const Text('Land'),
          onSort: (columnIndex, ascending) => onSort(
            columnIndex,
            ascending,
            (c) => resolveDisplayCountry(
              customer: c,
              countryNameByCode: countryNameByCode,
            ).toLowerCase(),
          ),
        ),
        DataColumn(
          label: const Text('E-Mail'),
          onSort: (columnIndex, ascending) =>
              onSort(columnIndex, ascending, (c) => c.cMail.toLowerCase()),
        ),
        const DataColumn(label: Text('Maps')),
      ],
      source: CustomerDataTableSource(
        customers: customers,
        countryNameByCode: countryNameByCode,
        loading: loading,
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
    required this.onOpenDetails,
    required this.onOpenMap,
  });

  final List<Customer> customers;
  final Map<String, String> countryNameByCode;
  final bool loading;
  final ValueChanged<Customer> onOpenDetails;
  final ValueChanged<Customer> onOpenMap;

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
      onSelectChanged: loading ? null : (_) => onOpenDetails(customer),
      cells: [
        DataCell(
          Text(customer.cId, softWrap: false, overflow: TextOverflow.ellipsis),
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
