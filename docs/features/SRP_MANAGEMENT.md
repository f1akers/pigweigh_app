# Feature: SRP Management (Flutter — Admin)

> **Purpose**: Allows authenticated admins to encode new SRP records (price, source reference, date of effectivity) and view/manage existing records.

---

## 1. Overview

SRP Management is the admin-side feature for encoding official DA Suggested Retail Prices into the system. Admins fill in a form with the price, a reference (DA memorandum URL), and a start date. The server handles cascade logic (auto-closing the previous active record) and real-time broadcasting.

This feature also includes the admin's view of all SRP records (the management/list view), which is distinct from the user-facing price history.

### Why It Exists

- DA personnel need a mobile-friendly way to encode new SRP values from the field.
- The encoding form must work offline — queuing the submission until connectivity is restored.
- Admins need to review what has been published and when.

---

## 2. Dependencies

| Depends On                                                                         | Why                                       |
| ---------------------------------------------------------------------------------- | ----------------------------------------- |
| [ADMIN_AUTH](ADMIN_AUTH.md)                                                        | Bearer token required for `POST /api/srp` |
| [OFFLINE_SYNC](OFFLINE_SYNC.md)                                                    | Queue SRP creation when offline           |
| `ApiClient`                                                                        | HTTP requests to server                   |
| `Drift` (AppDatabase)                                                              | Cache SRP records locally                 |
| Server: [SRP_MANAGEMENT](../../../pigweigh-server/docs/features/SRP_MANAGEMENT.md) | Backend CRUD endpoints                    |
| Server: [REALTIME_SRP](../../../pigweigh-server/docs/features/REALTIME_SRP.md)     | Socket.IO `srp:new` event after creation  |
| Server: [PRICE_HISTORY](../../../pigweigh-server/docs/features/PRICE_HISTORY.md)   | Cascade logic, immutability rules         |

---

## 3. Data Layer

### 3.1 Data Models

```dart
// lib/features/srp/data/models/srp_record_model.dart

@freezed
abstract class SrpRecordModel with _$SrpRecordModel {
  const factory SrpRecordModel({
    required String id,
    required double price,        // Decimal from server comes as string, parse to double
    required String reference,
    required DateTime startDate,
    DateTime? endDate,
    required bool isActive,
    SrpCreatedByModel? createdBy,
    required DateTime createdAt,
  }) = _SrpRecordModel;

  factory SrpRecordModel.fromJson(Map<String, dynamic> json) =>
      _$SrpRecordModelFromJson(json);
}

@freezed
abstract class SrpCreatedByModel with _$SrpCreatedByModel {
  const factory SrpCreatedByModel({
    required String id,
    required String name,
  }) = _SrpCreatedByModel;

  factory SrpCreatedByModel.fromJson(Map<String, dynamic> json) =>
      _$SrpCreatedByModelFromJson(json);
}

// lib/features/srp/data/models/srp_list_response_model.dart

@freezed
abstract class SrpListResponseModel with _$SrpListResponseModel {
  const factory SrpListResponseModel({
    required List<SrpRecordModel> items,
    required PaginationModel pagination,
  }) = _SrpListResponseModel;

  factory SrpListResponseModel.fromJson(Map<String, dynamic> json) =>
      _$SrpListResponseModelFromJson(json);
}

@freezed
abstract class PaginationModel with _$PaginationModel {
  const factory PaginationModel({
    required int page,
    required int limit,
    required int total,
    required int totalPages,
  }) = _PaginationModel;

  factory PaginationModel.fromJson(Map<String, dynamic> json) =>
      _$PaginationModelFromJson(json);
}
```

### 3.2 API Endpoints Used

| Method | Path              | Auth   | Description                              |
| ------ | ----------------- | ------ | ---------------------------------------- |
| `POST` | `/api/srp`        | Bearer | Create a new SRP record                  |
| `GET`  | `/api/srp`        | Public | List SRP records (paginated, filterable) |
| `GET`  | `/api/srp/active` | Public | Get the currently active SRP record      |
| `GET`  | `/api/srp/:id`    | Public | Get a single SRP record by ID            |

### 3.3 Create SRP Request Model

```dart
// lib/features/srp/data/models/create_srp_request.dart

@freezed
abstract class CreateSrpRequest with _$CreateSrpRequest {
  const factory CreateSrpRequest({
    required double price,
    required String reference,
    required DateTime startDate,   // Sent as ISO 8601 with timezone
    DateTime? endDate,
  }) = _CreateSrpRequest;

  factory CreateSrpRequest.fromJson(Map<String, dynamic> json) =>
      _$CreateSrpRequestFromJson(json);
}
```

### 3.4 SRP Repository

