import 'package:flutter/material.dart';

import '../../../theme/ff_tokens.dart';
import '../widgets/caption_strip.dart';
import '../widgets/frame_status_dot.dart';
import '../widgets/player_row.dart';
import '../widgets/rbi_row.dart';
import '../widgets/transmit_dock.dart';
import '../widgets/verb_tile.dart';

/// Debug gallery: all six caption_v2 widgets in every visual state.
///
/// Shown as the V2 home until the real layout lands.
class CaptionV2GalleryPage extends StatefulWidget {
  const CaptionV2GalleryPage({super.key});

  @override
  State<CaptionV2GalleryPage> createState() => _CaptionV2GalleryPageState();
}

class _CaptionV2GalleryPageState extends State<CaptionV2GalleryPage> {
  int _rbi = 2;
  bool _useDark = true;
  String? _lastTap;

  @override
  Widget build(BuildContext context) {
    final tokens = _useDark ? FfTokens.dark : FfTokens.light;

    return Theme(
      data: ThemeData(
        brightness: _useDark ? Brightness.dark : Brightness.light,
        useMaterial3: true,
        fontFamily: FfTokens.fontFamily,
        scaffoldBackgroundColor: tokens.bg,
        extensions: <ThemeExtension<dynamic>>[tokens],
      ),
      child: Builder(
        builder: (context) {
          final t = Theme.of(context).extension<FfTokens>()!;
          return Scaffold(
            backgroundColor: t.bg,
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _GalleryHeader(
                  useDark: _useDark,
                  lastTap: _lastTap,
                  onToggleTheme: () => setState(() => _useDark = !_useDark),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _Section(
                        title: 'FrameStatusDot',
                        child: Wrap(
                          spacing: 24,
                          runSpacing: 12,
                          children: [
                            for (final s in FrameState.values)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  FrameStatusDot(state: s),
                                  const SizedBox(width: 8),
                                  Text(s.name, style: t.secondaryLabelStyle),
                                ],
                              ),
                          ],
                        ),
                      ),
                      _Section(
                        title: 'PlayerRow',
                        child: Column(
                          children: [
                            PlayerRow(
                              jersey: '4',
                              name: 'George Springer',
                              selected: false,
                              usageCount: 3,
                              onTap: () => setState(
                                () => _lastTap = 'PlayerRow idle',
                              ),
                            ),
                            const SizedBox(height: 8),
                            PlayerRow(
                              jersey: '27',
                              name: 'Vladimir Guerrero Jr.',
                              selected: true,
                              usageCount: 14,
                              onTap: () => setState(
                                () => _lastTap = 'PlayerRow selected',
                              ),
                            ),
                            const SizedBox(height: 8),
                            PlayerRow(
                              jersey: '11',
                              name: 'Bo Bichette',
                              selected: false,
                              focused: true,
                              onTap: () => setState(
                                () => _lastTap = 'PlayerRow focused',
                              ),
                            ),
                          ],
                        ),
                      ),
                      _Section(
                        title: 'VerbTile + RbiRow',
                        child: Column(
                          children: [
                            VerbTile(
                              code: '1',
                              label: 'Single',
                              selected: false,
                              onTap: () => setState(
                                () => _lastTap = 'VerbTile idle',
                              ),
                            ),
                            const SizedBox(height: 8),
                            VerbTile(
                              code: '2',
                              label: 'Double',
                              selected: true,
                              onTap: () => setState(
                                () => _lastTap = 'VerbTile selected',
                              ),
                            ),
                            const SizedBox(height: 6),
                            RbiRow(
                              value: _rbi,
                              onChanged: (v) => setState(() {
                                _rbi = v;
                                _lastTap = 'RbiRow → $v';
                              }),
                            ),
                            const SizedBox(height: 8),
                            VerbTile(
                              code: '3',
                              label: 'Triple',
                              selected: false,
                              focused: true,
                              onTap: () => setState(
                                () => _lastTap = 'VerbTile focused',
                              ),
                            ),
                          ],
                        ),
                      ),
                      _Section(
                        title: 'CaptionStrip',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            CaptionStrip(
                              leading: 'Toronto Blue Jays ',
                              chips: const [
                                CaptionChipData(
                                  id: 'player',
                                  label: '27 Guerrero Jr.',
                                ),
                                CaptionChipData(
                                  id: 'verb',
                                  label: 'doubles',
                                ),
                                CaptionChipData(
                                  id: 'rbi',
                                  label: 'RBI 2',
                                ),
                              ],
                              trailing:
                                  ' in the 2nd inning against the Baltimore Orioles at Rogers Centre.',
                              inningLabel: '2nd',
                              preSelected: false,
                              postSelected: false,
                              onChipTap: (id) =>
                                  setState(() => _lastTap = 'chip:$id'),
                              onInningDecrement: () =>
                                  setState(() => _lastTap = 'inning−'),
                              onInningIncrement: () =>
                                  setState(() => _lastTap = 'inning+'),
                              onPreTap: () => setState(() => _lastTap = 'Pre'),
                              onPostTap: () =>
                                  setState(() => _lastTap = 'Post'),
                              onEditTap: () =>
                                  setState(() => _lastTap = 'edit'),
                            ),
                            const SizedBox(height: 12),
                            CaptionStrip(
                              leading: 'Toronto Blue Jays ',
                              chips: const [
                                CaptionChipData(
                                  id: 'player',
                                  placeholder: 'player',
                                ),
                                CaptionChipData(
                                  id: 'verb',
                                  placeholder: 'verb',
                                ),
                                CaptionChipData(
                                  id: 'rbi',
                                  placeholder: 'RBI',
                                ),
                              ],
                              trailing: ' in the inning against …',
                              onChipTap: (id) => setState(
                                () => _lastTap = 'empty chip:$id',
                              ),
                            ),
                          ],
                        ),
                      ),
                      _Section(
                        title: 'TransmitDock',
                        child: Column(
                          children: [
                            TransmitDock(
                              modesLabel: 'Modes 2 on',
                              sessionMeta: 'Burst detection',
                              destination: 'Photoshelter · FTP',
                              queueLabel: '4 queued · last sent 7:08 PM',
                              onTransmit: () =>
                                  setState(() => _lastTap = 'Transmit'),
                              onSaveNext: () =>
                                  setState(() => _lastTap = 'Save & next'),
                            ),
                            const SizedBox(height: 12),
                            TransmitDock(
                              modesLabel: 'Modes off',
                              destination: 'Photoshelter · FTP',
                              queueLabel: '0 queued',
                              transmitEnabled: false,
                              onTransmit: () {},
                              onSaveNext: () =>
                                  setState(() => _lastTap = 'Save only'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 48),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _GalleryHeader extends StatelessWidget {
  const _GalleryHeader({
    required this.useDark,
    required this.onToggleTheme,
    this.lastTap,
  });

  final bool useDark;
  final VoidCallback onToggleTheme;
  final String? lastTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>()!;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(bottom: BorderSide(color: t.divider)),
      ),
      child: Row(
        children: [
          Text('Caption V2 — Widget Gallery', style: t.labelStyle),
          const SizedBox(width: 12),
          Text(
            'Review only · layout next',
            style: t.metaStyle,
          ),
          const Spacer(),
          if (lastTap != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text('tap: $lastTap', style: t.monoMetaStyle),
            ),
          TextButton(
            onPressed: onToggleTheme,
            child: Text(
              useDark ? 'Light tokens' : 'Dark tokens',
              style: t.secondaryLabelStyle.copyWith(color: t.accent),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(FfTokens.radiusCard),
          border: Border.all(color: t.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.toUpperCase(), style: t.microStyle),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
