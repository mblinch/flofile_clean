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

/// Full coherent burst containing [anchorPath] using the V2 gap.
///
/// Same membership as [groupFramesIntoBursts] for that frame: walks both
/// earlier and later neighbors while adjacent capture gaps stay ≤ [maxGap].
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

/// Save-to-Burst popover order: [currentPath] first (Original), then every
/// other frame in [chain] order — including frames before current in capture
/// time. Does not drop pre-current members.
List<String> burstChainForSaveDock(List<String> chain, String currentPath) {
  if (chain.isEmpty) return const [];
  if (chain.length == 1 || chain.first == currentPath) {
    return List<String>.from(chain);
  }
  return <String>[
    currentPath,
    for (final path in chain)
      if (path != currentPath) path,
  ];
}

/// Non-Original thumbs that start checked in the Save-to-Burst popover.
///
/// [dockPaths] must already be [burstChainForSaveDock] order (index 0 =
/// current). Includes every remaining frame — earlier and later.
Set<String> defaultCheckedBurstExtras(List<String> dockPaths) {
  if (dockPaths.length <= 1) return <String>{};
  return dockPaths.skip(1).toSet();
}

/// Paths written by Save-to-Burst: Original ([dockPaths].first) plus each
/// extra that remains in [checkedExtras], preserving dock order.
List<String> resolveBurstSaveTargets({
  required List<String> dockPaths,
  required Set<String> checkedExtras,
}) {
  if (dockPaths.isEmpty) return const [];
  return <String>[
    dockPaths.first,
    for (final path in dockPaths.skip(1))
      if (checkedExtras.contains(path)) path,
  ];
}

/// Default write set: Original + every other coherent-burst frame.
List<String> defaultBurstSaveTargetsFromDock(List<String> dockPaths) {
  return resolveBurstSaveTargets(
    dockPaths: dockPaths,
    checkedExtras: defaultCheckedBurstExtras(dockPaths),
  );
}
