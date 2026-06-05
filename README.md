# OpenSesame — Motorized Apartment Door Handle

ESP32-S3 BLE actuator + SwiftUI iPhone app that pulls the door handle open on a tap. Fully 3D-printed mechanism with DC gear motor, limit switches, and closed-loop control. Daily driver on a real apartment door.

**Featured on [Sam Snyder's portfolio](https://ss1-ops.github.io#projects)** — see the Precision Mechatronics section.

## How It Works

1. Open the **OpenSesame** iPhone app (or trigger from lock screen / widget).
2. App scans for the BLE peripheral named `DoorOpener`.
3. Tap "Open" → writes the command `"OPEN"` to the BLE characteristic.
4. ESP32-S3 executes the full cycle:
   - Motor forward until `LIMIT_OPEN` triggers → stop.
   - Hold open for 2 seconds.
   - Motor reverse until `LIMIT_CLOSED` triggers → stop.
5. Firmware continuously notifies status (`Opening` / `Open` / `Closing` / `Closed`). App animates with glow effects and short video loops.
6. Handle returns to closed and ready state. Cycle is reliable and repeatable.

Serial console also accepts the literal string `OPEN` for testing.

## Hardware

| Component       | Detail                                      |
|-----------------|---------------------------------------------|
| MCU             | ESP32-S3                                    |
| Motor Driver    | L298N-style (IN1/IN2/ENA + PWM)             |
| Motor           | DC gear motor driving 3D-printed spur gear on the handle |
| Endstops        | 2× normally-open limit switches (INPUT_PULLUP) |
| Indicator       | 1× Adafruit NeoPixel (RGB)                  |
| Power           | USB or wall adapter to door frame           |
| Mechanism       | 5-part 3D-printed assembly (see below)      |

### Pin Assignments (ESP32-S3)

| Signal        | Pin | Notes                          |
|---------------|-----|--------------------------------|
| MOTOR_IN1     | 5   | Direction control              |
| MOTOR_IN2     | 6   | Direction control              |
| MOTOR_ENA     | 7   | PWM enable (speed)             |
| LIMIT_OPEN    | 8   | Active LOW when handle fully open |
| LIMIT_CLOSED  | 9   | Active LOW when handle fully closed |
| RGB LED       | 21  | NeoPixel data                  |

**Motor ramp**: Starts at PWM ~80 to overcome static friction, then ramps to full over ~180 ms. Prevents gear stripping on initial engagement.

## Firmware (ESP32-S3 + Arduino)

Key behaviors:
- BLE server with READ | WRITE | NOTIFY on a single characteristic.
- Device name: `DoorOpener`
- Service UUID: `4fafc201-1fb5-459e-8fcc-c5c9c331914b`
- Characteristic UUID: `beb5483e-36e1-4688-b7f5-ea07361b26a8`
- WiFi + ElegantOTA (wireless firmware updates at `http://<ip>/update` or mDNS `opensesame.local/update`).
- Status notifications on every state change.
- BLE advertising watchdog in the main loop (restarts advertising if it drops).
- Limit-switch homing with 10 s safety timeout.
- LED feedback: solid red (closed), green flash (opening), solid green (open), yellow flash (closing).

The firmware is self-contained in `Door_Handle_BLE_Code/Door_Handle_BLE_Code.ino`.

## iOS App (SwiftUI)

- **OpenSesame** — native SwiftUI app using CoreBluetooth.
- Scans for and connects to `DoorOpener`.
- Single prominent action to send the open command.
- Real-time status text + color glow updates driven by BLE notifications.
- Bundled short video assets (`Door Opening.mov`, `Door Open.mov`, `Door Closing.mov`) for rich animated feedback (fixed-height player area so layout doesn't jump).
- Core Data persistence layer.
- Clean, minimal UI designed for quick one-tap use.

Project is in the `OpenSesame/` directory (Xcode project).

## 3D-Printed Mechanical Parts

All parts were designed for easy FDM printing and apartment-door installation. The mechanism uses a toothed arc on the existing handle + spur gear on the motor shaft.

Files at repo root (GitHub renders these interactively in 3D — click any `.stl`):

- `Door Handle - Base Plate.stl`
- `Door Handle - Motor Mount Final.stl`
- `Door Handle - Motor Gear Final.stl`
- `Door Handle - Top Cover.stl`
- `Door Handle Toothed Arc.stl`

## Repo Structure

```
.
├── README.md
├── LICENSE
├── .gitignore
├── Door Handle - *.stl          # 5 mechanical parts (view in 3D on GitHub)
├── Door_Handle_BLE_Code/        # ESP32-S3 Arduino firmware (.ino)
│   └── Door_Handle_BLE_Code.ino
└── OpenSesame/                  # SwiftUI iPhone app (Xcode project + assets)
    ├── OpenSesame/
    │   ├── OpenSesameApp.swift
    │   ├── ContentView.swift
    │   ├── BLEManager... (and supporting files)
    │   ├── Assets.xcassets/...
    │   └── *.mov (demo animation clips)
```

## Building & Running

### Firmware
1. Open `Door_Handle_BLE_Code/Door_Handle_BLE_Code.ino` in Arduino IDE (or PlatformIO / Arduino CLI).
2. Select ESP32-S3 board, appropriate partition scheme (for OTA + BLE).
3. Update WiFi credentials if needed for your network (current: `WAVLINK-N`).
4. Flash over USB.
5. After first boot you can use ElegantOTA for future updates.

### iOS App
1. Open `OpenSesame/OpenSesame.xcodeproj` in Xcode.
2. Select your iPhone target, sign with your developer account (requires BLE / Local Network capability).
3. Build & run. The app will request Bluetooth permission on first launch.

Test without the phone: connect via Serial Monitor and type `OPEN` + Enter.

## Daily Driver Reality

Installed on a real apartment door. Works from the lock screen via the app or Shortcuts integration potential. Limit switches provide reliable end-of-travel detection with no encoder needed. The 2-second hold gives enough time to enter before it auto-closes.

## Tech Stack & Skills Demonstrated

- Embedded: ESP32-S3 (FreeRTOS under the hood), Arduino/C++, BLE (GATT server + notify), WiFi + OTA
- Motor control: PWM ramping, limit switch homing, direction logic
- iOS: SwiftUI, CoreBluetooth, AVKit (video players), Core Data
- Mechanical: 3D printed custom mechanism design + integration with existing door hardware
- End-to-end ownership: firmware ↔ BLE protocol ↔ phone UX ↔ physical mechanism

## License

MIT License — see [LICENSE](LICENSE).

---

**Sam Snyder** — Robotics / Automation / Precision Mechatronics  
Austin, TX | [samhsnyder.com](https://samhsnyder.com) | [Portfolio](https://ss1-ops.github.io)

This is a complete, ship-it personal project showing firmware + app + mechanism integration under real-world constraints.
