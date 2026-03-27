import '/plugins.dart';

enum _HomeTabStatusKind { loading, error, empty }

class HomeTabStatusView extends StatelessWidget {
  final _HomeTabStatusKind _kind;
  final VoidCallback? onRetry;

  const HomeTabStatusView.loading({super.key})
      : _kind = _HomeTabStatusKind.loading,
        onRetry = null;

  const HomeTabStatusView.error({
    super.key,
    required this.onRetry,
  }) : _kind = _HomeTabStatusKind.error;

  const HomeTabStatusView.empty({
    super.key,
    required this.onRetry,
  }) : _kind = _HomeTabStatusKind.empty;

  bool get _isLoading => _kind == _HomeTabStatusKind.loading;

  String get _title {
    switch (_kind) {
      case _HomeTabStatusKind.loading:
        return '正在加载';
      case _HomeTabStatusKind.error:
        return '加载失败';
      case _HomeTabStatusKind.empty:
        return '暂无内容';
    }
  }

  String _message(bool compact) {
    switch (_kind) {
      case _HomeTabStatusKind.loading:
        return compact ? '正在获取最新内容' : '正在获取最新内容，请稍候';
      case _HomeTabStatusKind.error:
        return compact ? '网络波动或片源异常，请重试' : '网络波动或片源异常，稍后再试一次';
      case _HomeTabStatusKind.empty:
        return compact ? '当前暂无可展示内容' : '当前片源还没有可展示内容，可以重新拉取看看';
    }
  }

  String get _buttonLabel {
    switch (_kind) {
      case _HomeTabStatusKind.loading:
        return '';
      case _HomeTabStatusKind.error:
        return '重新加载';
      case _HomeTabStatusKind.empty:
        return '刷新内容';
    }
  }

  Widget _buildCard(
    BuildContext context, {
    required bool compact,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = colorScheme.primary;
    final panelColor = colorScheme.brightness == Brightness.dark
        ? colorScheme.surfaceContainerLow
        : Colors.white;
    final horizontalPadding = compact ? 14.0 : 24.0;
    final verticalTopPadding = compact ? 14.0 : 24.0;
    final verticalBottomPadding = compact ? 14.0 : 22.0;
    final titleSize = compact ? 15.0 : 22.0;
    final messageSize = compact ? 11.0 : 14.0;
    final messageTopSpacing = compact ? 4.0 : 10.0;
    final buttonTopSpacing = compact ? 10.0 : 20.0;
    final buttonHeight = compact ? 36.0 : 48.0;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: compact ? 236 : 320,
        minWidth: compact ? 196 : 240,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: panelColor,
          borderRadius: BorderRadius.circular(compact ? 20 : 28),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.45),
          ),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            verticalTopPadding,
            horizontalPadding,
            verticalBottomPadding,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _title,
                style: TextStyle(
                  fontSize: titleSize,
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onSurface,
                ),
              ),
              SizedBox(height: messageTopSpacing),
              Text(
                _message(compact),
                textAlign: TextAlign.center,
                maxLines: compact ? 2 : null,
                overflow:
                    compact ? TextOverflow.ellipsis : TextOverflow.visible,
                style: TextStyle(
                  height: compact ? 1.2 : 1.45,
                  fontSize: messageSize,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              if (_isLoading) ...[
                SizedBox(height: buttonTopSpacing),
                SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation<Color>(accent),
                  ),
                ),
              ],
              if (!_isLoading) ...[
                SizedBox(height: buttonTopSpacing),
                FilledButton(
                  onPressed: onRetry,
                  style: FilledButton.styleFrom(
                    minimumSize: Size.fromHeight(buttonHeight),
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 16 : 24,
                      vertical: compact ? 10 : 14,
                    ),
                    textStyle: TextStyle(
                      fontSize: compact ? 14 : 16,
                      fontWeight: FontWeight.w700,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(compact ? 14 : 16),
                    ),
                  ),
                  child: Text(_buttonLabel),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomOverlayPadding = MediaQuery.paddingOf(context).bottom;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = max(
          constraints.maxHeight - bottomOverlayPadding,
          0.0,
        );
        final compact = availableHeight < 340 ||
            MediaQuery.orientationOf(context) == Orientation.landscape;

        return CustomScrollView(
          primary: false,
          physics: const NeverScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: SafeArea(
                top: false,
                bottom: false,
                child: Padding(
                  padding: EdgeInsets.only(bottom: bottomOverlayPadding),
                  child: Center(
                    child: _buildCard(
                      context,
                      compact: compact,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
