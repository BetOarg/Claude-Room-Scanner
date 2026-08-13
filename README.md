# 📐 Room Scanner AR

**Room Scanner AR** is a Flutter application for capturing indoor spaces with augmented reality, structuring rooms as editable 2D floor-plan data, and preparing measurements and openings for professional export.

The project is designed as the foundation for a **multi-room indoor scanner**: living room, kitchen, bathroom, bedrooms, laundry, hallways and other spaces can be represented as individual rooms within the same project.

> **Project status:** Active development / prototype-to-product stage.
>
> The repository contains the core Flutter architecture, room data model, AR-related modules, interactive floor-plan components, local persistence dependencies and PDF/export infrastructure. Hardware-specific AR accuracy and complete automatic room reconstruction should be considered work in progress.

---

## ✨ Highlights

- 📱 Flutter application targeting Android and iOS.
- 🥽 ARCore / ARKit-oriented architecture for indoor scanning.
- 🏠 Multi-room data model with living room, kitchen, bathroom, bedroom, laundry and hallway types.
- 📍 3D scan points represented as `x`, `y`, `z` coordinates.
- 🚪 Doors and 🪟 windows represented as wall features.
- 🧭 Foundation for transforming AR spatial data into a 2D floor plan.
- ✏️ Interactive 2D floor-plan editing components.
- 📄 PDF generation and printing support.
- 🖼️ Export/share infrastructure.
- 💾 Local persistence with Isar.
- ☁️ Supabase integration prepared for authentication, cloud data and synchronization.
- 📂 JSON/file import support.
- 📐 Vector mathematics through `vector_math`.
- 🔐 Native camera and AR permissions.
- 🧪 Unit and integration-test structure.
- 🎨 Material 3 / modern Flutter UI foundation.

## 🎯 Project Vision

The long-term objective is to evolve the project from a **single-room AR measurement prototype** into a complete indoor documentation workflow:

```text
Create Project → Select Room → AR Scan → Capture Spatial Data
      → Validate → Edit 2D Plan → Add Next Room → Export
```

The architecture is intentionally being developed toward a complete **property floor-plan workflow**, rather than treating each room as an isolated scan.

## 🧩 Current Domain Model

The core model represents a room through `RoomModel`, `ARPoint`, `WallFeature`, `RoomType` and `FeatureType`. A room contains 3D points and optional doors/windows, with JSON serialization/deserialization for persistence and interchange.

### Supported room types

| Type | Identifier |
|---|---|
| Living | `living` |
| Cocina | `cocina` |
| Baño | `bano` |
| Dormitorio | `dormitorio` |
| Lavadero | `lavadero` |
| Pasillo | `pasillo` |

### Supported wall features

| Feature | Identifier |
|---|---|
| Puerta | `door` |
| Ventana | `window` |

## 🏗️ Architecture

```text
lib/
├── controllers/      # AR/session controllers
├── models/           # Domain and spatial models
├── providers/        # Application state
├── screens/          # Application screens
├── services/         # Platform/session services
├── utils/            # Geometry, measurements and export helpers
├── widgets/          # Reusable AR and floor-plan widgets
└── main.dart         # Application entry point
```

The scanner state is centralized through `ScannerProvider`, which manages rooms, the active room, selected room type, tracking state and point capture.

## 📱 Scanning Experience

The scanner UI is structured around three operational modes:

1. **Pared** — capture wall/room vertices.
2. **Puerta** — insert a door feature.
3. **Ventana** — insert a window feature.

It also exposes room-type selection, undo and room closure.

### Intended workflow

```text
Calibrate AR
     ↓
Select room type
     ↓
Capture corners
     ↓
Validate polygon
     ↓
Add doors/windows
     ↓
Close room
     ↓
Edit 2D plan
     ↓
Save room
     ↓
Continue with next room
```

## 🏠 Multi-Room Strategy

The application is designed around a **property-level project**, where multiple rooms form one coherent floor plan.

```text
Property
├── Living
├── Cocina
├── Dormitorio 1
├── Dormitorio 2
├── Baño
├── Lavadero
└── Pasillo
```

This provides a scalable base for shared walls, room-to-room connectivity, global dimensions, total area and professional plan export.

