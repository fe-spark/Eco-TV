import 'package:flutter/scheduler.dart';
import 'package:video_player/video_player.dart';

import '/plugins.dart';
import '/utils/bv_utils.dart';

import 'percentage.dart';

const double _maxAndroidPlaybackRate = 3.0;
const double _maxIosPlaybackRate = 2.0;
const double _topBarHeight = 56.0;
const double _bottomBarHeight = 52.0;
const double _fullscreenBottomBarHeight = 76.0;
const double _bottomBarHorizontalPadding = 6.0;
const double _fullscreenBottomBarHorizontalPadding = 16.0;
const double _fullscreenBottomBarVerticalPadding = 4.0;
const double _fullscreenProgressStartCorrection = 5.0;
const double _bottomBarPlayProgressSpacing = 6.0;
const double _bottomBarProgressTimeSpacing = 8.0;
const double _bottomBarTimeActionSpacing = 4.0;
const double _bottomBarTrailingButtonSpacing = 0.0;
const double _bottomBarInlineButtonExtent = 30.0;
const double _fullscreenBottomBarInlineButtonExtent = 34.0;
const double _bottomBarInlineIconSize = 22.0;
const double _fullscreenBottomBarInlineIconSize = 24.0;
const double _bottomBarTrailingButtonWidth = 24.0;
const double _bottomBarTrailingButtonHeight = 30.0;
const double _bottomBarTrailingIconSize = 22.0;
const double _bottomBarTimeWidth = 84.0;
const double _fullscreenBottomBarRowSpacing = 6.0;
const double _fullscreenBottomBarTimeFontSize = 12.0;
const double _fullscreenTopActionHeight = 36.0;
const double _fullscreenTopToolbarSpacing = 10.0;
const double _fullscreenTopChipHorizontalPadding = 14.0;
const double _fullscreenTopChipIconSize = 18.0;
const double _fullscreenTopChipFontSize = 13.0;
const double _fullscreenTransportButtonSize = 52.0;
const double _fullscreenTransportButtonIconSize = 24.0;
const double _fullscreenTransportButtonSpacing = 24.0;
const double _fullscreenSideActionButtonSize = 44.0;
const double _fullscreenSideActionIconSize = 22.0;
const Duration _overlayAnimationDuration = Duration(milliseconds: 180);
const double _loadingOverlayMargin = 12.0;
const double _loadingIndicatorExtent = 120.0;
const double _gestureLockDistance = 10.0;
const double _gestureDirectionBias = 1.08;
const double _verticalGestureLockDistance = 18.0;
const double _verticalGestureSensitivity = 1.75;
const double _longPressGestureTolerance = 18.0;
const Duration _seekCompletionTolerance = Duration(milliseconds: 250);
const double _minHorizontalSeekRangeMs = 3 * 60 * 1000;
const double _maxHorizontalSeekRangeMs = 12 * 60 * 1000;

enum _CenterOverlayMode {
  hidden,
  transport,
  loading,
  error,
}

enum _GestureMode {
  idle,
  pending,
  horizontalSeek,
  verticalVolume,
  verticalBrightness,
  longPressSpeed,
}

@immutable
class VideoPlayerRuntimeState {
  final bool playing;
  final bool completed;
  final bool buffering;
  final bool stalledPlayback;
  final bool hasRecentProgress;
  final Duration position;
  final Duration duration;
  final Duration buffer;
  final double volume;
  final double playbackSpeed;
  final double lastAudibleVolume;

  const VideoPlayerRuntimeState({
    required this.playing,
    required this.completed,
    required this.buffering,
    required this.stalledPlayback,
    required this.hasRecentProgress,
    required this.position,
    required this.duration,
    required this.buffer,
    required this.volume,
    required this.playbackSpeed,
    required this.lastAudibleVolume,
  });

  static const empty = VideoPlayerRuntimeState(
    playing: false,
    completed: false,
    buffering: false,
    stalledPlayback: false,
    hasRecentProgress: false,
    position: Duration.zero,
    duration: Duration.zero,
    buffer: Duration.zero,
    volume: 100.0,
    playbackSpeed: 1.0,
    lastAudibleVolume: 100.0,
  );
}

class VideoPlayerMaterialControls extends StatefulWidget {
  final VideoPlayerController? controller;
  final bool isFullscreen;
  final VoidCallback onToggleFullscreen;
  final bool orientationLocked;
  final VoidCallback? onToggleOrientationLock;
  final ValueChanged<bool> onPlayRequestedChanged;
  final Widget title;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final Future<void> Function() onRetry;
  final bool opening;
  final String? errorMessage;
  final bool playbackReady;
  final bool playRequested;
  final VideoPlayerRuntimeState runtimeState;
  final bool showControlsOnInitialize;

  const VideoPlayerMaterialControls({
    super.key,
    required this.controller,
    required this.isFullscreen,
    required this.onToggleFullscreen,
    this.orientationLocked = false,
    this.onToggleOrientationLock,
    required this.onPlayRequestedChanged,
    required this.title,
    required this.onRetry,
    required this.opening,
    this.errorMessage,
    this.playbackReady = false,
    this.playRequested = false,
    this.runtimeState = VideoPlayerRuntimeState.empty,
    this.onPrev,
    this.onNext,
    this.showControlsOnInitialize = true,
  });

  @override
  State<VideoPlayerMaterialControls> createState() =>
      _VideoPlayerMaterialControlsState();
}

