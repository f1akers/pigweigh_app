import 'package:drift/drift.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/constants/storage_keys.dart';
import '../../../../core/providers/connectivity_provider.dart';
import '../../../../core/utils/app_error.dart';
import '../../../../core/utils/logger.dart';
import '../../../../core/utils/result.dart';
import '../../../../services/api/api_client.dart';
import '../../../../services/database/app_database.dart';
import '../../../../services/sync/sync_queue_service.dart';
import '../models/create_srp_request.dart';
import '../models/srp_list_response_model.dart';
import '../models/srp_record_model.dart';

part 'srp_repository.g.dart';

/// Data-access layer for SRP records.
///
/// Follows the **offline-first** pattern:
/// - **Reads**: Always attempt server → cache result in Drift.
///   Fall back to Drift cache if offline.
/// - **Writes**: If online, POST directly. If offline, enqueue in SyncQueue.
class SrpRepository {
  SrpRepository({
    required ApiClient apiClient,
    required AppDatabase database,
    required SyncQueueService syncQueue,
    required bool Function() isOnline,
  }) : _apiClient = apiClient,
       _db = database,
       _syncQueue = syncQueue,
       _isOnline = isOnline;

  final ApiClient _apiClient;
  final AppDatabase _db;
  final SyncQueueService _syncQueue;
  final bool Function() _isOnline;

  // ══════════════════════════════════════════════════════════════════════════
  // Read operations — server-first with Drift cache fallback
  // ══════════════════════════════════════════════════════════════════════════

  /// Fetch the active SRP from the server, cache it, and return it.
  /// Falls back to Drift cache if offline.
  Future<Result<SrpRecordModel?, AppError>> getActiveSrp() async {
    if (_isOnline()) {
      final result = await _apiClient.get<Map<String, dynamic>>(
        ApiConstants.srpActive,
      );

      return result.when(
        success: (data) async {
          final srp = SrpRecordModel.fromJson(data);
          await _upsertSrpRecord(srp);
          return Result.success(srp);
        },
        failure: (error) async {
          // 404 means no active record — not an error, return null.
          if (error.statusCode == 404) return const Result.success(null);

          AppLogger.warn(
            'Failed to fetch active SRP from server: ${error.message}',
            tag: 'SRP',
          );
          final cached = await getCachedActiveSrp();
          return Result.success(cached);
        },
      );
    }

    // Offline — return from cache.
    final cached = await getCachedActiveSrp();
    return Result.success(cached);
  }

  /// Fetch paginated SRP list from the server, cache all results.
  /// Falls back to Drift cache if offline.
  Future<Result<SrpListResponseModel, AppError>> getSrpList({
    int page = 1,
    int limit = 20,
    bool? isActive,
  }) async {
    if (_isOnline()) {
      final queryParams = <String, dynamic>{'page': page, 'limit': limit};
      if (isActive != null) queryParams['isActive'] = isActive.toString();

      final result = await _apiClient.get<Map<String, dynamic>>(
        ApiConstants.srpList,
        queryParameters: queryParams,
      );

      return result.when(
        success: (data) async {
          final response = SrpListResponseModel.fromJson(data);

          // Cache all items in Drift.
          await _cacheSrpRecords(response.items);
          await _updateLastSyncTime();

          return Result.success(response);
        },
        failure: (error) async {
          AppLogger.warn(
            'Failed to fetch SRP list from server: ${error.message}',
            tag: 'SRP',
          );
          return _buildCachedListResponse(page, limit);
        },
      );
    }

    // Offline — build response from cache.
    return _buildCachedListResponse(page, limit);
  }

