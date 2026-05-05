// import "/views/detail/related.dart";

import '/plugins.dart';
import "package:bracket/model/film_play_info/detail.dart";
import "package:bracket/model/film_play_info/relate.dart";
import 'package:flutter/foundation.dart' show kDebugMode;
import "/model/film_play_info/data.dart" show Data;
import "/model/film_play_info/film_play_info.dart" show FilmPlayInfo;
import "/views/detail/describe.dart" show Describe;
import "bplayer/airplay_button.dart"
    show
        AirPlayRoutePickerButton,
        AndroidCastBridge,
        AndroidCastMedia,
        AndroidCastPlaybackStatus,
        AndroidCastSession;
import "bplayer/player.dart"
    show Player, PlayerPlaybackController, PlayerNextEpisodeAvailability;

import "series.dart";

const bool _debugForceAndroidCastOverlay = false;

class Utils {
  static Future<String> getFileUrl(String fileName) async {
    final directory = await getApplicationDocumentsDirectory();
    return "${directory.path}/$fileName";
  }
}

class DetailPage extends StatefulWidget {
  final Map? arguments;
  const DetailPage({super.key, this.arguments});

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class MyTab {
  final Widget icon;
  final String label;
  final Key key;

  MyTab({required this.icon, required this.label, required this.key});
}

class _ActiveAndroidCastSession {
  final String deviceName;
  final String routeType;
  final String mediaKey;

  const _ActiveAndroidCastSession({
    required this.deviceName,
    required this.routeType,
    required this.mediaKey,
  });

  _ActiveAndroidCastSession copyWith({
    String? deviceName,
    String? routeType,
    String? mediaKey,
  }) {
    return _ActiveAndroidCastSession(
      deviceName: deviceName ?? this.deviceName,
      routeType: routeType ?? this.routeType,
      mediaKey: mediaKey ?? this.mediaKey,
    );
  }
}

class _DetailPageState extends State<DetailPage> {
  final double _playerAspectRatio = 16 / 9;
  final PlayerPlaybackController _playerPlaybackController =
      PlayerPlaybackController();
  final List<MyTab> _tabs = [
    MyTab(icon: const Icon(Icons.abc_outlined), label: '详情', key: UniqueKey()),
    MyTab(
      icon: const Icon(Icons.abc_outlined),
      label: '相关推荐',
      key: UniqueKey(),
    ),
  ];

  Data? _data;
  List<Relate>? _relate;
  bool _relateLoading = false;
  PlayVideoIdsStore? _playVideoIdsStore;
  _ActiveAndroidCastSession? _activeAndroidCastSession;
  Timer? _androidCastStatusTimer;
  String? _lastAndroidCastTransportState;
  int _lastAndroidCastPositionSeconds = 0;
  int _lastAndroidCastDurationSeconds = 0;
  int _androidCastStatusFailureCount = 0;
  bool _syncingActiveAndroidCast = false;
  bool _advancingActiveAndroidCast = false;
  bool _endingActiveAndroidCast = false;
  bool _debugAndroidCastOverlayVisible =
      kDebugMode && _debugForceAndroidCastOverlay;

  int _resolveOriginIndex(Data? data, Map<String, dynamic>? historyItem) {
    final playSourceList = data?.detail?.list;
    if (playSourceList == null || playSourceList.isEmpty) {
      return 0;
    }

    final historyOriginId = historyItem?['originId'];
    if (historyOriginId != null) {
      final historyIndex = playSourceList.indexWhere(
        (element) => historyOriginId == element.id,
      );
      if (historyIndex >= 0) {
        return historyIndex;
      }
    }

    final currentPlayFrom = data?.currentPlayFrom;
    if (currentPlayFrom != null && currentPlayFrom.isNotEmpty) {
      final currentIndex = playSourceList.indexWhere(
        (element) => currentPlayFrom == element.id,
      );
      if (currentIndex >= 0) {
        return currentIndex;
      }
    }

    return 0;
  }

  int _resolveTeleplayIndex(Data? data, Map<String, dynamic>? historyItem) {
    final historyTeleplayIndex = historyItem?['teleplayIndex'];
    if (historyTeleplayIndex is int && historyTeleplayIndex >= 0) {
      return historyTeleplayIndex;
    }

    final currentEpisode = data?.currentEpisode;
    if (currentEpisode != null && currentEpisode >= 0) {
      return currentEpisode;
    }

    return 0;
  }

