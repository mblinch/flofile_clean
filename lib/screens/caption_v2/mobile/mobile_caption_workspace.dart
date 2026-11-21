import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../photo_edit/photo_edit_session.dart';
import '../../../services/mlb_api_service.dart';
import '../../../widgets/oriented_file_preview.dart';
import '../data/caption_v2_controller.dart';
import '../data/effective_verb_catalog.dart';
import 'mobile_design.dart';
import 'mobile_phone_frame.dart';
import 'mobile_photos.dart';

/// Phone caption screen — layout from `design/mobile/screens/Main.dc.html`.
class MobileCaptionWorkspace extends StatelessWidget {
  const MobileCaptionWorkspace({
    super.key,
    required this.controller,
    required this.editSession,
    required this.pageController,
    required this.onPageChanged,
    required this.onBack,
    required this.onSettings,
    required this.onEditPhoto,
    required this.onOpenPhoto,
    required this.onSavePrevious,
    required this.onPasteLast,
    required this.onSaveNext,
    required this.onFtp,
    this.onEditRosters,
    this.onOpenPhotos,
    this.ftpLabel = 'FTP',
    this.showFtp = true,
  });

  final CaptionV2Controller controller;
  final PhotoEditSession editSession;
  final PageController pageController;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onBack;
  final VoidCallback onSettings;
  final VoidCallback onEditPhoto;
  final VoidCallback onOpenPhoto;
  final VoidCallback onSavePrevious;
  final VoidCallback onPasteLast;
  final VoidCallback onSaveNext;
  final VoidCallback? onFtp;
  final VoidCallback? onEditRosters;
  final VoidCallback? onOpenPhotos;
  final String ftpLabel;
  final bool showFtp;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([controller, editSession]),
      builder: (context, _) {
        return ColoredBox(
          color: MobileDesign.bg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MobileCaptionHeader(
                controller: controller,
                onBack: onBack,
                onSettings: onSettings,
                onOpenPhotos: onOpenPhotos,
              ),
              MobilePhotoBand(
                controller: controller,
                editSession: editSession,
                onOpen: onOpenPhoto,
                onEdit: onEditPhoto,
              ),
              MobileStatusBanner(controller: controller),
              MobileCaptionBlock(controller: controller),
              Expanded(
                child: MobileSwipeBody(
                  controller: controller,
                  pageController: pageController,
                  onPageChanged: onPageChanged,
                  onEditRosters: onEditRosters,
                ),
              ),
              MobileDockBar(
                onSavePrevious: onSavePrevious,
                onPasteLast: onPasteLast,
                onSaveNext: onSaveNext,
                onFtp: showFtp ? onFtp : null,
                ftpLabel: ftpLabel,
              ),
            ],
          ),
        );
      },
    );
  }
}

class MobileCaptionHeader extends StatelessWidget {
  const MobileCaptionHeader({
    super.key,
    required this.controller,
    required this.onBack,
    required this.onSettings,
    this.onOpenPhotos,
  });

  final CaptionV2Controller controller;
  final VoidCallback onBack;
  final VoidCallback onSettings;
  final VoidCallback? onOpenPhotos;