## 📐 Geometry & Measurements

Spatial points are stored as 3D coordinates and can be transformed into 2D floor-plan geometry.

The architecture supports:

- Wall lengths.
- Perimeter calculation.
- Polygon area.
- 3D-to-2D projection.
- Polygon validation.
- Duplicate-point detection.
- Self-intersection detection.
- Room closure validation.
- Editable vertices.

For professional surveying or architectural use, measurements should be independently verified against a known reference measurement.

## 📄 Export

The project includes PDF generation, printing, file sharing and local file handling.

The intended export pipeline is:

```text
Room / Property Data
        ↓
Validated Floor Plan
        ↓
PDF Renderer
        ↓
Professional Document
        ↓
Print / Share / Archive
```

Future professional export fields can include client, address, date, dimensions, areas, perimeter, graphic scale, north arrow, legend, observations, signatures and QR identification.

## 💾 Persistence & Cloud Roadmap

The dependency configuration includes Isar for local persistence and Supabase for the planned cloud/authentication/synchronization layer.

```text
Local Project → Sync Engine → Supabase → Cloud Project → Multi-device Access
```

## 🧰 Tech Stack

| Technology | Purpose |
|---|---|
| Flutter | Cross-platform application framework |
| Dart | Application language |
| ARCore | Android augmented reality |
| ARKit | iOS augmented reality |
| `ar_flutter_plugin_2` | AR integration layer |
| `vector_math` | 3D/vector mathematics |
| Provider | State management |
| Isar | Local database |
| Supabase | Cloud/auth/synchronization foundation |
| PDF | PDF generation |
| Printing | PDF preview/printing |
| Share Plus | File sharing |
| File Picker | File import |
| Geolocator | Location services |
| Permission Handler | Runtime permissions |
| Model Viewer Plus | 3D model visualization |
| Integration Test | Integration testing |

Current application version: **2.5.0+1**.

## 📋 Requirements

### Flutter / Dart

- Flutter `>= 3.16.0`
- Dart `>= 3.0.0 < 4.0.0`

### Android

Current configuration:

- `minSdkVersion 28`
- `compileSdkVersion 34`
- `targetSdkVersion 34`
- Java 17
- Kotlin JVM target 17
- ARCore required by the application manifest

> ARCore availability depends on the physical device and Google's supported-device matrix.

### iOS

The application declares camera permission for AR/ARKit scanning. The current Runner configuration supports portrait orientation.

> ARKit availability depends on the device, iOS version and the capabilities exposed by the AR integration used by the build.

## 🚀 Getting Started

### 1. Clone

```bash
git clone https://github.com/BetOarg/Flutter-ARCore-ARKit_room_scanner_ar.git
cd Flutter-ARCore-ARKit_room_scanner_ar
```

### 2. Install dependencies

```bash
flutter pub get
```

### 3. Generate Isar code

```bash
dart run build_runner build --delete-conflicting-outputs
```

### 4. Check the environment

```bash
flutter doctor -v
```

### 5. List devices

```bash
flutter devices
```

### 6. Run on a physical device

```bash
flutter run
```

For AR workloads, validate behavior on a **physical AR-capable device** rather than relying on a simulator/emulator.

### 7. Release builds

Android APK:

```bash
flutter build apk --release
```

Android App Bundle:

```bash
flutter build appbundle --release
```

iOS:

```bash
flutter build ios --release
```

## 🧪 Testing

```bash
flutter analyze
flutter test
flutter test integration_test
flutter test --coverage
```

## 🔐 Permissions

### Android

Camera access and AR camera capability are declared in the Android manifest, with ARCore marked as required.

### iOS

Camera access is declared through `NSCameraUsageDescription`.

## 📁 Project Structure

```text
.
├── android/
├── ios/
├── assets/
│   └── models/
├── integration_test/
├── lib/
│   ├── controllers/
│   ├── models/
│   ├── providers/
│   ├── screens/
│   ├── services/
│   ├── utils/
│   ├── widgets/
│   └── main.dart
├── packages/
│   └── ar_flutter_plugin/
├── test/
├── .github/
│   └── workflows/
├── pubspec.yaml
├── LICENSE
└── README.md
```

## 🔬 Development Status

### Present in the repository

