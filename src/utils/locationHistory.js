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
