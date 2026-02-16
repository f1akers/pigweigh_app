# Feature: Price History (Flutter — User)

> **Purpose**: Displays the historical timeline of SRP records to all users, with real-time push notifications when a new price is published.

---

## 1. Overview

Price History is a **user-facing, public feature** — no authentication required. It shows a chronological list of past and current SRP records so pig farmers and traders can track price trends. The feature also integrates with Socket.IO to show a real-time toast notification when the DA publishes a new SRP.

### Why It Exists

- Farmers need to compare current prices against historical trends to make selling decisions.
- Real-time notifications ensure traders are immediately aware of new DA price publications.
- Offline access to cached price history enables use in low-connectivity rural areas.

---

## 2. Dependencies

| Depends On                                                                       | Why                                |
| -------------------------------------------------------------------------------- | ---------------------------------- |
| [SRP_MANAGEMENT](SRP_MANAGEMENT.md)                                              | SRP data models, repository, cache |
| [OFFLINE_SYNC](OFFLINE_SYNC.md)                                                  | Drift cache for offline access     |
| `SocketService`                                                                  | Listen for `srp:new` events        |
| `Drift` (AppDatabase)                                                            | Read cached SRP records            |
| Server: [PRICE_HISTORY](../../../pigweigh-server/docs/features/PRICE_HISTORY.md) | Paginated SRP list endpoint        |
| Server: [REALTIME_SRP](../../../pigweigh-server/docs/features/REALTIME_SRP.md)   | `srp:new` WebSocket event          |

---

## 3. Data Layer

### 3.1 Data Models

Reuses models from [SRP_MANAGEMENT](SRP_MANAGEMENT.md):

- `SrpRecordModel`
- `SrpListResponseModel`
- `PaginationModel`

No additional models are needed for this feature.

### 3.2 API Endpoints Used

| Method | Path              | Auth   | Description                                  |
| ------ | ----------------- | ------ | -------------------------------------------- |
| `GET`  | `/api/srp`        | Public | Paginated list of SRP records (newest first) |
| `GET`  | `/api/srp/active` | Public | Currently active SRP record                  |

### 3.3 Real-Time Integration

```dart
// lib/features/srp/data/providers/srp_realtime_provider.dart

/// Listens to Socket.IO `srp:new` events and updates the SRP cache + providers.
@Riverpod(keepAlive: true)
class SrpRealtimeListener extends _$SrpRealtimeListener {
  @override
  void build() {
    final socket = ref.watch(socketServiceProvider);

    socket.on('srp:new', (data) {
      final newSrp = SrpRecordModel.fromJson(data as Map<String, dynamic>);

      // 1. Upsert into Drift cache
      final db = ref.read(appDatabaseProvider);
      db.into(db.srpRecords).insertOnConflictUpdate(toCompanion(newSrp));

      // 2. Invalidate active SRP provider (triggers UI refresh)
      ref.invalidate(activeSrpProvider);

      // 3. Emit a notification event for the UI toast
      ref.read(srpNotificationProvider.notifier).notify(newSrp);
    });

    ref.onDispose(() {
      socket.off('srp:new');
    });
  }
}
```

### 3.4 Notification Provider (for toast)

```dart
// lib/features/srp/data/providers/srp_notification_provider.dart

/// Holds the latest SRP notification for the UI to show a toast.
/// Resets to null after being consumed.
@riverpod
class SrpNotification extends _$SrpNotification {
  @override
  SrpRecordModel? build() => null;

  void notify(SrpRecordModel srp) {
    state = srp;
  }

  void dismiss() {
    state = null;
  }
}
```

### 3.5 Price History Provider

```dart
// lib/features/srp/data/providers/price_history_provider.dart

@riverpod
class PriceHistory extends _$PriceHistory {
  @override
  Future<List<SrpRecordModel>> build() async {
    final repo = ref.watch(srpRepositoryProvider);

    // Fetch from server (caches in Drift), fallback to cache
    final result = await repo.getSrpList(page: 1, limit: 50);
    return result.when(
      success: (data) => data.items,
      failure: (_) => repo.getCachedSrpRecords(),  // Offline fallback
    );
  }

  Future<void> refresh() async { /* re-fetch from server */ }
  Future<void> loadMore() async { /* append next page */ }
}
```

### 3.6 Socket.IO Reconnection Strategy

When Socket.IO reconnects after a disconnection:

1. The `socket_io_client` package handles automatic reconnection.
2. On reconnect, the app should fetch `GET /api/srp/active` to catch any missed `srp:new` events.
3. Compare the fetched active SRP with the cached one — if different, treat it as a new publication and show a toast.