  Future _fetchData(id) async {
    setState(() {
      _relate = null;
      _relateLoading = true;
    });
    unawaited(_fetchRelate(id));

    var playIdsInfo = context.read<PlayVideoIdsStore>();
    var res = await Api.filmPlayInfo(
      context: context,
      queryParameters: {'id': id},
    );
    if (!mounted) return;
    if (res != null && res.runtimeType != String) {
      FilmPlayInfo jsonData = FilmPlayInfo.fromJson(res);
      setState(() {
        _data = jsonData.data;
      });

      var item = getHistory(id);
      final originIndex = _resolveOriginIndex(_data, item);
      final teleplayIndex = _resolveTeleplayIndex(_data, item);
      final startAt = item?['startAt'] ?? 0;

      playIdsInfo.setVideoInfo(
        originIndex,
        teleplayIndex: teleplayIndex,
        startAt: startAt,
      );
      return;
    }
  }

  Future<void> _fetchRelate(id) async {
    var res = await Api.filmRelate(
      context: context,
      queryParameters: {'id': id},
    );
    if (!mounted) return;
    if (res is Map<String, dynamic>) {
      final rawList = res['data'];
      final relate = rawList is List
          ? rawList
              .whereType<Map>()
              .map((item) => Relate.fromJson(Map<String, dynamic>.from(item)))
              .toList()
          : <Relate>[];
      setState(() {
        _relate = relate;
        _relateLoading = false;
      });
      return;
    }

    setState(() {
      _relate = [];
      _relateLoading = false;
    });
  }

  Map<String, dynamic>? getHistory(id) {
    var data = context.read<HistoryStore>().data;
    var item = data.firstWhereOrNull((element) => element['id'] == id);

    return item;
  }

  AndroidCastMedia? _resolveAndroidCastMedia(
    Detail? detail,
    PlayVideoIdsStore playVideoIdsStore, {
    int positionSeconds = 0,
  }) {
    final list = detail?.list;
    if (detail == null || list == null || list.isEmpty) return null;

    final originIndex = playVideoIdsStore.originIndex.clamp(0, list.length - 1);
    final linkList = list[originIndex].linkList;
    if (linkList == null || linkList.isEmpty) return null;

    final teleplayIndex = (playVideoIdsStore.teleplayIndex ?? 0).clamp(
      0,
      linkList.length - 1,
    );
    final playItem = linkList[teleplayIndex];
    final url = playItem.link;
    if (url == null || url.isEmpty) return null;

    final titleParts = <String>[
      if (detail.name?.trim().isNotEmpty ?? false) detail.name!.trim(),
      if (playItem.episode?.trim().isNotEmpty ?? false)
        playItem.episode!.trim(),
    ];
    final title = titleParts.join(' - ');
    final subtitle = list[originIndex].name;

    return AndroidCastMedia(
      url: url,
      title: title.isEmpty ? 'EcoTV' : title,
      subtitle: subtitle,
      positionSeconds: max(0, positionSeconds),
      posterUrl: detail.picture,
    );
  }

  String? _currentAndroidCastMediaKey() {
    final playVideoIdsStore = _playVideoIdsStore;
    if (playVideoIdsStore == null) return null;
    final media = _resolveAndroidCastMedia(
      _data?.detail,
      playVideoIdsStore,
      positionSeconds: playVideoIdsStore.startAt ?? 0,
    );
    if (media == null) return null;
    return '${playVideoIdsStore.originIndex}:${playVideoIdsStore.teleplayIndex}:${media.url}';
  }

  AndroidCastMedia? _currentAndroidCastMediaForSession() {
    final playVideoIdsStore = _playVideoIdsStore;
    if (playVideoIdsStore == null) return null;
    return _resolveAndroidCastMedia(
      _data?.detail,
      playVideoIdsStore,
      positionSeconds: playVideoIdsStore.startAt ?? 0,
    );
  }

