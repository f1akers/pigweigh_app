import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/utils/logger.dart';

part 'connectivity_provider.g.dart';

/// Emits `true` when the device has network connectivity, `false` otherwise.
@riverpod
Stream<bool> connectivityStatus(Ref ref) {
  final connectivity = Connectivity();

  return connectivity.onConnectivityChanged.map((results) {
    final isOnline = results.any((r) => r != ConnectivityResult.none);
    AppLogger.debug(
      'Connectivity changed: ${isOnline ? "online" : "offline"}',
      tag: 'CONNECTIVITY',
    );
    return isOnline;
  });
}

/// Exposes the current connectivity state and allows imperative checks.
@Riverpod(keepAlive: true)
class ConnectivityNotifier extends _$ConnectivityNotifier {
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  @override
  bool build() {
    _subscription = Connectivity().onConnectivityChanged.listen((results) {
      final isOnline = results.any((r) => r != ConnectivityResult.none);
      if (state != isOnline) {
        AppLogger.info(
          'Connectivity: ${isOnline ? "ONLINE" : "OFFLINE"}',
          tag: 'CONNECTIVITY',
        );
        state = isOnline;
      }
    });

    ref.onDispose(() => _subscription?.cancel());

    // Assume online initially; the stream will correct if offline.
    return true;
  }

  /// Perform an imperative connectivity check.
  Future<bool> checkNow() async {
    final results = await Connectivity().checkConnectivity();
    final isOnline = results.any((r) => r != ConnectivityResult.none);
    state = isOnline;
    return isOnline;
  }
}
