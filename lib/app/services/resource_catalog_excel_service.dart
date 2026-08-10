import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:app_release_center/app/models/resource_catalog.dart';
import 'package:app_release_center/app/services/resource_catalog_crypto_service.dart';
import 'package:app_release_center/app/services/resource_catalog_password_store_service.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:xml/xml.dart';

class ResourceCatalogExcelService extends GetxService {
  ResourceCatalogExcelService({
    required ResourceCatalogCryptoService crypto,
    required ResourceCatalogPasswordStoreService passwordStore,
    Uuid? uuid,
  }) : _crypto = crypto,
       _passwordStore = passwordStore,
       _uuid = uuid ?? const Uuid();

  final ResourceCatalogCryptoService _crypto;
  final ResourceCatalogPasswordStoreService _passwordStore;
  final Uuid _uuid;

  Future<ResourceCatalogExcelExportResult> exportCatalog({
    required String outputPath,
    required List<ResourceCatalogItem> resources,
    required List<ResourcePasswordEntry> passwords,
  }) async {
    final archive = Archive();
    final passwordRows = <List<String>>[
      _passwordHeaders,
      for (final entry in passwords)
        [
          entry.id,
          entry.site,
          entry.loginUrl,
          entry.username,
          await _encryptedPassword(entry),
          entry.environment,
          entry.owner,
          entry.twoFactorLocation,
          entry.notes,
          entry.tags.join(', '),
          entry.secretKey,
          entry.updatedAt.toUtc().toIso8601String(),
        ],
    ];

    _addXlsxStructure(
      archive,
      resources: [
        _resourceHeaders,
        for (final entry in resources)
          [
            entry.id,
            entry.kind.name,
            entry.title,
            entry.url,
            entry.localPath,
            entry.environment,
            entry.owner,
            entry.notes,
            entry.tags.join(', '),
            entry.updatedAt.toUtc().toIso8601String(),
          ],
      ],
      passwords: passwordRows,
    );

    final target = File(p.normalize(outputPath));
    await target.parent.create(recursive: true);
    final bytes = ZipEncoder().encode(archive);
    await target.writeAsBytes(bytes, flush: true);

    return ResourceCatalogExcelExportResult(
      filePath: target.path,
      resourceCount: resources.length,
      passwordCount: passwords.length,
    );
  }

  Future<ResourceCatalogExcelImportResult> importCatalog({
    required String projectPath,
    required String inputPath,
  }) async {
    final source = File(p.normalize(inputPath));
    if (!source.existsSync()) {
      throw const ResourceCatalogExcelException('Excel file does not exist.');
    }

    final archive = ZipDecoder().decodeBytes(await source.readAsBytes());
    final resourceRows = _worksheetRows(_archiveText(archive, _resourceSheet));
    final passwordRows = _worksheetRows(_archiveText(archive, _passwordSheet));
    final resources = _resourceEntries(resourceRows);
    final passwords = await _passwordEntries(passwordRows);

    return ResourceCatalogExcelImportResult(
      bundle: ResourceCatalogBundle(
        projectPath: p.normalize(projectPath),
        resources: resources,
        passwords: passwords,
      ),
      resourceCount: resources.length,
      passwordCount: passwords.length,
    );
  }

  Future<String> _encryptedPassword(ResourcePasswordEntry entry) async {
    final password = await _passwordStore.read(entry.secretKey) ?? '';
    if (password.isEmpty) return '';
    return _crypto.encryptPassword(password);
  }

  List<ResourceCatalogItem> _resourceEntries(List<List<String>> rows) {
    if (rows.isEmpty) return const [];
    final headers = _headerMap(rows.first);
    final entries = <ResourceCatalogItem>[];

    for (final row in rows.skip(1)) {
      final values = _rowMap(headers, row);
      final title = _value(values, 'title');
      final url = _value(values, 'url');
      final localPath = _value(values, 'localPath');
      if (title.isEmpty && url.isEmpty && localPath.isEmpty) continue;

      entries.add(
        ResourceCatalogItem(
          id: _value(values, 'id', fallback: _uuid.v4()),
          kind: _kindFromImport(_value(values, 'kind')),
          title: title.isEmpty
              ? url.isEmpty
                    ? localPath
                    : url
              : title,
          url: url,
          localPath: localPath,
          environment: _value(values, 'environment'),
          owner: _value(values, 'owner'),
          notes: _value(values, 'notes'),
          tags: _tags(_value(values, 'tags')),
          updatedAt: _dateFromImport(_value(values, 'updatedAt')),
        ),
      );
    }

    return entries;
  }

