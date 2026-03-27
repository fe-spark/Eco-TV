import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '/model/film_play_info/detail.dart';
import '/plugins.dart';

import 'skin.dart';

const Duration _minimumResumeSeekOffset = Duration(seconds: 2);

@immutable
class _PlayerSurfaceState {
  final bool opening;
  final String? errorMessage;
  final bool playRequested;
  final VideoPlayerRuntimeState runtimeState;

  const _PlayerSurfaceState({
    required this.opening,
    required this.errorMessage,
    required this.playRequested,
    required this.runtimeState,
  });

  static const initial = _PlayerSurfaceState(
    opening: true,
    errorMessage: null,
    playRequested: true,
    runtimeState: VideoPlayerRuntimeState.empty,
  );

  _PlayerSurfaceState copyWith({
    bool? opening,
    String? errorMessage,
    bool clearError = false,
    bool? playRequested,
    VideoPlayerRuntimeState? runtimeState,
  }) {
    return _PlayerSurfaceState(
      opening: opening ?? this.opening,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      playRequested: playRequested ?? this.playRequested,
      runtimeState: runtimeState ?? this.runtimeState,
    );
  }
}

@immutable
class PlayerPlaybackSnapshot {
  final bool ready;
  final bool playing;
  final int positionSeconds;

  const PlayerPlaybackSnapshot({
    required this.ready,
    required this.playing,
    required this.positionSeconds,
  });

  static const empty = PlayerPlaybackSnapshot(
    ready: false,
    playing: false,
    positionSeconds: 0,
  );
}

class PlayerPlaybackController with ChangeNotifier {
  PlayerPlaybackSnapshot _snapshot = PlayerPlaybackSnapshot.empty;
  Future<void> Function()? _pauseLocalPlayback;

  PlayerPlaybackSnapshot get snapshot => _snapshot;

  bool get isReady => _snapshot.ready;

  bool get isPlaying => _snapshot.playing;

  int get positionSeconds => _snapshot.positionSeconds;

  Future<bool> pauseIfPlaying() async {
    if (!_snapshot.playing) return false;
    final pauseLocalPlayback = _pauseLocalPlayback;
    if (pauseLocalPlayback == null) return false;
    await pauseLocalPlayback();
    return true;
  }

  void _sync({
    required PlayerPlaybackSnapshot snapshot,
    Future<void> Function()? pauseLocalPlayback,
  }) {
    final snapshotChanged = _snapshot.ready != snapshot.ready ||
        _snapshot.playing != snapshot.playing ||
        _snapshot.positionSeconds != snapshot.positionSeconds;
    final pauseHandlerChanged = _pauseLocalPlayback != pauseLocalPlayback;
    if (!snapshotChanged && !pauseHandlerChanged) return;

    _snapshot = snapshot;
    _pauseLocalPlayback = pauseLocalPlayback;
    notifyListeners();
  }

  void _detach() {
    _sync(snapshot: PlayerPlaybackSnapshot.empty, pauseLocalPlayback: null);
  }
}

class Player extends StatefulWidget {
  final double aspectRatio;
  final double fullScreenAspectRatio;
  final Detail? detail;
  final PlayerPlaybackController? playbackController;
  final bool externalPlaybackActive;

  const Player({
    super.key,
    required this.aspectRatio,
    this.detail,
    required this.fullScreenAspectRatio,
    this.playbackController,
    this.externalPlaybackActive = false,
  });

  @override
  State<Player> createState() => _PlayerState();
}

class _PlayerState extends State<Player> with WidgetsBindingObserver {
  static const MethodChannel _audioSessionChannel =
      MethodChannel('bracket/audio_session');
  static const MethodChannel _orientationChannel =
      MethodChannel('bracket/orientation');

  final Throttler _throttler = Throttler(milliseconds: 5000);
  final ValueNotifier<int> _fullscreenRevision = ValueNotifier<int>(0);

  VideoPlayerController? _controller;
  PlayVideoIdsStore? _playVideoIdsStore;
  HistoryStore? _historyStore;
  VideoSourceStore? _videoSourceStore;
  _PlayerSurfaceState _surfaceState = _PlayerSurfaceState.initial;
  DateTime? _lastProgressAt;
  Duration _lastProgressPosition = Duration.zero;
  double _lastAudibleVolume = 100.0;

