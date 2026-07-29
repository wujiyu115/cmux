/// Result of [submitSessionHistoryReviewMessage].
final class HistoryContinueSubmitResult {
  const HistoryContinueSubmitResult({required this.ok});

  const HistoryContinueSubmitResult.failed() : ok = false;

  final bool ok;
}
