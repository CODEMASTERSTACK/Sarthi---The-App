# 🧭 Compass App

---

## 📖 Overview

Compass is a Flutter-based mobile application that provides users with a digital compass, location services, mapping, and sunrise/sunset calculations. It leverages device sensors and geolocation to deliver accurate directional and environmental information. The app is designed for outdoor enthusiasts, travelers, and anyone needing navigation or location-based utilities.

---

## 🚀 Features

- 🧭 **Digital Compass**  
  Utilizes device sensors to show real-time direction.

- 📍 **Geolocation**  
  Fetches and displays your current location using GPS.

- 🗺️ **Interactive Map**  
  Visualizes your position on a map with support for zoom and pan.

- 🌅 **Waypoint and Waypoint Map route**  
  User can add waypoint and copy it or show path then it will show the path to your waypooint from your current location.
  
- 🔦 **Emergency SOS Torch Signal**  
  User can Start SOS torch. And it will send the signal SOS in torch blink in code.

- 🔒 **Permission Handling**  
  Manages location and sensor permissions seamlessly.

- 💾 **Shared Preferences**  
  Stores user settings and preferences in their device.

---

## 📦 Dependencies

| Package                | Purpose                                    |
|------------------------|--------------------------------------------|
| flutter_compass        | Access device compass sensor               |
| geolocator             | Get device location                        |
| permission_handler     | Handle runtime permissions                 |
| geocoding              | Convert coordinates to addresses           |
| sensors_plus           | Access device sensors                      |
| sunrise_sunset_calc    | Calculate sunrise/sunset times             |
| flutter_map            | Display interactive maps                   |
| latlong2               | Handle latitude/longitude data             |
| torch_controller       | Control device flashlight                  |
| http                   | Make network requests                      |
| shared_preferences     | Store data locally                         |

---

## 🛠️ Installation & Setup

1. **Clone the Repository**
    ```bash
    git clone <https://github.com/CODEMASTERSTACK/Sarthi---The-App.git>
    cd compass
    ```

2. **Install Dependencies**
    ```bash
    flutter pub get
    ```

3. **Add Assets**  
   Ensure the following asset exists:
   - `assets/images/compass_rose.png`

   If you add custom fonts, update the `pubspec.yaml` under the `fonts:` section.

4. **Run the App**
    ```bash
    flutter run
    ```

---

## 🗂️ Project Structure

```
compass/
├── assets/
│   └── images/
│       └── compass_rose.png
├── lib/
│   └── main.dart
├── pubspec.yaml
└── ...
```

---

## 🔑 Permissions

The app requests the following permissions:

- **Location** (for GPS and mapping)
- **Sensors** (for compass functionality)
- **Camera/Flashlight** (for torch control)

Make sure to grant these permissions for full functionality.

---

## 📝 Customization

- **Assets:**  
  Add more images to `assets/images/` and declare them in `pubspec.yaml`.

- **Fonts:**  
  Add custom fonts in the `fonts:` section of `pubspec.yaml`.

---

## 🧑‍💻 Contribution

1. Fork the repository.
2. Create your feature branch (`git checkout -b feature/YourFeature`).
3. Commit your changes (`git commit -am 'Add new feature'`).
4. Push to the branch (`git push origin feature/YourFeature`).
5. Open a Pull Request.

---

## ❓ FAQ

**Q:** Why is the compass not working?  
**A:** Ensure your device has a magnetometer and permissions are granted.

**Q:** How do I add more assets?  
**A:** Place them in `assets/images/` and list them under `assets:` in `pubspec.yaml`.

---

## 📄 License

This project is licensed for personal use. Remove `publish_to: 'none'` in `pubspec.yaml` if you wish to publish.

---

## 📬 Contact

For issues or feature requests, open an issue on GitHub.

---

<div align="center">
  <img src="assets/images/compass_rose.png" alt="Compass Rose" width="120"/>
</div>

---

