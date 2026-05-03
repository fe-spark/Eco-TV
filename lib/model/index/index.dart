import 'package:collection/collection.dart';
import 'package:json_annotation/json_annotation.dart';

import 'data.dart';

part 'index.g.dart';

@JsonSerializable()
class Recommend {
  final Data? data;
  final int? code;

  const Recommend({this.data, this.code});

  @override
  String toString() => 'Recommend(data: $data, code: $code)';

  factory Recommend.fromJson(Map<String, dynamic> json) {
    return _$RecommendFromJson(json);
  }

  Map<String, dynamic> toJson() => _$RecommendToJson(this);

  Recommend copyWith({
    Data? data,
    int? code,
  }) {
    return Recommend(
      data: data ?? this.data,
      code: code ?? this.code,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    if (other is! Recommend) return false;
    final mapEquals = const DeepCollectionEquality().equals;
    return mapEquals(other.toJson(), toJson());
  }

  @override
  int get hashCode => data.hashCode ^ code.hashCode;
}