  Future<List<ResourcePasswordEntry>> _passwordEntries(
    List<List<String>> rows,
  ) async {
    if (rows.isEmpty) return const [];
    final headers = _headerMap(rows.first);
    final entries = <ResourcePasswordEntry>[];

    for (final row in rows.skip(1)) {
      final values = _rowMap(headers, row);
      final site = _value(values, 'site');
      final loginUrl = _value(values, 'loginUrl');
      final username = _value(values, 'username');
      if (site.isEmpty && loginUrl.isEmpty && username.isEmpty) continue;

      final secretKey = _value(values, 'secretKey', fallback: _uuid.v4());
      final encryptedPassword = _value(values, 'password');
      if (encryptedPassword.isNotEmpty) {
        if (!_crypto.isEncryptedPayload(encryptedPassword)) {
          throw const ResourceCatalogExcelException(
            'Password imports must use encrypted arcenc:v1 payloads.',
          );
        }
        await _passwordStore.save(
          secretKey,
          await _crypto.decryptPassword(encryptedPassword),
        );
      }

      entries.add(
        ResourcePasswordEntry(
          id: _value(values, 'id', fallback: _uuid.v4()),
          secretKey: secretKey,
          site: site.isEmpty ? loginUrl : site,
          loginUrl: loginUrl,
          username: username,
          environment: _value(values, 'environment'),
          owner: _value(values, 'owner'),
          twoFactorLocation: _value(values, 'twoFactorLocation'),
          notes: _value(values, 'notes'),
          tags: _tags(_value(values, 'tags')),
          updatedAt: _dateFromImport(_value(values, 'updatedAt')),
        ),
      );
    }

    return entries;
  }

  void _addXlsxStructure(
    Archive archive, {
    required List<List<String>> resources,
    required List<List<String>> passwords,
  }) {
    _addTextFile(archive, '[Content_Types].xml', _contentTypesXml);
    _addTextFile(archive, '_rels/.rels', _rootRelsXml);
    _addTextFile(archive, 'xl/workbook.xml', _workbookXml);
    _addTextFile(archive, 'xl/_rels/workbook.xml.rels', _workbookRelsXml);
    _addTextFile(archive, 'xl/styles.xml', _stylesXml);
    _addTextFile(archive, _resourceSheet, _worksheetXml(resources));
    _addTextFile(archive, _passwordSheet, _worksheetXml(passwords));
  }

  void _addTextFile(Archive archive, String name, String content) {
    archive.add(ArchiveFile.string(name, content.trimLeft()));
  }

  String _archiveText(Archive archive, String path) {
    final entry = archive.findFile(path);
    final bytes = entry?.readBytes();
    if (bytes == null) {
      throw ResourceCatalogExcelException('Missing worksheet: $path');
    }
    return utf8.decode(bytes);
  }

  String _worksheetXml(List<List<String>> rows) {
    final buffer = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write(
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">',
      )
      ..write('<sheetData>');

    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final rowNumber = rowIndex + 1;
      buffer.write('<row r="$rowNumber">');
      final row = rows[rowIndex];
      for (var columnIndex = 0; columnIndex < row.length; columnIndex++) {
        final cellRef = '${_columnName(columnIndex)}$rowNumber';
        buffer
          ..write('<c r="$cellRef" t="inlineStr"><is>')
          ..write('<t xml:space="preserve">${_escapeXml(row[columnIndex])}</t>')
          ..write('</is></c>');
      }
      buffer.write('</row>');
    }

