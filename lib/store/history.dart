import 'package:flutter/foundation.dart';
// import '/model/date/date.dart';
import '/plugins.dart';

class HistoryStore with ChangeNotifier, DiagnosticableTreeMixin {
  final preferenceKey = 'historyStore';
  final legacyEpisodeProgressKey = 'historyEpisodeProgress';

  List get data {
    return PreferenceUtil.getMap<List>(preferenceKey) ?? [];
  }

  int getEpisodeStartAt({
    required Object? id,
    required Object? originId,
    required int teleplayIndex,
  }) {
    final fallback = data.firstWhereOrNull(
      (item) =>
          item['id'] == id &&
          item['originId'] == originId &&
          item['teleplayIndex'] == teleplayIndex,
    );
    if (fallback is Map) {
      final startAt = fallback['startAt'];
      if (startAt is num) {
        return max(0, startAt.toInt());
      }
    }
    return 0;
  }

  void clearStore() async {
    await Future.wait([
      PreferenceUtil.remove(preferenceKey),
      PreferenceUtil.remove(legacyEpisodeProgressKey),
    ]);
    notifyListeners();
  }

  void addHistory(Map<String, dynamic> history) async {
    var newList = [history];

    for (var item in data) {
      if (item['id'] != history['id']) {
        newList.add(item);
      }
    }

    await Future.wait([
      PreferenceUtil.setMap(preferenceKey, newList),
      PreferenceUtil.remove(legacyEpisodeProgressKey),
    ]);
    notifyListeners();
  }

  Future<void> deleteHistoryForId(int id) async {
    var newList = [];

    for (var item in data) {
      if (item['id'] != id) {
        newList.add(item);
      }
    }

    await Future.wait([
      PreferenceUtil.setMap(preferenceKey, newList),
      PreferenceUtil.remove(legacyEpisodeProgressKey),
    ]);
    notifyListeners();
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(IterableProperty(preferenceKey, data));
  }
}
