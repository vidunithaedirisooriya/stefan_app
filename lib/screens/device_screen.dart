import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../utils/snackbar.dart';
import '../utils/extra.dart';
import '../utils/ble_device_manager.dart';
import '../utils/device_memory.dart';
import '../widgets/device/device_icon_button.dart';
import '../widgets/device/device_speed_slider.dart';
import '../widgets/device/device_timer_picker.dart';
import '../widgets/device/device_rename_dialog.dart';

class DeviceScreen extends StatefulWidget {
  final BluetoothDevice device;

  const DeviceScreen({super.key, required this.device});

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  BluetoothConnectionState _connectionState = BluetoothConnectionState.disconnected;
  bool _isConnecting = false;
  bool _isDisconnecting = false;
  
  // BLE Manager
  late BLEDeviceManager _bleManager;
  
  // State values
  int _currentTimerValue = 0;
  bool _isPowerOn = false;
  bool _isTimerOn = false;
  bool _isSwingOn = false;
  int _speedValue = 1;
  String _deviceName = "";
  
  FixedExtentScrollController? _pickerController;
  
  // Track if user is manually controlling
  bool _userIsScrollingPicker = false;
  bool _userIsMovingSlider = false;
  Timer? _scrollDebounceTimer;

  late StreamSubscription<BluetoothConnectionState> _connectionStateSubscription;
  late StreamSubscription<bool> _isConnectingSubscription;
  late StreamSubscription<bool> _isDisconnectingSubscription;

