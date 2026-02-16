import 'dart:async';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/constants/storage_keys.dart';
import '../../core/utils/logger.dart';
import '../../services/api/api_client.dart';
import '../../services/sync/sync_queue_service.dart';
import 'connectivity_provider.dart';

part 'sync_coordinator_provider.g.dart';

/// Orchestrates offline sync on connectivity changes.
///
/// Responsibilities:
/// 1. Listen to connectivity changes.
/// 2. Flush the sync queue (FIFO, oldest first) on reconnect.
/// 3. Pull latest SRP data on reconnect.
/// 4. Track last successful sync time in Hive.
@Riverpod(keepAlive: true)
class SyncCoordinator extends _$SyncCoordinator {
  bool _isSyncing = false;

  @override
  bool build() {
    // Listen for connectivity changes and trigger sync when coming online.
    ref.listen(connectivityProvider, (previous, next) {
      final wasOffline = previous == false;
      final isNowOnline = next == true;
      if (wasOffline && isNowOnline) {
        AppLogger.info('Connectivity restored — starting sync', tag: 'SYNC');
        syncNow();
      }
    });

    return false; // not syncing initially
  }

  /// Manually trigger a full sync cycle.
  Future<void> syncNow() async {
    if (_isSyncing) {
      AppLogger.debug('Sync already in progress — skipping', tag: 'SYNC');
      return;
    }

    _isSyncing = true;
    state = true; // syncing

    try {
      await flushQueue();
      await _updateLastSyncTime();
      AppLogger.info('Sync cycle complete', tag: 'SYNC');
    } catch (e) {
      AppLogger.error('Sync cycle failed', tag: 'SYNC', error: e);
    } finally {
      _isSyncing = false;
      state = false; // done syncing
    }
  }

  /// Process all pending sync queue entries (FIFO order).
  Future<void> flushQueue() async {
    final syncService = ref.read(syncQueueServiceProvider);
    final apiClient = ref.read(apiClientProvider);

    final pending = await syncService.getPending();
    if (pending.isEmpty) {
      AppLogger.debug('Sync queue empty', tag: 'SYNC');
      return;
    }

    AppLogger.info('Flushing ${pending.length} queued operations', tag: 'SYNC');

    for (final entry in pending) {
      try {
        final payload = syncService.decodePayload(entry.payload);

        final result = switch (entry.method.toUpperCase()) {
          'POST' => await apiClient.post<dynamic>(
            entry.endpoint,
            data: payload,
          ),
          'PUT' => await apiClient.put<dynamic>(entry.endpoint, data: payload),
          'PATCH' => await apiClient.patch<dynamic>(
            entry.endpoint,
            data: payload,
          ),
          'DELETE' => await apiClient.delete<dynamic>(entry.endpoint),
          _ => throw UnsupportedError('Unsupported method: ${entry.method}'),
        };

        result.when(
          success: (_) {
            syncService.markCompleted(entry.id);
            AppLogger.info(
              'Sync entry ${entry.id} completed: ${entry.method} ${entry.endpoint}',
              tag: 'SYNC',
            );
          },
          failure: (error) {
            // 4xx → terminal failure (validation/auth error)
            if (error.statusCode != null &&
                error.statusCode! >= 400 &&
                error.statusCode! < 500) {
              syncService.markFailed(entry.id);
              AppLogger.warn(
                'Sync entry ${entry.id} failed with ${error.statusCode}: ${error.message}',
                tag: 'SYNC',
              );
            } else {
              // 5xx or unknown → retryable
              syncService.incrementRetry(entry.id);
            }
          },
        );
      } catch (e) {
        // Network errors are retryable
        await syncService.incrementRetry(entry.id);
        AppLogger.error(
          'Sync entry ${entry.id} threw exception',
          tag: 'SYNC',
          error: e,
        );
      }
    }

    await syncService.clearCompleted();
  }

  /// Record the current time as last successful sync.
  Future<void> _updateLastSyncTime() async {
    final box = await Hive.openBox(StorageKeys.cacheBox);
    await box.put(StorageKeys.lastSrpSyncAt, DateTime.now().toIso8601String());
  }

  /// Enqueue a new operation for later sync.
  Future<int> enqueue({
    required String endpoint,
    required String method,
    required Map<String, dynamic> payload,
  }) async {
    final syncService = ref.read(syncQueueServiceProvider);
    return syncService.enqueue(
      endpoint: endpoint,
      method: method,
      payload: payload,
    );
  }
}