class _VideoPlayerMaterialControlsState
    extends State<VideoPlayerMaterialControls>
    with SingleTickerProviderStateMixin {
  final PercentageController _percentageController = PercentageController();
  GlobalKey _transportOverlayKey = GlobalKey();
  final GlobalKey _fullscreenSideActionKey = GlobalKey();
  Future<void> _seekOperationChain = Future<void>.value();

  VideoPlayerController? _controller;
  int _controllerSessionId = 0;
  Timer? _hideTimer;
  Timer? _initTimer;
  late final AnimationController _longPressSpeedOverlayController;

  bool _controlsVisible = true;
  bool _seeking = false;

  Duration? _seekTarget;
  Duration? _seekCompletionTarget;

  double _tempPlaybackSpeed = 1.0;
  bool _wasPlayingBeforeLongPress = false;
  bool _longPressSpeedRestoreInProgress = false;

  bool _draggingProgress = false;
  double _dragProgressValue = 0.0;

  bool _showLongPressSpeedOverlay = false;
  bool _discreteGestureAllowed = false;
  _GestureMode _gestureMode = _GestureMode.idle;
  int? _gesturePointerId;
  Offset? _gestureOriginLocalPosition;
  Offset? _gestureStartLocalPosition;
  Offset? _gestureLatestLocalPosition;
  bool _gestureStartedOnLeftSide = false;
  double _gestureStartVolume = 0.0;
  double _gestureStartBrightness = 0.5;
  Duration _gestureStartSeekPosition = Duration.zero;
  bool _gestureVolumePrimed = false;
  bool _gestureBrightnessPrimed = false;
  int _gesturePrimeGeneration = 0;
  double? _lastKnownSystemVolume;
  double? _lastKnownSystemBrightness;

  bool get _isFullscreen => widget.isFullscreen;

  double get _maxPlaybackRate =>
      Platform.isIOS ? _maxIosPlaybackRate : _maxAndroidPlaybackRate;

  String? get _error =>
      widget.errorMessage?.isEmpty ?? true ? null : widget.errorMessage;

  bool get _isPlaybackExpectedToContinue =>
      widget.playRequested && !_completed && _error == null;

  bool get _showPauseAction =>
      _isPlaybackExpectedToContinue &&
      !_stalledPlayback &&
      (_playing || _buffering);

  bool get _isRuntimeBlocked => _buffering || _stalledPlayback;

  bool get _showSeekLoading =>
      _seeking && !_draggingProgress && _isPlaybackExpectedToContinue;

  bool get _isLoading =>
      _error == null &&
      (widget.opening ||
          _showSeekLoading ||
          (!_draggingProgress &&
              _isPlaybackExpectedToContinue &&
              _isRuntimeBlocked));

  bool get _canInteractWithPlayback =>
      widget.playbackReady && !widget.opening && _error == null;

  bool get _playerGesturesEnabled => widget.playbackReady && _error == null;

  bool get _hasTrackedPointerGesture =>
      _gesturePointerId != null && _gestureMode != _GestureMode.idle;

  bool get _fullscreenSwipeGesturesEnabled =>
      _isFullscreen && _canInteractWithPlayback;

  bool get _showTransportControls =>
      _controlsVisible && widget.playbackReady && !_isLoading && _error == null;

  bool get _showCenterTransportButton =>
      _showTransportControls && !_isPlaybackExpectedToContinue;

  bool get _showBottomBar =>
      _controlsVisible && widget.playbackReady && _error == null;

  bool get _showBottomScrim =>
      _controlsVisible && widget.playbackReady && _error == null;

  bool get _showPausedBackdrop =>
      _showTransportControls &&
      !_isPlaybackExpectedToContinue &&
      _error == null &&
      !_isLoading;

  EdgeInsets get _fullscreenSafePadding =>
      _isFullscreen ? MediaQuery.paddingOf(context) : EdgeInsets.zero;

  double get _topControlsExtent {
    if (_isFullscreen) {
      if (!_controlsVisible) {
        return 0;
      }
      return _topBarHeight;
    }
    // Embedded player always has the page-level back button in the top-left.
    return _topBarHeight;
  }

  double get _bottomControlsExtent {
    if (!_showBottomBar) {
      return 0;
    }
    return _isFullscreen ? _fullscreenBottomBarHeight : _bottomBarHeight;
  }

  _CenterOverlayMode get _centerOverlayMode {
    if (_error != null) {
      return _CenterOverlayMode.error;
    }
    if (_isLoading) {
      return _CenterOverlayMode.loading;
    }
    if (_showCenterTransportButton) {
      return _CenterOverlayMode.transport;
    }
    return _CenterOverlayMode.hidden;
  }

  VideoPlayerController? get _currentController => widget.controller;
  VideoPlayerRuntimeState get _runtime => widget.runtimeState;
  bool get _playing => _runtime.playing;
  bool get _completed => _runtime.completed;
  bool get _buffering => _runtime.buffering;
  Duration get _position => _runtime.position;
  Duration get _duration => _runtime.duration;
  Duration get _buffer => _runtime.buffer;
  double get _volume => _runtime.volume;
  double get _rate => _runtime.playbackSpeed;
  double get _lastNonZeroVolume => _runtime.lastAudibleVolume;
  bool get _stalledPlayback => _runtime.stalledPlayback;

  @override
  void initState() {
    super.initState();
    _longPressSpeedOverlayController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _attachController();
    if (widget.showControlsOnInitialize) {
      _initTimer = Timer(const Duration(milliseconds: 200), () {
        if (!mounted) return;
        setState(() {
          _controlsVisible = true;
        });
      });
    }
  }

  @override
  void didUpdateWidget(covariant VideoPlayerMaterialControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasPlaybackExpectedToContinue = oldWidget.playRequested &&
        !oldWidget.runtimeState.completed &&
        oldWidget.errorMessage == null;
    if (oldWidget.controller != _currentController) {
      _detachController();
      _attachController();
      _resetTransientPlaybackUiState();
    }
    if (oldWidget.errorMessage != widget.errorMessage && _error != null) {
      _controlsVisible = true;
      _hideTimer?.cancel();
    }
    if (oldWidget.opening != widget.opening) {
      if (widget.opening) {
        _resetTransientPlaybackUiState();
        _hideTimer?.cancel();
      } else {
        _startHideTimer();
      }
    }
    if (wasPlaybackExpectedToContinue != _isPlaybackExpectedToContinue) {
      if (_isPlaybackExpectedToContinue) {
        _startHideTimer();
      } else {
        _hideTimer?.cancel();
        _controlsVisible = true;
      }
    }
    if (_seeking &&
        (oldWidget.runtimeState.position != widget.runtimeState.position ||
            oldWidget.runtimeState.buffering != widget.runtimeState.buffering ||
            oldWidget.runtimeState.completed !=
                widget.runtimeState.completed)) {
      _maybeCompleteSeeking(widget.runtimeState.position);
    }
    if (!_playerGesturesEnabled) {
      _cancelActiveGesture();
    }
  }

  void _attachController() {
    _controllerSessionId += 1;
    _controller = _currentController;
    if (_playing) {
      _startHideTimer();
    }
  }

  void _detachController() {
    _controller = null;
    _hideTimer?.cancel();
    _initTimer?.cancel();
  }

  void _resetTransientPlaybackUiState() {
    _hideTimer?.cancel();
    _percentageController.hide();
    _seekOperationChain = Future<void>.value();
    _longPressSpeedOverlayController
      ..stop()
      ..reset();
    _transportOverlayKey = GlobalKey();

    _controlsVisible = true;
    _seeking = false;
    _seekTarget = null;
    _seekCompletionTarget = null;
    _draggingProgress = false;
    _dragProgressValue = 0.0;
    _showLongPressSpeedOverlay = false;
    _wasPlayingBeforeLongPress = false;
    _longPressSpeedRestoreInProgress = false;
    _clearDiscreteGestureEligibility();
    _resetGestureTracking();
  }

  @override
  void dispose() {
    _percentageController.hide();
    _longPressSpeedOverlayController.dispose();
    _detachController();
    BVUtils.resetCustomBrightness();
    super.dispose();
  }

  void _toggleControls() {
    if (_controlsVisible) {
      if (!_isPlaybackExpectedToContinue) {
        _hideTimer?.cancel();
        return;
      }
      _hideTimer?.cancel();
      setState(() {
        _controlsVisible = false;
      });
    } else {
      _showControls();
    }
  }

  void _showControls() {
    _hideTimer?.cancel();
    setState(() {
      _controlsVisible = true;
    });
    _startHideTimer();
  }

  void _showFeedbackOverlay(
    String message, {
    IconData? icon,
  }) {
    _percentageController.show(
      message,
      icon: icon,
    );
  }

  bool _canHandleBackgroundGestureAt(Offset localPosition) {
    return _playerGesturesEnabled && _shouldHandlePointerGesture(localPosition);
  }

  bool _tracksPointer(int pointer) {
    return _playerGesturesEnabled &&
        _gesturePointerId == pointer &&
        _gestureMode != _GestureMode.idle;
  }

  void _rememberDiscreteGestureEligibility(Offset localPosition) {
    _discreteGestureAllowed = _canHandleBackgroundGestureAt(localPosition);
  }

  void _clearDiscreteGestureEligibility() {
    _discreteGestureAllowed = false;
  }

  void _initializeGestureTracking(
    Offset localPosition, {
    required bool primeSystemValues,
  }) {
    final gesturePrimeGeneration = ++_gesturePrimeGeneration;
    _gestureMode = _GestureMode.pending;
    _gestureOriginLocalPosition = localPosition;
    _gestureStartLocalPosition = localPosition;
    _gestureLatestLocalPosition = localPosition;
    _gestureStartedOnLeftSide =
        localPosition.dx <= (context.size?.width ?? 0) / 2;
    _gestureStartSeekPosition = _displayedPosition;
    _gestureStartVolume =
        (_lastKnownSystemVolume ?? (_volume / 100)).clamp(0.0, 1.0);
    _gestureStartBrightness =
        (_lastKnownSystemBrightness ?? 0.5).clamp(0.0, 1.0);
    _gestureVolumePrimed = _lastKnownSystemVolume != null;
    _gestureBrightnessPrimed = _lastKnownSystemBrightness != null;
    if (!primeSystemValues) {
      return;
    }
    unawaited(_primeGestureBrightness(gesturePrimeGeneration));
    unawaited(_primeGestureVolume(gesturePrimeGeneration));
  }

  Future<void> _primeGestureBrightness(int gesturePrimeGeneration) async {
    final brightness = (await BVUtils.brightness).clamp(0.0, 1.0);
    _lastKnownSystemBrightness = brightness;
    if (gesturePrimeGeneration != _gesturePrimeGeneration ||
        _gestureOriginLocalPosition == null) {
      return;
    }
    final hadPrimedBaseline = _gestureBrightnessPrimed;
    _gestureBrightnessPrimed = true;
    if (_gestureMode != _GestureMode.pending &&
        (_gestureMode != _GestureMode.verticalBrightness ||
            hadPrimedBaseline)) {
      return;
    }
    _gestureStartBrightness = brightness;
    if (_gestureMode == _GestureMode.verticalBrightness) {
      _applyDeferredVerticalGesture(isVolume: false);
    }
  }

  Future<void> _primeGestureVolume(int gesturePrimeGeneration) async {
    final volume = (await BVUtils.volume).clamp(0.0, 1.0);
    _lastKnownSystemVolume = volume;
    if (gesturePrimeGeneration != _gesturePrimeGeneration ||
        _gestureOriginLocalPosition == null) {
      return;
    }
    final hadPrimedBaseline = _gestureVolumePrimed;
    _gestureVolumePrimed = true;
    if (_gestureMode != _GestureMode.pending &&
        (_gestureMode != _GestureMode.verticalVolume || hadPrimedBaseline)) {
      return;
    }
    _gestureStartVolume = volume;
    if (_gestureMode == _GestureMode.verticalVolume) {
      _applyDeferredVerticalGesture(isVolume: true);
    }
  }

  void _applyDeferredVerticalGesture({required bool isVolume}) {
    final currentPosition = _gestureLatestLocalPosition;
    final originPosition = _gestureOriginLocalPosition;
    if (currentPosition == null || originPosition == null) {
      return;
    }
    _gestureStartLocalPosition = originPosition;
    _updateVerticalGesture(currentPosition, isVolume: isVolume);
  }

  void _resetGestureTracking() {
    _gesturePrimeGeneration += 1;
    _gestureMode = _GestureMode.idle;
    _gesturePointerId = null;
    _gestureOriginLocalPosition = null;
    _gestureStartLocalPosition = null;
    _gestureLatestLocalPosition = null;
    _gestureStartedOnLeftSide = false;
    _gestureStartSeekPosition = Duration.zero;
    _gestureVolumePrimed = false;
    _gestureBrightnessPrimed = false;
  }

  void _setLongPressSpeedOverlayVisible(bool visible) {
    if (_showLongPressSpeedOverlay == visible) return;
    if (!mounted) {
      _showLongPressSpeedOverlay = visible;
      return;
    }

    setState(() {
      _showLongPressSpeedOverlay = visible;
    });

    if (visible) {
      _longPressSpeedOverlayController
        ..stop()
        ..repeat();
    } else {
      _longPressSpeedOverlayController
        ..stop()
        ..reset();
    }
  }

  double _gestureTravelDistanceFromOrigin(Offset localPosition) {
    final origin = _gestureOriginLocalPosition ?? _gestureStartLocalPosition;
    if (origin == null) return double.infinity;
    return (localPosition - origin).distance;
  }

  bool _canStartLongPressSpeedGesture(Offset localPosition) {
    if (!_canHandleBackgroundGestureAt(localPosition) ||
        !_hasTrackedPointerGesture) {
      return false;
    }
    if (_gestureTravelDistanceFromOrigin(localPosition) >
        _longPressGestureTolerance) {
      return false;
    }
    return _gestureMode == _GestureMode.pending ||
        _gestureMode == _GestureMode.horizontalSeek;
  }

  void _prepareLongPressSpeedGesture() {
    if (_gestureMode == _GestureMode.horizontalSeek) {
      _clearProgressPreview();
      _percentageController.hide();
    }
  }

  Future<void> _restorePlaybackStateAfterLongPress({
    required VideoPlayerController controller,
    required bool shouldBePlaying,
    required bool awaitOperations,
  }) async {
    if (shouldBePlaying) {
      if (!controller.value.isPlaying) {
        if (awaitOperations) {
          await controller.play();
        } else {
          unawaited(controller.play());
        }
      }
      return;
    }

    if (controller.value.isPlaying) {
      if (awaitOperations) {
        await controller.pause();
      } else {
        unawaited(controller.pause());
      }
    }
  }

  Future<void> _restoreLongPressSpeedGesture({
    required bool awaitOperations,
  }) async {
    if (_gestureMode != _GestureMode.longPressSpeed ||
        _longPressSpeedRestoreInProgress) {
      return;
    }

    _longPressSpeedRestoreInProgress = true;
    final controller = _controller;
    final restoreSpeed = _tempPlaybackSpeed;
    final shouldResumePlayback = _wasPlayingBeforeLongPress;

    _setLongPressSpeedOverlayVisible(false);
    _percentageController.hide();
    _clearDiscreteGestureEligibility();
    _wasPlayingBeforeLongPress = false;
    _resetGestureTracking();

    try {
      if (controller == null) {
        return;
      }
      if (awaitOperations) {
        await controller.setPlaybackSpeed(restoreSpeed);
        await _restorePlaybackStateAfterLongPress(
          controller: controller,
          shouldBePlaying: shouldResumePlayback,
          awaitOperations: true,
        );
      } else {
        unawaited(controller.setPlaybackSpeed(restoreSpeed));
        unawaited(
          _restorePlaybackStateAfterLongPress(
            controller: controller,
            shouldBePlaying: shouldResumePlayback,
            awaitOperations: false,
          ),
        );
      }
    } finally {
      _longPressSpeedRestoreInProgress = false;
    }
  }

  void _cancelLongPressSpeedGesture() {
    if (_gestureMode != _GestureMode.longPressSpeed) {
      if (!_longPressSpeedRestoreInProgress) {
        _setLongPressSpeedOverlayVisible(false);
        _clearDiscreteGestureEligibility();
      }
      return;
    }
    unawaited(_restoreLongPressSpeedGesture(awaitOperations: false));
  }

  Future<void> _finishLongPressSpeedGesture() async {
    await _restoreLongPressSpeedGesture(awaitOperations: true);
  }

  void _cancelActiveGesture() {
    switch (_gestureMode) {
      case _GestureMode.horizontalSeek:
      case _GestureMode.verticalVolume:
      case _GestureMode.verticalBrightness:
      case _GestureMode.pending:
        _cancelPanGesture();
        return;
      case _GestureMode.longPressSpeed:
        _cancelLongPressSpeedGesture();
        return;
      case _GestureMode.idle:
        _setLongPressSpeedOverlayVisible(false);
        _percentageController.hide();
        _clearDiscreteGestureEligibility();
        _resetGestureTracking();
        return;
    }
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    if (!_isPlaybackExpectedToContinue ||
        _isLoading ||
        _error != null ||
        widget.opening) {
      return;
    }
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() {
        _controlsVisible = false;
      });
    });
  }

  Future<void> _onPlayPause() async {
    final controller = _controller;
    if (controller == null || !_canInteractWithPlayback) return;

    if (_completed) {
      widget.onPlayRequestedChanged(true);
      await _performSeek(Duration.zero);
    }

    if (_showPauseAction) {
      widget.onPlayRequestedChanged(false);
      await controller.pause();
      if (!mounted) return;
      _hideTimer?.cancel();
      setState(() {
        _controlsVisible = true;
      });
    } else {
      widget.onPlayRequestedChanged(true);
      await controller.play();
      _showControls();
    }
  }

  Future<void> _seekRelative(int seconds) async {
    final controller = _controller;
    if (controller == null || !_canInteractWithPlayback) return;
    final max = _duration;
    final basePosition = _displayedPosition;
    final next = _clampDuration(
      basePosition + Duration(seconds: seconds),
      Duration.zero,
      max,
    );
    _showControls();
    await _performSeek(next);
    _showControls();
  }

  Future<void> _performSeek(Duration target) async {
    final controller = _controller;
    if (controller == null || !_canInteractWithPlayback) return;

    _beginSeeking(target);
    final controllerSessionId = _controllerSessionId;
    final queuedSeek = _seekOperationChain.then((_) async {
      if (_controllerSessionId != controllerSessionId ||
          _controller != controller ||
          !_canInteractWithPlayback) {
        return;
      }
      final shouldResumePlayback = widget.playRequested;

      await SchedulerBinding.instance.endOfFrame;
      if (_controllerSessionId != controllerSessionId ||
          _controller != controller ||
          !_canInteractWithPlayback) {
        return;
      }
      await controller.seekTo(target);
      if (shouldResumePlayback &&
          _controllerSessionId == controllerSessionId &&
          _controller == controller) {
        await controller.play();
      }
    });
    _seekOperationChain =
        queuedSeek.catchError((Object error, StackTrace stack) {
      debugPrint('Failed to perform seek: $error');
    });
    await queuedSeek;
  }

  Duration get _displayedPosition {
    if (_draggingProgress) {
      return Duration(milliseconds: _dragProgressValue.round());
    }
    if (_seeking) {
      return _seekTarget ?? _position;
    }
    return _position;
  }

  void _beginProgressPreview(double value) {
    final durationMs = _duration.inMilliseconds.toDouble();
    final max = durationMs <= 0 ? 0.0 : durationMs;
    final clampedValue = value.clamp(0.0, max);
    _hideTimer?.cancel();
    if (!mounted) {
      _controlsVisible = true;
      _draggingProgress = true;
      _dragProgressValue = clampedValue;
      return;
    }
    setState(() {
      _controlsVisible = true;
      _draggingProgress = true;
      _dragProgressValue = clampedValue;
    });
  }

  void _updateProgressPreview(double value) {
    final durationMs = _duration.inMilliseconds.toDouble();
    final max = durationMs <= 0 ? 0.0 : durationMs;
    final clampedValue = value.clamp(0.0, max);
    if (!mounted) {
      _draggingProgress = true;
      _dragProgressValue = clampedValue;
      return;
    }
    setState(() {
      _draggingProgress = true;
      _dragProgressValue = clampedValue;
    });
  }

  void _clearProgressPreview() {
    if (!_draggingProgress) return;
    if (!mounted) {
      _draggingProgress = false;
      _dragProgressValue = 0;
      return;
    }
    setState(() {
      _draggingProgress = false;
      _dragProgressValue = 0;
    });
  }

  Future<void> _commitProgressPreview({
    bool clearPreviewBeforeSeek = false,
  }) async {
    if (!_draggingProgress) return;
    final target = Duration(milliseconds: _dragProgressValue.round());
    if (clearPreviewBeforeSeek) {
      _clearProgressPreview();
    }
    await _performSeek(target);
    if (!mounted) return;
    setState(() {
      if (!clearPreviewBeforeSeek) {
        _draggingProgress = false;
        _dragProgressValue = 0;
      }
      _controlsVisible = true;
    });
    _showControls();
  }

  void _beginSeeking(Duration target) {
    final remaining = max(
      0,
      _duration.inMilliseconds - target.inMilliseconds,
    );
    final settleOffset = Duration(
      milliseconds: min(300, remaining),
    );
    final completionTarget = target + settleOffset;

    if (!mounted) {
      _seeking = true;
      _seekTarget = target;
      _seekCompletionTarget = completionTarget;
      return;
    }
    setState(() {
      _seeking = true;
      _seekTarget = target;
      _seekCompletionTarget = completionTarget;
    });
  }

  void _maybeCompleteSeeking(Duration position) {
    if (!_seeking) return;
    final target = _seekTarget;
    if (target == null) {
      if (!mounted) {
        _seeking = false;
        _seekCompletionTarget = null;
      } else {
        setState(() {
          _seeking = false;
          _seekCompletionTarget = null;
        });
      }
      return;
    }

    final delta = (position - target).abs();
    if (delta > const Duration(milliseconds: 800) && position < target) {
      return;
    }

    if (_buffering) {
      return;
    }

    final completionTarget = _seekCompletionTarget ?? target;
    final settledAtTarget =
        delta <= _seekCompletionTolerance || position >= completionTarget;
    if ((_playing || widget.opening) &&
        position < completionTarget &&
        !settledAtTarget) {
      return;
    }

    if (!mounted) {
      _seeking = false;
      _seekTarget = null;
      _seekCompletionTarget = null;
      return;
    }

    setState(() {
      _seeking = false;
      _seekTarget = null;
      _seekCompletionTarget = null;
    });
  }

  Future<void> _toggleFullscreen() async {
    _showControls();
    widget.onToggleFullscreen();
  }

  Future<void> _toggleMute() async {
    final controller = _controller;
    if (controller == null) return;
    if (_volume <= 0) {
      await controller.setVolume(
        (_lastNonZeroVolume <= 0 ? 100.0 : _lastNonZeroVolume) / 100,
      );
    } else {
      await controller.setVolume(0.0);
    }
    _showControls();
  }

  Future<void> _showSpeedSheet() async {
    final controller = _controller;
    if (controller == null || !_canInteractWithPlayback) return;

    final options = Platform.isIOS
        ? const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
        : const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0];
    final rate = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
      builder: (context) {
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
                bottom: Radius.circular(24),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '播放速度',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const Spacer(),
                    Text(
                      '当前 ${_formatPlaybackRate(_rate)}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '点击后立即生效',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.62),
                      ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: options.map((item) {
                    final selected = (_rate - item).abs() < 0.01;
                    final child = Text(
                      _formatPlaybackRate(item),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    );

                    if (selected) {
                      return SizedBox(
                        width: 88,
                        child: FilledButton(
                          onPressed: () => Navigator.of(context).pop(item),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(88, 42),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: child,
                        ),
                      );
                    }

                    return SizedBox(
                      width: 88,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(item),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(88, 42),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          side: BorderSide(
                            color: Theme.of(
                              context,
                            ).colorScheme.outline.withValues(alpha: 0.45),
                          ),
                        ),
                        child: child,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (rate != null) {
      await controller.setPlaybackSpeed(rate);
      _showControls();
    }
  }

  double get _horizontalSeekRangeMs {
    final durationMs = _duration.inMilliseconds.toDouble();
    if (durationMs <= 0) return 0.0;
    final proportionalRange = durationMs * 0.35;
    return min(
      max(proportionalRange, _minHorizontalSeekRangeMs),
      min(durationMs, _maxHorizontalSeekRangeMs),
    );
  }

  bool _lockGestureMode(Offset localPosition) {
    final start = _gestureOriginLocalPosition ?? _gestureStartLocalPosition;
    if (start == null) return false;

    final delta = localPosition - start;
    final dx = delta.dx.abs();
    final dy = delta.dy.abs();
    if (max(dx, dy) < _gestureLockDistance) {
      return false;
    }

    // Keep horizontal seek outside the long-press tolerance window,
    // otherwise a slight drift can flash seek preview before long press wins.
    if (dx > _longPressGestureTolerance &&
        dx > dy * _gestureDirectionBias &&
        _canInteractWithPlayback &&
        _duration > Duration.zero) {
      _gestureMode = _GestureMode.horizontalSeek;
      _gestureStartSeekPosition = _displayedPosition;
      _beginProgressPreview(
          _gestureStartSeekPosition.inMilliseconds.toDouble());
      return true;
    }

    if (dy >= _verticalGestureLockDistance &&
        dy > dx * _gestureDirectionBias &&
        _fullscreenSwipeGesturesEnabled) {
      _gestureMode = _gestureStartedOnLeftSide
          ? _GestureMode.verticalBrightness
          : _GestureMode.verticalVolume;
      return true;
    }

    return false;
  }

  bool _shouldHandlePointerGesture(Offset localPosition) {
    final size = context.size;
    if (size == null) return true;

    final topBlockedExtent = _isFullscreen && _controlsVisible
        ? _topControlsExtent + _fullscreenSafePadding.top
        : 0.0;
    final bottomBlockedExtent = _showBottomBar
        ? _bottomControlsExtent + _fullscreenSafePadding.bottom
        : 0.0;

    if (localPosition.dy <= topBlockedExtent) {
      return false;
    }
    if (localPosition.dy >= size.height - bottomBlockedExtent) {
      return false;
    }
    if (_isPointInsideTransportOverlay(localPosition)) {
      return false;
    }
    if (_isPointInsideKey(_fullscreenSideActionKey, localPosition)) {
      return false;
    }
    return true;
  }

  bool _isPointInsideTransportOverlay(Offset localPosition) {
    if (!_showTransportControls) {
      return false;
    }
    return _isPointInsideKey(_transportOverlayKey, localPosition);
  }

  bool _isPointInsideKey(GlobalKey key, Offset localPosition) {
    final targetContext = key.currentContext;
    final targetObject = targetContext?.findRenderObject();
    final rootObject = context.findRenderObject();
    if (targetObject is! RenderBox || rootObject is! RenderBox) {
      return false;
    }
    if (!targetObject.attached || !rootObject.attached) {
      return false;
    }

    final targetOrigin =
        targetObject.localToGlobal(Offset.zero, ancestor: rootObject);
    final targetBounds = targetOrigin & targetObject.size;
    return targetBounds.contains(localPosition);
  }

  void _beginPointerGesture(PointerDownEvent event) {
    _gesturePointerId = event.pointer;
    _initializeGestureTracking(
      event.localPosition,
      primeSystemValues: true,
    );
  }

  void _updateLockedGesture(Offset localPosition) {
    switch (_gestureMode) {
      case _GestureMode.horizontalSeek:
        _updateHorizontalSeek(localPosition);
        return;
      case _GestureMode.verticalVolume:
        _updateVerticalGesture(localPosition, isVolume: true);
        return;
      case _GestureMode.verticalBrightness:
        _updateVerticalGesture(localPosition, isVolume: false);
        return;
      case _GestureMode.idle:
      case _GestureMode.pending:
      case _GestureMode.longPressSpeed:
        return;
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (!_canHandleBackgroundGestureAt(event.localPosition) ||
        _hasTrackedPointerGesture) {
      return;
    }
    _beginPointerGesture(event);
  }

  void _handleGestureMove(Offset localPosition) {
    if (!_hasTrackedPointerGesture ||
        _gestureMode == _GestureMode.longPressSpeed) {
      return;
    }

    _gestureLatestLocalPosition = localPosition;

    if (_gestureMode == _GestureMode.pending &&
        !_lockGestureMode(localPosition)) {
      return;
    }
    _updateLockedGesture(localPosition);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_tracksPointer(event.pointer)) {
      return;
    }
    _handleGestureMove(event.localPosition);
  }

  void _updateHorizontalSeek(Offset localPosition) {
    final start = _gestureOriginLocalPosition ?? _gestureStartLocalPosition;
    if (start == null) return;

    final width = max(context.size?.width ?? 0, 1.0);
    final targetMs = _gestureStartSeekPosition.inMilliseconds.toDouble() +
        (localPosition.dx - start.dx) / width * _horizontalSeekRangeMs;
    _updateProgressPreview(targetMs);

    final target = _displayedPosition;
    final deltaSeconds = (target - _gestureStartSeekPosition).inSeconds;
    final deltaText = deltaSeconds == 0
        ? '0s'
        : '${deltaSeconds > 0 ? '+' : '-'}${deltaSeconds.abs()}s';
    _showFeedbackOverlay(
      '${_formatDuration(target)} / ${_formatDuration(_duration)}  $deltaText',
      icon: deltaSeconds >= 0
          ? Icons.fast_forward_rounded
          : Icons.fast_rewind_rounded,
    );
  }

  void _updateVerticalGesture(
    Offset localPosition, {
    required bool isVolume,
  }) {
    if (isVolume ? !_gestureVolumePrimed : !_gestureBrightnessPrimed) {
      return;
    }
    final start = _gestureStartLocalPosition;
    if (start == null) return;

    final height = max(context.size?.height ?? 0, 1.0);
    final baseValue = isVolume ? _gestureStartVolume : _gestureStartBrightness;
    final nextValue = (baseValue -
            (localPosition.dy - start.dy) /
                height *
                _verticalGestureSensitivity)
        .clamp(0.0, 1.0);

    if (isVolume) {
      _gestureStartVolume = nextValue;
      _lastKnownSystemVolume = nextValue;
      _gestureStartLocalPosition = localPosition;
      unawaited(BVUtils.setVolume(nextValue));
      _showFeedbackOverlay(
        '${(nextValue * 100).round()}%',
        icon:
            nextValue <= 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
      );
      return;
    }

    _gestureStartBrightness = nextValue;
    _lastKnownSystemBrightness = nextValue;
    _gestureStartLocalPosition = localPosition;
    unawaited(BVUtils.setBrightness(nextValue));
    _showFeedbackOverlay(
      '${(nextValue * 100).round()}%',
      icon: Icons.light_mode_rounded,
    );
  }

  Future<void> _finishPanGesture() async {
    final mode = _gestureMode;
    _percentageController.hide();
    final commitFuture = mode == _GestureMode.horizontalSeek
        ? _commitProgressPreview(clearPreviewBeforeSeek: true)
        : Future<void>.sync(_clearProgressPreview);
    if (mode != _GestureMode.pending) {
      _clearDiscreteGestureEligibility();
    }
    _resetGestureTracking();
    await commitFuture;
  }

  void _cancelPanGesture() {
    _clearProgressPreview();
    _percentageController.hide();
    _clearDiscreteGestureEligibility();
    _resetGestureTracking();
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (_gestureMode == _GestureMode.longPressSpeed) {
      if (_gesturePointerId == event.pointer) {
        unawaited(_finishLongPressSpeedGesture());
      }
      return;
    }
    if (!_tracksPointer(event.pointer)) {
      return;
    }
    unawaited(_finishPanGesture());
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (_gestureMode == _GestureMode.longPressSpeed) {
      if (_gesturePointerId == null || _gesturePointerId == event.pointer) {
        _cancelLongPressSpeedGesture();
      }
      return;
    }
    if (!_tracksPointer(event.pointer)) {
      return;
    }
    _cancelPanGesture();
  }

  void _handleTapCancel() {
    _clearDiscreteGestureEligibility();
    // Tap cancellation also happens when long press wins the gesture arena.
    // Keep any in-flight pointer gesture intact and let pointer up/cancel
    // perform the real cleanup.
    if (_hasTrackedPointerGesture ||
        _gestureMode == _GestureMode.longPressSpeed) {
      return;
    }
    _resetGestureTracking();
  }

  Widget _buildTopBar() {
    if (!_isFullscreen) return const SizedBox.shrink();

    return IgnorePointer(
      ignoring: !_controlsVisible,
      child: AnimatedOpacity(
        opacity: _controlsVisible ? 1 : 0,
        duration: _overlayAnimationDuration,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.68),
                Colors.black.withValues(alpha: 0.34),
                Colors.transparent,
              ],
            ),
          ),
          child: SafeArea(
            bottom: false,
            left: true,
            right: true,
            child: SizedBox(
              height: _topBarHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: _fullscreenBottomBarHorizontalPadding,
                ),
                child: Row(
                  children: [
                    _buildFullscreenToolbarIconButton(
                      icon: Icons.arrow_back_rounded,
                      onPressed: _toggleFullscreen,
                    ),
                    const SizedBox(width: _fullscreenTopToolbarSpacing),
                    Expanded(child: widget.title),
                    const SizedBox(width: 12),
                    if (widget.onPrev != null)
                      _buildFullscreenActionChip(
                        icon: Icons.skip_previous_rounded,
                        label: '上集',
                        onTap: () {
                          _showControls();
                          widget.onPrev?.call();
                        },
                      ),
                    if (widget.onPrev != null)
                      const SizedBox(width: _fullscreenTopToolbarSpacing),
                    if (widget.onNext != null)
                      _buildFullscreenActionChip(
                        icon: Icons.skip_next_rounded,
                        label: '下集',
                        onTap: () {
                          _showControls();
                          widget.onNext?.call();
                        },
                      ),
                    if (widget.onNext != null)
                      const SizedBox(width: _fullscreenTopToolbarSpacing),
                    _buildFullscreenActionChip(
                      icon: Icons.speed_rounded,
                      label: _formatPlaybackRate(_rate),
                      onTap: _canInteractWithPlayback ? _showSpeedSheet : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    if (!_showBottomBar) {
      return const SizedBox.shrink();
    }

    final displayedPosition = _displayedPosition;
    final safeBottomInset = _isFullscreen ? _fullscreenSafePadding.bottom : 0.0;

    return IgnorePointer(
      ignoring: !_showBottomBar,
      child: AnimatedOpacity(
        opacity: _showBottomBar ? 1 : 0,
        duration: _overlayAnimationDuration,
        child: SizedBox(
          height: _bottomControlsExtent + safeBottomInset,
          child: SafeArea(
            top: false,
            bottom: _isFullscreen,
            left: _isFullscreen,
            right: _isFullscreen,
            child: SizedBox(
              height: _bottomControlsExtent,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  _isFullscreen
                      ? _fullscreenBottomBarHorizontalPadding
                      : _bottomBarHorizontalPadding,
                  _isFullscreen ? _fullscreenBottomBarVerticalPadding : 2,
                  _isFullscreen
                      ? _fullscreenBottomBarHorizontalPadding
                      : _bottomBarHorizontalPadding,
                  _isFullscreen ? _fullscreenBottomBarVerticalPadding : 2,
                ),
                child: _buildBottomBarContent(displayedPosition),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBarContent(Duration displayedPosition) {
    if (_isFullscreen) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildProgressBar(
            padding: const EdgeInsets.only(
              left: _fullscreenProgressStartCorrection,
            ),
          ),
          const SizedBox(height: _fullscreenBottomBarRowSpacing),
          Row(
            children: [
              _buildBottomInlineButton(
                icon: _showPauseAction
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                onTap: _canInteractWithPlayback ? _onPlayPause : null,
                iconSize: _fullscreenBottomBarInlineIconSize,
                buttonWidth: _fullscreenTopActionHeight,
                buttonHeight: _fullscreenTopActionHeight,
                circularBackground: true,
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: _bottomBarTimeWidth + 12,
                child: Text(
                  '${_formatDuration(displayedPosition)} / ${_formatDuration(_duration)}',
                  maxLines: 1,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: _fullscreenBottomBarTimeFontSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              _buildBottomInlineButton(
                icon: _volume > 0
                    ? Icons.volume_up_rounded
                    : Icons.volume_off_rounded,
                onTap: _canInteractWithPlayback ? _toggleMute : null,
                iconSize: _fullscreenBottomBarInlineIconSize,
                buttonWidth: _fullscreenBottomBarInlineButtonExtent,
                buttonHeight: _fullscreenBottomBarInlineButtonExtent,
              ),
              const SizedBox(width: 6),
              _buildBottomInlineButton(
                icon: Icons.fullscreen_exit_rounded,
                onTap: _canInteractWithPlayback ? _toggleFullscreen : null,
                iconSize: _fullscreenBottomBarInlineIconSize,
                buttonWidth: _fullscreenBottomBarInlineButtonExtent,
                buttonHeight: _fullscreenBottomBarInlineButtonExtent,
              ),
            ],
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildBottomInlineButton(
          icon:
              _showPauseAction ? Icons.pause_rounded : Icons.play_arrow_rounded,
          onTap: _canInteractWithPlayback ? _onPlayPause : null,
          iconSize: _bottomBarInlineIconSize,
          buttonWidth: _bottomBarInlineButtonExtent,
          buttonHeight: _bottomBarInlineButtonExtent,
        ),
        const SizedBox(width: _bottomBarPlayProgressSpacing),
        Expanded(
          child: _buildProgressBar(
            padding: EdgeInsets.zero,
          ),
        ),
        const SizedBox(width: _bottomBarProgressTimeSpacing),
        SizedBox(
          width: _bottomBarTimeWidth,
          child: Text(
            '${_formatDuration(displayedPosition)} / ${_formatDuration(_duration)}',
            maxLines: 1,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: _bottomBarTimeActionSpacing),
        _buildBottomInlineButton(
          icon:
              _volume > 0 ? Icons.volume_up_rounded : Icons.volume_off_rounded,
          onTap: _canInteractWithPlayback ? _toggleMute : null,
          iconSize: _bottomBarTrailingIconSize,
          buttonWidth: _bottomBarTrailingButtonWidth,
          buttonHeight: _bottomBarTrailingButtonHeight,
          iconAlignment: Alignment.centerRight,
        ),
        const SizedBox(width: _bottomBarTrailingButtonSpacing),
        _buildBottomInlineButton(
          icon: _isFullscreen
              ? Icons.fullscreen_exit_rounded
              : Icons.fullscreen_rounded,
          onTap: _canInteractWithPlayback ? _toggleFullscreen : null,
          iconSize: _bottomBarTrailingIconSize,
          buttonWidth: _bottomBarTrailingButtonWidth,
          buttonHeight: _bottomBarTrailingButtonHeight,
          iconAlignment: Alignment.centerLeft,
        ),
      ],
    );
  }

  Widget _buildBottomScrim() {
    if (!_showBottomScrim) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: 1,
        duration: _overlayAnimationDuration,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: FractionallySizedBox(
            widthFactor: 1,
            heightFactor: _isFullscreen ? 0.34 : 0.48,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.18),
                    Colors.black.withValues(alpha: 0.44),
                    Colors.black.withValues(alpha: 0.78),
                  ],
                  stops: const [0, 0.28, 0.65, 1],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPausedBackdrop() {
    if (!_showPausedBackdrop) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: 1,
          duration: _overlayAnimationDuration,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color:
                  Colors.black.withValues(alpha: _isFullscreen ? 0.20 : 0.24),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressBar({
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 12),
  }) {
    final durationMs = _duration.inMilliseconds.toDouble();
    final max = durationMs <= 0 ? 1.0 : durationMs;
    final canSeek = durationMs > 0 && _canInteractWithPlayback;
    final positionValue =
        _displayedPosition.inMilliseconds.toDouble().clamp(0.0, max);
    final bufferValue = _buffer.inMilliseconds.toDouble().clamp(0.0, max);

    return Padding(
      padding: padding,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: Align(
              child: LinearProgressIndicator(
                value: max <= 0 ? 0 : bufferValue / max,
                minHeight: 3,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Colors.white.withValues(alpha: 0.38),
                ),
                backgroundColor: Colors.white.withValues(alpha: 0.14),
              ),
            ),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              trackShape: const _EdgeToEdgeSliderTrackShape(),
              overlayShape: SliderComponentShape.noOverlay,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              inactiveTrackColor: Colors.transparent,
              activeTrackColor: Theme.of(context).colorScheme.primary,
              thumbColor: Theme.of(context).colorScheme.primary,
            ),
            child: Slider(
              padding: EdgeInsets.zero,
              value: positionValue,
              max: max,
              onChangeStart: canSeek
                  ? (value) {
                      _beginProgressPreview(value);
                    }
                  : null,
              onChanged: canSeek
                  ? (value) {
                      _updateProgressPreview(value);
                    }
                  : null,
              onChangeEnd: canSeek
                  ? (value) async {
                      await _commitProgressPreview(
                        clearPreviewBeforeSeek: true,
                      );
                    }
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransportOverlayContent() {
    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_isFullscreen)
          _buildTransportButton(
            icon: Icons.replay_10_rounded,
            size: _fullscreenTransportButtonSize,
            iconSize: _fullscreenTransportButtonIconSize,
            onTap: () => _seekRelative(-10),
            activateOnTapDown: true,
          ),
        if (_isFullscreen)
          const SizedBox(width: _fullscreenTransportButtonSpacing),
        _buildTransportButton(
          icon: _completed ? Icons.replay_rounded : Icons.play_arrow_rounded,
          size: 76,
          iconSize: 42,
          prominent: true,
          onTap: _onPlayPause,
        ),
        if (_isFullscreen)
          const SizedBox(width: _fullscreenTransportButtonSpacing),
        if (_isFullscreen)
          _buildTransportButton(
            icon: Icons.forward_10_rounded,
            size: _fullscreenTransportButtonSize,
            iconSize: _fullscreenTransportButtonIconSize,
            onTap: () => _seekRelative(10),
            activateOnTapDown: true,
          ),
      ],
    );

    return Padding(
      key: _transportOverlayKey,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: controls,
    );
  }

  Widget _buildTransportOverlay() {
    return Center(
      child: _buildTransportOverlayContent(),
    );
  }

  Widget _buildFullscreenSideActions() {
    if (!_isFullscreen || widget.onToggleOrientationLock == null) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !_controlsVisible,
        child: AnimatedOpacity(
          opacity: _controlsVisible ? 1 : 0,
          duration: _overlayAnimationDuration,
          child: Align(
            alignment: Alignment.centerRight,
            child: Padding(
              key: _fullscreenSideActionKey,
              padding: EdgeInsets.only(
                right: _fullscreenSafePadding.right + 12,
              ),
              child: _buildFullscreenToolbarIconButton(
                icon: widget.orientationLocked
                    ? Icons.lock_rounded
                    : Icons.lock_open_rounded,
                onPressed: widget.onToggleOrientationLock!,
                buttonSize: _fullscreenSideActionButtonSize,
                iconSize: _fullscreenSideActionIconSize,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOpeningLoadingCard() {
    return const RiveLoading();
  }

  Widget _buildPlaybackLoadingCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
          SizedBox(width: 12),
          Text(
            '加载中...',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedbackCard(PercentageOverlayData data) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (data.icon != null)
            Icon(
              data.icon,
              size: 18,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          if (data.icon != null) const SizedBox(width: 8),
          Text(
            data.message,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  double _centerOverlayBottomAvoidance({
    required BoxConstraints constraints,
    required double contentHeight,
  }) {
    if (!_showBottomBar) {
      return 0;
    }
    final controlTop = constraints.maxHeight - _bottomControlsExtent;
    final centeredBottom = constraints.maxHeight / 2 + contentHeight / 2;
    final requiredShift = max(
      0.0,
      centeredBottom - (controlTop - _loadingOverlayMargin),
    );
    return requiredShift * 2;
  }

  Widget _buildCenteredStatusGroup({
    required Widget primary,
    double primaryEstimatedHeight = 44,
    Widget? secondary,
    double secondaryEstimatedHeight = 0,
  }) {
    return IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          _loadingOverlayMargin,
          _loadingOverlayMargin,
          _loadingOverlayMargin,
          _loadingOverlayMargin,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final hasSecondary = secondary != null;
            final compact = constraints.maxHeight < 112;
            final spacing = compact ? 8.0 : 12.0;
            final estimatedHeight = primaryEstimatedHeight +
                (hasSecondary ? secondaryEstimatedHeight + spacing : 0.0);
            final bottomAvoidance = _centerOverlayBottomAvoidance(
              constraints: constraints,
              contentHeight: estimatedHeight,
            );
            return SizedBox(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              child: Padding(
                padding: EdgeInsets.only(bottom: bottomAvoidance),
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: max(0.0, constraints.maxHeight - bottomAvoidance),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.center,
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(maxWidth: constraints.maxWidth),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (hasSecondary) ...[
                            secondary,
                            SizedBox(height: spacing),
                          ],
                          primary,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLongPressSpeedOverlayContent() {
    return AnimatedBuilder(
      animation: _longPressSpeedOverlayController,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...List.generate(3, (index) {
              final delay = index * 0.16;
              final rawPhase = _longPressSpeedOverlayController.value - delay;
              final phase = rawPhase < 0 ? rawPhase + 1 : rawPhase;
              final activeProgress = phase < 0.45 ? 1 - (phase / 0.45) : 0.0;
              final emphasis = Curves.easeOut.transform(activeProgress);

              return Transform.translate(
                offset: Offset((1 - emphasis) * -2.5, 0),
                child: Padding(
                  padding: EdgeInsets.only(
                    left: index == 0 ? 0 : 0.5,
                  ),
                  child: Opacity(
                    opacity: 0.24 + (emphasis * 0.76),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(width: 6),
            Text(
              _formatPlaybackRate(_maxPlaybackRate),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showErrorDetailsDialog(String errorMessage) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          backgroundColor: const Color(0xFF191B20),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 12, 8),
          contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          title: Row(
            children: [
              const Expanded(
                child: Text(
                  '报错详情',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: '关闭',
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                },
                icon: Icon(
                  Icons.close_rounded,
                  color: Colors.white.withValues(alpha: 0.76),
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420, maxHeight: 320),
            child: SingleChildScrollView(
              child: SelectableText(
                errorMessage,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.92),
                  fontSize: 13.5,
                  height: 1.5,
                ),
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                shape: const StadiumBorder(),
              ),
              child: const Text('知道了'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildErrorOverlay() {
    final errorMessage = _error;
    if (errorMessage == null) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      ignoring: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 150;
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '播放异常',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 15 : 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: compact ? 4 : 8),
                    Text(
                      '视频无法播放，请重试！',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontSize: compact ? 12 : 13,
                        height: 1.35,
                      ),
                    ),
                    SizedBox(height: compact ? 10 : 12),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: compact ? 8 : 10,
                      runSpacing: 8,
                      children: [
                        FilledButton(
                          onPressed: widget.onRetry,
                          style: FilledButton.styleFrom(
                            minimumSize:
                                Size(compact ? 82 : 92, compact ? 32 : 36),
                            padding: EdgeInsets.symmetric(
                              horizontal: compact ? 14 : 16,
                              vertical: compact ? 6 : 8,
                            ),
                            shape: const StadiumBorder(),
                            textStyle: TextStyle(
                              fontSize: compact ? 12 : 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          child: const Text('重新播放'),
                        ),
                        OutlinedButton(
                          onPressed: () {
                            unawaited(_showErrorDetailsDialog(errorMessage));
                          },
                          style: OutlinedButton.styleFrom(
                            minimumSize:
                                Size(compact ? 92 : 104, compact ? 32 : 36),
                            padding: EdgeInsets.symmetric(
                              horizontal: compact ? 12 : 14,
                              vertical: compact ? 6 : 8,
                            ),
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.16),
                            ),
                            foregroundColor:
                                Colors.white.withValues(alpha: 0.94),
                            shape: const StadiumBorder(),
                            textStyle: TextStyle(
                              fontSize: compact ? 12 : 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('查看详情'),
                              SizedBox(width: compact ? 2 : 4),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: compact ? 16 : 18,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCenterOverlay() {
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _percentageController,
        builder: (context, _) {
          final feedback = _percentageController.data;
          final hasFeedback = !feedback.hidden;
          final hasLongPressSpeedOverlay = _showLongPressSpeedOverlay;
          final inlineSecondary =
              hasFeedback ? _buildFeedbackCard(feedback) : null;
          const inlineSecondaryHeight = 38.0;
          const longPressOverlayHeight = 46.0;
          final overlayPadding = _fullscreenSafePadding.add(
            _centerOverlayMode == _CenterOverlayMode.loading ||
                    _centerOverlayMode == _CenterOverlayMode.transport ||
                    (_centerOverlayMode == _CenterOverlayMode.hidden &&
                        (hasFeedback || hasLongPressSpeedOverlay))
                ? EdgeInsets.zero
                : EdgeInsets.only(
                    top: _topControlsExtent,
                    bottom: _bottomControlsExtent,
                  ),
          );

          Widget child = const SizedBox.shrink();
          switch (_centerOverlayMode) {
            case _CenterOverlayMode.hidden:
              child = hasLongPressSpeedOverlay
                  ? _buildCenteredStatusGroup(
                      primary: _buildLongPressSpeedOverlayContent(),
                      primaryEstimatedHeight: 46,
                    )
                  : hasFeedback
                      ? _buildCenteredStatusGroup(
                          primary: _buildFeedbackCard(feedback),
                          primaryEstimatedHeight: inlineSecondaryHeight,
                        )
                      : const SizedBox.shrink();
              break;
            case _CenterOverlayMode.transport:
              child = inlineSecondary != null
                  ? _buildCenteredStatusGroup(
                      primary: _buildTransportOverlayContent(),
                      primaryEstimatedHeight: 76,
                      secondary: inlineSecondary,
                      secondaryEstimatedHeight: inlineSecondaryHeight,
                    )
                  : _buildTransportOverlay();
              break;
            case _CenterOverlayMode.loading:
              final primary = widget.opening
                  ? _buildOpeningLoadingCard()
                  : _buildPlaybackLoadingCard();
              final loadingSecondary = hasLongPressSpeedOverlay
                  ? _buildLongPressSpeedOverlayContent()
                  : inlineSecondary;
              final loadingSecondaryHeight = hasLongPressSpeedOverlay
                  ? longPressOverlayHeight
                  : inlineSecondaryHeight;
              child = loadingSecondary != null
                  ? _buildCenteredStatusGroup(
                      primary: primary,
                      primaryEstimatedHeight:
                          widget.opening ? _loadingIndicatorExtent : 44,
                      secondary: loadingSecondary,
                      secondaryEstimatedHeight: loadingSecondaryHeight,
                    )
                  : _buildCenteredStatusGroup(
                      primary: primary,
                      primaryEstimatedHeight:
                          widget.opening ? _loadingIndicatorExtent : 44,
                    );
              break;
            case _CenterOverlayMode.error:
              child = _buildErrorOverlay();
              break;
          }

          return Padding(
            padding: overlayPadding,
            child: child,
          );
        },
      ),
    );
  }

  Widget _buildTransportButton({
    required IconData icon,
    required VoidCallback onTap,
    double size = 56,
    double iconSize = 28,
    bool prominent = false,
    bool activateOnTapDown = false,
  }) {
    final showBackground = prominent || _isFullscreen;
    final backgroundColor = prominent
        ? Colors.black.withValues(alpha: 0.34)
        : Colors.black.withValues(alpha: 0.20);
    final borderColor = prominent
        ? Colors.white.withValues(alpha: 0.22)
        : Colors.white.withValues(alpha: 0.12);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: activateOnTapDown ? (_) => onTap() : null,
      onTap: activateOnTapDown ? null : onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: showBackground ? backgroundColor : Colors.transparent,
          border: showBackground ? Border.all(color: borderColor) : null,
        ),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            size: iconSize,
            color:
                prominent ? Colors.white : Colors.white.withValues(alpha: 0.94),
          ),
        ),
      ),
    );
  }

  Widget _buildFullscreenToolbarIconButton({
    required IconData icon,
    required VoidCallback onPressed,
    double buttonSize = _fullscreenTopActionHeight,
    double iconSize = 20,
  }) {
    return IconButton(
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(
        width: buttonSize,
        height: buttonSize,
      ),
      style: IconButton.styleFrom(
        backgroundColor: Colors.black.withValues(alpha: 0.42),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.14),
          ),
        ),
      ),
      icon: Icon(
        icon,
        size: iconSize,
      ),
    );
  }

  Widget _buildFullscreenActionChip({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, _fullscreenTopActionHeight),
        padding: const EdgeInsets.symmetric(
          horizontal: _fullscreenTopChipHorizontalPadding,
          vertical: 4,
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: const VisualDensity(
          horizontal: -1,
          vertical: -1,
        ),
        backgroundColor: Colors.black.withValues(alpha: 0.42),
        disabledBackgroundColor: Colors.black.withValues(alpha: 0.22),
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.14),
          ),
        ),
      ),
      icon: Icon(icon, size: _fullscreenTopChipIconSize),
      label: Text(
        label,
        style: const TextStyle(
          fontSize: _fullscreenTopChipFontSize,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildBottomInlineButton({
    required IconData icon,
    VoidCallback? onTap,
    double iconSize = 22,
    double buttonWidth = 30,
    double buttonHeight = 30,
    AlignmentGeometry iconAlignment = Alignment.center,
    bool circularBackground = false,
  }) {
    final iconWidget = Align(
      alignment: iconAlignment,
      child: Icon(
        icon,
        size: iconSize,
        color:
            onTap == null ? Colors.white.withValues(alpha: 0.45) : Colors.white,
      ),
    );

    if (circularBackground) {
      return IconButton(
        padding: EdgeInsets.zero,
        constraints: BoxConstraints.tightFor(
          width: buttonWidth,
          height: buttonHeight,
        ),
        onPressed: onTap,
        style: IconButton.styleFrom(
          backgroundColor: Colors.black.withValues(alpha: 0.42),
          disabledBackgroundColor: Colors.black.withValues(alpha: 0.22),
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white.withValues(alpha: 0.45),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
            side: BorderSide(
              color: Colors.white.withValues(alpha: 0.14),
            ),
          ),
        ),
        icon: iconWidget,
      );
    }

    return IconButton(
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(
        width: buttonWidth,
        height: buttonHeight,
      ),
      onPressed: onTap,
      icon: iconWidget,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) {
          _rememberDiscreteGestureEligibility(details.localPosition);
        },
        onTap: () {
          if (!_discreteGestureAllowed) return;
          _clearDiscreteGestureEligibility();
          _resetGestureTracking();
          _toggleControls();
        },
        onTapCancel: _handleTapCancel,
        onDoubleTapDown: (details) {
          _rememberDiscreteGestureEligibility(details.localPosition);
        },
        onDoubleTap: () {
          if (!_discreteGestureAllowed) return;
          _clearDiscreteGestureEligibility();
          _resetGestureTracking();
          unawaited(_onPlayPause());
        },
        onLongPressStart: (details) async {
          if (!_canStartLongPressSpeedGesture(details.localPosition)) {
            return;
          }
          final controller = _controller;
          if (controller == null ||
              !_canInteractWithPlayback ||
              !controller.value.isPlaying) {
            return;
          }
          _clearDiscreteGestureEligibility();
          _prepareLongPressSpeedGesture();
          _gestureMode = _GestureMode.longPressSpeed;
          _tempPlaybackSpeed = _rate;
          _wasPlayingBeforeLongPress = controller.value.isPlaying;
          try {
            await controller.setPlaybackSpeed(_maxPlaybackRate);
            if (!controller.value.isPlaying) {
              await controller.play();
            }
            _setLongPressSpeedOverlayVisible(true);
          } catch (error) {
            debugPrint('Failed to start long press speed gesture: $error');
            try {
              await _restoreLongPressSpeedGesture(awaitOperations: true);
            } catch (restoreError) {
              debugPrint(
                'Failed to restore playback after long press error: '
                '$restoreError',
              );
            }
          }
        },
        onLongPressEnd: (_) async {
          await _finishLongPressSpeedGesture();
        },
        child: Stack(
          children: [
            _buildPausedBackdrop(),
            _buildBottomScrim(),
            _buildCenterOverlay(),
            _buildFullscreenSideActions(),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildTopBar(),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildBottomBar(),
            ),
          ],
        ),
      ),
    );
  }
}

Duration _clampDuration(Duration value, Duration min, Duration max) {
  if (value < min) return min;
  if (value > max) return max;
  return value;
}

String _formatDuration(Duration duration) {
  final totalSeconds = max(0, duration.inSeconds);
  final totalMinutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;

  return '${totalMinutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}

String _formatPlaybackRate(double rate) {
  final normalized = rate == rate.roundToDouble()
      ? rate.toStringAsFixed(0)
      : rate
          .toStringAsFixed(2)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
  return '${normalized}x';
}

class _EdgeToEdgeSliderTrackShape extends RoundedRectSliderTrackShape {
  const _EdgeToEdgeSliderTrackShape();

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final trackHeight = sliderTheme.trackHeight ?? 0;
    final trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    return Rect.fromLTWH(
      offset.dx,
      trackTop,
      parentBox.size.width,
      trackHeight,
    );
  }
}
