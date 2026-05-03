class Titles {
  final Map<String, String> values;

  Titles({Map<String, String>? values}) : values = values ?? {};

  factory Titles.fromJson(Map<String, dynamic> json) {
    return Titles(
      values: json.map((key, value) => MapEntry(key, value?.toString() ?? '')),
    );
  }

  Map<String, dynamic> toJson() => values;
}
