import 'package:flutter/material.dart';

class MetadataWidget extends StatelessWidget {
  const MetadataWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.purple, width: 3.0),
        borderRadius: BorderRadius.circular(8),
        color: Colors.purple.shade50,
      ),
      child: const Center(
        child: Text(
          'METADATA',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.purple,
          ),
        ),
      ),
    );
  }
}
