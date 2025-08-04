import 'package:flutter/material.dart';

class ContextMenuWidget extends StatelessWidget {
  final int selectedCount;
  final VoidCallback? onCopyIptc;
  final VoidCallback? onPasteIptc;
  final VoidCallback? onFtpImages;
  final Offset position;

  const ContextMenuWidget({
    super.key,
    required this.selectedCount,
    this.onCopyIptc,
    this.onPasteIptc,
    this.onFtpImages,
    required this.position,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx,
      top: position.dy,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Copy IPTC Data (disabled for multiple selection)
              if (selectedCount == 1)
                _buildMenuItem(
                  context,
                  'Copy IPTC Data',
                  Icons.copy,
                  onCopyIptc,
                ),
              
              // Paste IPTC Data (always available)
              _buildMenuItem(
                context,
                'Paste IPTC Data',
                Icons.paste,
                onPasteIptc,
              ),
              
              // FTP Images (always available, shows count for multiple)
              _buildMenuItem(
                context,
                selectedCount == 1 
                    ? 'FTP Image' 
                    : 'FTP Images ($selectedCount)',
                Icons.upload,
                onFtpImages,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context,
    String text,
    IconData icon,
    VoidCallback? onTap,
  ) {
    final isEnabled = onTap != null;
    
    return InkWell(
      onTap: isEnabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: isEnabled ? Colors.black87 : Colors.grey,
            ),
            const SizedBox(width: 8),
            Text(
              text,
              style: TextStyle(
                color: isEnabled ? Colors.black87 : Colors.grey,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
} 