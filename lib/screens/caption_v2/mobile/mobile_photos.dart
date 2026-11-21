import 'dart:io';

import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../widgets/oriented_file_preview.dart';
import '../data/caption_v2_controller.dart';
import 'mobile_design.dart';

enum MobilePhotoFilter { all, notCaptioned, flagged }

/// Phone photo grid — layout from `design/mobile/screens/Photos.dc.html`.
class MobilePhotosPage extends StatefulWidget {
  const MobilePhotosPage({
    super.key,
    required this.controller,
    this.onBack,
    this.title,
  });

  final CaptionV2Controller controller;
  final VoidCallback? onBack;
  final String? title;

  static Future<void> open(
    BuildContext context, {
    required CaptionV2Controller controller,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MobilePhotosPage(controller: controller),
      ),
    );
  }

  @override
  State<MobilePhotosPage> createState() => _MobilePhotosPageState();
}

class _MobilePhotosPageState extends State<MobilePhotosPage> {
  MobilePhotoFilter _filter = MobilePhotoFilter.all;
  bool _earliestFirst = true;
  bool _selecting = false;

  CaptionV2Controller get c => widget.controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        final paths = [...c.imagePaths];
        if (!_earliestFirst) {
          // imagePaths are typically earliest-first already.
          final reversed = paths.reversed.toList();
          paths
            ..clear()
            ..addAll(reversed);
        }
        final filtered = paths.where((path) {
          switch (_filter) {
            case MobilePhotoFilter.all:
              return true;
            case MobilePhotoFilter.notCaptioned:
              return !c.captionedImages.contains(path) &&
                  !c.savedImages.contains(path);
            case MobilePhotoFilter.flagged:
              return false;
          }
        }).toList(growable: false);

        final captioned = c.imagePaths
            .where((p) => c.captionedImages.contains(p) || c.savedImages.contains(p))
            .length;
        final title = widget.title ??
            () {
              final away = c.awayAbbr;
              final home = c.homeAbbr;
              if (away.isNotEmpty && home.isNotEmpty) return '$away @ $home';
              return home.isNotEmpty ? home : 'Photos';
            }();

        return ColoredBox(
          color: MobileDesign.bg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 52,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: MobileDesign.divider),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Back',
                          onPressed: widget.onBack ??
                              () => Navigator.of(context).maybePop(),
                          icon: const Icon(
                            PhosphorIconsRegular.caretLeft,
                            color: MobileDesign.text,
                          ),
                        ),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  fontFamily: MobileDesign.font,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: MobileDesign.text,
                                ),
                              ),
                              Text(
                                '${c.imagePaths.length} photos · $captioned captioned',
                                style: const TextStyle(
                                  fontFamily: MobileDesign.font,
                                  fontSize: 11,
                                  color: MobileDesign.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              setState(() => _selecting = !_selecting),
                          style: TextButton.styleFrom(
                            foregroundColor: MobileDesign.link,
                            minimumSize: const Size(44, 36),
                          ),
                          child: Text(
                            _selecting ? 'Done' : 'Select',
                            style: const TextStyle(
                              fontFamily: MobileDesign.font,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                child: Row(
                  children: [
                    _Pill(
                      label: _earliestFirst ? 'Earliest first' : 'Latest first',
                      onTap: () =>
                          setState(() => _earliestFirst = !_earliestFirst),
                      trailing: true,
                    ),
                    const SizedBox(width: 6),
                    _Pill(
                      label: 'All',
                      selected: _filter == MobilePhotoFilter.all,
                      onTap: () => setState(
                        () => _filter = MobilePhotoFilter.all,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _Pill(
                      label: 'Not captioned',
                      selected: _filter == MobilePhotoFilter.notCaptioned,
                      onTap: () => setState(
                        () => _filter = MobilePhotoFilter.notCaptioned,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _Pill(
                      label: 'Flagged',
                      selected: _filter == MobilePhotoFilter.flagged,
                      onTap: () => setState(
                        () => _filter = MobilePhotoFilter.flagged,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 4,
                    childAspectRatio: 3 / 2,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final path = filtered[i];
                    final done = c.captionedImages.contains(path) ||
                        c.savedImages.contains(path);
                    final current = path == c.currentPath;
                    final exists = File(path).existsSync();
                    return Material(
                      color: MobileDesign.button,
                      borderRadius: BorderRadius.circular(6),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () {
                          final index = c.imagePaths.indexOf(path);
                          if (index >= 0) c.goToIndex(index);
                          if (widget.onBack == null) {
                            Navigator.of(context).maybePop();
                          }
                        },
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (exists)
                              OrientedFilePreview(
                                path: path,
                                version: c.imageContentStamp(path),
                                fit: BoxFit.cover,
                                cacheWidth: 360,
                              )
                            else
                              const ColoredBox(color: MobileDesign.button),
                            if (current)
                              Positioned.fill(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: MobileDesign.selectedBg,
                                      width: 2,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ),
                            Positioned(
                              right: 4,
                              top: 4,
                              child: Container(
                                width: 16,
                                height: 16,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: done
                                      ? MobileDesign.statusCaptioned
                                      : MobileDesign.statusTodo,
                                ),
                                child: done
                                    ? const Text(
                                        '✓',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: MobileDesign.selectedFg,
                                          height: 1,
                                        ),
                                      )
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              DecoratedBox(
                decoration: const BoxDecoration(
                  color: MobileDesign.barBg,
                  border: Border(
                    top: BorderSide(color: MobileDesign.divider),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        _Legend(
                          color: MobileDesign.statusCaptioned,
                          label: 'Captioned',
                        ),
                        SizedBox(width: 18),
                        _Legend(
                          color: MobileDesign.statusTodo,
                          label: 'Not yet',
                        ),
                        SizedBox(width: 18),
                        _Legend(
                          color: MobileDesign.statusNew,
                          label: 'New from card',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.onTap,
    this.selected = false,
    this.trailing = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool selected;
  final bool trailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? MobileDesign.selectedBg : MobileDesign.input,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: SizedBox(
          height: 34,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: MobileDesign.font,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? MobileDesign.selectedFg
                        : MobileDesign.text,
                  ),
                ),
                if (trailing) ...[
                  const SizedBox(width: 6),
                  Icon(
                    PhosphorIconsBold.caretDown,
                    size: 12,
                    color: selected
                        ? MobileDesign.selectedFg
                        : MobileDesign.text,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontFamily: MobileDesign.font,
            fontSize: 11,
            color: MobileDesign.textMuted,
          ),
        ),
      ],
    );
  }
}
