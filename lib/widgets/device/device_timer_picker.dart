import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

class DeviceTimerPicker extends StatelessWidget {
  final int currentTimerValue;
  final bool isTimerOn;
  final bool isConnected;
  final FixedExtentScrollController? scrollController;
  final ValueChanged<int> onSelectedItemChanged;
  final VoidCallback onStartTimerPressed;

  const DeviceTimerPicker({
    super.key,
    required this.currentTimerValue,
    required this.isTimerOn,
    required this.isConnected,
    required this.scrollController,
    required this.onSelectedItemChanged,
    required this.onStartTimerPressed,
  });

  String _getTimerEndTime() {
    if (currentTimerValue == 0) return "";
    
    DateTime now = DateTime.now();
    DateTime endTime = now.add(Duration(minutes: currentTimerValue));
    
    String hour = endTime.hour.toString().padLeft(2, '0');
    String minute = endTime.minute.toString().padLeft(2, '0');
    
    return "$hour:$minute";
  }

  @override
  Widget build(BuildContext context) {
    String endTime = _getTimerEndTime();
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            // Cupertino Picker
            Expanded(
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 150,
                    child: CupertinoPicker(
                      scrollController: scrollController,
                      itemExtent: 40,
                      looping: false,
                      onSelectedItemChanged: onSelectedItemChanged,
                      children: List<Widget>.generate(100, (int index) {
                        return Center(
                          child: Text(
                            '$index',
                            style: const TextStyle(fontSize: 20),
                          ),
                        );
                      }),
                    ),
                  ),
                  const Text(
                    'Minutes',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(width: 16),
            
            // Start Timer Button
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: isConnected ? onStartTimerPressed : null,
                  child: AnimatedOpacity(
                    opacity: isConnected ? 1.0 : 0.5,
                    duration: const Duration(milliseconds: 350),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isTimerOn ? Colors.orange.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isTimerOn ? Colors.orange : Theme.of(context).colorScheme.surfaceContainer,
                          width: 2,
                        ),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Icon(
                        Icons.hourglass_bottom,
                        size: 32,
                        color: isTimerOn ? Colors.orange : Colors.grey,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isTimerOn ? 'Timer\nStarted' : 'Start\nTimer',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isTimerOn ? FontWeight.bold : FontWeight.normal,
                    color: isTimerOn ? Colors.orange : Colors.grey,
                  ),
                ),
                if (isTimerOn && endTime.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    endTime,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}