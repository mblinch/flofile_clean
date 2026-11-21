import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../layout/caption_v2_iptc_dialog.dart';
import 'mobile_design.dart';

/// Phone IPTC template chrome — opens the shared IPTC editor with mobile
/// colours/frame from `design/mobile/screens/Template.dc.html`.
class MobileTemplatePage extends StatelessWidget {
  const MobileTemplatePage({
    super.key,
    required this.folderPath,
    this.subtitle = 'Apply IPTC template',
    this.wireLabel = 'Getty',
    this.missingCount = 0,
    this.missingLabel,
  });

  final String? folderPath;
  final String subtitle;
  final String wireLabel;
  final int missingCount;
  final String? missingLabel;

  static Future<CaptionV2IptcSummary?> open(
    BuildContext context, {
    String? folderPath,
    bool enableWriting = true,
  }) {
    return showCaptionV2IptcDialog(
      context,
      folderPath: folderPath,
      enableWriting: enableWriting,
    );
  }

  @override
  Widget build(BuildContext context) {
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
                      onPressed: () => Navigator.of(context).maybePop(),
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
                          const Text(
                            'IPTC template',
                            style: TextStyle(
                              fontFamily: MobileDesign.font,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: MobileDesign.text,
                            ),
                          ),
                          Text(
                            '$wireLabel · $subtitle',
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
                      onPressed: () => MobileTemplatePage.open(
                        context,
                        folderPath: folderPath,
                      ),
                      style: TextButton.styleFrom(
                        backgroundColor: MobileDesign.input,
                        foregroundColor: MobileDesign.text,
                        minimumSize: const Size(0, 36),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Import',
                        style: TextStyle(
                          fontFamily: MobileDesign.font,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (missingCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: MobileDesign.warnBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  missingLabel ??
                      '$missingCount field${missingCount == 1 ? '' : 's'} missing for $wireLabel',
                  style: const TextStyle(
                    fontFamily: MobileDesign.font,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: MobileDesign.warnFg,
                  ),
                ),
              ),
            ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Edit the IPTC template used when applying metadata to photos.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: MobileDesign.font,
                        fontSize: 14,
                        color: MobileDesign.textMuted,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => MobileTemplatePage.open(
                        context,
                        folderPath: folderPath,
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: MobileDesign.selectedBg,
                        foregroundColor: MobileDesign.selectedFg,
                        minimumSize: const Size(200, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Open template',
                        style: TextStyle(
                          fontFamily: MobileDesign.font,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
