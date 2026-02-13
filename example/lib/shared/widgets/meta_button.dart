import 'package:flutter/material.dart';

class MetaButton extends StatelessWidget {
  final String? text;
  final Widget? icon;
  final VoidCallback onPressed;
  final Color? color;
  final bool enabled;
  final bool _isIconButton;

  // Constructor for text button
  const MetaButton.text({
    super.key,
    required this.text,
    required this.onPressed,
    this.color,
    this.enabled = true,
  }) : icon = null,
       _isIconButton = false;

  // Constructor for icon button (circle-shaped)
  const MetaButton.icon({
    super.key,
    required this.icon,
    required this.onPressed,
    this.color,
    this.enabled = true,
  }) : text = null,
       _isIconButton = true;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: _isIconButton ? _buildIconButton() : _buildTextButton(context),
    );
  }

  Widget _buildTextButton(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 55,
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: color,
          padding: EdgeInsets.zero,
        ),
        onPressed: () {
          if (enabled) onPressed();
        },
        child: Text(
          text!,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton() {
    return Container(
      height: 55,
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: color,
          shape: const CircleBorder(),
          padding: const EdgeInsets.all(16),
        ),
        onPressed: () {
          if (enabled) onPressed();
        },
        child: icon,
      ),
    );
  }
}
