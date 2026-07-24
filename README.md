# Air Mouse

A Flutter and Rust Project

A wireless air mouse project built for my **Embedded Systems and RTOS** course.
It reads motion from a microcontroller equipped with an IMU, sends movement and click data over Bluetooth, and moves the computer cursor in real-time.

---

## How It Works

The project has two main parts: the embedded hardware and the desktop application.

1. **Embedded Hardware (RTOS & Microcontroller)**
   * Reads sensor data from an onboard IMU (gyroscope and accelerometer).
   * FreeRTOS handles sampling the sensor, debouncing button presses, and packing everything into a small 6-byte data packet.
   * Sends movement updates ($\Delta X, \Delta Y$) and left/right click states over BLE notifications.

2. **Desktop App (Flutter + Rust)**
   * **Flutter** handles the UI for scanning and connecting to the Bluetooth device.
   * **Flutter Rust Bridge** passes the raw Bluetooth packets directly to Rust with minimal latency.
   * **Rust (`enigo`)** parses the packet and simulates native mouse movements and clicks on the operating system.

---

## Requirements

### Windows
Requires Visual Studio C++ build tools installed.
Run the app or terminal as Administrator so Windows allows input simulation.

### Linux
Install system packages for Bluetooth and X11 input simulation:

* Debian / Ubuntu based:
  sudo apt update && sudo apt install -y libxdo-dev bluetooth bluez
  
* Fedora / RHEL based:
  sudo dnf install libX11-devel libXtst-devel xdotool bluez bluez-tools
  sudo systemctl enable --now bluetooth

* Arch based:
  sudo pacman -S libx11 libxtst xdotool bluez bluez-utils
  sudo systemctl enable --now bluetooth

### macOS
Grant Accessibility permissions to the app (or terminal) under:
System Settings -> Privacy & Security -> Accessibility

---

## Setup and Running

1. Make sure Flutter, Rust, and flutter_rust_bridge_codegen are installed:
   cargo install flutter_rust_bridge_codegen

2. Get Flutter dependencies:
   flutter pub get

3. Generate the Rust-Flutter bindings:
   flutter_rust_bridge_codegen generate

4. Run the app:
   flutter run