  @override
  void initState() {
    super.initState();

    _deviceName = widget.device.platformName;
    _pickerController = FixedExtentScrollController(initialItem: _currentTimerValue);

    // Initialize BLE Manager with callbacks
    _bleManager = BLEDeviceManager(
      device: widget.device,
      onTimerValueChanged: (value) {
        if (!_userIsScrollingPicker && value != _currentTimerValue) {
          setState(() => _currentTimerValue = value);
          _pickerController?.animateToItem(
            value,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
      },
      onPowerStateChanged: (state) => setState(() => _isPowerOn = state),
      onTimerStateChanged: (state) => setState(() => _isTimerOn = state),
      onSwingStateChanged: (state) => setState(() => _isSwingOn = state),
      onSpeedChanged: (speed) {
        if (!_userIsMovingSlider) {
          setState(() => _speedValue = speed);
        }
      },
      onDeviceNameChanged: (name) => setState(() => _deviceName = name),
    );

        _connectionStateSubscription = widget.device.connectionState.listen((state) async {
      _connectionState = state;

      if (state == BluetoothConnectionState.connected) {
        // Save device to memory
        await DeviceMemory.saveDevice(
          widget.device.remoteId.toString(),
          widget.device.platformName,
        );

        try {
          await _bleManager.discoverAndSubscribe();
          if (mounted) {
            Snackbar.show(ABC.c, "Connected to remote", success: true);
          }
        } catch (e) {
          if (mounted) {
            Snackbar.show(ABC.c, prettyException("Discover Services Error:", e), success: false);
          }
        }
      }

      // REMOVED: Auto-navigate back if disconnected
      // Only show a message, don't navigate
      if (state == BluetoothConnectionState.disconnected) {
        if (mounted) {
          Snackbar.show(ABC.c, "Device disconnected", success: false);
          // DO NOT call Navigator.of(context).pop() here
        }
      }

      if (mounted) {
        setState(() {});
      }
    });

    _isConnectingSubscription = widget.device.isConnecting.listen((value) {
      if (mounted) {
        setState(() => _isConnecting = value);
      }
    });

    _isDisconnectingSubscription = widget.device.isDisconnecting.listen((value) {
      if (mounted) {
        setState(() => _isDisconnecting = value);
      }
    });
  }

  @override
  void dispose() {
    _connectionStateSubscription.cancel();
    _isConnectingSubscription.cancel();
    _isDisconnectingSubscription.cancel();
    _pickerController?.dispose();
    _scrollDebounceTimer?.cancel();
    _bleManager.dispose();
    super.dispose();
  }

  bool get isConnected => _connectionState == BluetoothConnectionState.connected;

  Future<void> showRenameDialog() async {
    String? newName = await DeviceRenameDialog.show(context, _deviceName);
    
    if (newName != null) {
      try {
        await _bleManager.writeName(newName);
        setState(() {
          _deviceName = newName.isEmpty ? widget.device.platformName : newName;
        });
        if (mounted) {
          Snackbar.show(ABC.c, "Device renamed successfully", success: true);
        }
      } catch (e) {
        if (mounted) {
          Snackbar.show(ABC.c, prettyException("Rename Error:", e), success: false);
        }
      }
    }
  }

  Future<void> writeToCharacteristic(String uuid, int value, String buttonName) async {
    try {
      await _bleManager.writeValue(uuid, value);
      if (mounted) {
        Snackbar.show(ABC.c, "$buttonName activated", success: true);
      }
    } catch (e) {
      if (mounted) {
        Snackbar.show(ABC.c, prettyException("Write Error:", e), success: false);
      }
    }
  }

  void onPickerChanged(int index) {
    setState(() {
      _userIsScrollingPicker = true;
      _currentTimerValue = index;
    });
    
    _scrollDebounceTimer?.cancel();
    _scrollDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      writeToCharacteristic("5cfd3a87-6b69-4396-85e3-bdef0b414d0a", index, "Timer");
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          setState(() => _userIsScrollingPicker = false);
        }
      });
    });
  }

  void onSpeedChanged(double value) {
    setState(() {
      _userIsMovingSlider = true;
      _speedValue = value.round();
    });
  }

  void onSpeedChangeEnd(double value) {
    int speed = value.round();
    writeToCharacteristic("5cfd3a88-6b69-4396-85e3-bdef0b414d0a", speed, "Speed");
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        setState(() => _userIsMovingSlider = false);
      }
    });
  }

  Widget buildRemoteControl() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top row: Power and Swing icons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: DeviceIconButton(
                  icon: Icons.power_settings_new,
                  label: 'Power',
                  isActive: _isPowerOn,
                  isConnected: isConnected,
                  onPressed: () => writeToCharacteristic("5cfd3a86-6b69-4396-85e3-bdef0b414d0a", 1, "Power"),
                ),
              ),
              DeviceIconButton(
                icon: Icons.sync,
                label: 'Swing',
                isActive: _isSwingOn,
                isConnected: isConnected,
                onPressed: () => writeToCharacteristic("5cfd3a8a-6b69-4396-85e3-bdef0b414d0a", 1, "Swing"),
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          // Speed Slider
          DeviceSpeedSlider(
            speedValue: _speedValue,
            isConnected: isConnected,
            onChanged: onSpeedChanged,
            onChangeEnd: onSpeedChangeEnd,
          ),
          
          const SizedBox(height: 20),
          
          // Timer Picker
          DeviceTimerPicker(
            currentTimerValue: _currentTimerValue,
            isTimerOn: _isTimerOn,
            isConnected: isConnected,
            scrollController: _pickerController,
            onSelectedItemChanged: onPickerChanged,
            onStartTimerPressed: () => writeToCharacteristic("5cfd3a89-6b69-4396-85e3-bdef0b414d0a", 1, "Timer"),
          ),
        ],
      ),
    );
  }

  @override
  @override
Widget build(BuildContext context) {
  return PopScope(
    canPop: false, // Prevent automatic pop
    onPopInvokedWithResult: (bool didPop, dynamic result) async {
      if (didPop) {
        return; // Already popped, do nothing
      }
      
      // Disconnect first
      if (isConnected) {
        try {
          await widget.device.disconnect();
        } catch (e) {
          print("Error disconnecting on back: $e");
        }
      }
      
      // Then manually pop
      if (mounted) {
        Navigator.of(context).pop();
      }
    },
    child: ScaffoldMessenger(
      key: Snackbar.snackBarKeyC,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              // Disconnect when back button pressed
              if (isConnected) {
                try {
                  await widget.device.disconnect();
                } catch (e) {
                  print("Error disconnecting: $e");
                }
              }
              Navigator.pop(context);
            },
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  _deviceName,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: showRenameDialog,
                tooltip: 'Rename device',
              ),
            ],
          ),
        ),
        body: SingleChildScrollView(
          child: isConnected 
            ? buildRemoteControl()
            : const Center(
                child: Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Text('Connecting to remote...'),
                ),
              ),
        ),
      ),
    ),
  );
}
}