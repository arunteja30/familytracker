# Family Tracker PWA

A Progressive Web Application for real-time family location tracking using Firebase Realtime Database.

## Features

- 📍 **Real-time Location Tracking** - View family members' locations on an interactive map
- 👥 **Family Management** - Organize members into family groups
- 📱 **Mobile-First Design** - Works seamlessly on Android, iOS, and web browsers
- 🔋 **Battery Monitoring** - Track device battery levels
- 📡 **GPS Status Monitoring** - Monitor GPS connectivity status
- 📊 **Admin Panel** - Administrative controls for family management
- 📱 **PWA Support** - Install as an app on mobile devices
- 🌐 **Offline Support** - Basic functionality works offline

## Technology Stack

- **Frontend**: React 18, React Router
- **Maps**: Leaflet (OpenStreetMap) - Free and open source
- **Database**: Firebase Realtime Database
- **Styling**: Pure CSS (no external CSS frameworks)
- **Icons**: React Icons
- **PWA**: Service Worker for offline functionality

## Prerequisites

Before running this application, you need:

1. **Node.js** (version 14 or higher)
2. **Firebase Project** with Realtime Database enabled

## Setup Instructions

### 1. Install Dependencies

```bash
npm install
```

### 2. Firebase Configuration

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Create a new project or use existing one
3. Enable **Realtime Database**
4. Get your Firebase configuration
5. Update `src/firebase-config.js` with your Firebase config:

```javascript
export const firebaseConfig = {
  apiKey: "your-api-key",
  authDomain: "your-project.firebaseapp.com",
  databaseURL: "https://your-project-default-rtdb.firebaseio.com/",
  projectId: "your-project-id",
  storageBucket: "your-project.appspot.com",
  messagingSenderId: "123456789",
  appId: "your-app-id"
};
```

### 3. Firebase Database Rules

Set up your Firebase Realtime Database rules for security:

```json
{
  "rules": {
    ".read": "auth != null",
    ".write": "auth != null"
  }
}
```

For development/testing, you can use:
```json
{
  "rules": {
    ".read": true,
    ".write": true
  }
}
```

### 4. Import Existing Data (Optional)

If you have existing data in the format shown in your export file, you can:

1. Go to Firebase Console > Realtime Database
2. Click on "Import JSON"
3. Upload your `familytracker-3231f-export.json` file

## Running the Application

### Development Mode

```bash
npm start
```

Open [http://localhost:3000](http://localhost:3000) to view it in the browser.

### Production Build

```bash
npm run build
```

This creates an optimized build in the `build` folder.

### Deploy to Firebase Hosting (Optional)

```bash
npm install -g firebase-tools
firebase login
firebase init hosting
firebase deploy
```

## PWA Installation

### On Mobile (Android/iOS):
1. Open the app in your mobile browser
2. Look for "Add to Home Screen" or "Install App" prompt
3. Follow the installation prompts

### On Desktop:
1. Open the app in Chrome/Edge
2. Click the install button in the address bar
3. Follow the installation prompts

## Application Structure

```
src/
├── components/
│   ├── LocationMap.js       # Real-time map with member locations
│   ├── FamilyMembers.js     # Family members list with status
│   ├── AdminPanel.js        # Admin controls for management
│   └── LocationHistory.js   # Location history viewer
├── firebase.js              # Firebase initialization
├── firebase-config.js       # Firebase configuration (UPDATE THIS!)
├── App.js                   # Main application component
├── index.js                 # Application entry point
└── index.css               # Global styles
```

## Features Overview

### 🗺️ Live Map
- Interactive map showing real-time member locations
- Color-coded markers (admin vs regular members)
- Battery and GPS status in location popups
- Family filtering options

### 👥 Family Members
- List view of all family members
- Real-time status (online/offline)
- Battery levels and GPS status
- Family group filtering

### 📊 Admin Panel
- Add/remove family groups
- Add/remove family members
- Edit member information
- Manage member relationships and roles

### 📈 Location History
- View historical location data
- Filter by member and time period
- Battery and GPS status tracking
- Link to Google Maps for each location

## Database Structure

The app uses the same structure as your existing database:

```
{
  "familyList": { /* Family groups */ },
  "familyMembersList": { /* Member details */ },
  "locationList": { /* Current locations */ },
  "registrations": { /* User registrations */ },
  "UpdateData": { /* App update info */ }
}
```

## Security Considerations

1. **Authentication**: Consider implementing Firebase Authentication
2. **Database Rules**: Secure your Firebase rules in production
3. **API Keys**: Keep Firebase API keys secure
4. **Privacy**: Ensure location data privacy compliance

## Browser Support

- ✅ Chrome (Android/Desktop)
- ✅ Safari (iOS/macOS)
- ✅ Firefox (Android/Desktop)
- ✅ Edge (Desktop)
- ✅ Samsung Internet (Android)

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## License

This project is open source and available under the [MIT License](LICENSE).

## Support

For issues or questions:
1. Check existing GitHub issues
2. Create a new issue with detailed description
3. Include browser/device information for bugs

---

**Note**: This application is designed to work with your existing Firebase Realtime Database structure. Make sure your Android app and this web app use the same Firebase project for data consistency.
