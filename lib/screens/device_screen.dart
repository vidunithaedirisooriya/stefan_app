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

  // Timer picker value and controller
  int _currentTimerValue = 0;
  FixedExtentScrollController? _pickerController;
  
  // Track if user is manually controlling the picker
  bool _userIsScrolling = false;
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
            if (mounted) {
              setState(() {
                _characteristicValues[uuid] = value;
                
                // Update timer value when received from device
                if (uuid == "5CFD3A87-6B69-4396-85E3-BDEF0B414D0A" && value.isNotEmpty) {
                  int newValue = value[0];
                  if (newValue != _currentTimerValue && !_userIsScrolling) {
                    // Only update picker if user is NOT manually scrolling
                    _currentTimerValue = newValue;
                    _pickerController?.animateToItem(
                      newValue,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  }
                }
              });
            }
          });
        } else if (characteristic.properties.read) {
          // Do initial read
          try {
            List<int> value = await characteristic.read();
            if (mounted) {
              setState(() {
                _characteristicValues[uuid] = value;
                
                // Set initial timer value
                if (uuid == "5CFD3A87-6B69-4396-85E3-BDEF0B414D0A" && value.isNotEmpty) {
                  int newValue = value[0];
                  _currentTimerValue = newValue;
                  _pickerController?.jumpToItem(newValue);
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

  // Write value 1 to a characteristic
  Future<void> writeToCharacteristic(String uuid, String buttonName) async {
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
      
      // Write value 1
      await characteristic.write([1], withoutResponse: characteristic.properties.writeWithoutResponse);
      
      Snackbar.show(ABC.c, "$buttonName activated", success: true);
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Write Error:", e), success: false);
      print(e);
    }
  }

  // Write timer value to BLE characteristic
  Future<void> writeTimerValue(int value) async {
    try {
      String uuid = "5CFD3A87-6B69-4396-85E3-BDEF0B414D0A";
      BluetoothCharacteristic? characteristic = _characteristics[uuid];
      
      if (characteristic == null) {
        Snackbar.show(ABC.c, "Timer characteristic not found", success: false);
        return;
      }
      
      if (!characteristic.properties.write && !characteristic.properties.writeWithoutResponse) {
        Snackbar.show(ABC.c, "Timer characteristic does not support write", success: false);
        return;
      }
      
      print("Writing timer value: $value");
      
      // Write the value
      await characteristic.write([value], withoutResponse: characteristic.properties.writeWithoutResponse);
      
      Snackbar.show(ABC.c, "Timer set to $value", success: true);
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Timer Write Error:", e), success: false);
      print(e);
    }
  }

  // Handle user scrolling the picker
  void onPickerChanged(int index) {
    // User is actively scrolling
    setState(() {
      _userIsScrolling = true;
      _currentTimerValue = index;
    });
    
    print("User scrolling to: $index");
    
    // Cancel previous timer if exists
    _scrollDebounceTimer?.cancel();
    
    // Start a new timer - write value after user stops scrolling for 500ms
    _scrollDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      print("User stopped scrolling at: $index, writing to BLE");
      writeTimerValue(index);
      
      // Re-enable automatic updates after a short delay
      Future.delayed(const Duration(milliseconds: 100), () {
        setState(() {
          _userIsScrolling = false;
        });
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

  // Build the permanent timer picker
  Widget buildTimerPicker() {
    return Card(
      elevation: 2,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.timer, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  'Timer Value',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                if (_userIsScrolling) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(
            height: 150,
            child: CupertinoPicker(
              scrollController: _pickerController,
              itemExtent: 40,
              onSelectedItemChanged: onPickerChanged,
              children: List<Widget>.generate(256, (int index) {
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
          // Permanent Timer Picker
          buildTimerPicker(),
          
          const SizedBox(height: 20),
          
          // Power Button
          ElevatedButton.icon(
            onPressed: isConnected 
              ? () => writeToCharacteristic("5cfd3a86-6b69-4396-85e3-bdef0b414d0a", "Power")
              : null,
            icon: const Icon(Icons.power_settings_new, size: 28),
            label: const Text("Power On/Off", style: TextStyle(fontSize: 18)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 60),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Speed Button
          ElevatedButton.icon(
            onPressed: isConnected 
              ? () => writeToCharacteristic("5cfd3a88-6b69-4396-85e3-bdef0b414d0a", "Speed")
              : null,
            icon: const Icon(Icons.speed, size: 28),
            label: const Text("Speed (1-4)", style: TextStyle(fontSize: 18)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 60),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Timer On/Off Button
          ElevatedButton.icon(
            onPressed: isConnected 
              ? () => writeToCharacteristic("5cfd3a89-6b69-4396-85e3-bdef0b414d0a", "Timer")
              : null,
            icon: const Icon(Icons.timer_outlined, size: 28),
            label: const Text("Timer On/Off", style: TextStyle(fontSize: 18)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 60),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Swing Button
          ElevatedButton.icon(
            onPressed: isConnected 
              ? () => writeToCharacteristic("5cfd3a8a-6b69-4396-85e3-bdef0b414d0a", "Swing")
              : null,
            icon: const Icon(Icons.sync, size: 28),
            label: const Text("Swing", style: TextStyle(fontSize: 18)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 60),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
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