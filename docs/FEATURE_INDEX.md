# PigWeigh App — Feature Index

> **Purpose**: Central navigation hub for all Flutter app features and documentation.

---

## Overview

**PigWeigh App** is a Flutter mobile application that estimates pig weight using an on-device TFLite model and displays live market prices (SRP) from the Philippine Department of Agriculture. It syncs with the PigWeigh Server backend for authentication, SRP data, and real-time price updates via Socket.IO.

### Technology Stack

| Technology                 | Version | Purpose                                   |
| -------------------------- | ------- | ----------------------------------------- |
| **Flutter**                | 3.x     | UI framework                              |
| **Dart SDK**               | ^3.11.0 | Programming language                      |
| **Riverpod**               | ^3.0.3  | State management (code-gen)               |
| **Drift**                  | ^2.29.0 | Local SQLite database (offline cache)     |
| **Hive**                   | ^2.2.3  | Key-value storage (settings, preferences) |
| **Dio**                    | ^5.9.0  | HTTP client                               |
| **go_router**              | ^17.0.1 | Navigation                                |
| **flutter_secure_storage** | ^10.0.0 | Secure token storage                      |
| **tflite_flutter**         | ^0.12.1 | On-device ML inference                    |
| **camera**                 | ^0.11.3 | Camera capture for weight estimation      |
| **socket_io_client**       | ^3.1.4  | Real-time SRP updates                     |
| **freezed**                | ^3.2.3  | Immutable data models                     |
| **json_serializable**      | ^6.11.2 | JSON serialisation                        |
| **connectivity_plus**      | ^7.0.0  | Network status monitoring                 |

### Architecture Approach

- **Simplified Clean Architecture** with feature-based organisation
- **Riverpod** for dependency injection and state management
- **Offline-first** — local Drift (SQLite) cache with server sync
- **Repository pattern** for data access abstraction
- **Standard `{ data, errors }` API envelope** (matches pigweigh-server)

---

## Documentation Structure

| Document                               | Purpose                                       |
| -------------------------------------- | --------------------------------------------- |
| [CONTEXT.md](CONTEXT.md)               | Core infrastructure, patterns, conventions    |
| [FEATURE_INDEX.md](FEATURE_INDEX.md)   | This file — navigation hub                    |
| [FEATURE_PROMPT.md](FEATURE_PROMPT.md) | Reusable template for generating feature docs |

---

## Feature Categories

### Core Infrastructure _(Documented in [CONTEXT.md](CONTEXT.md))_

| Topic              | Description                   | CONTEXT.md Section              |
| ------------------ | ----------------------------- | ------------------------------- |
| Project Structure  | Folder organisation           | Architecture Overview           |
| Riverpod Providers | State management patterns     | Key Implementation Patterns §1  |
| Freezed Models     | Immutable data models         | Key Implementation Patterns §2  |
| API Client (Dio)   | HTTP client + interceptors    | Key Implementation Patterns §4  |
| Result Type        | Error handling                | Key Implementation Patterns §5  |
| Drift Database     | Local SQLite offline cache    | Key Implementation Patterns §6  |
| Hive Storage       | Key-value preferences         | Key Implementation Patterns §7  |
| Secure Storage     | JWT token management          | Key Implementation Patterns §10 |
| TFLite Inference   | On-device ML model            | Key Implementation Patterns §8  |
| Socket.IO          | Real-time SRP updates         | Key Implementation Patterns §9  |
| Navigation         | go_router setup + auth guards | Key Implementation Patterns §11 |

### Features

| #   | Feature                      | Description                                                                   | Status             | Documentation                                                          |
| --- | ---------------------------- | ----------------------------------------------------------------------------- | ------------------ | ---------------------------------------------------------------------- |
| 0   | Offline Sync & Connectivity  | Connectivity monitoring, Drift cache, sync queue for offline admin operations | ⚙️ Data Layer Done | [features/OFFLINE_SYNC.md](features/OFFLINE_SYNC.md)                   |
| 1   | Admin Authentication         | Admin login, JWT storage, Hive session cache, offline session persistence     | ⚙️ Data Layer Done | [features/ADMIN_AUTH.md](features/ADMIN_AUTH.md)                       |
| 2   | SRP Management (Admin)       | Encode new SRP records, admin list view, offline queue                        | ⚙️ Data Layer Done | [features/SRP_MANAGEMENT.md](features/SRP_MANAGEMENT.md)               |
| 3   | Price History (User)         | Public SRP history list, Socket.IO real-time toast notifications              | ⚙️ Data Layer Done | [features/PRICE_HISTORY.md](features/PRICE_HISTORY.md)                 |
| 4   | Pig Weight Estimation (User) | Camera capture (top + side view), TFLite inference, price estimation          | 📝 Documented      | [features/PIG_WEIGHT_ESTIMATION.md](features/PIG_WEIGHT_ESTIMATION.md) |

> **Implementation order**: Follow the `#` column top-to-bottom. Each feature builds on its dependencies.
>
> **Data vs. Presentation**: Each feature doc separates the **data layer** (models, repositories, providers, services) from the **presentation layer** (screens, widgets, design). Data layers should be implemented first; presentation layers will be implemented per-screen when design screenshots are provided.

---

## Server API Endpoints (Reference)

These endpoints are served by [pigweigh-server](../../pigweigh-server/docs/FEATURE_INDEX.md):

| Method | Path              | Auth   | Description                  |
| ------ | ----------------- | ------ | ---------------------------- |
| POST   | `/api/auth/login` | Public | Admin login, returns JWT     |
| GET    | `/api/auth/me`    | Bearer | Get current admin profile    |
| POST   | `/api/srp`        | Bearer | Create a new SRP record      |
| GET    | `/api/srp`        | Public | List SRP records (paginated) |
| GET    | `/api/srp/active` | Public | Get currently active SRP     |
| GET    | `/api/srp/:id`    | Public | Get single SRP record        |

### WebSocket Events (Socket.IO)

| Event     | Direction       | Payload     | Description                                |
| --------- | --------------- | ----------- | ------------------------------------------ |
| `srp:new` | Server → Client | `SrpRecord` | Broadcast when a new SRP record is created |

---

## Getting Started

```bash
# 1. Install dependencies
fvm flutter pub get

# 2. Copy environment file
cp .env.example .env
# Edit .env with your API_BASE_URL and SOCKET_URL

# 3. Generate code (freezed, riverpod, drift, json_serializable)
fvm dart run build_runner build --delete-conflicting-outputs

# 4. Run the app
fvm flutter run
```

See [CONTEXT.md](CONTEXT.md) for full development conventions and patterns.
