# PigWeigh App — Agent Context

> **For AI Agents**: This document provides complete architectural context for the PigWeigh Flutter application. Read this first before making changes.

## Quick Reference

| Aspect | Value |
|--------|-------|
| **Framework** | Flutter 3.x with Dart SDK ^3.11.0 |
| **State Management** | Riverpod 3.x (riverpod_annotation + riverpod_generator) |
| **Local Database** | Drift 2.x (SQLite) — offline cache for server data |
| **Key-Value Storage** | Hive 2.x — lightweight settings & auth cache |
| **Secure Storage** | flutter_secure_storage — JWT tokens |
| **HTTP Client** | Dio 5.x |
| **Routing** | go_router 17.x |
| **Models** | freezed + json_serializable |
| **ML Inference** | tflite_flutter 0.12.x — on-device pig weight model |
| **Real-time** | socket_io_client 3.x — live SRP updates |
| **Camera** | camera 0.11.x — image capture for weight estimation |
| **Backend** | Express.js + Prisma (pigweigh-server) — JWT auth, REST + Socket.IO |
| **FVM** | Flutter Version Management — always use `fvm flutter` / `fvm dart` |

---

## Essential Commands

### When using FLUTTER / DART commands

```bash
# ALWAYS use the fvm prefix
fvm flutter
fvm dart
```

---

## Architecture Overview

The project follows a **simplified clean architecture** with **Riverpod** as the central state management solution.

```
lib/
├── core/                      # App-wide utilities and configuration
│   ├── constants/             # API endpoints, storage keys, app config
│   │   ├── api_constants.dart
│   │   ├── app_constants.dart
│   │   └── storage_keys.dart
│   ├── utils/                 # Logger, Result type, AppError, ApiResponse
│   │   ├── api_response.dart
│   │   ├── app_error.dart
│   │   ├── logger.dart
│   │   └── result.dart
│   └── theme/                 # AppTheme, colours, text styles
│       └── app_theme.dart
├── models/                    # Shared data models (freezed + json_serializable)
├── providers/                 # App-wide Riverpod providers
│   ├── auth_state_provider.dart
│   └── router_provider.dart
├── repositories/              # Data-access layer (abstracts API + DB)
├── services/
│   ├── api/                   # Dio HTTP client + interceptors
│   │   ├── api_client.dart
│   │   └── interceptors.dart
│   ├── database/              # Drift SQLite setup
│   │   └── app_database.dart
│   ├── ml/                    # TFLite inference service
│   │   └── tflite_service.dart
│   ├── realtime/              # Socket.IO service
│   │   └── socket_service.dart
│   └── storage/               # Secure storage (JWT tokens)
│       └── secure_storage_service.dart
├── features/                  # Feature modules
│   └── [feature]/
│       ├── data/              # Models, datasources, repositories
│       ├── presentation/      # Screens, widgets, feature providers
│       └── services/          # Feature-specific services
├── widgets/                   # Shared/reusable widgets
└── main.dart                  # App entry point with ProviderScope
```

---

## Essential Commands

### Code Generation (REQUIRED after model / provider changes)

```bash
# Generate all code (freezed, json_serializable, riverpod, drift)
fvm dart run build_runner build --delete-conflicting-outputs

# Watch mode (auto-regenerate on save)
fvm dart run build_runner watch --delete-conflicting-outputs
```

### Flutter Commands

```bash
# Get dependencies
fvm flutter pub get

# Run app
fvm flutter run

# Build APK
fvm flutter build apk --release

# Analyse code
fvm flutter analyze
```

### Drift Database Commands

```bash
# After changing tables in app_database.dart:
# 1. Increment schemaVersion
# 2. Add migration logic in MigrationStrategy.onUpgrade
# 3. Run build_runner
fvm dart run build_runner build --delete-conflicting-outputs
```

---

## Key Implementation Patterns

### 1. Creating Riverpod Providers

All providers use `riverpod_annotation` for code generation:

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
part 'my_provider.g.dart';

// Simple provider
@riverpod
String greeting(GreetingRef ref) => 'Hello';

// Provider with keepAlive (singleton services)
@Riverpod(keepAlive: true)
MyService myService(MyServiceRef ref) => MyService();

// Notifier (stateful)
@riverpod
class Counter extends _$Counter {
  @override
  int build() => 0;
  void increment() => state++;
}

// Async notifier
@riverpod
class UserData extends _$UserData {
  @override
  Future<User> build() async {
    return await fetchUser();
  }
}
```

### 2. Creating Models (freezed + json_serializable)

```dart
import 'package:freezed_annotation/freezed_annotation.dart';
part 'srp_record_model.freezed.dart';
part 'srp_record_model.g.dart';

// NOTE: In freezed 3.x, classes MUST be declared as 'abstract'
@freezed
abstract class SrpRecordModel with _$SrpRecordModel {
  const factory SrpRecordModel({
    required String id,
    required double price,
    required String reference,
    required DateTime startDate,
    DateTime? endDate,
    @Default(false) bool isActive,
    required DateTime createdAt,
  }) = _SrpRecordModel;

  factory SrpRecordModel.fromJson(Map<String, dynamic> json) =>
      _$SrpRecordModelFromJson(json);
}
```

### 3. Server Response Format

The server always returns responses in a standard envelope:

```json
// Success
{
  "data": { "id": "abc-123", "price": 230.00 },
  "errors": []
}

