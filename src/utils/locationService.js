import { database } from '../firebase';
import { ref, set } from 'firebase/database';

/**
 * Location Service
 * Handles getting user's current location and sending it to Firebase
 */

export const getCurrentPosition = () => {
  return new Promise((resolve, reject) => {
    if (!navigator.geolocation) {
      reject(new Error('Geolocation is not supported by this browser'));
      return;
    }

    const options = {
      enableHighAccuracy: true,
      timeout: 15000, // 15 seconds
      maximumAge: 60000 // 1 minute
    };

    navigator.geolocation.getCurrentPosition(
      (position) => {
        resolve({
          latitude: position.coords.latitude,
          longitude: position.coords.longitude,
          accuracy: position.coords.accuracy,
          timestamp: Date.now(),
          timeStamp: Date.now() // Keep both for compatibility
        });
      },
      (error) => {
        let errorMessage = 'Unable to get location';
        switch (error.code) {
          case error.PERMISSION_DENIED:
            errorMessage = 'Location access denied by user';
            break;
          case error.POSITION_UNAVAILABLE:
            errorMessage = 'Location information unavailable';
            break;
          case error.TIMEOUT:
            errorMessage = 'Location request timeout';
            break;
          default:
            errorMessage = 'Unknown location error';
            break;
        }
        reject(new Error(errorMessage));
      },
      options
    );
  });
};

export const sendLocationToServer = async (user, locationData) => {
  try {
    if (!user || !user.mobile) {
      throw new Error('User information is required');
    }

    // Get battery level if available
    let batteryPercentage = null;
    if ('getBattery' in navigator) {
      try {
        const battery = await navigator.getBattery();
        batteryPercentage = Math.round(battery.level * 100);
      } catch (e) {
        console.log('Battery API not available');
      }
    }

    // Prepare location data
    const locationPayload = {
      ...locationData,
      batteryPercentage: batteryPercentage || 'Unknown',
      gpsStatus: 'Enabled',
      gpsInfo: 'GPS Enabled..!',
      deviceInfo: {
        userAgent: navigator.userAgent,
        platform: navigator.platform,
        language: navigator.language
      },
      lastUpdated: new Date().toISOString()
    };

    // Send to current location (locationList)
    const locationRef = ref(database, `locationList/${user.mobile}`);
    await set(locationRef, locationPayload);

    // Also store in history (locationHistory)
    const today = new Date().toISOString().split('T')[0]; // YYYY-MM-DD
    const historyRef = ref(database, `locationHistory/${user.mobile}/${today}/${Date.now()}`);
    await set(historyRef, locationPayload);

    console.log('Location sent successfully to server');
    return true;
  } catch (error) {
    console.error('Error sending location to server:', error);
    throw error;
  }
};

export const requestLocationPermission = async () => {
  try {
    const permission = await navigator.permissions.query({ name: 'geolocation' });
    return permission.state; // 'granted', 'denied', or 'prompt'
  } catch (error) {
    console.log('Permission API not available, will try direct geolocation');
    return 'unknown';
  }
};

export const startLocationTracking = (user, intervalMinutes = 5) => {
  const updateLocation = async () => {
    try {
      const location = await getCurrentPosition();
      await sendLocationToServer(user, location);
    } catch (error) {
      console.error('Failed to update location:', error);
    }
  };

  // Send location immediately
  updateLocation();

  // Set up periodic updates
  const intervalId = setInterval(updateLocation, intervalMinutes * 60 * 1000);

  return () => {
    clearInterval(intervalId);
  };
};
