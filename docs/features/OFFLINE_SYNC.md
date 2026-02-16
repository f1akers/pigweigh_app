# Feature: Offline Sync & Connectivity

> **Purpose**: Provides offline-first data access, connectivity monitoring, and a sync queue for admin mutations performed while offline.

---

## 1. Overview

PigWeigh operates in environments with unreliable connectivity (rural farms, provincial areas). The app must remain **fully functional offline** for all user-facing features and gracefully queue admin write operations until connectivity is restored.

This is a **foundational feature** — every other data feature depends on it for caching strategy, connectivity checks, and sync coordination.

### Why It Exists

- Pig farmers often work in areas with intermittent mobile data.
- Weight estimation (TFLite) is already on-device; SRP data must also be available offline.
- Admins encoding SRP in the field should not lose work if the connection drops mid-save.

---

## 2. Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     Flutter App                          │
│                                                          │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐│
│  │ Connectivity  │   │  Drift (SQL) │   │  Hive (KV)   ││
│  │   Provider    │   │  SRP cache   │   │  Auth cache  ││
│  │               │   │  Sync queue  │   │  Settings    ││
│  └───────┬───────┘   └──────┬───────┘   └──────┬───────┘│
│          │                  │                   │        │
│          ▼                  ▼                   ▼        │
│  ┌──────────────────────────────────────────────────────┐│
│  │             Sync Coordinator Provider                ││
│  │  • Monitors connectivity                            ││
│  │  • Flushes pending queue on reconnect               ││
│  │  • Pulls latest server data on reconnect            ││
│  └──────────────────────────────────────────────────────┘│
│                           │                              │
└───────────────────────────┼──────────────────────────────┘
                            │ online
                            ▼
                    ┌──────────────┐
                    │ pigweigh-server│
                    └──────────────┘
```

---

## 3. Dependencies

| Depends On            | Why                                         |
| --------------------- | ------------------------------------------- |
| `connectivity_plus`   | Detect network state changes                |
| `Drift` (AppDatabase) | Store SRP cache & sync queue                |
| `Hive`                | Store admin auth cache, last sync timestamp |
| `ApiClient`           | Execute queued API calls on reconnect       |

---

## 4. Data Layer

### 4.1 Connectivity Provider

```dart
// lib/core/providers/connectivity_provider.dart

@riverpod
Stream<bool> connectivityStatus(Ref ref) {
  // Uses connectivity_plus to emit true/false on network changes
  // Initial check + stream of changes
}

@riverpod
class ConnectivityNotifier extends _$ConnectivityNotifier {
  // Exposes: bool isOnline
  // Method: Future<bool> checkNow()
}
```

### 4.2 Sync Queue Table (Drift)

A Drift table to persist pending admin write operations that failed due to offline status.

```dart
// In app_database.dart

/// Pending API operations queued while offline.
class SyncQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get endpoint => text()();           // e.g., '/srp'
  TextColumn get method => text()();             // 'POST', 'PUT', etc.
  TextColumn get payload => text()();            // JSON-encoded request body
  DateTimeColumn get createdAt => dateTime()();  // When the action was attempted
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('pending'))(); // pending | failed | completed
}
```

### 4.3 Last Sync Tracking (Hive)

```dart
// StorageKeys additions
static const String lastSrpSyncAt = 'last_srp_sync_at';  // ISO 8601 string
static const String adminCacheBox = 'admin_cache';
```

### 4.4 Sync Coordinator Provider

```dart
// lib/core/providers/sync_coordinator_provider.dart

@Riverpod(keepAlive: true)
class SyncCoordinator extends _$SyncCoordinator {
  // Responsibilities:
  // 1. Listen to connectivity changes
  // 2. On reconnect → flush sync queue (oldest first)
  // 3. On reconnect → pull latest SRP data from server
  // 4. Track last successful sync time in Hive
  //
  // Methods:
  // - Future<void> syncNow()         // Manual trigger
  // - Future<void> flushQueue()      // Process pending operations
  // - Future<void> pullLatestSrp()   // Fetch & cache latest SRP data
  // - Future<void> enqueue(...)      // Add operation to sync queue
}
```

### 4.5 Sync Queue Service

```dart
// lib/services/sync/sync_queue_service.dart