// Error
{
  "data": null,
  "errors": [{ "field": "price", "message": "Price must be positive" }]
}
```

**The `ApiClient` automatically handles this format:**
- On success → returns the unwrapped `data` field.
- On error → parses the `errors` array and returns an `AppError`.

### 4. Making API Calls

```dart
// Use ApiClient for ALL HTTP requests
final apiClient = ref.read(apiClientProvider);

final result = await apiClient.get<Map<String, dynamic>>('/srp/active');

result.when(
  success: (data) {
    // `data` is already unwrapped from { data: ... }
    final srp = SrpRecordModel.fromJson(data);
  },
  failure: (error) {
    // error is AppError with .message, .field, .statusCode
    print(error.message);
  },
);
```

### 5. Using the Result Type

```dart
import 'package:pigweigh_app/core/utils/result.dart';

Future<Result<SrpRecordModel, AppError>> getActiveSrp() async {
  final result = await _api.get<Map<String, dynamic>>('/srp/active');
  return result.when(
    success: (data) => Result.success(SrpRecordModel.fromJson(data)),
    failure: (error) => Result.failure(error),
  );
}
```

### 6. Database Operations (Drift)

Tables are defined in `lib/services/database/app_database.dart`. After adding/changing tables, run `build_runner`.

```dart
// Read from local cache
final db = ref.read(appDatabaseProvider);
final records = await db.select(db.srpRecords).get();

// Insert / update
await db.into(db.srpRecords).insertOnConflictUpdate(
  SrpRecordsCompanion.insert(
    id: record.id,
    price: record.price,
    reference: record.reference,
    startDate: record.startDate,
    isActive: Value(record.isActive),
    createdAt: record.createdAt,
  ),
);
```

### 7. Hive (Key-Value Storage)

Hive is initialised in `main.dart` and used for lightweight, non-sensitive data (settings, theme preference, cached flags).

```dart
import 'package:hive_flutter/hive_flutter.dart';

// Open a box
final box = await Hive.openBox('settings');

// Read / write
box.put('darkMode', true);
final isDark = box.get('darkMode', defaultValue: false);
```

> **Sensitive data** (tokens, credentials) must go through `SecureStorageService`, NOT Hive.

### 8. TFLite Inference

```dart
final ml = ref.read(tfliteServiceProvider);
await ml.loadModel(); // call once (e.g., on app start)

// Prepare input/output tensors matching your model
var input = /* preprocessed image data */;
var output = List.filled(1, 0.0).reshape([1, 1]);
ml.runInference(input, output);

final estimatedWeight = output[0][0];
```

### 9. Real-time (Socket.IO)

The `SocketService` connects to the same host as the API and listens for server-pushed events.

```dart
final socket = ref.read(socketServiceProvider);

// Listen for new SRP publications
socket.on('srp:new', (data) {
  final srp = SrpRecordModel.fromJson(data);
  // Update local state / cache
});
```

### 10. Secure Storage (JWT Flow)

```dart
final storage = ref.read(secureStorageServiceProvider);

// After login
await storage.saveTokens(
  accessToken: tokens.access,
  refreshToken: tokens.refresh,
  expiry: tokens.expiresAt,
);

// Check auth
final isLoggedIn = await storage.isAuthenticated();
```

### 11. Navigation (GoRouter)

Routes are defined in `lib/providers/router_provider.dart`.

```dart
// Navigate
context.go(AppRoutes.home);
context.push('/srp/details');

// Adding a new route:
// 1. Add the path constant to AppRoutes
// 2. Add a GoRoute entry in the routes list
// 3. Import the screen widget
```

---

## Logging

**Always** use `AppLogger` from `lib/core/utils/logger.dart` instead of `print()`.

```dart
import 'package:pigweigh_app/core/utils/logger.dart';

AppLogger.debug('Fetching SRP list', tag: 'SRP');
AppLogger.info('Model loaded', tag: 'ML');
AppLogger.warn('Token nearing expiry', tag: 'AUTH');
AppLogger.error('Network request failed', tag: 'API', error: e);
```

---

## Adding a New Feature

1. **Create the feature doc** in `docs/features/<FEATURE>.md` (use the template in `docs/FEATURE_PROMPT.md`).
2. **Create the feature folder** under `lib/features/<feature>/` with `data/`, `presentation/`, and optionally `services/`.
3. **Define models** as `@freezed abstract class` in `data/models/`.
4. **Create repository** in `data/` that uses `ApiClient` + `AppDatabase`.
5. **Create providers** using `@riverpod` annotation in `presentation/providers/`.
6. **Build screens** in `presentation/screens/`.
7. **Register routes** in `lib/providers/router_provider.dart`.
8. **Run code generation**: `fvm dart run build_runner build --delete-conflicting-outputs`.
9. **Update** `docs/FEATURE_INDEX.md` with a link to the new feature doc.

---

## Key Conventions

1. **Use `AppLogger`** — never raw `print()` in production code.
2. **Use `ApiClient`** — every HTTP call flows through the shared Dio client.
3. **Use `Result<S, E>`** — all fallible operations return `Result<T, AppError>`.
4. **Server envelope** — the `{ data, errors }` structure is parsed automatically by `ApiClient`.
5. **freezed 3.x** — model classes must be declared `abstract`.
6. **Riverpod code-gen** — use `@riverpod` / `@Riverpod(keepAlive: true)` annotations; never hand-write providers.
7. **Drift for offline cache** — server data that needs to survive restarts lives in SQLite via Drift.
8. **Hive for preferences** — lightweight key-value pairs (theme, flags, non-sensitive cache).
9. **Secure storage for secrets** — JWT tokens, credentials → `SecureStorageService`.
10. **File naming** — `snake_case` for all Dart files (e.g., `srp_record_model.dart`).
