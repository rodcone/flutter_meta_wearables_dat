import 'package:flutter/material.dart';

class SheetHandleBar extends StatelessWidget {
  const SheetHandleBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 4,
      width: 40,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }
}
