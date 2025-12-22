import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../utils/snackbar.dart';
import '../utils/extra.dart';

class DeviceScreen extends StatefulWidget {
  final BluetoothDevice device;

  const DeviceScreen({super.key, required this.device});

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  BluetoothConnectionState _connectionState = BluetoothConnectionState.disconnected;
  List<BluetoothService> _services = [];
  bool _isConnecting = false;
  bool _isDisconnecting = false;
  
  // Store characteristic objects for easy access
  Map<String, BluetoothCharacteristic> _characteristics = {};
  
  // Store characteristic values
  Map<String, List<int>> _characteristicValues = {};
  Map<String, StreamSubscription<List<int>>> _characteristicSubscriptions = {};

  // State values
  int _currentTimerValue = 0;
  bool _isPowerOn = false;
  bool _isTimerOn = false;
  bool _isSwingOn = false;
  int _speedValue = 1;
  
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

    _pickerController = FixedExtentScrollController(initialItem: _currentTimerValue);

    _connectionStateSubscription = widget.device.connectionState.listen((state) async {
      _connectionState = state;
      
      if (state == BluetoothConnectionState.connected) {
        await _discoverAndSubscribe();
      }
      
      if (mounted) {
        setState(() {});
      }
    });

    _isConnectingSubscription = widget.device.isConnecting.listen((value) {
      _isConnecting = value;
      if (mounted) {
        setState(() {});
      }
    });