```dart
// lib/features/srp/data/repositories/srp_repository.dart

class SrpRepository {
  SrpRepository({
    required ApiClient apiClient,
    required AppDatabase database,
    required SyncQueueService syncQueue,
    required ConnectivityNotifier connectivity,
  });

  // ── Read operations (always from cache, sync from server when online) ─────

  /// Fetch the active SRP from server and cache it.
  /// Falls back to Drift cache if offline.
  Future<Result<SrpRecordModel?, AppError>> getActiveSrp();

  /// Fetch paginated SRP list from server, cache all results.
  /// Falls back to Drift cache if offline.
  Future<Result<SrpListResponseModel, AppError>> getSrpList({
    int page = 1,
    int limit = 20,
    bool? isActive,
  });

  /// Get a single SRP record by ID (server first, cache fallback).
  Future<Result<SrpRecordModel, AppError>> getSrpById(String id);

  // ── Write operations (online → direct, offline → queue) ───────────────────

  /// Create a new SRP record.
  /// If online: POST to server, cache result, return success.
  /// If offline: enqueue in SyncQueue, return success with pending flag.
  Future<Result<SrpRecordModel?, AppError>> createSrp(CreateSrpRequest request);

  // ── Cache operations ──────────────────────────────────────────────────────

  /// Sync SRP records from server into Drift cache.
  /// Called on reconnect by SyncCoordinator.
  Future<void> syncFromServer();

  /// Get all cached SRP records from Drift (for offline use).
  Future<List<SrpRecordModel>> getCachedSrpRecords();

  /// Get the active SRP from Drift cache.
  Future<SrpRecordModel?> getCachedActiveSrp();
}
```

### 3.5 Drift ↔ Model Mapping

```dart
// Mapping between Drift SrpRecords table rows and SrpRecordModel

// SrpRecord (Drift row) → SrpRecordModel
SrpRecordModel fromDriftRow(SrpRecord row) {
  return SrpRecordModel(
    id: row.id,
    price: row.price,
    reference: row.reference,
    startDate: row.startDate,
    endDate: row.endDate,
    isActive: row.isActive,
    createdBy: null,  // Not stored in local cache
    createdAt: row.createdAt,
  );
}

// SrpRecordModel → SrpRecordsCompanion (for upsert)
SrpRecordsCompanion toCompanion(SrpRecordModel model) {
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
```

### 3.6 Providers

| Provider                | Type                  | Purpose                                             |
| ----------------------- | --------------------- | --------------------------------------------------- |
| `srpRepositoryProvider` | Provider (keepAlive)  | Singleton `SrpRepository`                           |
| `activeSrpProvider`     | AsyncNotifier         | Current active SRP (from cache, synced with server) |
| `srpListProvider`       | AsyncNotifier         | Paginated SRP list with filters                     |
| `srpByIdProvider(id)`   | FutureProvider.family | Single SRP record lookup                            |

```dart
// lib/features/srp/data/providers/srp_providers.dart

@Riverpod(keepAlive: true)
SrpRepository srpRepository(Ref ref) {
  return SrpRepository(
    apiClient: ref.watch(apiClientProvider),
    database: ref.watch(appDatabaseProvider),
    syncQueue: ref.watch(syncQueueServiceProvider),
    connectivity: ref.watch(connectivityNotifierProvider.notifier),
  );
}

@riverpod
class ActiveSrp extends _$ActiveSrp {
  @override
  Future<SrpRecordModel?> build() async {
    final repo = ref.watch(srpRepositoryProvider);
    final result = await repo.getActiveSrp();
    return result.when(
      success: (srp) => srp,
      failure: (_) => null,
    );
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(srpRepositoryProvider);
      final result = await repo.getActiveSrp();
      return result.when(
        success: (srp) => srp,
        failure: (_) => state.valueOrNull,
      );
    });
  }
}

@riverpod
class SrpList extends _$SrpList {
  int _currentPage = 1;

  @override
  Future<SrpListResponseModel> build() async {
    final repo = ref.watch(srpRepositoryProvider);
    final result = await repo.getSrpList(page: 1);
    return result.when(
      success: (data) => data,
      failure: (error) => throw error,
    );
  }

  Future<void> loadPage(int page) async { /* ... */ }
  Future<void> refresh() async { /* ... */ }
}
```

---

## 4. Presentation Layer

> **Note**: Presentation layer (screens, widgets, design) will be documented and implemented separately when design screenshots are provided.

### 4.1 Screens (Planned)

| Screen                | Route               | Auth   | Description                             |
| --------------------- | ------------------- | ------ | --------------------------------------- |
| `SrpEncodeScreen`     | `/admin/srp/encode` | Bearer | Form to create a new SRP record         |
| `SrpManagementScreen` | `/admin/srp`        | Bearer | List view of all SRP records for admins |

### 4.2 UI Behaviors (Placeholder)

**SRP Encode Form:**

- Price input (numeric, PHP currency)
- Reference input (text/URL for DA memorandum)
- Start date picker (date of effectivity)
- Submit button
- Loading state during submission
- Success feedback (toast/snackbar)
- Offline indicator + "will be submitted when online" message

