import '/model/film_classify_search/search.dart';
import '/model/film_classify_search/category.dart';
import '/plugins.dart';

class FilterBar extends StatelessWidget {
  final Map<String, Category>? activeMap;
  final Search? search;
  final Function onSearch;
  final bool loading;

  const FilterBar({
    super.key,
    required this.search,
    required this.onSearch,
    required this.activeMap,
    required this.loading,
  });

  List<String>? get _sortList {
    return search?.sortList;
  }

  Map<String, String> get _titles {
    final map = <String, String>{};
    final titles = search?.titles?.values ?? {};
    _sortList?.forEach(
      (e) {
        map[e] = titles[e] ?? e;
      },
    );
    return map;
  }

  Map<String, List<Category>> get _tags {
    final map = <String, List<Category>>{};
    final tags = search?.tags?.values ?? {};
    _sortList?.forEach((e) {
      final options = tags[e] ?? [];
      if (options.isNotEmpty) {
        map[e] = options;
      }
    });
    return map;
  }

  @override
  Widget build(BuildContext context) {
    // var theme = context.watch<ThemeStore>();

    if (_tags.keys.isEmpty) {
      return Container();
    }
    return Container(
      color: Theme.of(context).cardColor,
      padding: const EdgeInsets.only(
        top: 8,
        bottom: 8,
      ),
      child: Column(
        children: [
          ...(_tags.keys.map(
            (key) {
              return Row(
                children: [
                  Expanded(
                    flex: 0,
                    child: Padding(
                      padding: const EdgeInsets.only(
                        left: 12,
                      ),
                      child: Text(_titles[key] ?? key),
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      scrollDirection: Axis.horizontal,
                      child: Wrap(
                        spacing: 8,
                        children: (_tags[key] ?? []).map<ChoiceChip>((e) {
                          return ChoiceChip(
                            label: Text(
                              (e.name ?? ''),
                            ),
                            selected: activeMap?[key]?.value == e.value,
                            onSelected: !loading
                                ? (newValue) {
                                    Map params = {};
                                    activeMap?.forEach((k, v) {
                                      params[k] = k == key ? e.value : v.value;
                                    });
                                    if (activeMap?[key] == null) {
                                      params[key] = e.value;
                                    }
                                    onSearch(params);
                                  }
                                : null,
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              );
            },
          ).toList()),
        ],
      ),
    );
  }
}
