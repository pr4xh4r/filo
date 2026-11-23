import 'package:flutter/material.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_typography.dart';

/// Lightweight interactive spreadsheet table viewer for CSV and TSV files.
class CsvTableViewerWidget extends StatelessWidget {
  final String content;
  final String fileName;

  const CsvTableViewerWidget({
    super.key,
    required this.content,
    required this.fileName,
  });

  List<List<String>> _parseRows() {
    final delimiter = fileName.toLowerCase().endsWith('.tsv') ? '\t' : ',';
    final lines = content.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
    return lines.map((line) => line.split(delimiter)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _parseRows();
    if (rows.isEmpty) {
      return const Center(child: Text('Empty CSV spreadsheet'));
    }

    final headerRow = rows.first;
    final dataRows = rows.skip(1).toList();

    return Column(
      children: [
        // Summary Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.black.withValues(alpha: 0.06))),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${rows.length} rows • ${headerRow.length} columns',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: FiloColors.lightTextSecondary),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: FiloColors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'SPREADSHEET',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: FiloColors.success),
                ),
              ),
            ],
          ),
        ),

        // Scrollable Table Viewport
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(const Color(0xFFF2F2F7)),
                dataRowMinHeight: 38,
                dataRowMaxHeight: 44,
                headingTextStyle: FiloTypography.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  color: FiloColors.lightTextPrimary,
                ),
                columns: List.generate(
                  headerRow.length,
                  (index) => DataColumn(
                    label: Text(headerRow[index].trim()),
                  ),
                ),
                rows: dataRows.map((row) {
                  return DataRow(
                    cells: List.generate(headerRow.length, (colIdx) {
                      final val = colIdx < row.length ? row[colIdx].trim() : '';
                      return DataCell(
                        Text(
                          val,
                          style: const TextStyle(fontSize: 12, color: FiloColors.lightTextPrimary),
                        ),
                      );
                    }),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
