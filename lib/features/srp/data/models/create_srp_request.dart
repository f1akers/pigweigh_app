import 'package:freezed_annotation/freezed_annotation.dart';

part 'create_srp_request.freezed.dart';
part 'create_srp_request.g.dart';

/// Request body for `POST /api/srp`.
///
/// The server expects:
/// ```json
/// {
///   "price": 230.00,
///   "reference": "DA-MO-2026-001",
///   "startDate": "2026-01-15T00:00:00.000Z",
///   "endDate": "2026-02-15T00:00:00.000Z" // optional
/// }
/// ```
@freezed
abstract class CreateSrpRequest with _$CreateSrpRequest {
  const factory CreateSrpRequest({
    required double price,
    required String reference,
    required DateTime startDate,
    DateTime? endDate,
  }) = _CreateSrpRequest;

  factory CreateSrpRequest.fromJson(Map<String, dynamic> json) =>
      _$CreateSrpRequestFromJson(json);
}