    buffer
      ..write('</sheetData>')
      ..write('</worksheet>');
    return buffer.toString();
  }

  List<List<String>> _worksheetRows(String xml) {
    final document = XmlDocument.parse(xml);
    final rowNodes = document.findAllElements('row');
    final rows = <List<String>>[];

    for (final row in rowNodes) {
      final values = <int, String>{};
      for (final cell in row.findElements('c')) {
        final cellRef = cell.getAttribute('r') ?? '';
        final columnIndex = _columnIndex(cellRef);
        if (columnIndex == null) continue;
        values[columnIndex] = _cellValue(cell);
      }
      if (values.isEmpty) {
        rows.add(const []);
        continue;
      }

      final maxColumn = values.keys.reduce((a, b) => a > b ? a : b);
      rows.add([
        for (var index = 0; index <= maxColumn; index++) values[index] ?? '',
      ]);
    }

    return rows;
  }

  String _cellValue(XmlElement cell) {
    final inline = cell.findAllElements('t').map((node) => node.innerText);
    if (inline.isNotEmpty) return inline.join();
    final values = cell.findElements('v');
    return values.isEmpty ? '' : values.first.innerText;
  }

  Map<String, int> _headerMap(List<String> headers) {
    return {
      for (var index = 0; index < headers.length; index++)
        headers[index].trim(): index,
    };
  }

  Map<String, String> _rowMap(Map<String, int> headers, List<String> row) {
    return {
      for (final entry in headers.entries)
        entry.key: entry.value < row.length ? row[entry.value].trim() : '',
    };
  }

  String _value(
    Map<String, String> values,
    String key, {
    String fallback = '',
  }) {
    final value = values[key]?.trim() ?? '';
    return value.isEmpty ? fallback : value;
  }

  ResourceCatalogKind _kindFromImport(String value) {
    final normalized = value.trim().toLowerCase();
    for (final kind in ResourceCatalogKind.values) {
      if (kind.name.toLowerCase() == normalized ||
          kind.label.toLowerCase() == normalized) {
        return kind;
      }
    }
    return ResourceCatalogKind.other;
  }

  List<String> _tags(String value) {
    if (value.trim().isEmpty) return const [];
    return value
        .split(',')
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList();
  }

  DateTime _dateFromImport(String value) {
    return DateTime.tryParse(value)?.toUtc() ?? DateTime.now().toUtc();
  }

  String _columnName(int index) {
    var value = index + 1;
    final buffer = StringBuffer();
    while (value > 0) {
      final remainder = (value - 1) % 26;
      buffer.writeCharCode(65 + remainder);
      value = (value - remainder - 1) ~/ 26;
    }
    return buffer.toString().split('').reversed.join();
  }

  int? _columnIndex(String cellRef) {
    final letters = RegExp(r'^[A-Z]+').stringMatch(cellRef.toUpperCase());
    if (letters == null || letters.isEmpty) return null;
    var value = 0;
    for (final codeUnit in letters.codeUnits) {
      value = value * 26 + (codeUnit - 64);
    }
    return value - 1;
  }

  String _escapeXml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}

class ResourceCatalogExcelExportResult {
  const ResourceCatalogExcelExportResult({
    required this.filePath,
    required this.resourceCount,
    required this.passwordCount,
  });

  final String filePath;
  final int resourceCount;
  final int passwordCount;
}

class ResourceCatalogExcelImportResult {
  const ResourceCatalogExcelImportResult({
    required this.bundle,
    required this.resourceCount,
    required this.passwordCount,
  });

  final ResourceCatalogBundle bundle;
  final int resourceCount;
  final int passwordCount;
}

class ResourceCatalogExcelException implements Exception {
  const ResourceCatalogExcelException(this.message);

  final String message;

  @override
  String toString() => message;
}

const _resourceHeaders = [
  'id',
  'kind',
  'title',
  'url',
  'localPath',
  'environment',
  'owner',
  'notes',
  'tags',
  'updatedAt',
];

const _passwordHeaders = [
  'id',
  'site',
  'loginUrl',
  'username',
  'password',
  'environment',
  'owner',
  'twoFactorLocation',
  'notes',
  'tags',
  'secretKey',
  'updatedAt',
];

const _resourceSheet = 'xl/worksheets/sheet1.xml';
const _passwordSheet = 'xl/worksheets/sheet2.xml';

const _contentTypesXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
</Types>
''';

const _rootRelsXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>
''';

const _workbookXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="Resources" sheetId="1" r:id="rId1"/>
    <sheet name="Passwords" sheetId="2" r:id="rId2"/>
  </sheets>
</workbook>
''';

const _workbookRelsXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>
''';

const _stylesXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>
  <fills count="1"><fill><patternFill patternType="none"/></fill></fills>
  <borders count="1"><border/></borders>
  <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
  <cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>
</styleSheet>
''';
