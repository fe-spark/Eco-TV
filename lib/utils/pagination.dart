class PaginationState {
  final int nextPage;
  final bool isFinished;

  const PaginationState({
    required this.nextPage,
    required this.isFinished,
  });
}

PaginationState resolvePaginationState({
  required int currentPage,
  required int total,
  required int totalPages,
  required int receivedItemCount,
  required int accumulatedItemCount,
}) {
  final reachedLastPage = totalPages > 0 && currentPage >= totalPages;
  final hasNoMoreData = receivedItemCount == 0 || reachedLastPage;
  final isFinished = hasNoMoreData || accumulatedItemCount >= total;

  return PaginationState(
    nextPage: isFinished ? currentPage : currentPage + 1,
    isFinished: isFinished,
  );
}
