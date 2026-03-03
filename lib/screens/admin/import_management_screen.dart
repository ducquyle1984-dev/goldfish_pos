import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:goldfish_pos/models/customer_model.dart';
import 'package:goldfish_pos/models/employee_model.dart';
import 'package:goldfish_pos/models/item_category_model.dart';
import 'package:goldfish_pos/models/item_model.dart';
import 'package:goldfish_pos/repositories/pos_repository.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Import Management Screen
// ─────────────────────────────────────────────────────────────────────────────

class ImportManagementScreen extends StatefulWidget {
  const ImportManagementScreen({super.key});

  @override
  State<ImportManagementScreen> createState() => _ImportManagementScreenState();
}

class _ImportManagementScreenState extends State<ImportManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import Management'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.spa), text: 'Services & Categories'),
            Tab(icon: Icon(Icons.badge), text: 'Employees'),
            Tab(icon: Icon(Icons.people), text: 'Customers'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _ServicesImportTab(),
          _EmployeesImportTab(),
          _CustomersImportTab(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SERVICES & CATEGORIES TAB
// ─────────────────────────────────────────────────────────────────────────────

class _ServicesImportTab extends StatefulWidget {
  const _ServicesImportTab();

  @override
  State<_ServicesImportTab> createState() => _ServicesImportTabState();
}

class _ServicesImportTabState extends State<_ServicesImportTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _repo = PosRepository();
  List<Map<String, String>> _rows = [];
  List<String> _headers = [];
  bool _importing = false;
  _ImportResult? _result;

  // Column mapping: our field → CSV header
  final _mapping = <String, String?>{
    'category': null,
    'name': null,
    'price': null,
    'description': null,
  };

  static const _template = '''category,name,price,description
MANICURE,Basic Manicure,15.00,Regular polish manicure
MANICURE,Spa Manicure,25.00,Hot towel and scrub
MANICURE,Gel Manicure,35.00,Long-lasting gel polish
MANICURE,Acrylic Full Set,45.00,Acrylic nail extensions
MANICURE,Acrylic Fill,30.00,Fill for existing acrylics
MANICURE,Dip Powder Full Set,50.00,Dip powder nail set
MANICURE,Nail Art (per nail),3.00,Custom nail art design
PEDICURE,Basic Pedicure,25.00,Regular polish pedicure
PEDICURE,Spa Pedicure,40.00,Extended spa treatment
PEDICURE,Gel Pedicure,45.00,Gel polish pedicure
PEDICURE,Deluxe Pedicure,60.00,Hot stone massage included
WAXING,Eyebrow Wax,12.00,
WAXING,Lip Wax,8.00,
WAXING,Chin Wax,8.00,
WAXING,Full Face Wax,30.00,
WAXING,Underarm Wax,20.00,
WAXING,Half Leg Wax,35.00,
WAXING,Full Leg Wax,55.00,
WAXING,Bikini Wax,35.00,
''';

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) return;
    final content = utf8.decode(bytes);
    _parseCSV(content);
  }

  void _parseCSV(String content) {
    final rows = const CsvToListConverter(eol: '\n').convert(content);
    if (rows.isEmpty) return;
    final headers = rows.first.map((e) => e.toString().trim()).toList();
    final data = rows
        .skip(1)
        .where((r) => r.any((c) => c.toString().trim().isNotEmpty))
        .map(
          (r) => Map.fromIterables(
            headers,
            List.generate(
              headers.length,
              (i) => i < r.length ? r[i].toString().trim() : '',
            ),
          ),
        )
        .toList();

    // Auto-map columns
    final autoMap = <String, String?>{};
    for (final field in _mapping.keys) {
      final match = headers.firstWhere(
        (h) => h.toLowerCase().contains(field.toLowerCase()),
        orElse: () => '',
      );
      autoMap[field] = match.isEmpty ? null : match;
    }

    setState(() {
      _headers = headers;
      _rows = data;
      _mapping.addAll(autoMap);
      _result = null;
    });
  }

  Future<void> _import() async {
    if (_rows.isEmpty) return;
    if (_mapping['category'] == null || _mapping['name'] == null) {
      _showSnack('Map at least "category" and "name" columns.', Colors.red);
      return;
    }

    setState(() {
      _importing = true;
      _result = null;
    });

    int created = 0;
    int skipped = 0;
    final errors = <String>[];

    try {
      // 1. Load existing categories
      final existingCats = await _repo.getItemCategories().first;
      final catMap = {for (final c in existingCats) c.name.toLowerCase(): c};
      final newCatIds = <String, String>{};

      for (final row in _rows) {
        try {
          final catName = row[_mapping['category']!]?.trim() ?? '';
          final itemName = row[_mapping['name']!]?.trim() ?? '';
          final priceStr = _mapping['price'] != null
              ? row[_mapping['price']!]?.replaceAll(RegExp(r'[^\d.]'), '') ??
                    '0'
              : '0';
          final description = _mapping['description'] != null
              ? row[_mapping['description']!]?.trim()
              : null;

          if (catName.isEmpty || itemName.isEmpty) {
            skipped++;
            continue;
          }

          final price = double.tryParse(priceStr) ?? 0;

          // Get or create category
          String catId;
          if (catMap.containsKey(catName.toLowerCase())) {
            catId = catMap[catName.toLowerCase()]!.id;
          } else if (newCatIds.containsKey(catName.toLowerCase())) {
            catId = newCatIds[catName.toLowerCase()]!;
          } else {
            final now = DateTime.now();
            final cat = ItemCategory(
              id: '',
              name: catName,
              description: null,
              createdAt: now,
              updatedAt: now,
            );
            catId = await _repo.createItemCategory(cat);
            newCatIds[catName.toLowerCase()] = catId;
          }

          final now = DateTime.now();
          final item = Item(
            id: '',
            name: itemName,
            description: description?.isEmpty == true ? null : description,
            categoryId: catId,
            type: ItemType.service,
            price: price,
            isActive: true,
            createdAt: now,
            updatedAt: now,
          );
          await _repo.createItem(item);
          created++;
        } catch (e) {
          errors.add('Row error: $e');
          skipped++;
        }
      }
    } catch (e) {
      errors.add('Import failed: $e');
    }

    if (mounted) {
      setState(() {
        _importing = false;
        _result = _ImportResult(
          created: created,
          skipped: skipped,
          errors: errors,
        );
      });
    }
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _ImportTabLayout(
      importType: 'Services & Categories',
      templateContent: _template,
      templateFilename: 'services_template.csv',
      instructions: const [
        'CSV columns: category, name, price, description',
        'Categories are auto-created if they don\'t exist',
        'Price should be a number (e.g. 15.00)',
        'description column is optional',
      ],
      headers: _headers,
      rows: _rows,
      mapping: _mapping,
      requiredFields: const ['category', 'name'],
      optionalFields: const ['price', 'description'],
      importing: _importing,
      result: _result,
      onPickFile: _pickFile,
      onMappingChanged: (field, col) => setState(() => _mapping[field] = col),
      onImport: _import,
      onReset: () => setState(() {
        _rows = [];
        _headers = [];
        _result = null;
        _mapping.updateAll((_, __) => null);
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EMPLOYEES TAB
// ─────────────────────────────────────────────────────────────────────────────

class _EmployeesImportTab extends StatefulWidget {
  const _EmployeesImportTab();

  @override
  State<_EmployeesImportTab> createState() => _EmployeesImportTabState();
}

class _EmployeesImportTabState extends State<_EmployeesImportTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _repo = PosRepository();
  List<Map<String, String>> _rows = [];
  List<String> _headers = [];
  bool _importing = false;
  _ImportResult? _result;

  final _mapping = <String, String?>{
    'name': null,
    'phone': null,
    'email': null,
    'commission': null,
  };

  static const _template =
      'name,phone,email,commission\n'
      'Anna Smith,555-0101,anna@example.com,50\n'
      'Maria Jones,555-0102,,45\n'
      'Lisa Chen,555-0103,lisa@example.com,50\n';

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) return;
    _parseCSV(utf8.decode(bytes));
  }

  void _parseCSV(String content) {
    final rows = const CsvToListConverter(eol: '\n').convert(content);
    if (rows.isEmpty) return;
    final headers = rows.first.map((e) => e.toString().trim()).toList();
    final data = rows
        .skip(1)
        .where((r) => r.any((c) => c.toString().trim().isNotEmpty))
        .map(
          (r) => Map.fromIterables(
            headers,
            List.generate(
              headers.length,
              (i) => i < r.length ? r[i].toString().trim() : '',
            ),
          ),
        )
        .toList();

    final autoMap = <String, String?>{};
    for (final field in _mapping.keys) {
      final match = headers.firstWhere(
        (h) => h.toLowerCase().contains(field.toLowerCase()),
        orElse: () => '',
      );
      autoMap[field] = match.isEmpty ? null : match;
    }

    setState(() {
      _headers = headers;
      _rows = data;
      _mapping.addAll(autoMap);
      _result = null;
    });
  }

  Future<void> _import() async {
    if (_rows.isEmpty) return;
    if (_mapping['name'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Map the "name" column.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _importing = true;
      _result = null;
    });

    int created = 0;
    int skipped = 0;
    final errors = <String>[];

    for (final row in _rows) {
      try {
        final name = row[_mapping['name']!]?.trim() ?? '';
        if (name.isEmpty) {
          skipped++;
          continue;
        }
        final phone = _mapping['phone'] != null
            ? row[_mapping['phone']!]?.trim()
            : null;
        final email = _mapping['email'] != null
            ? row[_mapping['email']!]?.trim()
            : null;
        final commStr = _mapping['commission'] != null
            ? row[_mapping['commission']!]?.replaceAll(RegExp(r'[^\d.]'), '')
            : null;
        final commission = double.tryParse(commStr ?? '') ?? 0;

        final now = DateTime.now();
        final emp = Employee(
          id: '',
          name: name,
          phone: phone?.isEmpty == true ? null : phone,
          email: email?.isEmpty == true ? null : email,
          commissionPercentage: commission,
          isActive: true,
          createdAt: now,
          updatedAt: now,
        );
        await _repo.createEmployee(emp);
        created++;
      } catch (e) {
        errors.add('Row error: $e');
        skipped++;
      }
    }

    if (mounted) {
      setState(() {
        _importing = false;
        _result = _ImportResult(
          created: created,
          skipped: skipped,
          errors: errors,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _ImportTabLayout(
      importType: 'Employees',
      templateContent: _template,
      templateFilename: 'employees_template.csv',
      instructions: const [
        'CSV columns: name, phone, email, commission',
        '"name" is required; all other columns optional',
        'commission is a percentage (e.g. 50 for 50%)',
      ],
      headers: _headers,
      rows: _rows,
      mapping: _mapping,
      requiredFields: const ['name'],
      optionalFields: const ['phone', 'email', 'commission'],
      importing: _importing,
      result: _result,
      onPickFile: _pickFile,
      onMappingChanged: (field, col) => setState(() => _mapping[field] = col),
      onImport: _import,
      onReset: () => setState(() {
        _rows = [];
        _headers = [];
        _result = null;
        _mapping.updateAll((_, __) => null);
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CUSTOMERS TAB
// ─────────────────────────────────────────────────────────────────────────────

class _CustomersImportTab extends StatefulWidget {
  const _CustomersImportTab();

  @override
  State<_CustomersImportTab> createState() => _CustomersImportTabState();
}

class _CustomersImportTabState extends State<_CustomersImportTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _repo = PosRepository();
  List<Map<String, String>> _rows = [];
  List<String> _headers = [];
  bool _importing = false;
  _ImportResult? _result;

  final _mapping = <String, String?>{
    'name': null,
    'phone': null,
    'email': null,
    'birthMonth': null,
    'birthDay': null,
    'rewardPoints': null,
  };

  static const _template =
      'name,phone,email,birthMonth,birthDay,rewardPoints\n'
      'Jane Doe,555-1001,jane@example.com,3,15,250\n'
      'Mary Smith,555-1002,,6,22,100\n'
      'Susan Lee,555-1003,susan@example.com,12,5,0\n';

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) return;
    _parseCSV(utf8.decode(bytes));
  }

  void _parseCSV(String content) {
    final rows = const CsvToListConverter(eol: '\n').convert(content);
    if (rows.isEmpty) return;
    final headers = rows.first.map((e) => e.toString().trim()).toList();
    final data = rows
        .skip(1)
        .where((r) => r.any((c) => c.toString().trim().isNotEmpty))
        .map(
          (r) => Map.fromIterables(
            headers,
            List.generate(
              headers.length,
              (i) => i < r.length ? r[i].toString().trim() : '',
            ),
          ),
        )
        .toList();

    final autoMap = <String, String?>{};
    for (final field in _mapping.keys) {
      final match = headers.firstWhere(
        (h) => h
            .toLowerCase()
            .replaceAll(' ', '')
            .contains(field.toLowerCase().replaceAll(' ', '')),
        orElse: () => '',
      );
      autoMap[field] = match.isEmpty ? null : match;
    }

    setState(() {
      _headers = headers;
      _rows = data;
      _mapping.addAll(autoMap);
      _result = null;
    });
  }

  Future<void> _import() async {
    if (_rows.isEmpty) return;
    if (_mapping['name'] == null || _mapping['phone'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Map at least "name" and "phone" columns.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _importing = true;
      _result = null;
    });

    int created = 0;
    int skipped = 0;
    final errors = <String>[];

    for (final row in _rows) {
      try {
        final name = row[_mapping['name']!]?.trim() ?? '';
        final phone = row[_mapping['phone']!]?.trim() ?? '';
        if (name.isEmpty || phone.isEmpty) {
          skipped++;
          continue;
        }
        final email = _mapping['email'] != null
            ? row[_mapping['email']!]?.trim()
            : null;
        final birthMonth =
            int.tryParse(
              _mapping['birthMonth'] != null
                  ? row[_mapping['birthMonth']!] ?? '1'
                  : '1',
            ) ??
            1;
        final birthDay =
            int.tryParse(
              _mapping['birthDay'] != null
                  ? row[_mapping['birthDay']!] ?? '1'
                  : '1',
            ) ??
            1;
        final rewardPoints =
            double.tryParse(
              _mapping['rewardPoints'] != null
                  ? (row[_mapping['rewardPoints']!] ?? '0').replaceAll(
                      RegExp(r'[^\d.]'),
                      '',
                    )
                  : '0',
            ) ??
            0;

        final now = DateTime.now();
        final customer = Customer(
          id: '',
          name: name,
          phone: phone,
          email: email?.isEmpty == true ? null : email,
          birthMonth: birthMonth.clamp(1, 12),
          birthDay: birthDay.clamp(1, 31),
          rewardPoints: rewardPoints,
          isActive: true,
          createdAt: now,
          updatedAt: now,
        );
        await _repo.createCustomer(customer);
        created++;
      } catch (e) {
        errors.add('Row error: $e');
        skipped++;
      }
    }

    if (mounted) {
      setState(() {
        _importing = false;
        _result = _ImportResult(
          created: created,
          skipped: skipped,
          errors: errors,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _ImportTabLayout(
      importType: 'Customers',
      templateContent: _template,
      templateFilename: 'customers_template.csv',
      instructions: const [
        'CSV columns: name, phone, email, birthMonth, birthDay, rewardPoints',
        '"name" and "phone" are required',
        'birthMonth: 1–12, birthDay: 1–31',
        'rewardPoints: accumulated points balance',
      ],
      headers: _headers,
      rows: _rows,
      mapping: _mapping,
      requiredFields: const ['name', 'phone'],
      optionalFields: const ['email', 'birthMonth', 'birthDay', 'rewardPoints'],
      importing: _importing,
      result: _result,
      onPickFile: _pickFile,
      onMappingChanged: (field, col) => setState(() => _mapping[field] = col),
      onImport: _import,
      onReset: () => setState(() {
        _rows = [];
        _headers = [];
        _result = null;
        _mapping.updateAll((_, __) => null);
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared Tab Layout
// ─────────────────────────────────────────────────────────────────────────────

class _ImportTabLayout extends StatelessWidget {
  final String importType;
  final String templateContent;
  final String templateFilename;
  final List<String> instructions;
  final List<String> headers;
  final List<Map<String, String>> rows;
  final Map<String, String?> mapping;
  final List<String> requiredFields;
  final List<String> optionalFields;
  final bool importing;
  final _ImportResult? result;
  final VoidCallback onPickFile;
  final void Function(String field, String? col) onMappingChanged;
  final VoidCallback onImport;
  final VoidCallback onReset;

  const _ImportTabLayout({
    required this.importType,
    required this.templateContent,
    required this.templateFilename,
    required this.instructions,
    required this.headers,
    required this.rows,
    required this.mapping,
    required this.requiredFields,
    required this.optionalFields,
    required this.importing,
    required this.result,
    required this.onPickFile,
    required this.onMappingChanged,
    required this.onImport,
    required this.onReset,
  });

  // Download template as a file (web: triggers download, desktop: save dialog)
  Future<void> _downloadTemplate(BuildContext context) async {
    if (kIsWeb) {
      // On web, trigger browser download via anchor element
      final bytes = utf8.encode(templateContent);
      final base64 = base64Encode(bytes);
      // ignore: avoid_web_libraries_in_flutter
      final anchor =
          '''
        <a id="dld" download="$templateFilename" href="data:text/csv;base64,$base64"></a>
      ''';
      // Use url_launcher or just show the content to copy
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text('$importType Template'),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Copy this CSV content into a .csv file and then import it:',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 300),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        templateContent,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  // Hidden anchor for download trick
                  const SizedBox(height: 8),
                  Text(
                    '(Select all and copy, then paste into Excel or a text editor and save as .csv)',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
      return;
    }

    // Desktop: save file
    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Template',
      fileName: templateFilename,
      type: FileType.custom,
      allowedExtensions: ['csv'],
      bytes: utf8.encode(templateContent),
    );
    if (savePath != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Template saved to $savePath'),
          backgroundColor: Colors.teal,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasFile = rows.isNotEmpty;
    final allFields = [...requiredFields, ...optionalFields];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Step 1: Get template ──────────────────────────────────────
          _StepCard(
            step: '1',
            title: 'Download CSV Template',
            color: Colors.blue,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: instructions
                      .map(
                        (i) => Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.circle,
                              size: 6,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 6),
                            Text(i, style: const TextStyle(fontSize: 13)),
                          ],
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: Text('Download $importType Template'),
                  onPressed: () => _downloadTemplate(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Step 2: Upload file ───────────────────────────────────────
          _StepCard(
            step: '2',
            title: 'Upload CSV File',
            color: Colors.orange,
            child: Row(
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: const Text('Choose CSV File'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.orange),
                  onPressed: onPickFile,
                ),
                if (hasFile) ...[
                  const SizedBox(width: 12),
                  Chip(
                    avatar: const Icon(Icons.check_circle, size: 16),
                    label: Text(
                      '${rows.length} rows loaded',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    backgroundColor: Colors.green.shade50,
                    side: BorderSide(color: Colors.green.shade200),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Clear'),
                    onPressed: onReset,
                  ),
                ],
              ],
            ),
          ),

          if (hasFile) ...[
            const SizedBox(height: 16),

            // ── Step 3: Map columns ───────────────────────────────────
            _StepCard(
              step: '3',
              title: 'Map Columns',
              color: Colors.purple,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Match your CSV columns to the correct fields. Required fields are marked with *.',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    children: allFields.map((field) {
                      final isRequired = requiredFields.contains(field);
                      return SizedBox(
                        width: 220,
                        child: DropdownButtonFormField<String>(
                          value: mapping[field],
                          decoration: InputDecoration(
                            labelText: isRequired ? '$field *' : field,
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            prefixIcon: Icon(
                              isRequired
                                  ? Icons.label_important_outline
                                  : Icons.label_outline,
                              size: 18,
                              color: isRequired ? Colors.purple : Colors.grey,
                            ),
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: null,
                              child: Text(
                                '— not mapped —',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ),
                            ...headers.map(
                              (h) => DropdownMenuItem(
                                value: h,
                                child: Text(h, overflow: TextOverflow.ellipsis),
                              ),
                            ),
                          ],
                          onChanged: (v) => onMappingChanged(field, v),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Step 4: Preview ───────────────────────────────────────
            _StepCard(
              step: '4',
              title: 'Preview (first 10 rows)',
              color: Colors.teal,
              child: _DataPreviewTable(
                headers: headers,
                rows: rows.take(10).toList(),
              ),
            ),
            const SizedBox(height: 16),

            // ── Step 5: Import ────────────────────────────────────────
            _StepCard(
              step: '5',
              title: 'Import to Firebase',
              color: Colors.green,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${rows.length} row(s) ready to import.',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    icon: importing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.cloud_upload, size: 18),
                    label: Text(
                      importing ? 'Importing…' : 'Import $importType',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                    ),
                    onPressed: importing ? null : onImport,
                  ),

                  // Result summary
                  if (result != null) ...[
                    const SizedBox(height: 16),
                    _ImportResultCard(result: result!),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Supporting widgets
// ─────────────────────────────────────────────────────────────────────────────

class _StepCard extends StatelessWidget {
  final String step;
  final String title;
  final Color color;
  final Widget child;

  const _StepCard({
    required this.step,
    required this.title,
    required this.color,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: color,
                  child: Text(
                    step,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _DataPreviewTable extends StatelessWidget {
  final List<String> headers;
  final List<Map<String, String>> rows;

  const _DataPreviewTable({required this.headers, required this.rows});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(Colors.teal.shade50),
        columnSpacing: 24,
        border: TableBorder.all(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(8),
        ),
        columns: headers
            .map(
              (h) => DataColumn(
                label: Text(
                  h,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            )
            .toList(),
        rows: rows
            .map(
              (row) => DataRow(
                cells: headers
                    .map(
                      (h) => DataCell(
                        Text(
                          row[h] ?? '',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    )
                    .toList(),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _ImportResult {
  final int created;
  final int skipped;
  final List<String> errors;

  const _ImportResult({
    required this.created,
    required this.skipped,
    required this.errors,
  });
}

class _ImportResultCard extends StatelessWidget {
  final _ImportResult result;

  const _ImportResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final success = result.errors.isEmpty;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: success ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: success ? Colors.green.shade200 : Colors.orange.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                success ? Icons.check_circle : Icons.warning_amber,
                color: success ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 8),
              Text(
                success ? 'Import Complete' : 'Import Finished with Warnings',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: success
                      ? Colors.green.shade800
                      : Colors.orange.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _ResultBadge(
                label: 'Created',
                count: result.created,
                color: Colors.green,
              ),
              const SizedBox(width: 12),
              if (result.skipped > 0)
                _ResultBadge(
                  label: 'Skipped',
                  count: result.skipped,
                  color: Colors.orange,
                ),
            ],
          ),
          if (result.errors.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              'Errors:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.red,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            ...result.errors
                .take(5)
                .map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      '• $e',
                      style: const TextStyle(fontSize: 12, color: Colors.red),
                    ),
                  ),
                ),
            if (result.errors.length > 5)
              Text(
                '…and ${result.errors.length - 5} more',
                style: const TextStyle(fontSize: 12, color: Colors.red),
              ),
          ],
        ],
      ),
    );
  }
}

class _ResultBadge extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _ResultBadge({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
              fontSize: 16,
            ),
          ),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}
