import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../services/realtime/socket_service.dart';
import '../models/srp_record_model.dart';
import '../repositories/srp_repository.dart';
import 'srp_notification_provider.dart';
import 'srp_providers.dart';

part 'srp_realtime_provider.g.dart';

/// Listens to Socket.IO `srp:new` events and keeps the local cache in sync.
///
/// On receiving a new SRP record:
/// 1. Upserts it into the Drift cache via [SrpRepository].
/// 2. Invalidates [activeSrpProvider] to trigger UI refresh.
/// 3. Emits a notification via [SrpNotification] for the toast UI.
///
/// Also handles Socket.IO reconnection by re-fetching the active SRP.
@Riverpod(keepAlive: true)
class SrpRealtimeListener extends _$SrpRealtimeListener {
  @override
  void build() {
    final socketService = ref.watch(socketServiceProvider);

    // Listen for new SRP publications.
    socketService.on('srp:new', _onSrpNew);

    // On reconnect, fetch the latest active SRP to catch missed events.
    socketService.on('reconnect', (_) {
      ref.invalidate(activeSrpProvider);
    });

    ref.onDispose(() {
      socketService.off('srp:new');
      socketService.off('reconnect');
    });
  }

  void _onSrpNew(dynamic data) {
    if (data is! Map<String, dynamic>) return;

    try {
      final newSrp = SrpRecordModel.fromJson(data);

      // 1. Upsert into Drift cache.
      final repo = ref.read(srpRepositoryProvider);
      repo.upsertSrpRecord(newSrp);

      // 2. Invalidate active SRP provider → UI refresh.
      ref.invalidate(activeSrpProvider);

      // 3. Push notification for the toast.
      ref.read(srpNotificationProvider.notifier).notify(newSrp);
    } catch (e) {
      // Malformed payload — ignore silently.
    }
  }
}
