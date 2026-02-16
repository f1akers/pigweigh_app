# Feature: Admin Authentication (Flutter)

> **Purpose**: Allows DA admins to log in to the app, persist their session, and access admin-only screens (SRP encoding, price history management).

---

## 1. Overview

Admin authentication in the Flutter app mirrors the server's auth system. Admins log in with a username and password, receive a JWT, and the token is stored securely. The session persists across app restarts via `flutter_secure_storage` and is also cached in Hive for offline access.

There is **no registration** — admin accounts are seeded on the server side. The app only provides a login flow.

### Why It Exists

- Only authorized DA personnel should access the SRP encoding and management screens.
- The JWT token gates all write operations to the server (`POST /api/srp`).
- Offline session persistence means admins don't need to re-login every time they open the app or lose connectivity.

---

## 2. Dependencies

| Depends On                                                                 | Why                                               |
| -------------------------------------------------------------------------- | ------------------------------------------------- |
| `SecureStorageService`                                                     | Store JWT tokens securely                         |
| `ApiClient`                                                                | Make login API call                               |
| `Hive`                                                                     | Cache admin profile for offline display           |
| [OFFLINE_SYNC](OFFLINE_SYNC.md)                                            | Sync queue for operations performed while offline |
| Server: [ADMIN_AUTH](../../../pigweigh-server/docs/features/ADMIN_AUTH.md) | Backend login endpoint                            |

---

## 3. Data Layer

### 3.1 Data Models

```dart
// lib/features/auth/data/models/admin_model.dart

@freezed
abstract class AdminModel with _$AdminModel {
  const factory AdminModel({
    required String id,
    required String username,
    required String name,
  }) = _AdminModel;

  factory AdminModel.fromJson(Map<String, dynamic> json) =>
      _$AdminModelFromJson(json);
}

// lib/features/auth/data/models/login_response_model.dart

@freezed
abstract class LoginResponseModel with _$LoginResponseModel {
  const factory LoginResponseModel({
    required String token,
    required AdminModel admin,
  }) = _LoginResponseModel;

  factory LoginResponseModel.fromJson(Map<String, dynamic> json) =>
      _$LoginResponseModelFromJson(json);
}
```

### 3.2 API Endpoints Used

| Method | Path              | Auth   | Description                                               |
| ------ | ----------------- | ------ | --------------------------------------------------------- |
| `POST` | `/api/auth/login` | Public | Send `{ username, password }`, receive `{ token, admin }` |
| `GET`  | `/api/auth/me`    | Bearer | Verify token, get admin profile                           |

### 3.3 Auth Repository

```dart
// lib/features/auth/data/repositories/auth_repository.dart

class AuthRepository {
  AuthRepository({
    required ApiClient apiClient,
    required SecureStorageService secureStorage,
    required Box adminCacheBox,  // Hive box for offline admin profile
  });

  /// Authenticate with the server.
  /// On success: stores JWT in secure storage, caches admin profile in Hive.
  /// Returns: Result<AdminModel, AppError>
  Future<Result<AdminModel, AppError>> login({
    required String username,
    required String password,
  });

  /// Check if a valid session exists (token present + not expired).
  Future<bool> isAuthenticated();

  /// Get the cached admin profile from Hive (works offline).
  AdminModel? getCachedAdmin();

  /// Verify the current token with the server (GET /auth/me).
  /// Falls back to cached admin if offline.
  Future<Result<AdminModel, AppError>> verifySession();

  /// Clear all auth data (tokens + cached profile).
  Future<void> logout();
}
```

### 3.4 Hive Cache Strategy

Admin profile data is cached in a dedicated Hive box so the app can display the admin's name and maintain session awareness even when offline.

```dart
// Hive box: 'admin_cache'
// Keys:
//   'admin_profile' → JSON-encoded AdminModel
//   'is_logged_in'  → bool flag

// On successful login:
//   1. Save JWT to flutter_secure_storage (already handled)
//   2. Save admin profile JSON to Hive admin_cache box
//   3. Set is_logged_in = true

// On logout:
//   1. Clear JWT from secure storage
//   2. Clear admin_cache box
```

### 3.5 Providers

| Provider                 | Type                      | Purpose                                             |
| ------------------------ | ------------------------- | --------------------------------------------------- |
| `authRepositoryProvider` | Provider (keepAlive)      | Singleton `AuthRepository` instance                 |
| `authStateProvider`      | AsyncNotifier (keepAlive) | App-wide auth state (already exists, to be updated) |

#### Auth State Provider Updates

The existing `AuthStateNotifier` will be enhanced to:

