import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/utils/logger.dart';
import '../database/app_database.dart';

part 'sync_queue_service.g.dart';

/// CRUD service for the offline sync queue stored in Drift.
///
/// Pending write operations (e.g., SRP creation while offline) are
/// enqueued here and processed FIFO on reconnect by [SyncCoordinator].
class SyncQueueService {
  SyncQueueService({required AppDatabase database}) : _db = database;

  final AppDatabase _db;

  /// Enqueue a new pending API operation.
  Future<int> enqueue({
    required String endpoint,
    required String method,
    required Map<String, dynamic> payload,
  }) async {
    final id = await _db
        .into(_db.syncQueue)
        .insert(
          SyncQueueCompanion.insert(
            endpoint: endpoint,
            method: method,
            payload: jsonEncode(payload),
            createdAt: DateTime.now(),
          ),
        );
    AppLogger.debug(
      'Enqueued sync operation: $method $endpoint (id=$id)',
      tag: 'SYNC',
    );
    return id;
  }

  /// Get all pending entries ordered by creation time (FIFO).
  Future<List<SyncQueueData>> getPending() async {
    return (_db.select(_db.syncQueue)
          ..where((t) => t.status.equals('pending'))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  /// Mark an entry as completed.
  Future<void> markCompleted(int id) async {
    await (_db.update(_db.syncQueue)..where((t) => t.id.equals(id))).write(
      const SyncQueueCompanion(status: Value('completed')),
    );
  }

  /// Mark an entry as permanently failed.
  Future<void> markFailed(int id) async {
    await (_db.update(_db.syncQueue)..where((t) => t.id.equals(id))).write(
      const SyncQueueCompanion(status: Value('failed')),
    );
  }

  /// Increment the retry count for a retryable failure.
  Future<void> incrementRetry(int id) async {
    final entry = await (_db.select(
      _db.syncQueue,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (entry == null) return;

    final newCount = entry.retryCount + 1;
    if (newCount >= 3) {
      await markFailed(id);
      AppLogger.warn(
        'Sync entry $id exceeded max retries — marked failed',
        tag: 'SYNC',
      );
    } else {
      await (_db.update(_db.syncQueue)..where((t) => t.id.equals(id))).write(
        SyncQueueCompanion(retryCount: Value(newCount)),
      );
    }
  }

  /// Remove all completed entries.
  Future<void> clearCompleted() async {
    await (_db.delete(
      _db.syncQueue,
    )..where((t) => t.status.equals('completed'))).go();
  }

  /// Decode the JSON payload string from a queue entry.
  Map<String, dynamic> decodePayload(String payloadString) {
    return jsonDecode(payloadString) as Map<String, dynamic>;
  }
}

/// Singleton provider for [SyncQueueService].
@Riverpod(keepAlive: true)
SyncQueueService syncQueueService(Ref ref) {
  return SyncQueueService(database: ref.watch(appDatabaseProvider));
}
