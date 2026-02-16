import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/srp_record_model.dart';

part 'srp_notification_provider.g.dart';

/// Holds the latest SRP notification for the UI toast.
///
/// The presentation layer watches this provider and shows a toast when
/// a new SRP record arrives via Socket.IO. After the toast is shown,
/// call [dismiss] to clear the state.
@riverpod
class SrpNotification extends _$SrpNotification {
  @override
  SrpRecordModel? build() => null;

  /// Set a new SRP notification (triggers toast in the UI).
  void notify(SrpRecordModel srp) {
    state = srp;
  }

  /// Clear the notification after the toast has been consumed.
  void dismiss() {
    state = null;
  }
}
