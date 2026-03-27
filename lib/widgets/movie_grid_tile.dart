import 'dart:math' as math;

import '/plugins.dart';

const int _movieGridMinimumColumns = 3;
const int _movieGridMaximumColumns = 8;
const double _movieGridPreferredItemWidth = 156;
const double _movieGridMinimumItemWidth = 118;

SliverGridDelegate buildMovieGridDelegate({
  required double availableWidth,
  bool isLandscape = false,
  double mainAxisSpacing = 8,
  double crossAxisSpacing = 8,
  double childAspectRatio = .6,
}) {
  final preferredColumnCount = ((availableWidth + crossAxisSpacing) /
              (_movieGridPreferredItemWidth + crossAxisSpacing))
          .floor() +
      1;
  final maxAllowedColumnsByMinWidth = ((availableWidth + crossAxisSpacing) /
          (_movieGridMinimumItemWidth + crossAxisSpacing))
      .floor();
  final upperBound = math.max(
    _movieGridMinimumColumns,
    math.min(_movieGridMaximumColumns, maxAllowedColumnsByMinWidth),
  );
  final crossAxisCount = math.max(
    _movieGridMinimumColumns,
    preferredColumnCount.clamp(_movieGridMinimumColumns, upperBound),
  );

  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: crossAxisCount,
    mainAxisSpacing: mainAxisSpacing,
    crossAxisSpacing: crossAxisSpacing,
    childAspectRatio: childAspectRatio,
  );
}

class MovieGridTile extends StatelessWidget {
  final dynamic movie;
  final VoidCallback? onTap;

  const MovieGridTile({
    super.key,
    required this.movie,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 1,
            child: Stack(
              children: [
                Container(
                  width: double.infinity,
                  height: double.infinity,
                  clipBehavior: Clip.hardEdge,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(5),
                    color: Colors.grey,
                  ),
                  child: PosterImage(
                    imageUrl: movie?.picture,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                ),
                Positioned(
                  top: 4,
                  left: 4,
                  right: 4,
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      if (movie?.year != null &&
                          movie!.year!.isNotEmpty &&
                          movie.year != '0')
                        Container(
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).primaryColor.withAlpha(200),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Text(
                              movie.year!,
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.fontSize,
                              ),
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                            ),
                          ),
                        ),
                      Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor.withAlpha(200),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Text(
                            movie?.cName ?? '',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.fontSize,
                            ),
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                          ),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor.withAlpha(200),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Text(
                            movie?.remarks ?? '',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.fontSize,
                            ),
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 6, 0, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  movie?.name ?? '',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  textAlign: TextAlign.left,
                ),
                const SizedBox(
                  height: 2,
                ),
                Text(
                  (movie?.subTitle?.trim().isEmpty ?? true)
                      ? '暂无'
                      : movie?.subTitle?.trim() ?? '暂无',
                  style: TextStyle(
                    color: Theme.of(context).disabledColor,
                    fontSize: 10,
                  ),
                  overflow: TextOverflow.ellipsis,
                  softWrap: true,
                  maxLines: 1,
                  textAlign: TextAlign.left,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