class SyncQueueService {
  // CRUD for sync queue entries
  // Methods:
  // - Future<void> enqueue({endpoint, method, payload})
  // - Future<List<SyncQueueEntry>> getPending()
  // - Future<void> markCompleted(int id)
  // - Future<void> markFailed(int id)
  // - Future<void> incrementRetry(int id)
  // - Future<void> clearCompleted()
}
```

---

## 5. Offline Strategies by Feature

| Feature                   | Offline Strategy                                                                                         |
| ------------------------- | -------------------------------------------------------------------------------------------------------- |
| **Pig Weight Estimation** | Fully offline — TFLite model is on-device                                                                |
| **Active SRP Display**    | Read from Drift cache (`SrpRecords` table)                                                               |
| **Price History**         | Read from Drift cache, paginated locally                                                                 |
| **SRP Encoding (Admin)**  | Queue in `SyncQueue`, flush on reconnect                                                                 |
| **Admin Login**           | Use cached credentials from Hive (session persists)                                                      |
| **Socket.IO (Real-time)** | Auto-reconnect built into socket_io_client; on reconnect, fetch `GET /srp/active` to catch missed events |

---

## 6. Reconnection Flow

```
App detects connectivity restored
        │
        ▼
  ┌─ Flush sync queue (FIFO, oldest first) ──┐
  │  For each pending entry:                  │
  │    1. Send API request                    │
  │    2. On success → mark completed         │
  │    3. On 4xx → mark failed (don't retry)  │
  │    4. On 5xx/network → increment retry    │
  │       (max 3 retries, then mark failed)   │
  └───────────────────────────────────────────┘
        │
        ▼
  Pull latest SRP from server
  (GET /srp?limit=50 + GET /srp/active)
        │
        ▼
  Upsert into Drift SrpRecords cache
  Update lastSrpSyncAt in Hive
        │
        ▼
  Socket.IO auto-reconnects separately
```

---

## 7. Business Rules

1. **Sync queue is FIFO** — process oldest entries first to maintain chronological order.
2. **Max 3 retries** — after 3 failed attempts, mark as `failed` and skip. Admin can see failed items.
3. **4xx errors are terminal** — validation/auth errors won't succeed on retry; mark failed immediately.
4. **5xx / network errors are retryable** — server may recover.
5. **Last sync timestamp** — stored per data type in Hive. Used to determine staleness.
6. **Cache is the source of truth for reads** — the app always reads from Drift, never directly from the API for display. API calls populate the cache.
7. **SRP cache should store at least the most recent 50 records** — enough for meaningful history display offline.
8. **Admin auth tokens persist across restarts** — stored in `flutter_secure_storage`, not affected by offline status.

---

## 8. Implementation Files (Planned)

| File                                                | Purpose                          |
| --------------------------------------------------- | -------------------------------- |
| `lib/core/providers/connectivity_provider.dart`     | Network status stream & notifier |
| `lib/core/providers/sync_coordinator_provider.dart` | Orchestrates sync on reconnect   |
| `lib/services/sync/sync_queue_service.dart`         | CRUD for the sync queue table    |
| `lib/services/database/app_database.dart`           | `SyncQueue` table addition       |
| `lib/core/constants/storage_keys.dart`              | New Hive key constants           |

---

## 9. Status

- [x] Connectivity provider
- [x] SyncQueue Drift table + migration
- [x] SyncQueueService
- [x] SyncCoordinator provider
- [x] Hive last-sync tracking
- [ ] Integration with SRP repository
- [ ] Integration with admin SRP creation
- [ ] Reconnect pull logic
- [ ] Tests
