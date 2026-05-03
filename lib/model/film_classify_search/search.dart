import 'tags.dart';
import 'titles.dart';

class Search {
  List<String>? sortList;
  Tags? tags;
  Titles? titles;

  Search({this.sortList, this.tags, this.titles});

  factory Search.fromJson(Map<String, dynamic> json) {
    return Search(
      sortList: (json['sortList'] as List<dynamic>?)
          ?.map((item) => item.toString())
          .toList(),
      tags: json['tags'] is Map<String, dynamic>
          ? Tags.fromJson(json['tags'] as Map<String, dynamic>)
          : null,
      titles: json['titles'] is Map<String, dynamic>
          ? Titles.fromJson(json['titles'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'sortList': sortList,
        'tags': tags?.toJson(),
        'titles': titles?.toJson(),
      };
}
