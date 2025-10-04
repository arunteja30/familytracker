import { database } from '../firebase';
import { ref, push, set, onValue } from 'firebase/database';

/**
 * Store a location update in history
 */
export const storeLocationHistory = async (phoneNumber, locationData) => {
  try {
    const today = new Date().toISOString().split('T')[0]; // YYYY-MM-DD format
    const historyRef = ref(database, `locationHistory/${phoneNumber}/${today}`);
    
    // Add timestamp and format data
    const historyEntry = {
      ...locationData,
      timestamp: Date.now(),
      date: new Date().toLocaleString()
    };
    
    // Push to today's location history
    await push(historyRef, historyEntry);
    
    // Also update the current location in locationList for backwards compatibility
    const currentLocationRef = ref(database, `locationList/${phoneNumber}`);
    await set(currentLocationRef, locationData);
    
    return true;
  } catch (error) {
    console.error('Error storing location history:', error);
    return false;
  }
};

/**
 * Get location history for a member by date range
 */
export const getLocationHistory = (phoneNumber, startDate, endDate, callback) => {
  const historyRef = ref(database, `locationHistory/${phoneNumber}`);
  
  return onValue(historyRef, (snapshot) => {
    const data = snapshot.val();
    if (!data) {
      callback([]);
      return;
    }
    
    const filteredHistory = [];
    Object.entries(data).forEach(([date, dayLocations]) => {
      if (date >= startDate && date <= endDate) {
        Object.entries(dayLocations).forEach(([key, location]) => {
          filteredHistory.push({
            id: key,
            date,
            ...location
          });
        });
      }
    });
    
    // Sort by timestamp
    filteredHistory.sort((a, b) => b.timestamp - a.timestamp);
    callback(filteredHistory);
  });
};

/**
 * Get available dates for a member
 */
export const getAvailableDates = (phoneNumber, callback) => {
  const historyRef = ref(database, `locationHistory/${phoneNumber}`);
  
  return onValue(historyRef, (snapshot) => {
    const data = snapshot.val();
    if (!data) {
      callback([]);
      return;
    }
    
    const dates = Object.keys(data).sort().reverse();
    callback(dates);
  });
};

/**
 * Populate test historical data for a member
 * This is a utility function to create sample historical data for testing
 */
export const populateTestHistoricalData = async (phoneNumber, baseLocation) => {
  try {
    console.log(`Populating test historical data for ${phoneNumber}...`);
    
    const today = new Date();
    const promises = [];
    
    // Create historical data for the last 7 days
    for (let i = 0; i < 7; i++) {
      const date = new Date(today.getTime() - i * 24 * 60 * 60 * 1000);
      const dateString = date.toISOString().split('T')[0];
      
      // Create 3-5 location entries per day
      const entriesCount = Math.floor(Math.random() * 3) + 3; // 3-5 entries
      
      for (let j = 0; j < entriesCount; j++) {
        const timestamp = date.getTime() + (j * 3 * 60 * 60 * 1000); // Every 3 hours
        
        const locationEntry = {
          latitude: baseLocation.latitude + (Math.random() - 0.5) * 0.01, // Small variation
          longitude: baseLocation.longitude + (Math.random() - 0.5) * 0.01,
          timestamp: timestamp,
          batteryPercentage: Math.floor(Math.random() * 80) + 20, // 20-100%
          gpsStatus: 'Enabled',
          accuracy: Math.floor(Math.random() * 10) + 5, // 5-15 meters
          speed: Math.floor(Math.random() * 50) // 0-50 km/h
        };
        
        const historyRef = ref(database, `locationHistory/${phoneNumber}/${dateString}`);
        promises.push(push(historyRef, locationEntry));
      }
    }
    
    await Promise.all(promises);
    console.log(`Test historical data populated successfully for ${phoneNumber}`);
    return true;
  } catch (error) {
    console.error('Error populating test historical data:', error);
    return false;
  }
};