  @override
  Widget build(BuildContext context) {
    final matchup = _matchup(controller);
    final date = controller.currentGameInfoForCaption().gameDate;
    final wire = _wireLabel(controller);
    final sub = [
      if (date != null) _shortDate(date),
      if (wire.isNotEmpty) wire,
    ].join(' · ');
    final count = controller.imagePaths.isEmpty
        ? '0 / 0'
        : '${controller.currentIndex + 1} / ${controller.imagePaths.length}';

    return SizedBox(
      height: MobileDesign.headerH,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: MobileDesign.divider)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              _IconHit(
                tooltip: 'Back to sessions',
                onTap: onBack,
                child: const Icon(
                  PhosphorIconsRegular.caretLeft,
                  size: 20,
                  color: MobileDesign.text,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      matchup.isEmpty ? 'Game' : matchup,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: MobileDesign.font,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: MobileDesign.text,
                        height: 1.1,
                      ),
                    ),
                    if (sub.isNotEmpty)
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: MobileDesign.font,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: MobileDesign.textSecondary,
                          height: 1.2,
                        ),
                      ),
                  ],
                ),
              ),
              Material(
                color: MobileDesign.button,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: onOpenPhotos ??
                      () => MobilePhotosPage.open(
                            context,
                            controller: controller,
                          ),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Text(
                      count,
                      style: const TextStyle(
                        fontFamily: MobileDesign.font,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: MobileDesign.textSoft,
                      ),
                    ),
                  ),
                ),
              ),
              _IconHit(
                tooltip: 'Settings',
                onTap: onSettings,
                child: const Icon(
                  PhosphorIconsRegular.gearSix,
                  size: 20,
                  color: MobileDesign.textSoft,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MobilePhotoBand extends StatelessWidget {
  const MobilePhotoBand({
    super.key,
    required this.controller,
    required this.editSession,
    required this.onOpen,
    required this.onEdit,
  });

  final CaptionV2Controller controller;
  final PhotoEditSession editSession;
  final VoidCallback onOpen;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final paths = controller.imagePaths;
    final path = paths.isEmpty
        ? null
        : paths[controller.currentIndex.clamp(0, paths.length - 1)];
    final grade = editSession.adjustmentsFor(path);
    final cropping = editSession.cropping;
    final viewCrop =
        path == null || cropping ? null : editSession.cropFor(path);
    final name = controller.currentFileName;

    return SizedBox(
      height: MobileDesign.photoH,
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              onTap: cropping ? null : onOpen,
              child: path == null
                  ? const Center(
                      child: Icon(
                        PhosphorIconsRegular.image,
                        size: 36,
                        color: MobileDesign.textDim,
                      ),
                    )
                  : OrientedFilePreview(
                      key: ValueKey(
                        'mobile-band-$path-${controller.imageContentStamp(path)}',
                      ),
                      path: path,
                      version: controller.imageContentStamp(path),
                      fit: BoxFit.cover,
                      cacheWidth: 780,
                      adjustments: grade.isNeutral ? null : grade,
                      viewCrop: viewCrop != null && !viewCrop.isFull
                          ? viewCrop
                          : null,
                    ),
            ),
            if (name.isNotEmpty)
              Positioned(
                left: 10,
                bottom: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0x8C000000),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: MobileDesign.font,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              right: 10,
              bottom: 8,
              child: Material(
                color: const Color(0x99000000),
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: onEdit,
                  borderRadius: BorderRadius.circular(8),
                  child: const SizedBox(
                    height: 32,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Center(
                        child: Text(
                          'Edit',
                          style: TextStyle(
                            fontFamily: MobileDesign.font,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Always-reserved 30px banner slot (warning / saved / empty).
class MobileStatusBanner extends StatelessWidget {
  const MobileStatusBanner({super.key, required this.controller});

  final CaptionV2Controller controller;

  @override
  Widget build(BuildContext context) {
    final status = controller.statusMessage?.trim() ?? '';
    final incomplete =
        status == CaptionV2Controller.incompleteCaptionWarning;
    final missingPhotographer =
        status == CaptionV2Controller.missingPhotographerWarning;
    final saved = status.startsWith('Saved');
    final Color bg;
    final Color fg;
    final String text;
    if (incomplete) {
      bg = MobileDesign.errorBg;
      fg = MobileDesign.errorFg;
      text = 'Pick an action before saving — swiped you to Actions';
    } else if (missingPhotographer) {
      bg = MobileDesign.errorBg;
      fg = MobileDesign.errorFg;
      text = CaptionV2Controller.missingPhotographerWarning;
    } else if (saved) {
      bg = MobileDesign.successBg;
      fg = MobileDesign.successFg;
      final file = controller.currentFileName;
      text = status == 'Saved' && file.isNotEmpty ? 'Saved $file' : status;
    } else {
      bg = Colors.transparent;
      fg = MobileDesign.text;
      text = '';
    }

    return SizedBox(
      height: MobileDesign.bannerH,
      child: ColoredBox(
        color: bg,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: MobileDesign.font,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MobileCaptionBlock extends StatelessWidget {
  const MobileCaptionBlock({super.key, required this.controller});

  final CaptionV2Controller controller;

  @override
  Widget build(BuildContext context) {
    // Match desktop: show the photo's embedded caption until the user picks.
    final caption = controller.displayedCaption.trim();
    final idle = caption.isEmpty;
    final display = idle
        ? 'Tap a player to start the caption.'
        : caption;
    final personality = (controller.personality.trim().isNotEmpty
            ? controller.personality
            : controller.originalPersonality)
        .trim();

    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: MobileDesign.divider)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text(
                  'CAPTION',
                  style: TextStyle(
                    fontFamily: MobileDesign.font,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.08 * 11,
                    color: MobileDesign.text,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'PERSONALITY',
                  style: TextStyle(
                    fontFamily: MobileDesign.font,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.06 * 10,
                    color: MobileDesign.textSecondary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    personality.isEmpty ? '—' : personality,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: MobileDesign.font,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: MobileDesign.text,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: MobileDesign.captionBoxH,
              child: SingleChildScrollView(
                child: Text(
                  display,
                  style: TextStyle(
                    fontFamily: MobileDesign.font,
                    fontSize: 13,
                    height: 1.38,
                    color: idle ? MobileDesign.textDim : MobileDesign.text,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            MobilePeriodChips(controller: controller),
          ],
        ),
      ),
    );
  }
}

class MobilePeriodChips extends StatelessWidget {
  const MobilePeriodChips({super.key, required this.controller});

  final CaptionV2Controller controller;

  @override
  Widget build(BuildContext context) {
    final reg = controller.timingRegulationCount;
    final otLabel = controller.sport.toLowerCase() == 'soccer'
        ? 'ET'
        : (controller.sport.toLowerCase() == 'baseball' ? 'X' : 'OT');
    final chips = <_PeriodChip>[
      _PeriodChip(
        label: 'Pre',
        selected: controller.preGame,
        onTap: () => controller.setPre(!controller.preGame),
      ),
      for (var i = 1; i <= reg; i++)
        _PeriodChip(
          label: '$i',
          selected: !controller.preGame &&
              !controller.postGame &&
              controller.inning == i,
          onTap: () {
            controller.activateInning();
            controller.setInning(i);
          },
        ),
      _PeriodChip(
        label: otLabel,
        selected: !controller.preGame &&
            !controller.postGame &&
            controller.inning > reg,
        onTap: () {
          controller.activateInning();
          controller.setInning(reg + 1);
        },
      ),
      _PeriodChip(
        label: 'Post',
        selected: controller.postGame,
        onTap: () => controller.setPost(!controller.postGame),
      ),
    ];

    return Row(
      children: [
        const Padding(
          padding: EdgeInsets.only(right: 6),
          child: Text(
            'PERIOD',
            style: TextStyle(
              fontFamily: MobileDesign.font,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.08 * 10,
              color: MobileDesign.textSecondary,
            ),
          ),
        ),
        for (final chip in chips)
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: _PeriodChipButton(chip: chip),
          ),
      ],
    );
  }
}

class _PeriodChip {
  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
}

class _PeriodChipButton extends StatelessWidget {
  const _PeriodChipButton({required this.chip});
  final _PeriodChip chip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: chip.selected ? MobileDesign.chipOn : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: chip.onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: 32,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11),
            child: Center(
              child: Text(
                chip.label,
                style: TextStyle(
                  fontFamily: MobileDesign.font,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: chip.selected
                      ? Colors.white
                      : MobileDesign.textMuted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MobileSwipeBody extends StatefulWidget {
  const MobileSwipeBody({
    super.key,
    required this.controller,
    required this.pageController,
    required this.onPageChanged,
    this.onEditRosters,
  });

  final CaptionV2Controller controller;
  final PageController pageController;
  final ValueChanged<int> onPageChanged;
  final VoidCallback? onEditRosters;

  @override
  State<MobileSwipeBody> createState() => _MobileSwipeBodyState();
}

class _MobileSwipeBodyState extends State<MobileSwipeBody> {
  double _tabProgress = 0;
  int _scrollLock = -1;

  CaptionV2Controller get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _tabProgress = c.columnFocus.clamp(0, 2).toDouble();
    widget.pageController.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.pageController.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!widget.pageController.hasClients || _scrollLock >= 0) return;
    final page = widget.pageController.page ?? _tabProgress;
    if ((page - _tabProgress).abs() > 0.001) {
      setState(() => _tabProgress = page);
    }
  }

  void _go(int i) {
    _scrollLock = i;
    setState(() => _tabProgress = i.toDouble());
    widget.onPageChanged(i);
    widget.pageController
        .animateToPage(
          i,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() {
      if (mounted) setState(() => _scrollLock = -1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final single = c.singleTeamMode;
    final pageCount = single ? 2 : 3;
    final focus = _tabProgress.round().clamp(0, pageCount - 1);
    final tabs = <String>[
      c.homeAbbr.isEmpty ? 'Home' : c.homeAbbr,
      'Actions',
      if (!single) (c.awayAbbr.isEmpty ? 'Away' : c.awayAbbr),
    ];

    return Column(
      children: [
        SizedBox(
          height: MobileDesign.tabH,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: MobileDesign.divider)),
            ),
            child: Row(
              children: [
                for (var i = 0; i < tabs.length; i++)
                  Expanded(
                    child: InkWell(
                      onTap: () => _go(i),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              width: 2,
                              color: focus == i
                                  ? MobileDesign.link
                                  : Colors.transparent,
                            ),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            tabs[i],
                            style: TextStyle(
                              fontFamily: MobileDesign.font,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.02 * 13,
                              color: focus == i
                                  ? Colors.white
                                  : MobileDesign.textIdle,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ScrollConfiguration(
            behavior: const MobileDragScrollBehavior(),
            child: PageView(
              controller: widget.pageController,
              onPageChanged: (i) {
                if (_scrollLock < 0) {
                  setState(() => _tabProgress = i.toDouble());
                }
                widget.onPageChanged(i);
              },
              children: [
                MobilePlayerPane(
                  controller: c,
                  isHome: true,
                  onEditRosters: widget.onEditRosters,
                ),
                MobileActionsPane(controller: c),
                if (!single)
                  MobilePlayerPane(
                    controller: c,
                    isHome: false,
                    onEditRosters: widget.onEditRosters,
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 6, 0, 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < pageCount; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: focus == i
                        ? MobileDesign.text
                        : MobileDesign.dotIdle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class MobilePlayerPane extends StatelessWidget {
  const MobilePlayerPane({
    super.key,
    required this.controller,
    required this.isHome,
    this.onEditRosters,
  });

  final CaptionV2Controller controller;
  final bool isHome;
  final VoidCallback? onEditRosters;

  static String _shortName(Player player) {
    final parts = player.fullName.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return player.fullName;
    final last = parts.sublist(1).join(' ');
    if (last.length <= 10) return last;
    return '${last.substring(0, 8)}…';
  }

  static String? _jersey(Player player) {
    var raw = player.jerseyNumber?.trim() ?? '';
    while (raw.startsWith('#')) {
      raw = raw.substring(1).trim();
    }
    return raw.isEmpty ? null : raw;
  }

  @override
  Widget build(BuildContext context) {
    final roster = isHome ? controller.homeRoster : controller.awayRoster;
    final players = [...roster]..sort((a, b) {
      final an = int.tryParse(_jersey(a) ?? '') ?? 999;
      final bn = int.tryParse(_jersey(b) ?? '') ?? 999;
      if (an != bn) return an.compareTo(bn);
      return a.fullName.compareTo(b.fullName);
    });

    final playersOn = controller.teamPlayersIsHome == isHome &&
        controller.teamSubjectKind == TeamSubjectKind.players;
    final teamOn = controller.teamPlayersIsHome == isHome &&
        controller.teamSubjectKind == TeamSubjectKind.name;
    final matesOn = controller.withTeammatesIsHome == isHome;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: players.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 5,
            mainAxisSpacing: MobileDesign.playerGap,
            crossAxisSpacing: MobileDesign.playerGap,
            mainAxisExtent: MobileDesign.playerH,
          ),
          itemBuilder: (context, i) {
            final player = players[i];
            final selected =
                controller.isPlayerSelected(player, isHome: isHome);
            return _PlayerTile(
              short: _shortName(player),
              number: _jersey(player) ?? '—',
              selected: selected,
              aria:
                  '${selected ? 'Selected: ' : ''}${player.fullName} number ${_jersey(player) ?? ''}',
              onTap: () => controller.selectPlayer(player, isHome: isHome),
            );
          },
        ),
        const SizedBox(height: 14),
        const Text(
          'OTHER',
          style: TextStyle(
            fontFamily: MobileDesign.font,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.08 * 10,
            color: MobileDesign.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _OtherButton(
                label: 'Players',
                selected: playersOn,
                onTap: () => controller.toggleTeamSubject(
                  isHome: isHome,
                  kind: TeamSubjectKind.players,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _OtherButton(
                label: 'Team',
                selected: teamOn,
                onTap: () => controller.toggleTeamSubject(
                  isHome: isHome,
                  kind: TeamSubjectKind.name,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _OtherButton(
                label: 'Teammates',
                selected: matesOn,
                onTap: () => controller.toggleTeamSubject(
                  isHome: isHome,
                  kind: TeamSubjectKind.teammates,
                ),
              ),
            ),
          ],
        ),
        if (onEditRosters != null) ...[
          const SizedBox(height: 10),
          TextButton(
            onPressed: onEditRosters,
            child: const Text('Edit roster'),
          ),
        ],
      ],
    );
  }
}

class _PlayerTile extends StatelessWidget {
  const _PlayerTile({
    required this.short,
    required this.number,
    required this.selected,
    required this.onTap,
    this.aria,
  });

  final String short;
  final String number;
  final bool selected;
  final VoidCallback onTap;
  final String? aria;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: aria,
      selected: selected,
      child: Material(
        color: selected ? MobileDesign.selectedBg : MobileDesign.button,
        borderRadius: BorderRadius.circular(MobileDesign.playerRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(MobileDesign.playerRadius),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  short.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: MobileDesign.font,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.04 * 9,
                    color: selected
                        ? MobileDesign.selectedFg
                        : MobileDesign.text,
                  ),
                ),
                Text(
                  number,
                  style: TextStyle(
                    fontFamily: MobileDesign.font,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    color: selected
                        ? MobileDesign.selectedFg
                        : MobileDesign.text,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OtherButton extends StatelessWidget {
  const _OtherButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MobileDesign.otherH,
      child: Material(
        color: selected ? MobileDesign.selectedBg : MobileDesign.button,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: selected
              ? BorderSide.none
              : const BorderSide(color: MobileDesign.otherBorder),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: MobileDesign.font,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected
                    ? MobileDesign.selectedFg
                    : MobileDesign.otherText,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MobileActionsPane extends StatefulWidget {
  const MobileActionsPane({super.key, required this.controller});

  final CaptionV2Controller controller;

  @override
  State<MobileActionsPane> createState() => _MobileActionsPaneState();
}

class _MobileActionsPaneState extends State<MobileActionsPane> {
  final _filter = TextEditingController();

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  List<EffectiveVerb> _allVerbs() {
    final out = <EffectiveVerb>[];
    final seen = <String>{};
    for (final cat in widget.controller.verbCategories) {
      for (final v
          in widget.controller.verbDefinitionsByCategory[cat] ??
              const <EffectiveVerb>[]) {
        if (seen.add(v.key)) out.add(v);
      }
    }
    out.sort(
      (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
    );
    final q = _filter.text.trim().toLowerCase();
    if (q.isEmpty) return out;
    return out
        .where((v) => v.label.toLowerCase().contains(q))
        .toList(growable: false);
  }

  String _indexLetter(String label, String? previous) {
    final t = label.trim();
    if (t.isEmpty) return '';
    final ch = t[0].toUpperCase();
    if (!RegExp(r'[A-Z]').hasMatch(ch)) return '';
    if (previous != null && previous.trim().isNotEmpty) {
      final prev = previous.trim()[0].toUpperCase();
      if (prev == ch) return '';
    }
    return ch;
  }

  @override
  Widget build(BuildContext context) {
    final verbs = _allVerbs();
    final selected = widget.controller.selectedVerb;
    String? prevLabel;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: Container(
            height: MobileDesign.searchH,
            decoration: BoxDecoration(
              color: MobileDesign.button,
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Icon(
                  PhosphorIconsRegular.magnifyingGlass,
                  size: 16,
                  color: MobileDesign.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _filter,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(
                      fontFamily: MobileDesign.font,
                      fontSize: 14,
                      color: MobileDesign.text,
                    ),
                    cursorColor: MobileDesign.link,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
            itemCount: verbs.length,
            itemBuilder: (context, i) {
              final verb = verbs[i];
              final letter = _indexLetter(verb.label, prevLabel);
              prevLabel = verb.label;
              final on = selected == verb.key;
              return Material(
                color: on ? MobileDesign.selectedBg : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  onTap: () {
                    if (on) {
                      widget.controller.clearSelectedVerb();
                    } else {
                      widget.controller.selectVerb(verb.key);
                    }
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    height: MobileDesign.actionRowH,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 14,
                            child: Text(
                              letter,
                              style: const TextStyle(
                                fontFamily: MobileDesign.font,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: MobileDesign.letter,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              verb.label,
                              style: TextStyle(
                                fontFamily: MobileDesign.font,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: on
                                    ? MobileDesign.selectedFg
                                    : MobileDesign.text,
                              ),
                            ),
                          ),
                          if (on)
                            const Text(
                              '✓',
                              style: TextStyle(
                                fontFamily: MobileDesign.font,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: MobileDesign.selectedFg,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class MobileDockBar extends StatelessWidget {
  const MobileDockBar({
    super.key,
    required this.onSavePrevious,
    required this.onPasteLast,
    required this.onSaveNext,
    this.onFtp,
    this.ftpLabel = 'FTP',
  });

  final VoidCallback onSavePrevious;
  final VoidCallback onPasteLast;
  final VoidCallback onSaveNext;
  final VoidCallback? onFtp;
  final String ftpLabel;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: MobileDesign.barBg,
        border: Border(top: BorderSide(color: MobileDesign.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
          child: Row(
            children: [
              _DockIcon(
                width: 52,
                tooltip: 'Save and previous photo',
                onTap: onSavePrevious,
                child: const Icon(
                  PhosphorIconsBold.caretLeft,
                  size: 18,
                  color: MobileDesign.text,
                ),
              ),
              const SizedBox(width: 8),
              _DockIcon(
                width: 52,
                tooltip: 'Paste last caption',
                onTap: onPasteLast,
                child: const Icon(
                  PhosphorIconsRegular.clipboardText,
                  size: 18,
                  color: MobileDesign.text,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DockPrimary(
                  label: 'Save & Next',
                  onTap: onSaveNext,
                ),
              ),
              if (onFtp != null) ...[
                const SizedBox(width: 8),
                _DockIcon(
                  width: 64,
                  tooltip: 'Send by FTP',
                  onTap: onFtp,
                  child: Text(
                    ftpLabel,
                    style: const TextStyle(
                      fontFamily: MobileDesign.font,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: MobileDesign.text,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DockIcon extends StatelessWidget {
  const _DockIcon({
    required this.width,
    required this.onTap,
    required this.child,
    this.tooltip,
  });

  final double width;
  final VoidCallback? onTap;
  final Widget child;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: MobileDesign.button,
      borderRadius: BorderRadius.circular(MobileDesign.dockRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(MobileDesign.dockRadius),
        child: SizedBox(
          width: width,
          height: MobileDesign.dockH,
          child: Center(child: child),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

class _DockPrimary extends StatelessWidget {
  const _DockPrimary({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MobileDesign.selectedBg,
      borderRadius: BorderRadius.circular(MobileDesign.dockRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(MobileDesign.dockRadius),
        child: SizedBox(
          height: MobileDesign.dockH,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontFamily: MobileDesign.font,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: MobileDesign.selectedFg,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                PhosphorIconsBold.caretRight,
                size: 16,
                color: MobileDesign.selectedFg,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconHit extends StatelessWidget {
  const _IconHit({
    required this.onTap,
    required this.child,
    this.tooltip,
  });

  final VoidCallback onTap;
  final Widget child;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final hit = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(child: child),
        ),
      ),
    );
    if (tooltip == null) return hit;
    return Tooltip(message: tooltip!, child: hit);
  }
}

String _matchup(CaptionV2Controller c) {
  final away = c.awayAbbr.trim();
  final home = c.homeAbbr.trim();
  if (away.isNotEmpty && home.isNotEmpty) return '$away @ $home';
  if (home.isNotEmpty) return home;
  if (away.isNotEmpty) return away;
  return '';
}

String _wireLabel(CaptionV2Controller c) {
  final token = c.activeCaptionStyleToken.toLowerCase();
  if (token.contains('getty')) return 'Getty';
  if (token.contains('imagn')) return 'Imagn';
  if (token.contains('ap')) return 'AP';
  if (token.contains('cp') || token.contains('canadian')) return 'CP';
  final raw = c.activeCaptionStyleToken.trim();
  if (raw.isEmpty) return '';
  return raw[0].toUpperCase() + raw.substring(1);
}

String _shortDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}
