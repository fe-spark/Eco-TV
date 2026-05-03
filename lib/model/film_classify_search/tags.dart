import 'category.dart';

class Tags {
  final Map<String, List<Category>> values;

  Tags({Map<String, List<Category>>? values}) : values = values ?? {};

  factory Tags.fromJson(Map<String, dynamic> json) {
    final values = <String, List<Category>>{};
    json.forEach((key, value) {
      if (value is List) {
        values[key] = value
            .whereType<Map>()
            .map((item) => Category.fromJson(Map<String, dynamic>.from(item)))
            .toList();
      }
    });
    return Tags(values: values);
  }

  Map<String, dynamic> toJson() => values.map(
        (key, value) => MapEntry(
          key,
          value.map((item) => item.toJson()).toList(),
        ),
      );
}
