import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../core/utils/logger.dart';

part 'socket_service.g.dart';

/// Manages the Socket.IO connection to the PigWeigh server.
///
/// Listens for real-time events (e.g., `srp:new`) and exposes them
/// via callbacks or Riverpod providers.
class SocketService {
  SocketService() {
    _connect();
  }

  late final io.Socket _socket;

  io.Socket get socket => _socket;

  void _connect() {
    final url = dotenv.env['SOCKET_URL'] ?? 'http://localhost:3000';

    _socket = io.io(
      url,
      io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .disableAutoConnect()
          .build(),
    );

    _socket.onConnect((_) {
      AppLogger.info('Socket connected', tag: 'SOCKET');
    });

    _socket.onDisconnect((_) {
      AppLogger.warn('Socket disconnected', tag: 'SOCKET');
    });

    _socket.onError((err) {
      AppLogger.error('Socket error', tag: 'SOCKET', error: err);
    });

    _socket.connect();
  }

  /// Register a listener for a named event.
  void on(String event, Function(dynamic) callback) {
    _socket.on(event, callback);
  }

  /// Remove listener(s) for a named event.
  void off(String event) {
    _socket.off(event);
  }

  void dispose() {
    _socket.dispose();
  }
}

/// Singleton provider for [SocketService].
@Riverpod(keepAlive: true)
SocketService socketService(Ref ref) {
  final service = SocketService();
  ref.onDispose(() => service.dispose());
  return service;
}
