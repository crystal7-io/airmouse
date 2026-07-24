import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:air_mouse_app/src/rust/api/simple.dart';
import 'package:air_mouse_app/src/rust/frb_generated.dart';

const String targetServiceUuid = "19b10000-e8f2-537e-4f6c-d104768a1214";
const String targetCharUuid = "19b10001-e8f2-537e-4f6c-d104768a1214";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  runApp(const AirMouseApp());
}

class AirMouseApp extends StatelessWidget {
  const AirMouseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const AirMouseHomeScreen(),
    );
  }
}

class AirMouseHomeScreen extends StatefulWidget {
  const AirMouseHomeScreen({super.key});

  @override
  State<AirMouseHomeScreen> createState() => _AirMouseHomeScreenState();
}

class _AirMouseHomeScreenState extends State<AirMouseHomeScreen> {
  List<ScanResult> _scanResults = [];
  BluetoothDevice? _connectedDevice;
  StreamSubscription? _scanSub;
  StreamSubscription? _notifySub;
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  void _startScan() async {
    setState(() {
      _isScanning = true;
      _scanResults = [];
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));

    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      if (mounted) {
        setState(() {
          _scanResults = results;
        });
      }
    });

    await Future.delayed(const Duration(seconds: 5));
    if (mounted) setState(() => _isScanning = false);
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    await FlutterBluePlus.stopScan();
    await device.connect(license: License.free);

    setState(() {
      _connectedDevice = device;
    });

    List<BluetoothService> services = await device.discoverServices();
    for (var service in services) {
      if (service.uuid.toString().toLowerCase() == targetServiceUuid) {
        for (var characteristic in service.characteristics) {
          if (characteristic.uuid.toString().toLowerCase() == targetCharUuid) {
            await characteristic.setNotifyValue(true);
            
            _notifySub = characteristic.lastValueStream.listen((value) {
              if (value.length >= 6) {
                processBlePayload(payload: Uint8List.fromList(value));
              }
            });
          }
        }
      }
    }
  }

  Future<void> _disconnect() async {
    await _notifySub?.cancel();
    await _connectedDevice?.disconnect();
    setState(() {
      _connectedDevice = null;
    });
    _startScan();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _notifySub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("AirMouse Desktop Controller"),
        actions: [
          IconButton(
            icon: Icon(_isScanning ? Icons.sync : Icons.refresh),
            onPressed: _isScanning ? null : _startScan,
          )
        ],
      ),
      body: _connectedDevice != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.mouse, size: 80, color: Colors.greenAccent),
                  const SizedBox(height: 16),
                  Text(
                    "Connected to ${_connectedDevice!.platformName}",
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text("Processing motion & dual-clicks via Rust engine."),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _disconnect,
                    icon: const Icon(Icons.bluetooth_disabled),
                    label: const Text("Disconnect"),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                  )
                ],
              ),
            )
          : ListView.builder(
              itemCount: _scanResults.length,
              itemBuilder: (context, index) {
                final result = _scanResults[index];
                final name = result.device.platformName.isNotEmpty
                    ? result.device.platformName
                    : "Unknown Device";

                return ListTile(
                  leading: const Icon(Icons.bluetooth),
                  title: Text(name),
                  subtitle: Text(result.device.remoteId.str),
                  trailing: Text("${result.rssi} dBm"),
                  onTap: () => _connectToDevice(result.device),
                );
              },
            ),
    );
  }
}
