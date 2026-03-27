import '/plugins.dart';

class PercentageOverlayData {
  final String message;
  final bool hidden;
  final IconData? icon;

  const PercentageOverlayData({
    this.message = '',
    this.hidden = true,
    this.icon,
  });
}

class PercentageController extends ChangeNotifier {
  PercentageOverlayData _data = const PercentageOverlayData();

  PercentageOverlayData get data => _data;

  void show(
    String message, {
    IconData? icon,
  }) {
    _data = PercentageOverlayData(
      message: message,
      hidden: false,
      icon: icon,
    );
    notifyListeners();
  }

  void hide() {
    if (_data.hidden) return;
    _data = const PercentageOverlayData();
    notifyListeners();
  }
}
