import 'package:flutter/material.dart';

class SportSelectionDialog extends StatelessWidget {
  final Function(String sport) onSportSelected;

  const SportSelectionDialog({
    Key? key,
    required this.onSportSelected,
  }) : super(key: key);

  Widget _buildSportCard(
    BuildContext context,
    String sport,
    IconData icon,
    Color color,
  ) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onSportSelected(sport.toLowerCase()),
        child: Container(
          width: 128,
          height: 132,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 28,
                  color: color,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                sport,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.5),
      child: Center(
        child: Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            width: 720,
            height: 600,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            color: Colors.white,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                const Text(
                  'FLO FILE',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  height: 1,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(height: 14),

                // Question
                const Text(
                  'What sport are you working on today?',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 18),

                // Sport cards (MLS uses ESPN usa.1 in app; same pattern as other ESPN sports)
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    _buildSportCard(
                      context,
                      'Baseball',
                      Icons.sports_baseball,
                      const Color(0xFF0052CC),
                    ),
                    _buildSportCard(
                      context,
                      'Hockey',
                      Icons.sports_hockey,
                      const Color(0xFFD32F2F),
                    ),
                    _buildSportCard(
                      context,
                      'Basketball',
                      Icons.sports_basketball,
                      const Color(0xFFFF6F00),
                    ),
                    _buildSportCard(
                      context,
                      'Soccer',
                      Icons.sports_soccer,
                      const Color(0xFF1B5E20),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
