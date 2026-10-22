# SheepPing (Windows / Flutter)

พอร์ตแอป **SheepPing** ของ macOS (SwiftUI) มาสู่ Windows ด้วย **Flutter + `macos_ui`**
หน้าตาออกแบบให้เหมือนต้นฉบับ: title bar แบบ unified toolbar, ตารางคอลัมน์เดียวกัน,
log pane 3 โหมด, สถานะ/สีเดียวกัน และเมนู Settings/Add Host แบบ sheet

ต้นฉบับ: <https://github.com/bestonehxh/SheepPing> (MIT)

---

## ฟีเจอร์

| | |
|---|---|
| Ping หลาย host พร้อมกัน | หนึ่ง session ต่อ host, ยิง `ping -n 1` ตาม interval ที่ตั้งไว้ |
| ตาราง | HOST · RESOLVED IP · STATUS · LATENCY · SUCCESS · FAILED · RATE |
| สถานะ | จุดสี (Idle / กำลังวิ่งมีวงเต้น / OK / Fail) + capsule "OK" |
| Log ต่อ host | เก็บสูงสุด 500 บรรทัด, เวลา, latency, ข้อความจาก `ping.exe` |
| Log 3 โหมด | ยังไม่เลือก host / เลือก 1 host / เลือกหลาย host |
| Export | Copy / Save เป็น CSV (ตรงกับต้นฉบับ macOS ทุกคอลัมน์) |
| เลือกหลายแถว | Click, Ctrl+Click, Shift+Click, Ctrl+A |
| ตั้งค่า | Ping interval (0.5–30 วิ), Reply timeout (0.5–15 วิ) |
| ธีม | Dark (night mode) อย่างเดียว — ตั้งใจให้ตาราง/log ใช้ชุดสีเดียว |
| จำค่า | host, interval, timeout เก็บใน `%APPDATA%\SheepPing\settings.json` |

## คีย์ลัด

| ปุ่ม | การทำงาน |
|---|---|
| `Ctrl` + `A` | เลือกทุก host |
| `Ctrl` + `C` | คัดลอกแถวที่เลือกเป็น CSV |
| `Delete` / `Backspace` | ลบ host ที่เลือก |
| `Esc` | ยกเลิกการเลือก / ปิด sheet |
| `Ctrl` + `Enter` | เพิ่ม host (ในหน้า Add Host) |

## ความต้องการของระบบ

* Windows 10/11 (x64)
* Flutter **3.47+** (ทดสอบกับ 3.47.7 / Dart 3.13.5)
* Visual Studio 2022 + workload **Desktop development with C++**
  (ต้องมี component `MSVC v143` + `C++ CMake tools for Windows` + Windows SDK)

## Build / Run

```powershell
# ครั้งแรก
flutter pub get

# รันแบบ debug
flutter run -d windows

# สร้างไฟล์แจกจ่าย
flutter build windows --release
# ได้ที่ build\windows\x64\runner\Release\sheepping.exe
```

> ถ้า `flutter build windows` ฟ้อง *"Unable to find suitable Visual Studio toolchain"*
> ให้เปิด **Visual Studio Installer → Modify → Desktop development with C++** แล้วกด Modify

## ทดสอบ

```powershell
flutter test          # unit test: parser ของ ping, CSV, ชื่อไฟล์
```

ภาพหน้าจอสำหรับรีวิว UI (ไม่ใช้ assertion, รันเมื่อต้องการเท่านั้น):

```powershell
flutter test test\ui_goldens.dart --update-goldens
# ได้ภาพที่ test\goldens\dark.png, empty.png, settings.png, add-host.png
```

## โครงสร้างโค้ด

```
lib/
  main.dart              MaterialApp + MacosTheme, title bar, splitter, คีย์ลัด
  src/
    models.dart          PingHost (ChangeNotifier), PingStatus, LogEntry
    ping_engine.dart     ping 1 ครั้งต่อ tick + parser ข้อความ ping.exe
    view_model.dart      สถานะแอป, session, การเลือก, การบันทึกค่า
    store.dart           settings.json
    theme.dart           สี/ฟอนต์ของ macOS (ใช้ชุดสี dark เท่านั้น)
    export.dart          CSV (ping row / log / หลาย host)
    save_panel.dart      Save dialog ผ่าน GetSaveFileNameW (dart:ffi)
    win32_window.dart    ถอด title bar, มุมโค้ง, ลากหน้าต่าง, ปุ่มย่อ/ขยาย/ปิด
    widgets/             title_bar, host_table, log_panel, sheets
```

## ความต่างจากต้นฉบับ macOS

| macOS | พอร์ตนี้ | เหตุผล |
|---|---|---|
| SF Pro / SF Mono | Segoe UI / Cascadia Mono (fallback Consolas) | ฟอนต์ Apple แจกจ่ายไม่ได้ |
| SF Symbols | Material Icons | license ของ SF Symbols จำกัดการใช้งาน |
| ไฟจราจรซ้ายบน + toolbar ระบบ | title bar วาดเอง: toolbar ชิดซ้าย + ปุ่มย่อ/ขยาย/ปิดเป็น bar แยกชิดขวา | Windows ไม่มี traffic lights |
| ธีมตามระบบ (System/Light/Dark) | dark อย่างเดียว | ตาราง/log ออกแบบมาบนชุดสีเดียว |
| one long-lived `ping -i` | `ping -n 1` ทุก tick | `ping.exe` ไม่มี `-i` และ `-t` คุมจังหวะไม่ได้ |
| `NSSavePanel` | `GetSaveFileNameW` | dialog มาตรฐานของ Windows |
| `UserDefaults` | `%APPDATA%\SheepPing\settings.json` | อ่าน/แก้ไขง่าย |

ตรรกะสำคัญที่คงไว้เหมือนต้นฉบับ: การนับ success/fail, rate, การรีเซ็ตสถิติ,
`generation`/session guard (ผลที่มาช้ากว่าการถูกทิ้ง), และการ restart session
เมื่อเปลี่ยน interval/timeout

## License

MIT — งานต้นฉบับโดย [@bestonehxh](https://github.com/bestonehxh/SheepPing)
