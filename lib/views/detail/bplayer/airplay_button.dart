import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;

import '/plugins.dart';

const String _airPlayRoutePickerViewType = 'bracket/airplay_route_picker';
const MethodChannel _androidMediaRouteChannel = MethodChannel(
  'bracket/media_route_picker',
);

class AndroidCastMedia {
  final String url;
  final String title;
  final String? subtitle;
  final int positionSeconds;
  final String? posterUrl;

  const AndroidCastMedia({
    required this.url,
    required this.title,
    this.subtitle,
    this.positionSeconds = 0,
    this.posterUrl,
  });

  Map<String, dynamic> toMap() {
    return {
      'url': url,
      'title': title,
      'subtitle': subtitle,
      'positionSeconds': positionSeconds,
      'posterUrl': posterUrl,
    };
  }
}

@immutable
class AndroidCastSession {
  final String deviceName;
  final String routeType;

  const AndroidCastSession({
    required this.deviceName,
    required this.routeType,
  });
}

@immutable
class AndroidCastPlaybackStatus {
  final String deviceName;
  final String routeType;
  final String transportState;
  final int positionSeconds;
  final int durationSeconds;

  const AndroidCastPlaybackStatus({
    required this.deviceName,
    required this.routeType,
    required this.transportState,
    required this.positionSeconds,
    required this.durationSeconds,
  });

  bool get isPlaying => transportState == 'PLAYING';

  bool get isTerminal =>
      transportState == 'STOPPED' ||
      transportState == 'NO_MEDIA_PRESENT' ||
      transportState == 'ENDED';

  static AndroidCastPlaybackStatus? fromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    final deviceName = map['name'] as String?;
    if (deviceName == null || deviceName.isEmpty) return null;
    return AndroidCastPlaybackStatus(
      deviceName: deviceName,
      routeType: (map['type'] as String?) ?? 'dlna',
      transportState: (map['transportState'] as String?) ?? 'UNKNOWN',
      positionSeconds: (map['positionSeconds'] as num?)?.toInt() ?? 0,
      durationSeconds: (map['durationSeconds'] as num?)?.toInt() ?? 0,
    );
  }
}

class AndroidCastBridge {
  const AndroidCastBridge._();

  static Future<AndroidCastSession?> recastOnActiveDevice(
    AndroidCastMedia media,
  ) async {
    final response =
        await _androidMediaRouteChannel.invokeMapMethod<String, dynamic>(
      'recastOnActiveDevice',
      media.toMap(),
    );
    if (response == null) return null;
    final deviceName = response['name'] as String?;
    if (deviceName == null || deviceName.isEmpty) return null;
    return AndroidCastSession(
      deviceName: deviceName,
      routeType: (response['type'] as String?) ?? 'dlna',
    );
  }

  static Future<AndroidCastPlaybackStatus?> queryActivePlaybackStatus() async {
    final response =
        await _androidMediaRouteChannel.invokeMapMethod<String, dynamic>(
      'queryActiveCastStatus',
    );
    return AndroidCastPlaybackStatus.fromMap(response);
  }

  static Future<void> clearActiveSession() async {
    await _androidMediaRouteChannel
        .invokeMethod<void>('clearActiveCastSession');
  }

  static Future<void> stopActiveSession() async {
    await _androidMediaRouteChannel.invokeMethod<void>('stopActiveCastSession');
  }
}

class AirPlayRoutePickerButton extends StatelessWidget {
  final double size;
  final double iconScale;
  final Color iconColor;
  final Color activeIconColor;
  final Color backgroundColor;
  final EdgeInsetsGeometry padding;
  final BorderRadiusGeometry borderRadius;
  final AndroidCastMedia? androidMedia;
  final AndroidCastMedia? Function()? androidMediaBuilder;
  final Future<void> Function(AndroidCastSession session)?
      onAndroidCastConnected;
  final bool active;

  const AirPlayRoutePickerButton({
    super.key,
    this.size = 32,
    this.iconScale = 1.0,
    this.iconColor = Colors.white,
    this.activeIconColor = Colors.white,
    this.backgroundColor = Colors.transparent,
    this.padding = const EdgeInsets.all(4),
    this.borderRadius = const BorderRadius.all(Radius.circular(999)),
    this.androidMedia,
    this.androidMediaBuilder,
    this.onAndroidCastConnected,
    this.active = false,
  });

  static bool get isSupported => Platform.isIOS || Platform.isAndroid;

  @override
  Widget build(BuildContext context) {
    if (!isSupported) {
      return const SizedBox.shrink();
    }

    if (Platform.isAndroid) {
      final resolvedPadding = padding.resolve(Directionality.of(context));
      final resolvedIconColor = active ? activeIconColor : iconColor;
      final iconSize = max(
            16.0,
            size - max(resolvedPadding.horizontal, resolvedPadding.vertical),
          ) *
          iconScale.clamp(0.6, 1.0);
      final hasCustomBackground = backgroundColor.a > 0;
      final baseBackground =
          hasCustomBackground ? backgroundColor : const Color(0x29000000);
      final resolvedBackground = active
          ? Color.alphaBlend(const Color(0x33FF7A1A), baseBackground)
          : baseBackground;
      final resolvedBorderColor = active
          ? activeIconColor.withValues(alpha: 0.42)
          : resolvedIconColor.withValues(
              alpha: hasCustomBackground ? 0.14 : 0.18);

      return SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: resolvedBackground,
            borderRadius: borderRadius,
            border: Border.all(color: resolvedBorderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: borderRadius.resolve(Directionality.of(context)),
              onTap: () async {
                final media = androidMediaBuilder?.call() ?? androidMedia;
                if (media == null) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('当前视频暂不支持投屏')),
                  );
                  return;
                }

                final uri = Uri.tryParse(media.url);
                final isSupportedMedia = uri != null &&
                    (uri.scheme == 'http' || uri.scheme == 'https');

                if (!isSupportedMedia) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('当前视频暂不支持投屏')),
                  );
                  return;
                }

                final castMedia = media;
                try {
                  final response = await _androidMediaRouteChannel
                      .invokeMapMethod<String, dynamic>(
                    'presentDevicePicker',
                    castMedia.toMap(),
                  );
                  if (!context.mounted || response == null) return;
                  final deviceName = response['name'] as String?;
                  if (deviceName != null && deviceName.isNotEmpty) {
                    final session = AndroidCastSession(
                      deviceName: deviceName,
                      routeType: (response['type'] as String?) ?? 'dlna',
                    );
                    final onAndroidCastConnected = this.onAndroidCastConnected;
                    if (onAndroidCastConnected != null) {
                      await onAndroidCastConnected(session);
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('已发送到 $deviceName')),
                    );
                  }
                } on PlatformException catch (error) {
                  if (error.code == 'cancelled') {
                    return;
                  }
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(error.message ?? '无法打开投屏设备列表'),
                    ),
                  );
                }
              },
              child: Padding(
                padding: padding,
                child: Icon(
                  Icons.cast_rounded,
                  size: iconSize,
                  color: resolvedIconColor,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: borderRadius,
        ),
        child: Padding(
          padding: padding,
          child: UiKitView(
            viewType: _airPlayRoutePickerViewType,
            hitTestBehavior: PlatformViewHitTestBehavior.opaque,
            creationParams: {
              'tintColor': iconColor.toARGB32(),
              'activeTintColor': activeIconColor.toARGB32(),
              'iconScale': iconScale.clamp(0.6, 1.0),
            },
            creationParamsCodec: const StandardMessageCodec(),
          ),
        ),
      ),
    );
  }
}