  bool _presentingFullscreen = false;
  bool _fullscreenOrientationLocked = false;
  bool _advancingToNextEpisode = false;
  bool _lastPlaying = false;
  bool _lastCompleted = false;
  int _openRequestId = 0;
  Timer? _resumePlayKickTimer;
  Duration? _backgroundPosition;

  bool get _isPlaybackReady =>
      _controller?.value.isInitialized == true &&
      !_surfaceState.opening &&
      _surfaceState.errorMessage == null;

  bool get _hasRecentPlaybackProgress {
    final lastProgressAt = _lastProgressAt;
    if (lastProgressAt == null) return false;
    return DateTime.now().difference(lastProgressAt) <=
        const Duration(milliseconds: 900);
  }

  double get _resolvedVideoAspectRatio {
    final controller = _controller;
    final value = controller?.value;
    if (value != null &&
        value.isInitialized &&
        value.aspectRatio.isFinite &&
        value.aspectRatio > 0) {
      return value.aspectRatio;
    }
    return widget.aspectRatio;
  }

  bool get _isPortraitVideo => _resolvedVideoAspectRatio < 1.0;

  VideoViewType get _videoViewType =>
      Platform.isIOS ? VideoViewType.platformView : VideoViewType.textureView;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _playVideoIdsStore = context.read<PlayVideoIdsStore>();
    _historyStore = context.read<HistoryStore>();
    _videoSourceStore = context.read<VideoSourceStore>();
    _playVideoIdsStore?.addListener(_handleVideoInfoChanged);
    _openCurrentMedia();
  }

  @override
  void didChangeDependencies() {
    _playVideoIdsStore = context.read<PlayVideoIdsStore>();
    _historyStore = context.read<HistoryStore>();
    _videoSourceStore = context.read<VideoSourceStore>();
    super.didChangeDependencies();
  }

  @override
  void didUpdateWidget(covariant Player oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playbackController != widget.playbackController) {
      oldWidget.playbackController?._detach();
      _publishPlaybackController();
    }
    if (!oldWidget.externalPlaybackActive &&
        widget.externalPlaybackActive &&
        _controller?.value.isPlaying == true) {
      unawaited(_pauseForRemotePlayback());
    }
    if (oldWidget.detail?.id != widget.detail?.id) {
      _openCurrentMedia();
    }
  }

  @override
  void dispose() {
    _setHistory();
    _throttler.cancel();
    _fullscreenRevision.dispose();
    _resumePlayKickTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _playVideoIdsStore?.removeListener(_handleVideoInfoChanged);
    widget.playbackController?._detach();
    final controller = _controller;
    if (controller != null) {
      controller.removeListener(_handleControllerValueChanged);
      unawaited(controller.dispose());
    }
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _resumePlayKickTimer?.cancel();
        _backgroundPosition = _controller?.value.position;
        break;
      case AppLifecycleState.resumed:
        _scheduleResumePlayKickIfNeeded();
        break;
      case AppLifecycleState.detached:
        _resumePlayKickTimer?.cancel();
        break;
    }
  }

  void _notifyFullscreenRebuild() {
    if (_presentingFullscreen) {
      _fullscreenRevision.value += 1;
    }
  }

  void _publishPlaybackController() {
    final playbackController = widget.playbackController;
    if (playbackController == null) return;

    final controller = _controller;
    final value = controller?.value;
    final positionSeconds =
        (value?.position ?? _surfaceState.runtimeState.position).inSeconds;

    playbackController._sync(
      snapshot: PlayerPlaybackSnapshot(
        ready: _isPlaybackReady,
        playing: value?.isPlaying ?? false,
        positionSeconds: max(0, positionSeconds),
      ),
      pauseLocalPlayback: _pauseForRemotePlayback,
    );
  }

  void _setPlayerState(VoidCallback update) {
    if (!mounted) {
      update();
      _publishPlaybackController();
      _notifyFullscreenRebuild();
      return;
    }
    setState(update);
    _publishPlaybackController();
    _notifyFullscreenRebuild();
  }

  void _updateSurfaceState(_PlayerSurfaceState next) {
    if (_surfaceState == next) return;
    _setPlayerState(() {
      _surfaceState = next;
    });
  }

  void _handleVideoInfoChanged() {
    if (!mounted) return;
    _openCurrentMedia();
  }

  void _setPlayRequested(bool value) {
    if (!value) {
      _resumePlayKickTimer?.cancel();
    }
    if (_surfaceState.playRequested == value) return;
    _updateSurfaceState(_surfaceState.copyWith(playRequested: value));
  }

  void _scheduleResumePlayKickIfNeeded() {
    _resumePlayKickTimer?.cancel();

    final controller = _controller;
    final backgroundPosition = _backgroundPosition;
    if (controller == null ||
        backgroundPosition == null ||
        !_surfaceState.playRequested ||
        _surfaceState.errorMessage != null ||
        _surfaceState.opening) {
      return;
    }

    _resumePlayKickTimer = Timer(const Duration(milliseconds: 600), () async {
      if (!mounted) return;

      final currentController = _controller;
      if (currentController == null ||
          currentController != controller ||
          !_surfaceState.playRequested ||
          _surfaceState.errorMessage != null ||
          _surfaceState.opening) {
        return;
      }

      final value = currentController.value;
      final progressed = value.position > backgroundPosition;
      if (progressed || _hasRecentPlaybackProgress) {
        return;
      }

      try {
        await currentController.play();
      } catch (error) {
        debugPrint('Failed to kick playback after resume: $error');
      }
    });
  }

  Future<void> _pauseForRemotePlayback() async {
    final controller = _controller;
    if (controller == null) return;

    _setPlayRequested(false);
    if (!controller.value.isPlaying) {
      return;
    }

    await controller.pause();
    if (!mounted) return;
    _handleControllerValueChanged();
  }

  Future<void> _openCurrentMedia() async {
    final media = _resolveCurrentMedia();
    if (media == null) {
      final previous = _controller;
      previous?.removeListener(_handleControllerValueChanged);
      _controller = null;
      _advancingToNextEpisode = false;
      _lastPlaying = false;
      _lastCompleted = false;
      _lastProgressAt = null;
      _lastProgressPosition = Duration.zero;
      _lastAudibleVolume = 100.0;
      _resumePlayKickTimer?.cancel();
      _backgroundPosition = null;
      _updateSurfaceState(
        _surfaceState.copyWith(
          opening: false,
          errorMessage: '暂无可播放资源',
          playRequested: false,
          runtimeState: VideoPlayerRuntimeState.empty,
        ),
      );
      if (previous != null) {
        unawaited(previous.dispose());
      }
      return;
    }

    final previous = _controller;
    previous?.removeListener(_handleControllerValueChanged);

    final headers = _buildVideoRequestHeaders();
    final formatHint = _buildVideoFormatHint(media.url);
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(media.url),
      formatHint: formatHint,
      httpHeaders: headers,
      viewType: _videoViewType,
    );
    controller.addListener(_handleControllerValueChanged);

    final requestId = ++_openRequestId;
    _controller = controller;
    _advancingToNextEpisode = false;
    _lastPlaying = false;
    _lastCompleted = false;
    _lastProgressAt = null;
    _lastProgressPosition = Duration.zero;
    _lastAudibleVolume = 100.0;
    _resumePlayKickTimer?.cancel();
    _backgroundPosition = null;
    _updateSurfaceState(
      _surfaceState.copyWith(
        opening: true,
        clearError: true,
        playRequested: !widget.externalPlaybackActive,
        runtimeState: VideoPlayerRuntimeState.empty,
      ),
    );

    if (previous != null) {
      unawaited(previous.dispose());
    }

    try {
      await _ensurePlaybackAudioSession();
      final initializeFuture = controller.initialize();
      if (!widget.externalPlaybackActive) {
        await controller.play();
      }
      await initializeFuture;
      if (!mounted || requestId != _openRequestId) {
        controller.removeListener(_handleControllerValueChanged);
        await controller.dispose();
        return;
      }

      _handleControllerValueChanged();

      if (widget.externalPlaybackActive) {
        _updateSurfaceState(
          _surfaceState.copyWith(
            opening: false,
            playRequested: false,
          ),
        );
        return;
      }

      if (media.startAt >= _minimumResumeSeekOffset.inSeconds) {
        final target = _clampDuration(
          Duration(seconds: media.startAt),
          Duration.zero,
          controller.value.duration,
        );
        if (target > Duration.zero) {
          await controller.seekTo(target);
          if (_surfaceState.playRequested && !controller.value.isPlaying) {
            await controller.play();
          }
        }
      }
      if (!mounted || requestId != _openRequestId) return;
      _handleControllerValueChanged();
    } catch (error) {
      if (!mounted || requestId != _openRequestId) return;
      _setFatalError('$error');
    }
  }

  Future<void> _ensurePlaybackAudioSession() async {
    if (!Platform.isIOS) return;
    try {
      final info = await _audioSessionChannel.invokeMapMethod<String, dynamic>(
        'ensurePlaybackSession',
      );
      if (info != null) {
        debugPrint('AVAudioSession ready: $info');
      }
    } catch (error) {
      debugPrint('Failed to ensure AVAudioSession: $error');
    }
  }

  Future<void> _syncWakelock(bool playing) async {
    if (playing) {
      final enabled = await WakelockPlus.enabled;
      if (!enabled) {
        await WakelockPlus.enable();
      }
    } else {
      await WakelockPlus.disable();
    }
  }

  void _handleControllerValueChanged() {
    final controller = _controller;
    if (controller == null) return;
    final requestId = _openRequestId;

    final value = controller.value;
    final playing = value.isPlaying;
    final completed = value.isCompleted;
    final position = value.position;
    if (position != _lastProgressPosition) {
      _resumePlayKickTimer?.cancel();
      _lastProgressPosition = position;
      _lastProgressAt = DateTime.now();
    }

    if (value.hasError) {
      _setFatalError(value.errorDescription ?? '播放失败');
      return;
    }

    if (playing) {
      _throttler.run(_setHistory);
    }
    if (!playing && _lastPlaying) {
      _setHistory();
    }
    if (completed && !_lastCompleted) {
      if (!_advanceToNextEpisodeInCurrentSource()) {
        _setHistory();
      }
    }
    if (requestId != _openRequestId || !identical(controller, _controller)) {
      return;
    }

    _lastPlaying = playing;
    _lastCompleted = completed;
    final volume = value.volume * 100;
    if (volume > 0) {
      _lastAudibleVolume = volume;
    }
    final bufferedPosition = _bufferedPosition(value.buffered);
    final hasBufferedHeadroom =
        bufferedPosition - position > const Duration(milliseconds: 600);
    final stalledPlayback = _surfaceState.playRequested &&
        !completed &&
        !value.hasError &&
        value.duration > Duration.zero &&
        !value.isBuffering &&
        !hasBufferedHeadroom &&
        !_hasRecentPlaybackProgress;
    final nextPlayRequested =
        completed ? false : (playing ? true : _surfaceState.playRequested);
    final nextRuntimeState = VideoPlayerRuntimeState(
      playing: playing,
      completed: completed,
      buffering: value.isBuffering,
      stalledPlayback: stalledPlayback,
      hasRecentProgress: _hasRecentPlaybackProgress,
      position: position,
      duration: value.duration,
      buffer: bufferedPosition,
      volume: volume,
      playbackSpeed: value.playbackSpeed,
      lastAudibleVolume: _lastAudibleVolume,
    );
    final nextSurfaceState = _surfaceState.copyWith(
      playRequested: nextPlayRequested,
      runtimeState: nextRuntimeState,
    );
    final shouldRebuild = _surfaceState != nextSurfaceState;
    if (shouldRebuild) {
      _updateSurfaceState(nextSurfaceState);
    }
    unawaited(_syncWakelock(playing));

    if (_surfaceState.opening &&
        value.isInitialized &&
        (playing || value.isBuffering || position > Duration.zero)) {
      _updateSurfaceState(_surfaceState.copyWith(opening: false));
      return;
    }

    if (!shouldRebuild) {
      _notifyFullscreenRebuild();
    }
  }

  void _setFatalError(String message) {
    _resumePlayKickTimer?.cancel();
    _updateSurfaceState(
      _surfaceState.copyWith(
        opening: false,
        errorMessage: message,
        playRequested: false,
        runtimeState: VideoPlayerRuntimeState(
          playing: false,
          completed: false,
          buffering: false,
          stalledPlayback: false,
          hasRecentProgress: false,
          position: _surfaceState.runtimeState.position,
          duration: _surfaceState.runtimeState.duration,
          buffer: _surfaceState.runtimeState.buffer,
          volume: _surfaceState.runtimeState.volume,
          playbackSpeed: _surfaceState.runtimeState.playbackSpeed,
          lastAudibleVolume: _surfaceState.runtimeState.lastAudibleVolume,
        ),
      ),
    );
  }

  Future<void> _enterFullscreen() async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        await Future.wait([
          SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.immersiveSticky,
            overlays: [],
          ),
          _applyFullscreenOrientations(),
        ]);
      }
    } catch (error) {
      debugPrint('Failed to enter fullscreen: $error');
    }
  }

  Future<void> _exitFullscreen() async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        if (Platform.isIOS) {
          await _orientationChannel.invokeMethod<void>('clearOrientationLock');
        }
        await Future.wait([
          SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.manual,
            overlays: SystemUiOverlay.values,
          ),
          SystemChrome.setPreferredOrientations(const []),
        ]);
      }
    } catch (error) {
      debugPrint('Failed to exit fullscreen: $error');
    }
  }

  Future<void> _showFullscreen() async {
    if (_presentingFullscreen) return;
    _setPlayerState(() {
      _presentingFullscreen = true;
      _fullscreenOrientationLocked = false;
    });
    await _enterFullscreen();
    if (!mounted) return;

    try {
      await Navigator.of(context).push(
        PageRouteBuilder<void>(
          opaque: true,
          pageBuilder: (routeContext, _, __) {
            return ValueListenableBuilder<int>(
              valueListenable: _fullscreenRevision,
              builder: (context, _, __) {
                return Scaffold(
                  backgroundColor: Colors.black,
                  body: _buildViewport(
                    isFullscreen: true,
                    onToggleFullscreen: () {
                      Navigator.of(routeContext).maybePop();
                    },
                  ),
                );
              },
            );
          },
        ),
      );
    } finally {
      _setPlayerState(() {
        _presentingFullscreen = false;
        _fullscreenOrientationLocked = false;
      });
      await _exitFullscreen();
    }
  }

  List<DeviceOrientation> get _preferredFullscreenOrientations =>
      _isPortraitVideo
          ? const [
              DeviceOrientation.portraitUp,
              DeviceOrientation.portraitDown,
            ]
          : const [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ];

  Future<DeviceOrientation?> _readCurrentDeviceOrientation() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return null;
    }
    try {
      final value = await _orientationChannel.invokeMethod<String>(
        'getCurrentDeviceOrientation',
      );
      switch (value) {
        case 'portraitUp':
          return DeviceOrientation.portraitUp;
        case 'portraitDown':
          return DeviceOrientation.portraitDown;
        case 'landscapeLeft':
          return DeviceOrientation.landscapeLeft;
        case 'landscapeRight':
          return DeviceOrientation.landscapeRight;
      }
    } catch (error) {
      debugPrint('Failed to read current device orientation: $error');
    }
    return null;
  }

  Future<void> _applyFullscreenOrientations() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (_fullscreenOrientationLocked) {
      final current = await _readCurrentDeviceOrientation() ??
          _preferredFullscreenOrientations.first;
      if (Platform.isIOS) {
        await _orientationChannel.invokeMethod<void>('lockCurrentOrientation');
      }
      await SystemChrome.setPreferredOrientations([current]);
      return;
    }
    if (Platform.isIOS) {
      await _orientationChannel.invokeMethod<void>('clearOrientationLock');
    }
    await SystemChrome.setPreferredOrientations(
        _preferredFullscreenOrientations);
  }

  Future<void> _toggleFullscreenOrientationLock() async {
    if (!_presentingFullscreen) return;
    _setPlayerState(() {
      _fullscreenOrientationLocked = !_fullscreenOrientationLocked;
    });
    await _applyFullscreenOrientations();
  }

  _CurrentMedia? _resolveCurrentMedia() {
    final detail = widget.detail;
    final list = detail?.list;
    if (detail == null || list == null || list.isEmpty) return null;

    final originIndex =
        (_playVideoIdsStore?.originIndex ?? 0).clamp(0, list.length - 1);
    final linkList = list[originIndex].linkList;
    if (linkList == null || linkList.isEmpty) return null;

    final teleplayIndex =
        (_playVideoIdsStore?.teleplayIndex ?? 0).clamp(0, linkList.length - 1);
    final url = linkList[teleplayIndex].link;
    if (url == null || url.isEmpty) return null;

    return _CurrentMedia(
      originIndex: originIndex,
      teleplayIndex: teleplayIndex,
      startAt: _playVideoIdsStore?.startAt ?? 0,
      url: url,
    );
  }

  Map<String, String> _buildVideoRequestHeaders() {
    if (!Platform.isIOS && !Platform.isAndroid) {
      return const <String, String>{};
    }

    final headers = <String, String>{
      'User-Agent': Platform.isIOS
          ? 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1'
          : 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Mobile Safari/537.36',
    };

    final source = _videoSourceStore?.data?.actived;
    if (source != null && source.isNotEmpty) {
      headers['Referer'] = source;
      final sourceUri = Uri.tryParse(source);
      if (sourceUri != null &&
          sourceUri.hasScheme &&
          sourceUri.host.isNotEmpty) {
        headers['Origin'] = '${sourceUri.scheme}://${sourceUri.host}';
      }
    }
    return headers;
  }

  VideoFormat? _buildVideoFormatHint(String url) {
    if (!Platform.isAndroid) {
      return null;
    }

    final uri = Uri.tryParse(url);
    final normalized = uri == null
        ? url.toLowerCase()
        : '${uri.path.toLowerCase()}?${uri.query.toLowerCase()}';

    if (normalized.contains('.m3u8')) {
      return VideoFormat.hls;
    }
    if (normalized.contains('.mpd')) {
      return VideoFormat.dash;
    }
    if (normalized.contains('.ism/manifest') ||
        normalized.contains('.isml/manifest') ||
        normalized.contains('format=ss')) {
      return VideoFormat.ss;
    }
    return null;
  }

  void _prev() {
    final originIndex = _playVideoIdsStore?.originIndex;
    final teleplayIndex = _playVideoIdsStore?.teleplayIndex;
    if (teleplayIndex == null || teleplayIndex <= 0) return;

    _playVideoIdsStore?.setVideoInfo(
      originIndex,
      teleplayIndex: teleplayIndex - 1,
      startAt: 0,
    );
  }

  void _next() {
    _advanceToNextEpisodeInCurrentSource();
  }

  bool _advanceToNextEpisodeInCurrentSource() {
    final detail = widget.detail;
    final list = detail?.list;
    if (list == null || list.isEmpty || _advancingToNextEpisode) return false;

    final originIndex =
        (_playVideoIdsStore?.originIndex ?? 0).clamp(0, list.length - 1);
    final linkList = list[originIndex].linkList;
    final teleplayIndex = _playVideoIdsStore?.teleplayIndex;

    if (teleplayIndex == null ||
        linkList == null ||
        teleplayIndex >= linkList.length - 1) {
      return false;
    }

    _advancingToNextEpisode = true;
    _setHistory();
    _playVideoIdsStore?.setVideoInfo(
      originIndex,
      teleplayIndex: teleplayIndex + 1,
      startAt: 0,
    );
    return true;
  }

  Future<void> _retry() async {
    await _openCurrentMedia();
  }

  void _setHistory() {
    final detail = widget.detail;
    final list = detail?.list;
    final controller = _controller;
    if (detail == null || list == null || list.isEmpty || controller == null) {
      return;
    }

    final originIndex =
        (_playVideoIdsStore?.originIndex ?? 0).clamp(0, list.length - 1);
    final teleplayIndex = _playVideoIdsStore?.teleplayIndex ?? 0;
    final position = controller.value.position.inSeconds;

    _historyStore?.addHistory({
      'id': detail.id,
      'name': detail.name,
      'timeStamp': DateTime.now().microsecondsSinceEpoch,
      'picture': detail.picture,
      'originId': list[originIndex].id,
      'teleplayIndex': teleplayIndex,
      'startAt': position,
    });
  }

  Widget _buildVideoContent({
    required VideoPlayerController controller,
    required double fallbackAspectRatio,
  }) {
    final value = controller.value;
    final aspectRatio = value.isInitialized &&
            value.aspectRatio.isFinite &&
            value.aspectRatio > 0
        ? value.aspectRatio
        : fallbackAspectRatio;

    return Center(
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: VideoPlayer(controller),
      ),
    );
  }

  Widget _buildViewport({
    required bool isFullscreen,
    required VoidCallback onToggleFullscreen,
  }) {
    if (_presentingFullscreen && !isFullscreen) {
      return const ColoredBox(color: Colors.black);
    }

    final controller = _controller;
    final showVideo = controller != null &&
        controller.value.isInitialized &&
        (!_presentingFullscreen || isFullscreen);

    final titleText = _buildTitleText();
    final availability = _episodeAvailability();

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (showVideo)
            _buildVideoContent(
              controller: controller,
              fallbackAspectRatio: isFullscreen
                  ? widget.fullScreenAspectRatio
                  : widget.aspectRatio,
            ),
          VideoPlayerMaterialControls(
            controller: controller,
            isFullscreen: isFullscreen,
            onToggleFullscreen: onToggleFullscreen,
            orientationLocked: _fullscreenOrientationLocked,
            onToggleOrientationLock: isFullscreen
                ? () {
                    unawaited(_toggleFullscreenOrientationLock());
                  }
                : null,
            onPlayRequestedChanged: _setPlayRequested,
            title: Text(
              titleText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            onPrev: availability.hasPrev ? _prev : null,
            onNext: availability.hasNext ? _next : null,
            onRetry: _retry,
            opening: _surfaceState.opening,
            errorMessage: _surfaceState.errorMessage,
            playbackReady: _isPlaybackReady,
            playRequested: _surfaceState.playRequested,
            runtimeState: _surfaceState.runtimeState,
          ),
        ],
      ),
    );
  }

  PlayerNextEpisodeAvailability _episodeAvailability() {
    final detail = widget.detail;
    final list = detail?.list;
    final originIndex = _playVideoIdsStore?.originIndex ?? 0;
    final teleplayIndex = _playVideoIdsStore?.teleplayIndex;
    final linkList =
        list != null && list.isNotEmpty && originIndex < list.length
            ? list[originIndex].linkList
            : null;

    final hasPrev = teleplayIndex != null && teleplayIndex > 0;
    final hasNext = teleplayIndex != null &&
        linkList != null &&
        teleplayIndex < linkList.length - 1;
    return PlayerNextEpisodeAvailability(hasPrev: hasPrev, hasNext: hasNext);
  }

  String _buildTitleText() {
    final detail = widget.detail;
    final list = detail?.list;
    final originIndex = _playVideoIdsStore?.originIndex ?? 0;
    final teleplayIndex = _playVideoIdsStore?.teleplayIndex;
    final linkList =
        list != null && list.isNotEmpty && originIndex < list.length
            ? list[originIndex].linkList
            : null;

    if (teleplayIndex != null &&
        linkList != null &&
        teleplayIndex >= 0 &&
        teleplayIndex < linkList.length) {
      return '${detail?.name ?? ''}-${linkList[teleplayIndex].episode ?? ''}';
    }
    return '${detail?.name ?? ''}-未选择';
  }

  @override
  Widget build(BuildContext context) {
    return _buildViewport(
      isFullscreen: false,
      onToggleFullscreen: _showFullscreen,
    );
  }
}

class _CurrentMedia {
  final int originIndex;
  final int teleplayIndex;
  final int startAt;
  final String url;

  const _CurrentMedia({
    required this.originIndex,
    required this.teleplayIndex,
    required this.startAt,
    required this.url,
  });
}

class PlayerNextEpisodeAvailability {
  final bool hasPrev;
  final bool hasNext;

  const PlayerNextEpisodeAvailability({
    required this.hasPrev,
    required this.hasNext,
  });
}

Duration _clampDuration(Duration value, Duration min, Duration max) {
  if (value < min) return min;
  if (value > max) return max;
  return value;
}

Duration _bufferedPosition(List<DurationRange> ranges) {
  if (ranges.isEmpty) return Duration.zero;
  Duration maxEnd = Duration.zero;
  for (final range in ranges) {
    if (range.end > maxEnd) {
      maxEnd = range.end;
    }
  }
  return maxEnd;
}
