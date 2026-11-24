/// Burst helpers: from [anchorPath], expand to every adjacent frame in
/// [orderedPaths] (capture-time order) whose capture gap to its neighbor is
/// ≤ [maxGap]. Walks both earlier and later frames so any selection inside a
/// coherent burst sees the same group.
List<String> burstChainAdjacentInList(
  List<String> orderedPaths,
  String anchorPath,
  Map<String, DateTime> captureByPath, {
  Duration maxGap = const Duration(seconds: 1),
}) {
  if (orderedPaths.isEmpty || anchorPath.isEmpty) return [anchorPath];
  final idx = orderedPaths.indexOf(anchorPath);
  if (idx < 0) return [anchorPath];

  int start = idx;
  while (start > 0) {
    final tPrev = captureByPath[orderedPaths[start - 1]];
    final tCur = captureByPath[orderedPaths[start]];
    if (tPrev == null || tCur == null) break;
    if (tCur.difference(tPrev) > maxGap) break;
    start--;
  }

  int end = idx;
  while (end < orderedPaths.length - 1) {
    final tCur = captureByPath[orderedPaths[end]];
    final tNext = captureByPath[orderedPaths[end + 1]];
    if (tCur == null || tNext == null) break;
    if (tNext.difference(tCur) > maxGap) break;
    end++;
  }
  return orderedPaths.sublist(start, end + 1);
}
