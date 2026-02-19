import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/models/srp_record_model.dart';
import '../../data/providers/srp_providers.dart';

/// Record History tab — shows a paginated admin table of all SRP records.
///
/// Columns: **PRICE / KG** and **LAST UPDATE** (startDate).
/// Supports pull-to-refresh and forward/backward page navigation.
class RecordHistoryTab extends ConsumerWidget {
  const RecordHistoryTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(srpListProvider);

    return state.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryRed),
      ),
      error: (error, _) => _ErrorView(
        message: error.toString(),
        onRetry: () => ref.read(srpListProvider.notifier).refresh(),
      ),
      data: (response) => RefreshIndicator(
        color: AppTheme.primaryRed,
        onRefresh: () => ref.read(srpListProvider.notifier).refresh(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // ── Records card ──────────────────────────────────────────────
              Card(
                elevation: 2,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                clipBehavior: Clip.antiAlias,
                child: _SrpTable(items: response.items),
              ),

              const SizedBox(height: 16),

              // ── Pagination controls ────────────────────────────────────────
              if (response.pagination.totalPages > 1)
                _PaginationRow(
                  currentPage: response.pagination.page,
                  totalPages: response.pagination.totalPages,
                  total: response.pagination.total,
                  onPageChanged: (page) =>
                      ref.read(srpListProvider.notifier).loadPage(page),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Table ─────────────────────────────────────────────────────────────────────

class _SrpTable extends StatelessWidget {
  const _SrpTable({required this.items});

  final List<SrpRecordModel> items;

  static final _dateFormat = DateFormat('MMM d, yyyy @ h:mm a');

  @override
  Widget build(BuildContext context) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(2),
        1: FlexColumnWidth(3),
        2: FlexColumnWidth(2),
      },
      border: TableBorder(
        horizontalInside: BorderSide(color: Colors.grey.shade200),
        bottom: BorderSide(color: Colors.grey.shade200),
      ),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        // Header row
        TableRow(
          decoration: const BoxDecoration(color: Colors.white),
          children: [
            _headerCell('PRICE / KG'),
            _headerCell('LAST UPDATE'),
            _headerCell('STATUS'),
          ],
        ),

        // Data rows (empty placeholder rows keep the table frame visible)
        if (items.isEmpty)
          TableRow(
            decoration: const BoxDecoration(color: Colors.white),
            children: [_emptyCell(), _emptyCell(), _emptyCell()],
          )
        else
          ...items.map(_buildRow),
      ],
    );
  }

  TableRow _buildRow(SrpRecordModel item) {
    final priceText = 'PHP ${item.price.toStringAsFixed(0)}';
    final dateText = _dateFormat.format(item.startDate.toLocal());
    final isActive = item.isActive;

    return TableRow(
      decoration: BoxDecoration(
        color: isActive ? AppTheme.primaryRed.withAlpha(10) : Colors.white,
      ),
      children: [
        _dataCell(priceText, bold: true),
        _dataCell(dateText),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isActive ? Colors.green.shade100 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isActive
                      ? Colors.green.shade400
                      : Colors.grey.shade400,
                ),
              ),
              child: Text(
                isActive ? 'Active' : 'Inactive',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isActive
                      ? Colors.green.shade700
                      : Colors.grey.shade600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _headerCell(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
    child: Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 11,
        letterSpacing: 0.5,
        color: Colors.black87,
      ),
      textAlign: TextAlign.center,
    ),
  );

  Widget _dataCell(String text, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        color: Colors.black87,
      ),
      textAlign: TextAlign.center,
    ),
  );

  Widget _emptyCell() => const SizedBox(height: 40);
}

// ── Pagination ─────────────────────────────────────────────────────────────────

class _PaginationRow extends StatelessWidget {
  const _PaginationRow({
    required this.currentPage,
    required this.totalPages,
    required this.total,
    required this.onPageChanged,
  });

  final int currentPage;
  final int totalPages;
  final int total;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: currentPage > 1
              ? () => onPageChanged(currentPage - 1)
              : null,
          icon: const Icon(Icons.chevron_left),
          color: AppTheme.primaryRed,
          disabledColor: Colors.grey.shade400,
        ),
        Text(
          'Page $currentPage of $totalPages  ($total records)',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        IconButton(
          onPressed: currentPage < totalPages
              ? () => onPageChanged(currentPage + 1)
              : null,
          icon: const Icon(Icons.chevron_right),
          color: AppTheme.primaryRed,
          disabledColor: Colors.grey.shade400,
        ),
      ],
    );
  }
}

// ── Error view ─────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: AppTheme.primaryRed, size: 48),
            const SizedBox(height: 16),
            Text(
              'Failed to load records',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryRed,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
