import 'package:freezed_annotation/freezed_annotation.dart';

part 'srp_record_model.freezed.dart';
part 'srp_record_model.g.dart';

/// Prisma sends Decimal fields as strings; this converter handles both
/// `num` and `String` inputs and always serialises back as `double`.
class PriceConverter implements JsonConverter<double, dynamic> {
  const PriceConverter();

  @override
  double fromJson(dynamic json) {
    if (json is num) return json.toDouble();
    if (json is String) return double.parse(json);
    throw FormatException('Cannot parse price: $json');
  }

  @override
  dynamic toJson(double value) => value;
}

/// A single SRP (Suggested Retail Price) record.
///
/// Server response shape:
/// ```json
/// {
///   "id": "clx...",
///   "price": "230",          // Prisma Decimal → string
///   "reference": "DA-MO-...",
///   "startDate": "2026-01-15T00:00:00.000Z",
///   "endDate": null,
///   "isActive": true,
///   "createdBy": { "id": "...", "name": "Admin" },
///   "createdAt": "2026-01-15T12:30:00.000Z"
/// }
/// ```
@freezed
abstract class SrpRecordModel with _$SrpRecordModel {
  const factory SrpRecordModel({
    required String id,
    @PriceConverter() required double price,
    required String reference,
    required DateTime startDate,
    DateTime? endDate,
    required bool isActive,
    SrpCreatedByModel? createdBy,
    required DateTime createdAt,
  }) = _SrpRecordModel;

  factory SrpRecordModel.fromJson(Map<String, dynamic> json) =>
      _$SrpRecordModelFromJson(json);
}

/// The `createdBy` relation embedded in SRP records.
@freezed
abstract class SrpCreatedByModel with _$SrpCreatedByModel {
  const factory SrpCreatedByModel({required String id, required String name}) =
      _SrpCreatedByModel;

  factory SrpCreatedByModel.fromJson(Map<String, dynamic> json) =>
      _$SrpCreatedByModelFromJson(json);
}