  PlayerNextEpisodeAvailability _currentEpisodeAvailability() {
    final detail = _data?.detail;
    final list = detail?.list;
    final originIndex = _playVideoIdsStore?.originIndex ?? 0;
    final teleplayIndex = _playVideoIdsStore?.teleplayIndex;
    final linkList =
        list != null && list.isNotEmpty && originIndex < list.length
            ? list[originIndex].linkList ?? const []
            : const [];
    final hasPrev = teleplayIndex != null && teleplayIndex > 0;
    final hasNext = teleplayIndex != null &&
        teleplayIndex >= 0 &&
        teleplayIndex < linkList.length - 1;
    return PlayerNextEpisodeAvailability(hasPrev: hasPrev, hasNext: hasNext);
  }

  void _handleSelectedMediaChanged() {
    if (!mounted || _activeAndroidCastSession == null) return;
    unawaited(_syncActiveAndroidCastMedia());
  }

  void _handlePlayerPlaybackChanged() {
    if (!mounted || _activeAndroidCastSession == null) return;
    if (_playerPlaybackController.isPlaying) {
      unawaited(_clearActiveAndroidCastSession());
    }
  }

  bool get _showingDebugAndroidCastOverlay =>
      _activeAndroidCastSession == null && _debugAndroidCastOverlayVisible;

