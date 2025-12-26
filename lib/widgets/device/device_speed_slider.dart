import 'package:flutter/material.dart';

class DeviceSpeedSlider extends StatelessWidget {
  final int speedValue;
  final bool isConnected;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;

  const DeviceSpeedSlider({
    super.key,
    required this.speedValue,
    required this.isConnected,
    this.onChanged,
    this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Speed',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  '$speedValue',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
            Slider(
              value: speedValue.toDouble(),
              min: 1,
              max: 4,
              divisions: 3,
              label: speedValue.toString(),
              onChanged: isConnected ? onChanged : null,
              onChangeEnd: isConnected ? onChangeEnd : null,
            ),
          ],
        ),
      ),
    );
  }
}