    _isDisconnectingSubscription = widget.device.isDisconnecting.listen((value) {
      _isDisconnecting = value;
      if (mounted) {
        setState(() {});
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
    
    for (var subscription in _characteristicSubscriptions.values) {
      subscription.cancel();
    }
    
    super.dispose();
  }

  bool get isConnected {
    return _connectionState == BluetoothConnectionState.connected;
  }

  // Calculate end time
  String getTimerEndTime() {
    if (_currentTimerValue == 0) return "";
    
    DateTime now = DateTime.now();
    DateTime endTime = now.add(Duration(minutes: _currentTimerValue));
    
    String hour = endTime.hour.toString().padLeft(2, '0');
    String minute = endTime.minute.toString().padLeft(2, '0');
    
    return "$hour:$minute";
  }

  Future<void> _discoverAndSubscribe() async {
    try {
      _services = await widget.device.discoverServices();
      
      BluetoothService? targetService;
      try {
        targetService = _services.firstWhere(
          (service) => service.uuid == Guid("5cfd3a85-6b69-4396-85e3-bdef0b414d0a"),
        );
      } catch (e) {
        Snackbar.show(ABC.c, "Service not found on this device", success: false);
        return;
      }

      // Store characteristics for easy access and subscribe to all
      for (var characteristic in targetService.characteristics) {
        String uuid = characteristic.uuid.toString().toUpperCase();
        _characteristics[uuid] = characteristic;
        
        // Subscribe to notifications if supported
        if (characteristic.properties.notify) {
          await characteristic.setNotifyValue(true);
          
          _characteristicSubscriptions[uuid] = characteristic.lastValueStream.listen((value) {
            if (mounted && value.isNotEmpty) {
              setState(() {
                _characteristicValues[uuid] = value;
                
                // Update state based on characteristic
                switch (uuid) {
                  case "5CFD3A86-6B69-4396-85E3-BDEF0B414D0A": // Power
                    _isPowerOn = value[0] == 1;
                    break;
                  case "5CFD3A87-6B69-4396-85E3-BDEF0B414D0A": // Timer value
                    int newValue = value[0];
                    if (newValue != _currentTimerValue && !_userIsScrollingPicker) {
                      _currentTimerValue = newValue;
                      _pickerController?.animateToItem(
                        newValue,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    }
                    break;
                  case "5CFD3A88-6B69-4396-85E3-BDEF0B414D0A": // Speed
                    int newSpeed = value[0];
                    if (newSpeed >= 1 && newSpeed <= 4 && !_userIsMovingSlider) {
                      _speedValue = newSpeed;
                    }
                    break;
                  case "5CFD3A89-6B69-4396-85E3-BDEF0B414D0A": // Timer on/off
                    _isTimerOn = value[0] == 1;
                    break;
                  case "5CFD3A8A-6B69-4396-85E3-BDEF0B414D0A": // Swing
                    _isSwingOn = value[0] == 1;
                    break;
                }
              });
            }
          });
        } else if (characteristic.properties.read) {
          // Do initial read
          try {
            List<int> value = await characteristic.read();
            if (mounted && value.isNotEmpty) {
              setState(() {
                _characteristicValues[uuid] = value;
                
                // Set initial values
                switch (uuid) {
                  case "5CFD3A86-6B69-4396-85E3-BDEF0B414D0A":
                    _isPowerOn = value[0] == 1;
                    break;
                  case "5CFD3A87-6B69-4396-85E3-BDEF0B414D0A":
                    _currentTimerValue = value[0];
                    _pickerController?.jumpToItem(value[0]);
                    break;
                  case "5CFD3A88-6B69-4396-85E3-BDEF0B414D0A":
                    if (value[0] >= 1 && value[0] <= 4) {
                      _speedValue = value[0];
                    }
                    break;
                  case "5CFD3A89-6B69-4396-85E3-BDEF0B414D0A":
                    _isTimerOn = value[0] == 1;
                    break;
                  case "5CFD3A8A-6B69-4396-85E3-BDEF0B414D0A":
                    _isSwingOn = value[0] == 1;
                    break;
                }
              });
            }
          } catch (e) {
            // Ignore read errors
          }
        }
      }

      Snackbar.show(ABC.c, "Connected to remote", success: true);
      
    } catch (e, backtrace) {
      Snackbar.show(ABC.c, prettyException("Discover Services Error:", e), success: false);
      print(e);
      print("backtrace: $backtrace");
    }
  }

  Future onConnectPressed() async {
    try {
      await widget.device.connectAndUpdateStream();
      Snackbar.show(ABC.c, "Connect: Success", success: true);
    } catch (e, backtrace) {
      if (e is FlutterBluePlusException && e.code == FbpErrorCode.connectionCanceled.index) {
        // ignore connections canceled by the user
      } else {
        Snackbar.show(ABC.c, prettyException("Connect Error:", e), success: false);
        print(e);
        print("backtrace: $backtrace");
      }
    }
  }

  Future onCancelPressed() async {
    try {
      await widget.device.disconnectAndUpdateStream(queue: false);
      Snackbar.show(ABC.c, "Cancel: Success", success: true);
    } catch (e, backtrace) {
      Snackbar.show(ABC.c, prettyException("Cancel Error:", e), success: false);
      print("$e");
      print("backtrace: $backtrace");
    }
  }

  Future onDisconnectPressed() async {
    try {
      await widget.device.disconnectAndUpdateStream();
      Snackbar.show(ABC.c, "Disconnect: Success", success: true);
    } catch (e, backtrace) {
      Snackbar.show(ABC.c, prettyException("Disconnect Error:", e), success: false);
      print("$e backtrace: $backtrace");
    }
  }

  // Write value to a characteristic
  Future<void> writeToCharacteristic(String uuid, int value, String buttonName) async {
    try {
      BluetoothCharacteristic? characteristic = _characteristics[uuid.toUpperCase()];
      
      if (characteristic == null) {
        Snackbar.show(ABC.c, "Characteristic not found", success: false);
        return;
      }
      
      if (!characteristic.properties.write && !characteristic.properties.writeWithoutResponse) {
        Snackbar.show(ABC.c, "Characteristic does not support write", success: false);
        return;
      }
      
      await characteristic.write([value], withoutResponse: characteristic.properties.writeWithoutResponse);
      
      Snackbar.show(ABC.c, "$buttonName activated", success: true);
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Write Error:", e), success: false);
      print(e);
    }
  }

  // Handle user scrolling the picker
  void onPickerChanged(int index) {
    setState(() {
      _userIsScrollingPicker = true;
      _currentTimerValue = index;
    });
    
    _scrollDebounceTimer?.cancel();
    
    _scrollDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      writeToCharacteristic("5cfd3a87-6b69-4396-85e3-bdef0b414d0a", index, "Timer");
      
      Future.delayed(const Duration(milliseconds: 100), () {
        setState(() {
          _userIsScrollingPicker = false;
        });
      });
    });
  }

  // Handle speed slider change
  void onSpeedChanged(double value) {
    setState(() {
      _userIsMovingSlider = true;
      _speedValue = value.round();
    });
  }

  // Handle speed slider release
  void onSpeedChangeEnd(double value) {
    int speed = value.round();
    writeToCharacteristic("5cfd3a88-6b69-4396-85e3-bdef0b414d0a", speed, "Speed");
    
    Future.delayed(const Duration(milliseconds: 100), () {
      setState(() {
        _userIsMovingSlider = false;
      });
    });
  }

  Widget buildSpinner(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14.0),
      child: AspectRatio(
        aspectRatio: 1.0,
        child: CircularProgressIndicator(
          backgroundColor: Colors.black12,
          color: Colors.black26,
        ),
      ),
    );
  }

  // Build icon button with opacity fade
  Widget buildIconButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onPressed,
  }) {
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
                  color: isActive ? Colors.blue : Colors.grey,
                  width: 2,
                ),
              ),
              padding: const EdgeInsets.all(25.0),
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

  // Build the speed slider
  Widget buildSpeedSlider() {
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
                  '$_speedValue',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
            Slider(
              value: _speedValue.toDouble(),
              min: 1,
              max: 4,
              divisions: 3,
              label: _speedValue.toString(),
              onChanged: isConnected ? onSpeedChanged : null,
              onChangeEnd: isConnected ? onSpeedChangeEnd : null,
            ),
          ],
        ),
      ),
    );
  }

  // Build the permanent timer picker
  Widget buildTimerPicker() {
    String endTime = getTimerEndTime();
    
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
                  const Text(
                    'Minutes',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 150,
                    child: CupertinoPicker(
                      scrollController: _pickerController,
                      itemExtent: 40,
                      looping: false, // No looping
                      onSelectedItemChanged: onPickerChanged,
                      children: List<Widget>.generate(100, (int index) { // 0-99
                        return Center(
                          child: Text(
                            '$index',
                            style: const TextStyle(fontSize: 20),
                          ),
                        );
                      }),
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
                  onTap: isConnected 
                    ? () => writeToCharacteristic("5cfd3a89-6b69-4396-85e3-bdef0b414d0a", 1, "Timer")
                    : null,
                  child: AnimatedOpacity(
                    opacity: isConnected ? 1.0 : 0.5,
                    duration: const Duration(milliseconds: 350),
                    child: Container(
                      decoration: BoxDecoration(
                        color: _isTimerOn ? Colors.orange.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _isTimerOn ? Colors.orange : Colors.grey,
                          width: 2,
                        ),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Icon(
                        Icons.hourglass_bottom,
                        size: 32,
                        color: _isTimerOn ? Colors.orange : Colors.grey,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isTimerOn ? 'Timer\nStarted' : 'Start\nTimer',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: _isTimerOn ? FontWeight.bold : FontWeight.normal,
                    color: _isTimerOn ? Colors.orange : Colors.grey,
                  ),
                ),
                if (_isTimerOn && endTime.isNotEmpty) ...[
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

  // Build the remote control interface
  Widget buildRemoteControl() {
    if (_characteristics.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20.0),
          child: Text('Connecting to remote...'),
        ),
      );
    }

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
                padding: const EdgeInsets.symmetric(vertical: 35.0),
                child: buildIconButton(
                  icon: Icons.power_settings_new,
                  label: 'Power',
                  isActive: _isPowerOn,
                  onPressed: () => writeToCharacteristic("5cfd3a86-6b69-4396-85e3-bdef0b414d0a", 1, "Power"),
                ),
              ),
              buildIconButton(
                icon: Icons.sync,
                label: 'Swing',
                isActive: _isSwingOn,
                onPressed: () => writeToCharacteristic("5cfd3a8a-6b69-4396-85e3-bdef0b414d0a", 1, "Swing"),
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          // Speed Slider
          buildSpeedSlider(),
          
          const SizedBox(height: 20),
          
          // Timer Picker with Start Timer button
          buildTimerPicker(),
        ],
      ),
    );
  }

  Widget buildConnectButton(BuildContext context) {
    return Row(children: [
      if (_isConnecting || _isDisconnecting) buildSpinner(context),
      ElevatedButton(
          onPressed: _isConnecting ? onCancelPressed : (isConnected ? onDisconnectPressed : onConnectPressed),
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).primaryColor,
            foregroundColor: Colors.white,
          ),
          child: Text(
            _isConnecting ? "CANCEL" : (isConnected ? "DISCONNECT" : "CONNECT"),
            style: Theme.of(context).primaryTextTheme.labelLarge?.copyWith(color: Colors.white),
          ))
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: Snackbar.snackBarKeyC,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.device.platformName),
          actions: [buildConnectButton(context), const SizedBox(width: 15)],
        ),
        body: SingleChildScrollView(
          child: buildRemoteControl(),
        ),
      ),
    );
  }
}