**SRP Management List:**

- Paginated list of SRP records
- Each item shows: price, start date, end date, active badge, created by
- Active record highlighted
- Pull-to-refresh
- Offline indicator showing cached data age

### 4.3 Navigation / Routing

```dart
// AppRoutes additions:
static const String adminSrpList = '/admin/srp';
static const String adminSrpEncode = '/admin/srp/encode';

// All /admin/* routes require auth (GoRouter redirect guard)
```

---

## 5. Offline Behavior

### Creating SRP While Offline

1. Admin fills in the SRP form and taps submit.
2. `SrpRepository.createSrp()` detects offline status.
3. The request payload is serialized and enqueued in the `SyncQueue` Drift table.
4. The UI shows a success state with an "offline — will sync when connected" message.
5. When connectivity is restored, `SyncCoordinator` flushes the queue:
   - Sends `POST /api/srp` with the queued payload.
   - On server success, caches the returned record in Drift.
   - On failure (e.g., date conflict), marks the queue entry as failed.

### Reading SRP While Offline

- All read operations (`getActiveSrp`, `getSrpList`) fall back to the Drift cache.
- The cache is populated on every successful server fetch.
- UI shows a "cached data" indicator with the last sync timestamp.

---

## 6. Business Rules

1. **Price must be positive** — validated client-side before submission.
2. **Reference is required** — non-empty string.
3. **Start date is required** — must be a valid date.
4. **Server handles cascade** — the app does NOT auto-close previous records. The server's transaction does this.
5. **`isActive` is read-only on the client** — never set by the app, always from the server.
6. **Price stored as `double`** — server returns decimal strings (e.g., `"230.00"`), parsed to `double` in Dart. Display with 2 decimal places.
7. **Timestamps in UTC** — server returns ISO 8601 UTC. App converts to local time (`Asia/Manila`) for display.
8. **Offline queue preserves submission order** — FIFO processing ensures chronological integrity.

---

## 7. Implementation Files (Planned)

| File                                                               | Layer        | Purpose                    |
| ------------------------------------------------------------------ | ------------ | -------------------------- |
| `lib/features/srp/data/models/srp_record_model.dart`               | Data         | SRP record model (freezed) |
| `lib/features/srp/data/models/srp_created_by_model.dart`           | Data         | Embedded creator model     |
| `lib/features/srp/data/models/srp_list_response_model.dart`        | Data         | Paginated list wrapper     |
| `lib/features/srp/data/models/create_srp_request.dart`             | Data         | Create request payload     |
| `lib/features/srp/data/repositories/srp_repository.dart`           | Data         | Server + cache data access |
| `lib/features/srp/data/providers/srp_providers.dart`               | Data         | Riverpod providers         |
| `lib/features/srp/presentation/screens/srp_encode_screen.dart`     | Presentation | Encode form UI             |
| `lib/features/srp/presentation/screens/srp_management_screen.dart` | Presentation | Admin list view UI         |
| `lib/features/srp/presentation/providers/srp_form_provider.dart`   | Presentation | Form state                 |

---

## 8. Server Response Reference

### Create SRP (`POST /api/srp` → 201)

```json
{
  "data": {
    "id": "clx...",
    "price": "230.00",
    "reference": "https://www.da.gov.ph/srp-memo-2026-001",
    "startDate": "2026-02-14T16:00:00.000Z",
    "endDate": null,
    "isActive": true,
    "createdBy": { "id": "clx...", "name": "Default Admin" },
    "createdAt": "2026-02-15T00:00:00.000Z",
    "updatedAt": "2026-02-15T00:00:00.000Z"
  },
  "errors": []
}
```

### List SRP (`GET /api/srp` → 200)

```json
{
  "data": {
    "items": [
      /* SrpRecord objects */
    ],
    "pagination": { "page": 1, "limit": 20, "total": 5, "totalPages": 1 }
  },
  "errors": []
}
```

### Active SRP (`GET /api/srp/active` → 200)

```json
{
  "data": {
    /* single SrpRecord object */
  },
  "errors": []
}
```

### No Active SRP (`GET /api/srp/active` → 404)

```json
{
  "data": null,
  "errors": [{ "message": "No active SRP record found" }]
}
```

---

## 9. Status

**Data Layer:**

- [x] SrpRecordModel (freezed)
- [x] SrpCreatedByModel (freezed)
- [x] SrpListResponseModel + PaginationModel (freezed)
- [x] CreateSrpRequest (freezed)
- [x] SrpRepository (server + cache + offline queue)
- [x] SRP Riverpod providers
- [x] Drift ↔ Model mapping utilities

**Presentation Layer:**

- [ ] SrpEncodeScreen UI (pending design)
- [ ] SrpManagementScreen UI (pending design)
- [ ] Form validation
- [ ] Offline indicators
