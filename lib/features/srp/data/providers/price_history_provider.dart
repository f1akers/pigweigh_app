import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/utils/logger.dart';
import '../models/srp_record_model.dart';
import '../repositories/srp_repository.dart';

part 'price_history_provider.g.dart';

/// User-facing price history list (public, no auth required).
///
/// Fetches SRP records sorted newest-first, with support for
/// pull-to-refresh and infinite scroll (load more).
///
/// **Cache-first**: if cached data exists, shows it immediately and
/// refreshes in the background. Never shows a loading spinner if
/// the cache has data.
@riverpod
class PriceHistory extends _$PriceHistory {
  int _currentPage = 1;
  static const int _pageSize = 20;
  bool _hasMore = true;

  @override
  Future<List<SrpRecordModel>> build() async {
    _currentPage = 1;
    _hasMore = true;

    final repo = ref.watch(srpRepositoryProvider);

    // Try server first; on failure, fall back to full cache.
    final result = await repo.getSrpList(page: 1, limit: _pageSize);
    return result.when(
      success: (data) {
        _hasMore = data.pagination.page < data.pagination.totalPages;
        return data.items;
      },
      failure: (_) async {
        AppLogger.debug('Loading price history from cache', tag: 'HISTORY');
        _hasMore = false;
        return repo.getCachedSrpRecords();
      },
    );
  }

  /// Pull-to-refresh — re-fetch page 1 from the server.
  Future<void> refresh() async {
    _currentPage = 1;
    _hasMore = true;
    ref.invalidateSelf();
  }

  /// Infinite scroll — append the next page of results.
  Future<void> loadMore() async {
    if (!_hasMore) return;

    final current = state.value ?? [];
    final nextPage = _currentPage + 1;

    final repo = ref.read(srpRepositoryProvider);
    final result = await repo.getSrpList(page: nextPage, limit: _pageSize);

    result.when(
      success: (data) {
        _currentPage = nextPage;
        _hasMore = data.pagination.page < data.pagination.totalPages;
        state = AsyncData([...current, ...data.items]);
      },
      failure: (error) {
        AppLogger.warn(
          'Failed to load more price history: ${error.message}',
          tag: 'HISTORY',
        );
        // Keep existing data — don't wipe the list on pagination failure.
      },
    );
  }

  /// Whether there are more pages to load.
  bool get hasMore => _hasMore;
}
