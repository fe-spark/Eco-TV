import 'package:flutter/foundation.dart';
// import '/model/date/date.dart';
import '/plugins.dart';

class HistoryStore with ChangeNotifier, DiagnosticableTreeMixin {
  final preferenceKey = 'historyStore';
  final legacyEpisodeProgressKey = 'historyEpisodeProgress';

  List get data {
    final historyList = PreferenceUtil.getMap<List>(preferenceKey) ?? [];
    return historyList
        .map((item) => item is Map ? _normalizeHistoryItem(item) : item)
        .toList();
  }

  Map<String, dynamic> _normalizeHistoryItem(Map item) {
    final normalized = Map<String, dynamic>.from(item);
    final startAt = normalized['startAt'];
    if (startAt is num) {
      normalized['startAt'] = max(0, startAt.toInt());
    }

    final teleplayIndex = normalized['teleplayIndex'];
    if (teleplayIndex is num) {
      normalized['teleplayIndex'] = max(0, teleplayIndex.toInt());
    }

    return normalized;
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
    final normalizedHistory = _normalizeHistoryItem(history);
    var newList = [normalizedHistory];

    for (var item in data) {
      if (item['id'] != normalizedHistory['id']) {
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
