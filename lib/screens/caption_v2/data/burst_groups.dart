import '../../../utils/burst_chain_helper.dart';

/// Default burst gap for caption V2 (~2s as specified for the redesign).
const Duration kCaptionV2BurstGap = Duration(seconds: 2);

/// Partition [orderedPaths] into burst groups where a gap > [maxGap] starts a
/// new group. Additive helper — does not change [burstChainAdjacentInList].
List<List<String>> groupFramesIntoBursts(
  List<String> orderedPaths,
  Map<String, DateTime> captureByPath, {
  Duration maxGap = kCaptionV2BurstGap,
}) {
  if (orderedPaths.isEmpty) return const [];
  final groups = <List<String>>[];
  var current = <String>[orderedPaths.first];

  for (var i = 1; i < orderedPaths.length; i++) {
    final prev = orderedPaths[i - 1];
    final next = orderedPaths[i];
    final tPrev = captureByPath[prev];
    final tNext = captureByPath[next];
    final split = tPrev == null ||
        tNext == null ||
        tNext.difference(tPrev) > maxGap;
    if (split) {
      groups.add(current);
      current = <String>[next];
    } else {
      current.add(next);
    }
  }
  groups.add(current);
  return groups;
}

/// Burst chain from [anchorPath] using the V2 gap (wraps existing helper).
List<String> burstChainFromAnchor(
  List<String> orderedPaths,
  String anchorPath,
  Map<String, DateTime> captureByPath, {
  Duration maxGap = kCaptionV2BurstGap,
}) {
  return burstChainAdjacentInList(
    orderedPaths,
    anchorPath,
    captureByPath,
    maxGap: maxGap,
  );
}
