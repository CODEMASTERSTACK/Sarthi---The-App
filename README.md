🧭 Compass App
<span style="color:#1976D2"><u>📖 Overview</u></span>
Compass is a Flutter-based mobile application that provides users with a digital compass, location services, mapping, and sunrise/sunset calculations. It leverages device sensors and geolocation to deliver accurate directional and environmental information. The app is designed for outdoor enthusiasts, travelers, and anyone needing navigation or location-based utilities.

<span style="color:#388E3C"><u>🚀 Features</u></span>
🧭 Digital Compass
Utilizes device sensors to show real-time direction.

📍 Geolocation
Fetches and displays your current location using GPS.

🗺️ Interactive Map
Visualizes your position on a map with support for zoom and pan.

🌅 Sunrise & Sunset Calculation
Calculates and displays daily sunrise and sunset times for your location.

🔦 Torch Control
Allows you to toggle your device's flashlight.

🔒 Permission Handling
Manages location and sensor permissions seamlessly.

💾 Shared Preferences
Stores user settings and preferences locally.

<span style="color:#FBC02D"><u>📦 Dependencies</u></span>
The app uses the following main packages:

Package	Purpose
flutter_compass	Access device compass sensor
geolocator	Get device location
permission_handler	Handle runtime permissions
geocoding	Convert coordinates to addresses
sensors_plus	Access device sensors
sunrise_sunset_calc	Calculate sunrise/sunset times
flutter_map	Display interactive maps
latlong2	Handle latitude/longitude data
torch_controller	Control device flashlight
http	Make network requests
shared_preferences	Store data locally
<span style="color:#D32F2F"><u>🛠️ Installation & Setup</u></span>
1. Clone the Repository

git clone <your-repo-url>cd compass
2. Install Dependencies

flutter pub get
3. Add Assets
Ensure the following asset exists:

compass_rose.png
If you add custom fonts, update the pubspec.yaml under the fonts: section.

4. Run the App

flutter run
<span style="color:#7B1FA2"><u>🗂️ Project Structure</u></span>

compass/├── assets/│   └── images/│       └── compass_rose.png├── lib/│   └── main.dart├── pubspec.yaml└── ...
<span style="color:#0288D1"><u>🔑 Permissions</u></span>
The app requests the following permissions:

Location (for GPS and mapping)
Sensors (for compass functionality)
Camera/Flashlight (for torch control)
Make sure to grant these permissions for full functionality.

<span style="color:#F57C00"><u>📝 Customization</u></span>
Assets:
Add more images to images and declare them in pubspec.yaml.

Fonts:
Add custom fonts in the fonts: section of pubspec.yaml.

<span style="color:#388E3C"><u>🧑‍💻 Contribution</u></span>
Fork the repository.
Create your feature branch (git checkout -b feature/YourFeature).
Commit your changes (git commit -am 'Add new feature').
Push to the branch (git push origin feature/YourFeature).
Open a Pull Request.
<span style="color:#C2185B"><u>❓ FAQ</u></span>
Q: Why is the compass not working?
A: Ensure your device has a magnetometer and permissions are granted.

Q: How do I add more assets?
A: Place them in images and list them under assets: in pubspec.yaml.

<span style="color:#1976D2"><u>📄 License</u></span>
This project is licensed for personal use. Remove publish_to: 'none' in pubspec.yaml if you wish to publish.

<span style="color:#009688"><u>📬 Contact</u></span>
For issues or feature requests, open an issue on GitHub.

<div align="center"> <img src="assets/images/compass_rose.png" alt="Compass Rose" width="120"/> </div>
Made with ❤️ using Flutter