import 'package:flutter/material.dart';

class InfoBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? bg;
  final Color? fg;

  const InfoBadge(this.icon, this.label, {super.key, this.bg, this.fg});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final back = bg ?? cs.secondaryContainer;
    final front = fg ?? cs.onSecondaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: back,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: front),
          const SizedBox(width: 4),
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: front)),
        ],
      ),
    );
  }
}
