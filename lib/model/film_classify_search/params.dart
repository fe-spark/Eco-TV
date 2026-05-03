class Params {
  final Map<String, dynamic> values;

  Params({Map<String, dynamic>? values}) : values = values ?? {};

  factory Params.fromJson(Map<String, dynamic> json) {
    return Params(values: Map<String, dynamic>.from(json));
  }

  Map<String, dynamic> toJson() => values;
}
