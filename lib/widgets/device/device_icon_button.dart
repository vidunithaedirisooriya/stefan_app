import 'package:flutter/material.dart';

class DeviceIconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final bool isConnected;
  final VoidCallback onPressed;

  const DeviceIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.isActive,
    required this.isConnected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: isConnected ? onPressed : null,
          child: AnimatedOpacity(
            opacity: isConnected ? 1.0 : 0.5,
            duration: const Duration(milliseconds: 350),
            child: Container(
              decoration: BoxDecoration(
                color: isActive ? Colors.blue.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isActive ? Colors.blue : Theme.of(context).colorScheme.surfaceContainer,
                  width: 2,
                ),
              ),
              padding: const EdgeInsets.all(20),
              child: Icon(
                icon,
                size: 40,
                color: isActive ? Colors.blue : Colors.grey,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isActive ? Colors.blue : Colors.grey,
          ),
        ),
      ],
    );
  }
}