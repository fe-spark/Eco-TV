import 'package:flutter/foundation.dart';

class PlayVideoIdsStore with ChangeNotifier {
  int _originIndex = 0;
  int? _teleplayIndex = 0;
  int? _startAt = 0;

  int get originIndex => _originIndex;

  int? get teleplayIndex => _teleplayIndex;

  int? get startAt => _startAt;

  void setVideoInfo(int? num,
      {required int? teleplayIndex, required int? startAt}) {
    final nextOriginIndex = num ?? 0;
    final nextTeleplayIndex = teleplayIndex;
    final nextStartAt = startAt ?? 0;

    if (_originIndex == nextOriginIndex &&
        _teleplayIndex == nextTeleplayIndex &&
        _startAt == nextStartAt) {
      return;
    }

    _originIndex = nextOriginIndex;
    _teleplayIndex = nextTeleplayIndex;
    _startAt = nextStartAt;

    notifyListeners();
  }
}
