import 'package:freezed_annotation/freezed_annotation.dart';

import 'srp_record_model.dart';

part 'srp_list_response_model.freezed.dart';
part 'srp_list_response_model.g.dart';

/// Paginated SRP list response (unwrapped from the `{ data }` envelope).
///
/// Server shape:
/// ```json
/// {
///   "items": [ { SrpRecord }, ... ],
///   "pagination": { "page": 1, "limit": 20, "total": 42, "totalPages": 3 }
/// }
/// ```
@freezed
abstract class SrpListResponseModel with _$SrpListResponseModel {
  const factory SrpListResponseModel({
    required List<SrpRecordModel> items,
    required PaginationModel pagination,
  }) = _SrpListResponseModel;

  factory SrpListResponseModel.fromJson(Map<String, dynamic> json) =>
      _$SrpListResponseModelFromJson(json);
}

/// Pagination metadata returned alongside list responses.
@freezed
abstract class PaginationModel with _$PaginationModel {
  const factory PaginationModel({
    required int page,
    required int limit,
    required int total,
    required int totalPages,
  }) = _PaginationModel;

  factory PaginationModel.fromJson(Map<String, dynamic> json) =>
      _$PaginationModelFromJson(json);
}
