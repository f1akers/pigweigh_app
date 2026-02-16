import 'package:freezed_annotation/freezed_annotation.dart';

part 'admin_model.freezed.dart';
part 'admin_model.g.dart';

/// Admin profile returned by the server.
///
/// Server response shape:
/// ```json
/// { "id": "clx...", "username": "admin", "name": "Default Admin" }
/// ```
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
