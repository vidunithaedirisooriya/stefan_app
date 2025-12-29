import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BLEDeviceManager {
  final BluetoothDevice device;
  
  List<BluetoothService> _services = [];
  final Map<String, BluetoothCharacteristic> _characteristics = {};
  final Map<String, StreamSubscription<List<int>>> _subscriptions = {};

  // Callbacks
  final Function(int)? onTimerValueChanged;
  final Function(bool)? onPowerStateChanged;
  final Function(bool)? onTimerStateChanged;
  final Function(bool)? onSwingStateChanged;
  final Function(int)? onSpeedChanged;
  final Function(String)? onDeviceNameChanged;

  BLEDeviceManager({
    required this.device,
    this.onTimerValueChanged,
    this.onPowerStateChanged,
    this.onTimerStateChanged,
    this.onSwingStateChanged,
    this.onSpeedChanged,
    this.onDeviceNameChanged,
  });

  Future<void> discoverAndSubscribe() async {
    _services = await device.discoverServices();
    
    BluetoothService? targetService = _services.firstWhere(
      (service) => service.uuid == Guid("5cfd3a85-6b69-4396-85e3-bdef0b414d0a"),
      orElse: () => throw Exception("Service not found"),
    );

    for (var characteristic in targetService.characteristics) {
      String uuid = characteristic.uuid.toString().toUpperCase();
      _characteristics[uuid] = characteristic;
      
      if (characteristic.properties.notify) {
        await characteristic.setNotifyValue(true);
        
        _subscriptions[uuid] = characteristic.lastValueStream.listen((value) {
          if (value.isNotEmpty) {
            _handleCharacteristicUpdate(uuid, value);
          }
        });
      } else if (characteristic.properties.read) {
        try {
          List<int> value = await characteristic.read();
          if (value.isNotEmpty) {
            _handleCharacteristicUpdate(uuid, value);
          }
        } catch (e) {
          // Ignore read errors
        }
      }
    }
  }

  void _handleCharacteristicUpdate(String uuid, List<int> value) {
    switch (uuid) {
      case "5CFD3A86-6B69-4396-85E3-BDEF0B414D0A": // Power
        onPowerStateChanged?.call(value[0] == 1);
        break;
      case "5CFD3A87-6B69-4396-85E3-BDEF0B414D0A": // Timer value
        onTimerValueChanged?.call(value[0]);
        break;
      case "5CFD3A88-6B69-4396-85E3-BDEF0B414D0A": // Speed
        if (value[0] >= 1 && value[0] <= 4) {
          onSpeedChanged?.call(value[0]);
        }
        break;
      case "5CFD3A89-6B69-4396-85E3-BDEF0B414D0A": // Timer on/off
        onTimerStateChanged?.call(value[0] == 1);
        break;
      case "5CFD3A8A-6B69-4396-85E3-BDEF0B414D0A": // Swing
        onSwingStateChanged?.call(value[0] == 1);
        break;
      case "5CFD3A8B-6B69-4396-85E3-BDEF0B414D0A": // Device name
        try {
          String name = utf8.decode(value);
          if (name.isNotEmpty) {
            onDeviceNameChanged?.call(name);
          }
        } catch (e) {
          // print("Error decoding device name: $e");
        }
        break;
    }
  }

  Future<void> writeValue(String uuid, int value) async {
    BluetoothCharacteristic? characteristic = _characteristics[uuid.toUpperCase()];
    
    if (characteristic == null) {
      throw Exception("Characteristic not found");
    }
    
    if (!characteristic.properties.write && !characteristic.properties.writeWithoutResponse) {
      throw Exception("Characteristic does not support write");
    }
    
    await characteristic.write([value], withoutResponse: characteristic.properties.writeWithoutResponse);
  }

  Future<void> writeName(String name) async {
    String uuid = "5CFD3A8B-6B69-4396-85E3-BDEF0B414D0A";
    BluetoothCharacteristic? characteristic = _characteristics[uuid];
    
    if (characteristic == null) {
      throw Exception("Name characteristic not found");
    }
    
    if (!characteristic.properties.write && !characteristic.properties.writeWithoutResponse) {
      throw Exception("Characteristic does not support write");
    }
    
    List<int> nameBytes = utf8.encode(name);
    await characteristic.write(nameBytes, withoutResponse: characteristic.properties.writeWithoutResponse);
  }

  void dispose() {
    for (var subscription in _subscriptions.values) {
      subscription.cancel();
    }
    _subscriptions.clear();
  }
}