  Future<void> _handleAndroidCastConnected(AndroidCastSession session) async {
    final localWasPlaying = _playerPlaybackController.isPlaying;
    try {
      await _playerPlaybackController.pauseIfPlaying();
    } catch (error) {
      debugPrint('Failed to pause local playback after casting: $error');
    }

    if (!mounted) return;

    final mediaKey = _currentAndroidCastMediaKey();
    if (mediaKey == null) return;

    setState(() {
      _activeAndroidCastSession = _ActiveAndroidCastSession(
        deviceName: session.deviceName,
        routeType: session.routeType,
        mediaKey: mediaKey,
      );
      _lastAndroidCastTransportState = null;
      _lastAndroidCastPositionSeconds = 0;
      _lastAndroidCastDurationSeconds = 0;
      _androidCastStatusFailureCount = 0;
      _advancingActiveAndroidCast = false;
      _endingActiveAndroidCast = false;
    });
    _startAndroidCastStatusPolling();

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          localWasPlaying
              ? '已投屏到 ${session.deviceName}，本地播放已暂停'
              : '已投屏到 ${session.deviceName}',
        ),
      ),
    );
  }

  @override
  void initState() {
    int id = widget.arguments?['id'];
    super.initState();
    _playVideoIdsStore = context.read<PlayVideoIdsStore>();
    _playVideoIdsStore?.addListener(_handleSelectedMediaChanged);
    _playerPlaybackController.addListener(_handlePlayerPlaybackChanged);
    // _saveAssetVideoToFile();
    _fetchData(id);
  }

  @override
  void dispose() {
    _androidCastStatusTimer?.cancel();
    if (Platform.isAndroid) {
      unawaited(AndroidCastBridge.clearActiveSession());
    }
    _playVideoIdsStore?.removeListener(_handleSelectedMediaChanged);
    _playerPlaybackController.removeListener(_handlePlayerPlaybackChanged);
    _playerPlaybackController.dispose();
    super.dispose();
  }

  void _startAndroidCastStatusPolling() {
    _androidCastStatusTimer?.cancel();
    if (!Platform.isAndroid || _activeAndroidCastSession == null) return;
    _androidCastStatusTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_pollActiveAndroidCastStatus()),
    );
    unawaited(_pollActiveAndroidCastStatus());
  }

  Future<void> _pollActiveAndroidCastStatus() async {
    if (!mounted ||
        !Platform.isAndroid ||
        _activeAndroidCastSession == null ||
        _syncingActiveAndroidCast ||
        _advancingActiveAndroidCast ||
        _endingActiveAndroidCast) {
      return;
    }

    try {
      final status = await AndroidCastBridge.queryActivePlaybackStatus();
      if (!mounted || _activeAndroidCastSession == null) return;
      if (status == null) {
        await _clearActiveAndroidCastSession(clearNative: false);
        return;
      }

      _androidCastStatusFailureCount = 0;
      final shouldAdvance = _shouldAdvanceForActiveAndroidCast(status);

      setState(() {
        _activeAndroidCastSession = _activeAndroidCastSession?.copyWith(
          deviceName: status.deviceName,
          routeType: status.routeType,
        );
        _lastAndroidCastTransportState = status.transportState;
        _lastAndroidCastPositionSeconds = status.positionSeconds;
        _lastAndroidCastDurationSeconds = status.durationSeconds;
      });

      if (shouldAdvance) {
        await _advanceActiveAndroidCastEpisode();
      }
    } on PlatformException catch (error) {
      debugPrint('Failed to query cast status: ${error.message ?? error.code}');
      _androidCastStatusFailureCount += 1;
      if (_androidCastStatusFailureCount >= 2) {
        await _clearActiveAndroidCastSession(clearNative: false);
      }
    } catch (error) {
      debugPrint('Failed to query cast status: $error');
      _androidCastStatusFailureCount += 1;
      if (_androidCastStatusFailureCount >= 2) {
        await _clearActiveAndroidCastSession(clearNative: false);
      }
    }
  }

  bool _shouldAdvanceForActiveAndroidCast(AndroidCastPlaybackStatus status) {
    final previousState = _lastAndroidCastTransportState;
    final previousNearEnd = _lastAndroidCastDurationSeconds > 0 &&
        _lastAndroidCastPositionSeconds >= _lastAndroidCastDurationSeconds - 3;
    final currentNearEnd = status.durationSeconds > 0 &&
        status.positionSeconds >= status.durationSeconds - 2;

    return status.isTerminal &&
        !_advancingActiveAndroidCast &&
        (currentNearEnd || (previousState == 'PLAYING' && previousNearEnd));
  }

  Future<void> _advanceActiveAndroidCastEpisode() async {
    final debugOverlayOnly = _showingDebugAndroidCastOverlay;
    if (!mounted ||
        _advancingActiveAndroidCast ||
        (_activeAndroidCastSession == null && !debugOverlayOnly)) {
      return;
    }

    final availability = _currentEpisodeAvailability();
    if (!availability.hasNext) {
      await _clearActiveAndroidCastSession();
      return;
    }

    final playVideoIdsStore = _playVideoIdsStore;
    final teleplayIndex = playVideoIdsStore?.teleplayIndex;
    if (playVideoIdsStore == null || teleplayIndex == null) return;

    if (!debugOverlayOnly) {
      setState(() {
        _advancingActiveAndroidCast = true;
      });
    }

    playVideoIdsStore.setVideoInfo(
      playVideoIdsStore.originIndex,
      teleplayIndex: teleplayIndex + 1,
      startAt: 0,
    );
  }

  Future<void> _retreatActiveAndroidCastEpisode() async {
    final debugOverlayOnly = _showingDebugAndroidCastOverlay;
    if (!mounted ||
        _advancingActiveAndroidCast ||
        (_activeAndroidCastSession == null && !debugOverlayOnly)) {
      return;
    }

    final availability = _currentEpisodeAvailability();
    if (!availability.hasPrev) {
      return;
    }

    final playVideoIdsStore = _playVideoIdsStore;
    final teleplayIndex = playVideoIdsStore?.teleplayIndex;
    if (playVideoIdsStore == null || teleplayIndex == null) return;

    if (!debugOverlayOnly) {
      setState(() {
        _advancingActiveAndroidCast = true;
      });
    }

    playVideoIdsStore.setVideoInfo(
      playVideoIdsStore.originIndex,
      teleplayIndex: teleplayIndex - 1,
      startAt: 0,
    );
  }

  Future<void> _syncActiveAndroidCastMedia() async {
    final activeSession = _activeAndroidCastSession;
    if (!mounted || !Platform.isAndroid || activeSession == null) return;

    final mediaKey = _currentAndroidCastMediaKey();
    final media = _currentAndroidCastMediaForSession();
    if (mediaKey == null || media == null) {
      await _clearActiveAndroidCastSession();
      return;
    }
    if (_syncingActiveAndroidCast || mediaKey == activeSession.mediaKey) {
      return;
    }

    _syncingActiveAndroidCast = true;
    try {
      final session = await AndroidCastBridge.recastOnActiveDevice(media);
      if (!mounted || _activeAndroidCastSession == null) return;
      if (session == null) {
        await _clearActiveAndroidCastSession(clearNative: false);
        return;
      }

      try {
        await _playerPlaybackController.pauseIfPlaying();
      } catch (error) {
        debugPrint('Failed to pause local playback during recast: $error');
      }

      if (!mounted || _activeAndroidCastSession == null) return;
      setState(() {
        _activeAndroidCastSession = _activeAndroidCastSession?.copyWith(
          deviceName: session.deviceName,
          routeType: session.routeType,
          mediaKey: mediaKey,
        );
        _lastAndroidCastTransportState = null;
        _lastAndroidCastPositionSeconds = 0;
        _lastAndroidCastDurationSeconds = 0;
        _androidCastStatusFailureCount = 0;
        _advancingActiveAndroidCast = false;
        _endingActiveAndroidCast = false;
      });
      _startAndroidCastStatusPolling();
    } on PlatformException catch (error) {
      debugPrint(
        'Failed to recast active media: ${error.message ?? error.code}',
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text(error.message ?? '投屏切集失败')),
      );
      await _clearActiveAndroidCastSession(clearNative: false);
    } catch (error) {
      debugPrint('Failed to recast active media: $error');
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(content: Text('投屏切集失败')));
      await _clearActiveAndroidCastSession(clearNative: false);
    } finally {
      _syncingActiveAndroidCast = false;
      final latestKey = _currentAndroidCastMediaKey();
      final latestSession = _activeAndroidCastSession;
      if (mounted &&
          latestSession != null &&
          latestKey != null &&
          latestKey != latestSession.mediaKey &&
          !_syncingActiveAndroidCast) {
        unawaited(_syncActiveAndroidCastMedia());
      }
    }
  }

  Future<void> _clearActiveAndroidCastSession({bool clearNative = true}) async {
    _androidCastStatusTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _activeAndroidCastSession = null;
      _lastAndroidCastTransportState = null;
      _lastAndroidCastPositionSeconds = 0;
      _lastAndroidCastDurationSeconds = 0;
      _androidCastStatusFailureCount = 0;
      _syncingActiveAndroidCast = false;
      _advancingActiveAndroidCast = false;
      _endingActiveAndroidCast = false;
    });
    if (clearNative && Platform.isAndroid) {
      try {
        await AndroidCastBridge.clearActiveSession();
      } catch (error) {
        debugPrint('Failed to clear cast session: $error');
      }
    }
  }

  Future<void> _stopActiveAndroidCastSession() async {
    final debugOverlayOnly = _showingDebugAndroidCastOverlay;
    if (!mounted || _endingActiveAndroidCast) {
      return;
    }

    if (debugOverlayOnly) {
      setState(() {
        _debugAndroidCastOverlayVisible = false;
      });
      return;
    }

    if (!Platform.isAndroid || _activeAndroidCastSession == null) {
      return;
    }

    final messenger = ScaffoldMessenger.maybeOf(context);
    _androidCastStatusTimer?.cancel();
    setState(() {
      _endingActiveAndroidCast = true;
    });

    try {
      await AndroidCastBridge.stopActiveSession();
      if (!mounted) return;
      await _clearActiveAndroidCastSession(clearNative: false);

      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(const SnackBar(content: Text('已结束投屏')));
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _endingActiveAndroidCast = false;
      });
      _startAndroidCastStatusPolling();

      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(
        SnackBar(content: Text(error.message ?? '结束投屏失败')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _endingActiveAndroidCast = false;
      });
      _startAndroidCastStatusPolling();

      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(const SnackBar(content: Text('结束投屏失败')));
    }
  }

  Widget _buildAndroidCastOverlay() {
    final availability = _currentEpisodeAvailability();
    final actionBusy = _syncingActiveAndroidCast ||
        _advancingActiveAndroidCast ||
        _endingActiveAndroidCast;

    Widget buildCircleAction({
      required IconData icon,
      required String tooltip,
      required double size,
      required bool primary,
      required VoidCallback? onTap,
    }) {
      final enabled = onTap != null;
      final backgroundColor = primary
          ? (enabled
              ? const Color(0xFFFF8A2B)
              : Colors.white.withValues(alpha: 0.10))
          : Colors.black.withValues(alpha: enabled ? 0.28 : 0.16);
      final iconColor = primary
          ? Colors.white.withValues(alpha: enabled ? 1 : 0.44)
          : Colors.white.withValues(alpha: enabled ? 0.92 : 0.34);
      final borderColor = primary
          ? Colors.transparent
          : Colors.white.withValues(alpha: enabled ? 0.18 : 0.08);

      return Tooltip(
        message: tooltip,
        child: SizedBox.square(
          dimension: size,
          child: Semantics(
            button: true,
            enabled: enabled,
            label: tooltip,
            child: GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: backgroundColor,
                  border: Border.all(color: borderColor),
                  boxShadow: primary && enabled
                      ? [
                          BoxShadow(
                            color: const Color(
                              0xFFFF8A2B,
                            ).withValues(alpha: 0.34),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Icon(
                    icon,
                    size: size * (primary ? 0.42 : 0.4),
                    color: iconColor,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: Color(0xFF151B22),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF202833), Color(0xFF12171E)],
            ),
          ),
          child: LayoutBuilder(
            builder: (context, overlayConstraints) {
              final compact = overlayConstraints.maxHeight < 240 ||
                  overlayConstraints.maxWidth < 320;
              final primarySize = compact ? 58.0 : 66.0;
              final secondarySize = compact ? 44.0 : 50.0;
              final gap = compact ? 10.0 : 14.0;
              final stackGap = compact ? 12.0 : 16.0;
              final horizontalPadding = compact ? 14.0 : 18.0;
              final verticalPadding = compact ? 10.0 : 12.0;
              final sideInset = compact ? 14.0 : 22.0;
              final controlsOffsetY = compact ? 24.0 : 34.0;

              return Center(
                child: Transform.translate(
                  offset: Offset(0, controlsOffsetY),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: sideInset),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xCC17191F),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.10),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.22),
                                blurRadius: 24,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: horizontalPadding,
                              vertical: verticalPadding,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                buildCircleAction(
                                  icon: Icons.skip_previous_rounded,
                                  tooltip: '上一集',
                                  size: secondarySize,
                                  primary: false,
                                  onTap: availability.hasPrev && !actionBusy
                                      ? () {
                                          unawaited(
                                            _retreatActiveAndroidCastEpisode(),
                                          );
                                        }
                                      : null,
                                ),
                                SizedBox(width: gap),
                                buildCircleAction(
                                  icon: actionBusy
                                      ? Icons.sync_rounded
                                      : Icons.skip_next_rounded,
                                  tooltip: '下一集',
                                  size: primarySize,
                                  primary: true,
                                  onTap: availability.hasNext && !actionBusy
                                      ? () {
                                          unawaited(
                                            _advanceActiveAndroidCastEpisode(),
                                          );
                                        }
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(height: stackGap),
                        buildCircleAction(
                          icon: _endingActiveAndroidCast
                              ? Icons.sync_disabled_rounded
                              : Icons.cancel_presentation_rounded,
                          tooltip: _endingActiveAndroidCast ? '结束中' : '结束投屏',
                          size: secondarySize,
                          primary: false,
                          onTap: actionBusy
                              ? null
                              : () {
                                  unawaited(_stopActiveAndroidCastSession());
                                },
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Detail? detail = _data?.detail;
    final playVideoIdsStore = context.watch<PlayVideoIdsStore>();
    final tabContentOverlap = 1 / MediaQuery.devicePixelRatioOf(context);
    final androidCastMedia = _resolveAndroidCastMedia(
      detail,
      playVideoIdsStore,
      positionSeconds: _playerPlaybackController.positionSeconds,
    );
    final showCastButton = AirPlayRoutePickerButton.isSupported &&
        (Platform.isIOS || androidCastMedia != null);
    final activeAndroidCastSession = _activeAndroidCastSession;
    final debugAndroidCastSession = _showingDebugAndroidCastOverlay
        ? const _ActiveAndroidCastSession(
            deviceName: '调试投屏设备',
            routeType: 'debug',
            mediaKey: 'debug',
          )
        : null;
    final presentedAndroidCastSession =
        activeAndroidCastSession ?? debugAndroidCastSession;
    final showAndroidCastStatus = presentedAndroidCastSession != null;

    return Scaffold(
      // floatingActionButton: FloatingActionButton(
      //   onPressed: () {},
      //   child: const Icon(Icons.expand),
      // ),
      body: OrientationBuilder(
        builder: (context, orientation) {
          return Flex(
            direction: orientation == Orientation.portrait
                ? Axis.vertical
                : Axis.horizontal,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: orientation == Orientation.portrait ? 0 : 1,
                child: Container(
                  decoration: const BoxDecoration(color: Colors.black),
                  child: SafeArea(
                    bottom: orientation != Orientation.portrait,
                    right: orientation == Orientation.portrait,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        Size size = MediaQuery.of(context).size;
                        double width = constraints.maxWidth;
                        double height = constraints.maxHeight;
                        double aspectRatio = orientation == Orientation.portrait
                            ? _playerAspectRatio
                            : width / height;
                        double fullScreenAspectRatio = size.width / size.height;

                        return Stack(
                          children: [
                            AspectRatio(
                              aspectRatio: aspectRatio,
                              child: detail == null
                                  ? const RiveLoading()
                                  : Player(
                                      externalPlaybackActive:
                                          presentedAndroidCastSession != null,
                                      aspectRatio: aspectRatio,
                                      fullScreenAspectRatio:
                                          fullScreenAspectRatio,
                                      detail: detail,
                                      playbackController:
                                          _playerPlaybackController,
                                    ),
                            ),
                            if (presentedAndroidCastSession != null)
                              _buildAndroidCastOverlay(),
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: Row(
                                  children: [
                                    BackButton(
                                      color: Colors.white,
                                      onPressed: () {
                                        Navigator.of(context).pop();
                                      },
                                    ),
                                    const Spacer(),
                                    if (showAndroidCastStatus)
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 176,
                                        ),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0x593B2209),
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                            border: Border.all(
                                              color: const Color(0x80FF9A3D),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                Icons.cast_connected_rounded,
                                                size: 16,
                                                color: Color(0xFFFFB067),
                                              ),
                                              const SizedBox(width: 6),
                                              Flexible(
                                                child: Text(
                                                  presentedAndroidCastSession
                                                      .deviceName,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    if (showAndroidCastStatus)
                                      const SizedBox(width: 8),
                                    if (showCastButton)
                                      SizedBox.square(
                                        dimension: kMinInteractiveDimension,
                                        child: Center(
                                          child: AirPlayRoutePickerButton(
                                            size: 34,
                                            iconScale: 0.94,
                                            padding: const EdgeInsets.all(6),
                                            active: showAndroidCastStatus,
                                            activeIconColor: const Color(
                                              0xFFFFB067,
                                            ),
                                            backgroundColor: const Color(
                                              0x59000000,
                                            ),
                                            androidMediaBuilder: () =>
                                                _resolveAndroidCastMedia(
                                              _data?.detail,
                                              context.read<PlayVideoIdsStore>(),
                                              positionSeconds:
                                                  _playerPlaybackController
                                                      .positionSeconds,
                                            ),
                                            androidMedia: androidCastMedia,
                                            onAndroidCastConnected: Platform
                                                    .isAndroid
                                                ? _handleAndroidCastConnected
                                                : null,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
              if (orientation == Orientation.portrait)
                Container(
                  height: 8,
                  color: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                )
              else
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Container(
                    width: 0.5,
                    color: Theme.of(context).dividerColor,
                  ),
                ),
              Expanded(
                flex: 1,
                child: SafeArea(
                  top: false,
                  left: orientation == Orientation.portrait,
                  child: DefaultTabController(
                    length: _tabs.length,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ColoredBox(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          child: TabBar(
                            tabAlignment: TabAlignment.start,
                            isScrollable: true,
                            dividerColor: Colors.transparent,
                            dividerHeight: 0,
                            tabs: _tabs
                                .map<Tab>(
                                  (MyTab e) => Tab(
                                    key: e.key,
                                    child: Text(
                                      e.label,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: ClipRect(
                            child: Transform.translate(
                              offset: Offset(0, -tabContentOverlap),
                              child: ColoredBox(
                                color: Theme.of(
                                  context,
                                ).scaffoldBackgroundColor,
                                child: TabBarView(
                                  children: [
                                    Series(data: _data),
                                    Describe(
                                      data: _data,
                                      relate: _relate,
                                      relateLoading: _relateLoading,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
