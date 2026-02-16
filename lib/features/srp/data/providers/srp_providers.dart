import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/create_srp_request.dart';
import '../models/srp_list_response_model.dart';
import '../models/srp_record_model.dart';
import '../repositories/srp_repository.dart';

part 'srp_providers.g.dart';

/// The currently active SRP record (if any).
///
/// Reads from the server first, falling back to Drift cache.
/// Invalidate this provider to trigger a refresh (e.g., after `srp:new`).
@riverpod
class ActiveSrp extends _$ActiveSrp {
  @override
  Future<SrpRecordModel?> build() async {
    final repo = ref.watch(srpRepositoryProvider);
    final result = await repo.getActiveSrp();
    return result.when(success: (srp) => srp, failure: (_) => null);
  }

  /// Force-refresh from the server.
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(srpRepositoryProvider);
      final result = await repo.getActiveSrp();
      return result.when(success: (srp) => srp, failure: (_) => state.value);
    });
  }
}

/// Paginated list of SRP records (admin management view).
///
/// Always sorted newest-first. Supports page loading and refresh.
@riverpod
class SrpList extends _$SrpList {
  int _currentPage = 1;
  static const int _pageSize = 20;

  @override
  Future<SrpListResponseModel> build() async {
    _currentPage = 1;
    return _fetchPage(1);
  }

  /// Load a specific page.
  Future<void> loadPage(int page) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      _currentPage = page;
      return _fetchPage(page);
    });
  }

  /// Refresh the current page (pull-to-refresh).
  Future<void> refresh() async {
    _currentPage = 1;
    ref.invalidateSelf();
  }

  /// Create a new SRP record and refresh the list.
  Future<SrpRecordModel?> createSrp(CreateSrpRequest request) async {
    final repo = ref.read(srpRepositoryProvider);
    final result = await repo.createSrp(request);

    return result.when(
      success: (srp) {
        // Refresh both list and active SRP.
        ref.invalidateSelf();
        ref.invalidate(activeSrpProvider);
        return srp;
      },
      failure: (_) => null,
    );
  }

  /// The current page number.
  int get currentPage => _currentPage;

  Future<SrpListResponseModel> _fetchPage(int page) async {
    final repo = ref.read(srpRepositoryProvider);
    final result = await repo.getSrpList(page: page, limit: _pageSize);
    return result.when(
      success: (data) => data,
      failure: (error) => throw error,
    );
  }
}

/// Lookup a single SRP record by ID.
@riverpod
Future<SrpRecordModel?> srpById(Ref ref, String id) async {
  final repo = ref.watch(srpRepositoryProvider);
  final result = await repo.getSrpById(id);
  return result.when(success: (srp) => srp, failure: (_) => null);
}
