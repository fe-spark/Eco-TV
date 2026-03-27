// import '/model/index/child.dart';
import '/model/index/data.dart';
import '/model/index/content.dart';
import '/views/home/status_view.dart';
import '/views/home/tabs/recommend/search/search_bar.dart';
import '/views/home/tabs/recommend/test.dart';
// import 'search/sliver_search_app_bar.dart';

import '/plugins.dart';
// import './search.dart';
import './movies.dart';
// import './swiper.dart';
// import 'search_test.dart';

class RecommendTab extends StatefulWidget {
  const RecommendTab({super.key});

  @override
  State<RecommendTab> createState() => _RecommendTabState();
}

class _RecommendTabState extends State<RecommendTab>
    with AutomaticKeepAliveClientMixin {
  final GlobalKey<RefreshIndicatorState> _refreshKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();
  Data? _data;
  bool _error = false;
  bool _loading = true;

  double _responsiveValue({
    required double compact,
    required double regular,
    required double viewportHeight,
  }) {
    const compactHeight = 390.0;
    const regularHeight = 844.0;
    final t =
        ((viewportHeight - compactHeight) / (regularHeight - compactHeight))
            .clamp(0.0, 1.0);
    return compact + (regular - compact) * t;
  }

  List<Content> get _content {
    return _data?.content ?? [];
  }

  bool get _hasContent => _content.isNotEmpty;

  Future _fetchData() async {
    setState(() {
      _loading = true;
      _error = false;
    });

    try {
      final res = await Api.index(
        context: context,
      );

      if (res != null && res is! String) {
        final jsonData = Recommend.fromJson(res);
        setState(() {
          _data = jsonData.data;
          _error = false;
          _loading = false;
        });
        _resetScrollIfLocked();
        return;
      }
    } catch (_) {
      // Leave the page in the same empty/error state instead of hanging in loading.
    }

    setState(() {
      _data = null;
      _error = true;
      _loading = false;
    });
    _resetScrollIfLocked();
  }

  bool get _shouldAllowScroll => !_loading && !_error && _hasContent;

  void _resetScrollIfLocked() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _shouldAllowScroll || !_scrollController.hasClients) {
        return;
      }
      _scrollController.jumpTo(0);
    });
  }

  SearchHeader _buildSearchHeader({
    required double headerMinHeight,
    required double headerMaxHeight,
    required double searchContainerHeight,
    required double searchContainerWidth,
    required double searchBottomPadding,
    required double headerBorderRadius,
    required double safeAreaTopInset,
    required EdgeInsets titlePadding,
    required double expandedTitleSize,
    required double collapsedTitleSize,
    required double searchBarHeight,
  }) {
    return SearchHeader(
      title: '推荐',
      minTopBarHeight: headerMinHeight,
      maxTopBarHeight: headerMaxHeight,
      searchContainerHeight: searchContainerHeight,
      searchContainerWidth: searchContainerWidth,
      searchBottomPadding: searchBottomPadding,
      borderRadius: headerBorderRadius,
      safeAreaTopInset: safeAreaTopInset,
      titlePadding: titlePadding,
      titleStyle: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: expandedTitleSize,
      ),
      collapsedTitleStyle: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: collapsedTitleSize,
      ),
      search: SearchAppBar(
        height: searchBarHeight,
      ),
    );
  }

  @override
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      _fetchData();
    });
    super.initState();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void setState(fn) {
    if (mounted) {
      super.setState(fn);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final mediaSize = MediaQuery.sizeOf(context);
    final viewportHeight = mediaSize.height;
    final mediaPadding = MediaQuery.paddingOf(context);
    final safeAreaTopInset = mediaPadding.top;
    final collapsedTitleSize = _responsiveValue(
      compact: 22,
      regular: 26,
      viewportHeight: viewportHeight,
    );
    final expandedTitleSize = _responsiveValue(
      compact: 32,
      regular: 44,
      viewportHeight: viewportHeight,
    );
    final headerMinHeight = max(
      _responsiveValue(
        compact: 72,
        regular: 100,
        viewportHeight: viewportHeight,
      ),
      safeAreaTopInset +
          (collapsedTitleSize * 1.2) +
          _responsiveValue(
            compact: 8,
            regular: 12,
            viewportHeight: viewportHeight,
          ),
    );
    final searchContainerHeight = _responsiveValue(
      compact: 42,
      regular: 50,
      viewportHeight: viewportHeight,
    );
    final searchBottomPadding = _responsiveValue(
      compact: 8,
      regular: 10,
      viewportHeight: viewportHeight,
    );
    final headerMaxHeight = max(
      _responsiveValue(
        compact: 112,
        regular: 200,
        viewportHeight: viewportHeight,
      ),
      headerMinHeight +
          _responsiveValue(
            compact: 20,
            regular: 56,
            viewportHeight: viewportHeight,
          ),
    );
    final bottomNavigationInset = mediaPadding.bottom;
    final searchContainerWidth =
        (mediaSize.width * 0.52).clamp(180.0, 240.0).toDouble();
    final headerBorderRadius = _responsiveValue(
      compact: 24,
      regular: 36,
      viewportHeight: viewportHeight,
    );
    final titlePadding = EdgeInsets.only(
      top: _responsiveValue(
        compact: 10,
        regular: 20,
        viewportHeight: viewportHeight,
      ),
      bottom: _responsiveValue(
        compact: 16,
        regular: 28,
        viewportHeight: viewportHeight,
      ),
    );
    final searchBarHeight = _responsiveValue(
      compact: 38,
      regular: 44,
      viewportHeight: viewportHeight,
    );
    final searchHeader = _buildSearchHeader(
      headerMinHeight: headerMinHeight,
      headerMaxHeight: headerMaxHeight,
      searchContainerHeight: searchContainerHeight,
      searchContainerWidth: searchContainerWidth,
      searchBottomPadding: searchBottomPadding,
      headerBorderRadius: headerBorderRadius,
      safeAreaTopInset: safeAreaTopInset,
      titlePadding: titlePadding,
      expandedTitleSize: expandedTitleSize,
      collapsedTitleSize: collapsedTitleSize,
      searchBarHeight: searchBarHeight,
    );

    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: false,
        child: NestedScrollView(
          controller: _scrollController,
          physics: _shouldAllowScroll
              ? const ClampingScrollPhysics()
              : const NeverScrollableScrollPhysics(),
          headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
            return [
              SliverPersistentHeader(
                pinned: true,
                delegate: searchHeader,
              ),
            ];
          },
          body: Consumer2<UserStore, ThemeStore>(
            builder: (_, profile, global, child) {
              if (_loading) {
                return const HomeTabStatusView.loading();
              }

              if (_error) {
                return HomeTabStatusView.error(
                  onRetry: _fetchData,
                );
              }

              if (!_hasContent) {
                return HomeTabStatusView.empty(
                  onRetry: _fetchData,
                );
              }

              return RefreshIndicator(
                key: _refreshKey,
                onRefresh: () async {
                  return await _fetchData();
                },
                child: _buildContentList(bottomNavigationInset),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;

  Widget _buildContentList(double bottomNavigationInset) {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(
        parent: ClampingScrollPhysics(),
      ),
      padding: EdgeInsets.only(bottom: bottomNavigationInset),
      itemCount: _content.length,
      itemBuilder: (context, index) {
        return MovieGrid(content: _content[index]);
      },
    );
  }
}
