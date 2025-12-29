import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'device_memory.dart';

class AutoConnectManager {
  static const int _scanDuration = 3; // Scan for 5 seconds
  static const int _minRSSI = -95; // Only consider devices with RSSI > -80
  
  // Find and connect to the best available device
  static Future<BluetoothDevice?> findAndConnectToBestDevice() async {
    try {
      // print("Starting auto-connect scan...");
      
      // Start scanning
      List<ScanResult> foundDevices = [];
      
      StreamSubscription<List<ScanResult>>? subscription;
      subscription = FlutterBluePlus.scanResults.listen((results) {
        foundDevices = results;
      });
      
      await FlutterBluePlus.startScan(
        timeout: Duration(seconds: _scanDuration),
        androidUsesFineLocation: false,
      );
      
      // Wait for scan to complete
      await Future.delayed(Duration(seconds: _scanDuration));
      await subscription.cancel();
      
      if (foundDevices.isEmpty) {
        // print("No devices found during auto-connect");
        return null;
      }
      
      // print("Found ${foundDevices.length} devices");
      
      // Filter and score devices
      List<Map<String, dynamic>> scoredDevices = [];
      
      for (var result in foundDevices) {
        String deviceId = result.device.remoteId.toString();
        int rssi = result.rssi;
        
        // Skip devices with weak signal
        if (rssi < _minRSSI) {
          continue;
        }
        
        // Get priority from history
        int historyPriority = await DeviceMemory.getDevicePriority(deviceId);
        
        // Skip devices not in history
        if (historyPriority == 0) {
          continue;
        }
        
        // Calculate score: history priority (0-5) + normalized RSSI (0-10)
        // RSSI range: -80 to -30 (stronger signal = higher score)
        int rssiScore = ((rssi + 80) / 5).round().clamp(0, 10);
        int totalScore = (historyPriority * 10) + rssiScore;
        
        scoredDevices.add({
          'device': result.device,
          'score': totalScore,
          'rssi': rssi,
          'historyPriority': historyPriority,
        });
        
        // print("Device: ${result.device.platformName} | RSSI: $rssi | Priority: $historyPriority | Score: $totalScore");
      }
      
      if (scoredDevices.isEmpty) {
        // print("No known devices found nearby");
        return null;
      }
      
      // Sort by score (highest first)
      scoredDevices.sort((a, b) => b['score'].compareTo(a['score']));
      
      // Get the best device
      BluetoothDevice bestDevice = scoredDevices.first['device'];
      
      // print("Best device to connect: ${bestDevice.platformName} (Score: ${scoredDevices.first['score']})");
      
      // Try to connect
      try {
        await bestDevice.connect(timeout: Duration(seconds: 10));
        // print("Successfully connected to ${bestDevice.platformName}");
        return bestDevice;
      } catch (e) {
        // print("Failed to connect to best device: $e");
        
        // Try the next best device if available
        if (scoredDevices.length > 1) {
          try {
            BluetoothDevice secondBest = scoredDevices[1]['device'];
            await secondBest.connect(timeout: Duration(seconds: 10));
            // print("Connected to second best device: ${secondBest.platformName}");
            return secondBest;
          } catch (e2) {
            // print("Failed to connect to second best device: $e2");
          }
        }
        
        return null;
      }
      
    } catch (e) {
      // print("Error in auto-connect: $e");
      return null;
    }
  }
  
  // Check if a specific device is available and connect
  static Future<bool> connectToDevice(String deviceId) async {
    try {
      List<ScanResult> foundDevices = [];
      
      // Subscribe to scan results
      StreamSubscription<List<ScanResult>>? subscription;
      subscription = FlutterBluePlus.scanResults.listen((results) {
        foundDevices = results;
      });
      
      // Start scanning
      await FlutterBluePlus.startScan(timeout: Duration(seconds: 3));
      
      // Wait for scan to complete
      await Future.delayed(Duration(seconds: 3));
      await subscription.cancel();
      
      // Look for the device in scan results
      for (var result in foundDevices) {
        if (result.device.remoteId.toString() == deviceId) {
          try {
            await result.device.connect(timeout: Duration(seconds: 10));
            return true;
          } catch (e) {
            // print("Failed to connect to device: $e");
            return false;
          }
        }
      }
      
      return false;
    } catch (e) {
      // print("Error connecting to specific device: $e");
      return false;
    }
  }
}