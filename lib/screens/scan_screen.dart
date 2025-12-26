import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'device_screen.dart';
import '../utils/snackbar.dart';
import '../utils/auto_connect_manager.dart';
import '../utils/device_memory.dart';
import '../widgets/system_device_tile.dart';
import '../widgets/scan_result_tile.dart';
import '../utils/extra.dart';

class ScanScreen extends StatefulWidget {
  final VoidCallback onThemeToggle;
  final ThemeMode themeMode;

  const ScanScreen({
    super.key,
    required this.onThemeToggle,
    required this.themeMode,
  });

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  List<BluetoothDevice> _systemDevices = [];
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  bool _isAutoConnecting = false;
  late StreamSubscription<List<ScanResult>> _scanResultsSubscription;
  late StreamSubscription<bool> _isScanningSubscription;

  @override
  void initState() {
    super.initState();

    _scanResultsSubscription = FlutterBluePlus.scanResults.listen((results) {
      if (mounted) {
        setState(() => _scanResults = results);
      }
    }, onError: (e) {
      Snackbar.show(ABC.b, prettyException("Scan Error:", e), success: false);
    });

    _isScanningSubscription = FlutterBluePlus.isScanning.listen((state) {
      if (mounted) {
        setState(() => _isScanning = state);
      }
    });

    // Attempt auto-connect after a short delay
    Future.delayed(Duration(milliseconds: 500), () {
      _attemptAutoConnect();
    });
  }

  @override
  void dispose() {
    _scanResultsSubscription.cancel();
    _isScanningSubscription.cancel();
    super.dispose();
  }

  // Attempt to auto-connect to a remembered device
  Future<void> _attemptAutoConnect() async {
    if (!mounted) return;

    // Request permissions first
    bool hasPermission = await _requestPermissions();
    if (!hasPermission) {
      return;
    }

    setState(() => _isAutoConnecting = true);

    try {
      BluetoothDevice? device = await AutoConnectManager.findAndConnectToBestDevice();
      
      if (device != null && mounted) {
        // Navigate to device screen
        MaterialPageRoute route = MaterialPageRoute(
          builder: (context) => DeviceScreen(device: device),
          settings: RouteSettings(name: '/DeviceScreen'),
        );
        Navigator.of(context).push(route);
      } else if (mounted) {
        // No device found, show message
        Snackbar.show(ABC.b, "No known devices nearby", success: false);
      }
    } catch (e) {
      if (mounted) {
        print("Auto-connect error: $e");
      }
    } finally {
      if (mounted) {
        setState(() => _isAutoConnecting = false);
      }
    }
  }

  Future<bool> _requestPermissions() async {
    if (Platform.isAndroid) {
      Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();
      
      return statuses[Permission.bluetoothScan]?.isGranted ?? false;
    }
    return true;
  }

  Future<void> onScanPressed() async {
    bool hasPermission = await _requestPermissions();
    
    if (!hasPermission) {
      Snackbar.show(ABC.b, "Bluetooth permissions required", success: false);
      return;
    }

    try {
      var withServices = [Guid("180f")];
      _systemDevices = await FlutterBluePlus.systemDevices(withServices);
    } catch (e, backtrace) {
      Snackbar.show(ABC.b, prettyException("System Devices Error:", e), success: false);
      print(e);
      print("backtrace: $backtrace");
    }
    
    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        webOptionalServices: [
          Guid("180f"),
          Guid("180a"),
          Guid("1800"),
          Guid("6e400001-b5a3-f393-e0a9-e50e24dcca9e"),
        ],
      );
    } catch (e, backtrace) {
      Snackbar.show(ABC.b, prettyException("Start Scan Error:", e), success: false);
      print(e);
      print("backtrace: $backtrace");
    }
    
    if (mounted) {
      setState(() {});
    }
  }

  Future onStopPressed() async {
    try {
      FlutterBluePlus.stopScan();
    } catch (e, backtrace) {
      Snackbar.show(ABC.b, prettyException("Stop Scan Error:", e), success: false);
      print(e);
      print("backtrace: $backtrace");
    }
  }

  void onConnectPressed(BluetoothDevice device) {
    device.connectAndUpdateStream().catchError((e) {
      Snackbar.show(ABC.c, prettyException("Connect Error:", e), success: false);
    });
    MaterialPageRoute route = MaterialPageRoute(
        builder: (context) => DeviceScreen(device: device), 
        settings: RouteSettings(name: '/DeviceScreen'));
    Navigator.of(context).push(route);
  }

  Future onRefresh() {
    if (_isScanning == false) {
      FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    }
    if (mounted) {
      setState(() {});
    }
    return Future.delayed(Duration(milliseconds: 500));
  }

  Widget buildScanButton() {
    if (_isAutoConnecting) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          buildSpinner(),
          SizedBox(width: 8),
          Text("Auto-connecting...", style: TextStyle(fontSize: 12)),
        ],
      );
    }

    final button = _isScanning
        ? ElevatedButton(
            onPressed: onStopPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Colors.white,
            ),
            child: const Text("STOP"),
          )
        : ElevatedButton(
            onPressed: onScanPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
            ),
            child: const Text("SCAN"),
          );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_isScanning) buildSpinner(),
        button,
      ],
    );
  }

  Widget buildSpinner() {
    return const Padding(
      padding: EdgeInsets.only(right: 20.0),
      child: SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2.5),
      ),
    );
  }

  List<Widget> _buildSystemDeviceTiles() {
    return _systemDevices
        .map(
          (d) => SystemDeviceTile(
            device: d,
            onOpen: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => DeviceScreen(device: d),
                settings: RouteSettings(name: '/DeviceScreen'),
              ),
            ),
            onConnect: () => onConnectPressed(d),
          ),
        )
        .toList();
  }

  Iterable<Widget> _buildScanResultTiles() {
    return _scanResults.map((r) => ScanResultTile(result: r, onTap: () => onConnectPressed(r.device)));
  }

  @override
  Widget build(BuildContext context) {
    bool isDarkMode = widget.themeMode == ThemeMode.dark;
    
    return ScaffoldMessenger(
      key: Snackbar.snackBarKeyB,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Find Devices'),
          actions: [
            buildScanButton(),
            const SizedBox(width: 15),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView(
            children: <Widget>[
              ..._buildSystemDeviceTiles(),
              ..._buildScanResultTiles(),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
                onPressed: widget.onThemeToggle,
                tooltip: isDarkMode ? 'Light Mode' : 'Dark Mode',
                child: Icon(isDarkMode ? Icons.light_mode : Icons.dark_mode),
              ),
      ),
    );
  }
}