  /// Get a single SRP record by ID (server first, cache fallback).
  Future<Result<SrpRecordModel, AppError>> getSrpById(String id) async {
    if (_isOnline()) {
      final result = await _apiClient.get<Map<String, dynamic>>(
        ApiConstants.srpById(id),
      );

      return result.when(
        success: (data) async {
          final srp = SrpRecordModel.fromJson(data);
          await _upsertSrpRecord(srp);
          return Result.success(srp);
        },
        failure: (error) async {
          final cached = await _getCachedById(id);
          if (cached != null) return Result.success(cached);
          return Result.failure(error);
        },
      );
    }

    final cached = await _getCachedById(id);
    if (cached != null) return Result.success(cached);
    return Result.failure(
      const AppError(message: 'SRP record not found in local cache'),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Write operations — online direct / offline queue
  // ══════════════════════════════════════════════════════════════════════════

  /// Create a new SRP record.
  ///
  /// - **Online**: POST to server, cache result, return it.
  /// - **Offline**: Enqueue in SyncQueue, return `null` (pending).
  Future<Result<SrpRecordModel?, AppError>> createSrp(
    CreateSrpRequest request,
  ) async {
    final payload = request.toJson();

    if (_isOnline()) {
      final result = await _apiClient.post<Map<String, dynamic>>(
        ApiConstants.srpList,
        data: payload,
      );

      return result.when(
        success: (data) async {
          final srp = SrpRecordModel.fromJson(data);
          await _upsertSrpRecord(srp);
          AppLogger.info('SRP record created: ${srp.id}', tag: 'SRP');
          return Result.success(srp);
        },
        failure: (error) => Result.failure(error),
      );
    }

    // Offline — enqueue for later sync.
    await _syncQueue.enqueue(
      endpoint: ApiConstants.srpList,
      method: 'POST',
      payload: payload,
    );
    AppLogger.info('SRP creation queued for sync', tag: 'SRP');
    return const Result.success(null); // null = pending
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Cache operations
  // ══════════════════════════════════════════════════════════════════════════

  /// Sync SRP records from server into Drift cache.
  /// Called on reconnect by [SyncCoordinator].
  Future<void> syncFromServer() async {
    try {
      // Fetch active SRP
      await getActiveSrp();

      // Fetch latest page of records
      await getSrpList(page: 1, limit: 50);

      AppLogger.info('SRP cache synced from server', tag: 'SRP');
    } catch (e) {
      AppLogger.error('Failed to sync SRP from server', tag: 'SRP', error: e);
    }
  }

  /// Get all cached SRP records from Drift (for offline use).
  Future<List<SrpRecordModel>> getCachedSrpRecords() async {
    final rows = await (_db.select(
      _db.srpRecords,
    )..orderBy([(t) => OrderingTerm.desc(t.startDate)])).get();
    return rows.map(_fromDriftRow).toList();
  }

  /// Get the active SRP from Drift cache.
  Future<SrpRecordModel?> getCachedActiveSrp() async {
    final row =
        await (_db.select(_db.srpRecords)
              ..where((t) => t.isActive.equals(true))
              ..orderBy([(t) => OrderingTerm.desc(t.startDate)])
              ..limit(1))
            .getSingleOrNull();
    return row != null ? _fromDriftRow(row) : null;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Private helpers
  // ══════════════════════════════════════════════════════════════════════════

  /// Upsert a single SRP record into Drift.
  Future<void> _upsertSrpRecord(SrpRecordModel model) async {
    await _db.into(_db.srpRecords).insertOnConflictUpdate(_toCompanion(model));
  }

  /// Bulk-cache a list of SRP records into Drift.
  Future<void> _cacheSrpRecords(List<SrpRecordModel> records) async {
    await _db.batch((batch) {
      for (final record in records) {
        batch.insert(
          _db.srpRecords,
          _toCompanion(record),
          onConflict: DoUpdate((_) => _toCompanion(record)),
        );
      }
    });
  }

  /// Upsert a single SRP record into Drift cache (public, for real-time updates).
  Future<void> upsertSrpRecord(SrpRecordModel model) async {
    await _upsertSrpRecord(model);
  }

  /// Fetch a single cached record by ID.
  Future<SrpRecordModel?> _getCachedById(String id) async {
    final row = await (_db.select(
      _db.srpRecords,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row != null ? _fromDriftRow(row) : null;
  }

  /// Build a paginated response from cached data.
  Future<Result<SrpListResponseModel, AppError>> _buildCachedListResponse(
    int page,
    int limit,
  ) async {
    final allRecords = await getCachedSrpRecords();
    final total = allRecords.length;
    final totalPages = (total / limit)
        .ceil()
        .clamp(1, double.maxFinite)
        .toInt();
    final start = (page - 1) * limit;
    final end = (start + limit).clamp(0, total);
    final items = start < total
        ? allRecords.sublist(start, end)
        : <SrpRecordModel>[];

    return Result.success(
      SrpListResponseModel(
        items: items,
        pagination: PaginationModel(
          page: page,
          limit: limit,
          total: total,
          totalPages: totalPages,
        ),
      ),
    );
  }

  /// Update the last SRP sync timestamp in Hive.
  Future<void> _updateLastSyncTime() async {
    try {
      final box = Hive.box(StorageKeys.cacheBox);
      await box.put(
        StorageKeys.lastSrpSyncAt,
        DateTime.now().toIso8601String(),
      );
    } catch (_) {
      // Non-critical — don't propagate.
    }
  }

  // ── Drift ↔ Model mapping ──────────────────────────────────────────────

  /// Convert a Drift row to a domain model.
  SrpRecordModel _fromDriftRow(SrpRecord row) {
    return SrpRecordModel(
      id: row.id,
      price: row.price,
      reference: row.reference,
      startDate: row.startDate,
      endDate: row.endDate,
      isActive: row.isActive,
      createdBy: null, // Not stored in local cache.
      createdAt: row.createdAt,
    );
  }

  /// Convert a domain model to a Drift companion for upsert.
  SrpRecordsCompanion _toCompanion(SrpRecordModel model) {
    return SrpRecordsCompanion.insert(
      id: model.id,
      price: model.price,
      reference: model.reference,
      startDate: model.startDate,
      endDate: Value(model.endDate),
      isActive: Value(model.isActive),
      createdAt: model.createdAt,
      syncedAt: Value(DateTime.now()),
    );
  }
}

/// Singleton provider for [SrpRepository].
@Riverpod(keepAlive: true)
SrpRepository srpRepository(Ref ref) {
  return SrpRepository(
    apiClient: ref.watch(apiClientProvider),
    database: ref.watch(appDatabaseProvider),
    syncQueue: ref.watch(syncQueueServiceProvider),
    isOnline: () => ref.read(connectivityProvider),
  );
}