```dart
// Inside SocketService or SrpRealtimeListener:
socket.onReconnect((_) {
  // Trigger a fresh pull of active SRP
  ref.invalidate(activeSrpProvider);
});
```

---

## 4. Presentation Layer

> **Note**: Presentation layer (screens, widgets, design) will be documented and implemented separately when design screenshots are provided.

### 4.1 Screens (Planned)

| Screen               | Route            | Auth   | Description                               |
| -------------------- | ---------------- | ------ | ----------------------------------------- |
| `PriceHistoryScreen` | `/price-history` | Public | Scrollable list of historical SRP records |

### 4.2 Widgets (Planned)

| Widget             | Description                                                        |
| ------------------ | ------------------------------------------------------------------ |
| `SrpHistoryCard`   | Individual SRP record card (price, dates, reference, active badge) |
| `SrpNewPriceToast` | Top-down toast notification for new SRP publications               |
| `SrpActiveBanner`  | Highlighted banner showing the current active SRP price            |

### 4.3 UI Behaviors (Placeholder)

**Price History List:**

- List of SRP records sorted by `startDate` descending (newest first)
- Active record highlighted/badged
- Each card shows: price (₱), start date, end date (or "Active"), reference
- Pull-to-refresh
- Infinite scroll / load more pagination
- Offline indicator with last sync time

**Real-Time Toast:**

- When `srp:new` event arrives, show a top-down toast/banner
- Toast content: "New SRP posted: ₱{price} effective {date}"
- Toast auto-dismisses after ~5 seconds
- Tapping the toast scrolls to the new record or refreshes the list

### 4.4 Navigation / Routing

```dart
// AppRoutes additions:
static const String priceHistory = '/price-history';

// Accessible from:
// - Weight estimation result screen (button: "View Price History")
// - Home screen (if applicable)
// No auth required
```

---

## 5. Offline Behavior

- **Full offline access** — price history is read from the Drift cache.
- Cache is populated on every successful `GET /api/srp` response.
- At least the most recent 50 records are cached (configurable).
- The active SRP is always cached separately for quick access.
- Offline indicator shows "Last updated: {timestamp}" using the Hive `lastSrpSyncAt` value.
- Socket.IO auto-reconnects; on reconnect, a fresh pull catches missed events.

---

## 6. Business Rules

1. **Public access** — no authentication required to view price history.
2. **Newest first** — records always sorted by `startDate` descending.
3. **Toast only for genuinely new records** — compare incoming `srp:new` ID with cached active SRP to avoid duplicate toasts.
4. **Time display** — all server UTC timestamps converted to local time (`Asia/Manila`) for display.
5. **Price display** — always show 2 decimal places with ₱ symbol (e.g., `₱230.00`).
6. **No user writes** — this feature is read-only for users. All mutations go through admin SRP Management.
7. **Cache first** — never show a loading spinner if cached data exists. Show cached data immediately, then refresh in background.

---

## 7. Implementation Files (Planned)

| File                                                              | Layer        | Purpose                           |
| ----------------------------------------------------------------- | ------------ | --------------------------------- |
| `lib/features/srp/data/providers/srp_realtime_provider.dart`      | Data         | Socket.IO listener + cache update |
| `lib/features/srp/data/providers/srp_notification_provider.dart`  | Data         | Toast notification state          |
| `lib/features/srp/data/providers/price_history_provider.dart`     | Data         | Paginated history list            |
| `lib/features/srp/presentation/screens/price_history_screen.dart` | Presentation | History list UI                   |
| `lib/features/srp/presentation/widgets/srp_history_card.dart`     | Presentation | Individual record card            |
| `lib/features/srp/presentation/widgets/srp_new_price_toast.dart`  | Presentation | Top-down toast widget             |
| `lib/features/srp/presentation/widgets/srp_active_banner.dart`    | Presentation | Active SRP highlight              |

---

## 8. Status

**Data Layer:**

- [x] SrpRealtimeListener provider
- [x] SrpNotification provider
- [x] PriceHistory provider (paginated)
- [x] Socket.IO reconnection strategy
- [x] Cache-first read logic

**Presentation Layer:**

- [ ] PriceHistoryScreen UI (pending design)
- [ ] SrpHistoryCard widget (pending design)
- [ ] SrpNewPriceToast widget (pending design)
- [ ] SrpActiveBanner widget (pending design)
- [ ] Offline indicator
