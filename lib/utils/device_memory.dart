import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class DeviceMemory {
  static const String _keyDeviceHistory = 'device_history';
  static const int _maxDevices = 5; // Remember last 5 devices

  // Save a device to history
  static Future<void> saveDevice(String deviceId, String deviceName) async {
    final prefs = await SharedPreferences.getInstance();
    
    List<Map<String, dynamic>> history = await getDeviceHistory();
    
    // Check if device already exists
    int existingIndex = history.indexWhere((device) => device['id'] == deviceId);
    
    if (existingIndex != -1) {
      // Update last connected time and move to top
      history.removeAt(existingIndex);
    }
    
    // Add device to the front (most recent)
    history.insert(0, {
      'id': deviceId,
      'name': deviceName,
      'lastConnected': DateTime.now().millisecondsSinceEpoch,
    });
    
    // Keep only the most recent devices
    if (history.length > _maxDevices) {
      history = history.sublist(0, _maxDevices);
    }
    
    // Save to SharedPreferences
    await prefs.setString(_keyDeviceHistory, jsonEncode(history));
  }

  // Get device history
  static Future<List<Map<String, dynamic>>> getDeviceHistory() async {
    final prefs = await SharedPreferences.getInstance();
    String? historyJson = prefs.getString(_keyDeviceHistory);
    
    if (historyJson == null) {
      return [];
    }
    
    try {
      List<dynamic> decoded = jsonDecode(historyJson);
      return decoded.cast<Map<String, dynamic>>();
    } catch (e) {
      // ("Error decoding device history: $e");
      return [];
    }
  }

  // Get the most recently connected device ID
  static Future<String?> getLastConnectedDeviceId() async {
    List<Map<String, dynamic>> history = await getDeviceHistory();
    
    if (history.isEmpty) {
      return null;
    }
    
    return history.first['id'] as String?;
  }

  // Check if device is in history
  static Future<bool> isDeviceInHistory(String deviceId) async {
    List<Map<String, dynamic>> history = await getDeviceHistory();
    return history.any((device) => device['id'] == deviceId);
  }

  // Get device priority score (higher = should connect first)
  // Based on: recency (when last connected) and if it's in history
  static Future<int> getDevicePriority(String deviceId) async {
    List<Map<String, dynamic>> history = await getDeviceHistory();
    
    for (int i = 0; i < history.length; i++) {
      if (history[i]['id'] == deviceId) {
        // Priority: most recent = highest number
        // Device at index 0 (most recent) gets priority 5
        // Device at index 1 gets priority 4, etc.
        return _maxDevices - i;
      }
    }
    
    return 0; // Not in history
  }

  // Clear all device history
  static Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyDeviceHistory);
  }
}