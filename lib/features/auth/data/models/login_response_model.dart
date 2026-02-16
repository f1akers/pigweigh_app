import 'package:freezed_annotation/freezed_annotation.dart';

import 'admin_model.dart';

part 'login_response_model.freezed.dart';
part 'login_response_model.g.dart';

/// Login API response (unwrapped from the `{ data }` envelope).
///
/// Server shape:
/// ```json
/// { "token": "eyJ...", "admin": { "id": "...", "username": "...", "name": "..." } }
/// ```
@freezed
abstract class LoginResponseModel with _$LoginResponseModel {
  const factory LoginResponseModel({
    required String token,
    required AdminModel admin,
  }) = _LoginResponseModel;

  factory LoginResponseModel.fromJson(Map<String, dynamic> json) =>
      _$LoginResponseModelFromJson(json);
}
