import 'package:flutter/material.dart';

class CaptionFieldsWidget extends StatelessWidget {
  const CaptionFieldsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.orange, width: 3.0),
        borderRadius: BorderRadius.circular(8),
        color: Colors.orange.shade50,
      ),
      child: const Center(
        child: Text(
          'CAPTION FIELDS',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.orange,
          ),
        ),
      ),
    );
  }
}
