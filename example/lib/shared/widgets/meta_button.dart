import 'package:flutter/material.dart';

enum _MetaButtonVariant { primaryText, secondaryText, icon }

class MetaButton extends StatelessWidget {
  final String? text;
  final Widget? icon;
  final VoidCallback onPressed;
  final Color? color;
  final bool enabled;
  final _MetaButtonVariant _variant;

  // Primary text button — full-height (55), used for main actions.
  const MetaButton.text({
    super.key,
    required this.text,
    required this.onPressed,
    this.color,
    this.enabled = true,
  }) : icon = null,
       _variant = _MetaButtonVariant.primaryText;

  // Secondary text button — reduced height, suited for dense tool rows.
  const MetaButton.secondary({
    super.key,
    required this.text,
    required this.onPressed,
    this.color,
    this.enabled = true,
  }) : icon = null,
       _variant = _MetaButtonVariant.secondaryText;

  // Icon button (circle-shaped)
  const MetaButton.icon({
    super.key,
    required this.icon,
    required this.onPressed,
    this.color,
    this.enabled = true,
  }) : text = null,
       _variant = _MetaButtonVariant.icon;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: switch (_variant) {
        _MetaButtonVariant.primaryText => _buildTextButton(context),
        _MetaButtonVariant.secondaryText => _buildSecondaryTextButton(context),
        _MetaButtonVariant.icon => _buildIconButton(),
      },
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

  Widget _buildSecondaryTextButton(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 36,
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: FilledButton.tonal(
        style: FilledButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(0, 36),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: () {
          if (enabled) onPressed();
        },
        child: Text(
          text!,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: color == null ? null : Colors.white,
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
