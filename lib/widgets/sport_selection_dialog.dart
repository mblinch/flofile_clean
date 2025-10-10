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
          width: 200,
          height: 220,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 40,
                  color: color,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                sport,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
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
            width: 700,
            height: 500,
            padding: const EdgeInsets.all(40),
            color: Colors.white,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                const Text(
                  'FLO FILE',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  height: 1,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(height: 32),

                // Question
                const Text(
                  'What sport are you working on today?',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 48),

                // Sport cards
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildSportCard(
                      context,
                      'Baseball',
                      Icons.sports_baseball,
                      const Color(0xFF0052CC),
                    ),
                    const SizedBox(width: 24),
                    _buildSportCard(
                      context,
                      'Hockey',
                      Icons.sports_hockey,
                      const Color(0xFFD32F2F),
                    ),
                    const SizedBox(width: 24),
                    _buildSportCard(
                      context,
                      'Basketball',
                      Icons.sports_basketball,
                      const Color(0xFFFF6F00),
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