```dart
// lib/providers/auth_state_provider.dart (updated)

@Riverpod(keepAlive: true)
class AuthStateNotifier extends _$AuthStateNotifier {
  // State shape (already exists):
  // AuthState { status, userId, email, isLoading, errorMessage }
  //
  // Updates needed:
  // - Add: String? username, String? name  (admin fields)
  // - login() method → calls authRepository.login()
  // - logout() method → calls authRepository.logout()
  // - _checkAuthStatus() → try verifySession(), fallback to cached admin
  //
  // Offline behavior:
  //   If token exists in secure storage but network is down,
  //   load cached admin from Hive and set status = authenticated.
  //   The token will be validated with the server on next connectivity.
}
```

---

## 4. Presentation Layer

> **Note**: Presentation layer (screens, widgets, design) will be documented and implemented separately when design screenshots are provided.

### 4.1 Screens (Planned)

| Screen        | Route    | Description                            |
| ------------- | -------- | -------------------------------------- |
| `LoginScreen` | `/login` | Username + password form, login button |

### 4.2 Navigation / Routing

```dart
// AppRoutes additions:
static const String login = '/login';

// Redirect logic (already scaffolded in router_provider.dart):
// - Unauthenticated users trying to access admin routes → redirect to /login
// - Authenticated admins on /login → redirect to admin home
// - Regular user routes (weight estimation) → NO auth required
```

### 4.3 UI Behaviors (Placeholder)

- Login form with username and password fields
- Loading indicator during login API call
- Error display (server error messages mapped from `{ errors }` envelope)
- Auto-redirect to admin dashboard on success
- "Offline mode" indicator when cached session is used

---

## 5. Business Rules

1. **No registration** — login only. Admins are seeded on the server.
2. **JWT stored in `flutter_secure_storage`** — never in Hive or SharedPreferences.
3. **Admin profile cached in Hive** — for offline display (name, username). Non-sensitive data only.
4. **Token expiry check on app start** — if expired, attempt refresh. If refresh fails, set unauthenticated.
5. **Offline login** — if the token is present and not expired, allow access to admin features using the cached profile. Token validation happens on next connectivity.
6. **Logout clears everything** — secure storage tokens + Hive admin cache.
7. **Generic error on login failure** — the server returns `"Invalid username or password"` for both wrong username and wrong password. Display this as-is.
8. **Admin routes are guarded** — GoRouter redirect checks auth state before allowing access to admin-only routes (`/admin/*`).

---

## 6. Implementation Files (Planned)

| File                                                                | Layer        | Purpose                             |
| ------------------------------------------------------------------- | ------------ | ----------------------------------- |
| `lib/features/auth/data/models/admin_model.dart`                    | Data         | Admin profile model (freezed)       |
| `lib/features/auth/data/models/login_response_model.dart`           | Data         | Login API response model (freezed)  |
| `lib/features/auth/data/repositories/auth_repository.dart`          | Data         | Auth logic + Hive caching           |
| `lib/features/auth/presentation/screens/login_screen.dart`          | Presentation | Login UI                            |
| `lib/features/auth/presentation/providers/login_form_provider.dart` | Presentation | Form state management               |
| `lib/providers/auth_state_provider.dart`                            | Core         | Update existing auth state provider |
| `lib/providers/router_provider.dart`                                | Core         | Add admin route guards              |
| `lib/core/constants/storage_keys.dart`                              | Core         | Add Hive box/key constants          |

---

## 7. Server Response Reference

### Login Success (`POST /api/auth/login` → 200)

```json
{
  "data": {
    "token": "eyJhbGciOiJIUzI1NiIs...",
    "admin": {
      "id": "clx...",
      "username": "admin",
      "name": "Default Admin"
    }
  },
  "errors": []
}
```

### Login Failure (401)

```json
{
  "data": null,
  "errors": [{ "message": "Invalid username or password" }]
}
```

### Get Profile (`GET /api/auth/me` → 200)

```json
{
  "data": {
    "id": "clx...",
    "username": "admin",
    "name": "Default Admin"
  },
  "errors": []
}
```

---

## 8. Status

**Data Layer:**

- [ ] AdminModel (freezed)
- [ ] LoginResponseModel (freezed)
- [ ] AuthRepository (login, verify, cache, logout)
- [ ] Update AuthStateNotifier
- [ ] Hive admin cache integration
- [ ] Router guard updates

**Presentation Layer:**

- [ ] LoginScreen UI (pending design)
- [ ] Login form provider
- [ ] Error display
- [ ] Offline indicator
