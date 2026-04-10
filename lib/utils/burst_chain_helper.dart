/// Burst helpers: from [anchorPath], only **later** files in [orderedPaths]
/// (capture-time order) are included. Each step forward must be ≤ [maxGap]
/// after the previous; earlier photos are never part of the chain.
List<String> burstChainAdjacentInList(
  List<String> orderedPaths,
  String anchorPath,
  Map<String, DateTime> captureByPath, {
  Duration maxGap = const Duration(seconds: 1),
}) {
  if (orderedPaths.isEmpty || anchorPath.isEmpty) return [anchorPath];
  final idx = orderedPaths.indexOf(anchorPath);
  if (idx < 0) return [anchorPath];

  int end = idx;
  while (end < orderedPaths.length - 1) {
    final tCur = captureByPath[orderedPaths[end]];
    final tNext = captureByPath[orderedPaths[end + 1]];
    if (tCur == null || tNext == null) break;
    final gap = tNext.difference(tCur);
    if (gap > maxGap) break;
    end++;
  }
  return orderedPaths.sublist(idx, end + 1);
}
