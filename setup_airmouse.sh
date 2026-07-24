#!/usr/bin/env bash
set -e

# Force PATH inclusion for ~/.cargo/bin so subshell script commands work
export PATH="$HOME/.cargo/bin:$PATH"

APP_NAME="air_mouse_app"

echo "=== Creating Flutter App ($APP_NAME) ==="
flutter create --platforms=windows,macos,linux $APP_NAME
cd $APP_NAME

echo "=== Installing Flutter Dependencies ==="
flutter pub add flutter_blue_plus flutter_rust_bridge provider
flutter pub add --dev ffigen custom_lint

# Install FRB Codegen CLI if missing from ~/.cargo/bin
if ! command -v flutter_rust_bridge_codegen &> /dev/null; then
    echo "Installing flutter_rust_bridge_codegen..."
    cargo install flutter_rust_bridge_codegen
fi

echo "=== Initializing Flutter Rust Bridge Integration ==="
flutter_rust_bridge_codegen integrate

echo "=== Configuring Rust Engine (Cargo.toml) ==="
cat << 'EOF' > rust/Cargo.toml
[package]
name = "rust_lib_air_mouse_app"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib", "staticlib"]

[dependencies]
flutter_rust_bridge = "2.0"
enigo = "0.3"
lazy_static = "1.4"
EOF

echo "=== Writing Rust Engine Logic (rust/src/api/simple.rs) ==="
mkdir -p rust/src/api
cat << 'EOF' > rust/src/api/simple.rs
use enigo::{Button, Coordinate, Direction, Enigo, Mouse, Settings};
use std::sync::Mutex;
use lazy_static::lazy_static;

struct AirMouseState {
    enigo: Enigo,
    left_pressed: bool,
    right_pressed: bool,
}

lazy_static! {
    static ref STATE: Mutex<Option<AirMouseState>> = Mutex::new(None);
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    if let Ok(enigo_instance) = Enigo::new(&Settings::default()) {
        let mut state = STATE.lock().unwrap();
        *state = Some(AirMouseState {
            enigo: enigo_instance,
            left_pressed: false,
            right_pressed: false,
        });
    }
}

pub fn process_ble_payload(payload: Vec<u8>) {
    if payload.len() < 6 {
        return;
    }

    let mut state_guard = STATE.lock().unwrap();
    if let Some(state) = state_guard.as_mut() {
        let dx = i16::from_le_bytes([payload[0], payload[1]]) as i32;
        let dy = i16::from_le_bytes([payload[2], payload[3]]) as i32;

        let left_is_pressed = payload[4] == 1;
        let right_is_pressed = payload[5] == 1;

        if dx != 0 || dy != 0 {
            let _ = state.enigo.move_mouse(dx, dy, Coordinate::Rel);
        }

        if left_is_pressed && !state.left_pressed {
            let _ = state.enigo.button(Button::Left, Direction::Press);
            state.left_pressed = true;
        } else if !left_is_pressed && state.left_pressed {
            let _ = state.enigo.button(Button::Left, Direction::Release);
            state.left_pressed = false;
        }

        if right_is_pressed && !state.right_pressed {
            let _ = state.enigo.button(Button::Right, Direction::Press);
            state.right_pressed = true;
        } else if !right_is_pressed && state.right_pressed {
            let _ = state.enigo.button(Button::Right, Direction::Release);
            state.right_pressed = false;
        }
    }
}
EOF

echo "=== Generating FFI Bridge Bindings ==="
flutter_rust_bridge_codegen generate

echo "=== Writing UI Layer (lib/main.dart) ==="
cat << 'EOF' > lib/main.dart
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
    await device.connect();

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
EOF

echo "=== Done! Everything created successfully ==="