- [x] Flutter application structure.
- [x] Android/iOS project configuration.
- [x] AR-oriented scanning modules.
- [x] Room domain model.
- [x] 3D point model.
- [x] Door/window feature model.
- [x] Multi-room state container.
- [x] Room type selection.
- [x] Point insertion/removal workflow.
- [x] Room closure workflow.
- [x] JSON serialization model.
- [x] PDF/export dependencies.
- [x] Isar persistence dependencies.
- [x] Supabase dependency foundation.
- [x] Integration-test structure.

### Recommended next milestones

- [ ] Complete robust AR hit-test capture throughout the production flow.
- [ ] Automatic wall/plane detection.
- [ ] Improve tracking and drift correction.
- [ ] Scale calibration against a known physical reference.
- [ ] Complete door/window placement on wall segments.
- [ ] Room-to-room connectivity.
- [ ] Property-level floor-plan editor.
- [ ] Dimensions and measurement annotations.
- [ ] North orientation and compass calibration.
- [ ] Columns, pillars and stairs.
- [ ] Professional PDF templates.
- [ ] Complete Isar project persistence.
- [ ] Supabase authentication and synchronization.
- [ ] Cloud conflict resolution.
- [ ] Automated CI quality gates.
- [ ] Device compatibility and AR accuracy test suite.

## ⚠️ Accuracy & Production Considerations

AR measurements are affected by sensor quality, camera calibration, lighting, visual features, reflective/transparent surfaces, device movement, plane detection and accumulated positional drift.

For architectural, construction, cadastral or legal documentation, measurements should be independently verified before being treated as authoritative.

This project should therefore be considered a **measurement/documentation tool in active development**, not a replacement for certified surveying equipment or a legally authoritative survey.

## 🛣️ Roadmap

### Phase 1 — Stable Room Scanner

- AR tracking.
- Reliable corner capture.
- Stability filtering.
- Wall detection.
- Automatic room closure.
- Measurement validation.

### Phase 2 — Professional Room Editor

- 2D editing.
- Dimensions.
- Doors/windows.
- Wall correction.
- Room metadata.
- Undo/redo.

### Phase 3 — Complete Property

- Multiple rooms.
- Room connectivity.
- Shared walls.
- Hallways.
- Stairs.
- Columns.
- Global property plan.

### Phase 4 — Professional Documentation

- PDF plans.
- Scale.
- North arrow.
- Legend.
- Client/property information.
- QR identification.
- Observations.
- Signatures.

### Phase 5 — Cloud Platform

- Authentication.
- Project synchronization.
- Cloud backup.
- Multi-device access.
- Project sharing.
- Version history.

## 🤝 Contributing

Contributions are welcome.

```bash
git checkout -b feature/my-feature
flutter pub get
flutter analyze
flutter test
git commit -m "feat: describe the change"
git push origin feature/my-feature
```

Pull Requests should include a clear description, screenshots/video for UI or AR changes, device information, Flutter/Dart version, test results and known limitations.

## 🐛 Issues & Feature Requests

For AR issues, include:

1. Device model.
2. Android/iOS version.
3. Flutter version.
4. App version.
5. Physical environment conditions.
6. Steps to reproduce.
7. Expected behavior.
8. Actual behavior.
9. Logs/screenshots/video when applicable.

## 📄 License

This project is released under the **MIT License**.

Copyright © 2024 BetOarg.

## 🔗 Repository

https://github.com/BetOarg/Flutter-ARCore-ARKit_room_scanner_ar

## 👤 Author

**BetOarg** — https://github.com/BetOarg

## ⭐ Project Direction

Room Scanner AR is being developed as the foundation for a professional **AR indoor measurement and floor-plan generation platform**.

The key architectural principle is to treat a property as a structured spatial project rather than as a collection of photographs or isolated room scans:

```text
PROPERTY
   │
   ├── ROOMS
   │    ├── Walls
   │    ├── Doors
   │    └── Windows
   │
   ├── METADATA
   │    ├── Client
   │    ├── Address
   │    └── Date
   │
   ↓
3D SPATIAL DATA
   ↓
2D FLOOR PLAN
   ↓
VALIDATION
   ↓
PROFESSIONAL EXPORT
```
