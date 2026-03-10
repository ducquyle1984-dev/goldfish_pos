import 'package:flutter/material.dart';

/// A numeric grid pad used for touchscreen PIN entry.
///
/// Digits [0-9] and a backspace key are reported through [onDigit] and
/// [onDelete] respectively. Plug the callbacks into a [TextEditingController]
/// to drive any PIN field.
class PinNumpad extends StatelessWidget {
  const PinNumpad({super.key, required this.onDigit, required this.onDelete});

  final void Function(String digit) onDigit;
  final VoidCallback onDelete;

  static const _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in _rows) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: row
                .map((d) => _NumKey(label: d, onTap: () => onDigit(d)))
                .toList(),
          ),
          const SizedBox(height: 8),
        ],
        // Bottom row: blank spacer | 0 | backspace
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 68 + 12), // matches one key + padding
            _NumKey(label: '0', onTap: () => onDigit('0')),
            _NumKey(icon: Icons.backspace_outlined, onTap: onDelete),
          ],
        ),
      ],
    );
  }
}

class _NumKey extends StatelessWidget {
  const _NumKey({this.label, this.icon, required this.onTap});

  final String? label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      child: Material(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 68,
            height: 52,
            child: Center(
              child: label != null
                  ? Text(
                      label!,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 22,
                        fontWeight: FontWeight.w500,
                      ),
                    )
                  : Icon(icon, color: cs.onSurface, size: 22),
            ),
          ),
        ),
      ),
    );
  }
}

/// Appends [digit] to the controller, keeping the cursor at the end.
void pinNumpadAppend(TextEditingController ctrl, String digit) {
  final text = ctrl.text + digit;
  ctrl.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );
}

/// Removes the last character from the controller.
void pinNumpadDelete(TextEditingController ctrl) {
  if (ctrl.text.isEmpty) return;
  final text = ctrl.text.substring(0, ctrl.text.length - 1);
  ctrl.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );
}
