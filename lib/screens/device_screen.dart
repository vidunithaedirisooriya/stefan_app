import 'dart:async';

import 'package:flutter/material.dart';
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

  late StreamSubscription<BluetoothConnectionState> _connectionStateSubscription;
  late StreamSubscription<bool> _isConnectingSubscription;
  late StreamSubscription<bool> _isDisconnectingSubscription;

  @override
  void initState() {
    super.initState();

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

    // Get timer value if available
    String timerValue = "N/A";
    List<int>? timerData = _characteristicValues["5CFD3A87-6B69-4396-85E3-BDEF0B414D0A"];
    if (timerData != null && timerData.isNotEmpty) {
      timerValue = timerData[0].toString();
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timer Display
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  const Icon(Icons.timer, size: 40, color: Colors.blue),
                  const SizedBox(height: 8),
                  const Text(
                    'Timer Value',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    timerValue,
                    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.blue),
                  ),
                ],
              ),
            ),
          ),
          
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