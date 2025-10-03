// Utility functions for reverse geocoding (latitude/longitude to address)

/**
 * Get address from latitude and longitude using Nominatim (OpenStreetMap) API
 * @param {number} lat - Latitude
 * @param {number} lon - Longitude
 * @returns {Promise<string>} - Formatted address string
 */
export const getAddressFromCoordinates = async (lat, lon) => {
  try {
    // Using Nominatim (OpenStreetMap) reverse geocoding API - it's free and doesn't require API key
    const response = await fetch(
      `https://nominatim.openstreetmap.org/reverse?format=json&lat=${lat}&lon=${lon}&zoom=18&addressdetails=1&accept-language=en`
    );
    
    if (!response.ok) {
      throw new Error('Geocoding request failed');
    }
    
    const data = await response.json();
    
    if (data && data.display_name) {
      // Format the address to be more readable
      const address = data.address;
      
      // Build a formatted address from components
      let formattedAddress = '';
      
      if (address) {
        const parts = [];
        
        // Add house number and road
        if (address.house_number && address.road) {
          parts.push(`${address.house_number} ${address.road}`);
        } else if (address.road) {
          parts.push(address.road);
        }
        
        // Add locality/neighbourhood
        if (address.neighbourhood || address.suburb || address.locality) {
          parts.push(address.neighbourhood || address.suburb || address.locality);
        }
        
        // Add city
        if (address.city || address.town || address.village) {
          parts.push(address.city || address.town || address.village);
        }
        
        // Add state/region
        if (address.state || address.region) {
          parts.push(address.state || address.region);
        }
        
        // Add country
        if (address.country) {
          parts.push(address.country);
        }
        
        formattedAddress = parts.join(', ');
      }
      
      // Fallback to display_name if formatting fails
      return formattedAddress || data.display_name;
    }
    
    return 'Address not found';
  } catch (error) {
    console.error('Error fetching address:', error);
    return `${lat.toFixed(6)}, ${lon.toFixed(6)}`; // Fallback to coordinates
  }
};

/**
 * Get a short address (just main parts) from coordinates
 * @param {number} lat - Latitude
 * @param {number} lon - Longitude
 * @returns {Promise<string>} - Short formatted address
 */
export const getShortAddressFromCoordinates = async (lat, lon) => {
  try {
    const response = await fetch(
      `https://nominatim.openstreetmap.org/reverse?format=json&lat=${lat}&lon=${lon}&zoom=16&addressdetails=1&accept-language=en`
    );
    
    if (!response.ok) {
      throw new Error('Geocoding request failed');
    }
    
    const data = await response.json();
    
    if (data && data.address) {
      const address = data.address;
      const parts = [];
      
      // Add road
      if (address.road) {
        parts.push(address.road);
      }
      
      // Add city
      if (address.city || address.town || address.village) {
        parts.push(address.city || address.town || address.village);
      }
      
      return parts.join(', ') || 'Location';
    }
    
    return 'Location';
  } catch (error) {
    console.error('Error fetching short address:', error);
    return 'Location';
  }
};

/**
 * Cache for storing addresses to avoid repeated API calls
 */
class AddressCache {
  constructor() {
    this.cache = new Map();
    this.maxSize = 100; // Maximum number of cached addresses
  }
  
  getKey(lat, lon) {
    // Round to 4 decimal places for caching (about 11 meter precision)
    return `${lat.toFixed(4)},${lon.toFixed(4)}`;
  }
  
  get(lat, lon) {
    return this.cache.get(this.getKey(lat, lon));
  }
  
  set(lat, lon, address) {
    const key = this.getKey(lat, lon);
    
    // Remove oldest entry if cache is full
    if (this.cache.size >= this.maxSize) {
      const firstKey = this.cache.keys().next().value;
      this.cache.delete(firstKey);
    }
    
    this.cache.set(key, address);
  }
}

// Global cache instance
const addressCache = new AddressCache();

/**
 * Get address with caching
 * @param {number} lat - Latitude
 * @param {number} lon - Longitude
 * @param {boolean} short - Whether to return short address
 * @returns {Promise<string>} - Formatted address string
 */
export const getCachedAddress = async (lat, lon, short = false) => {
  // Check cache first
  const cached = addressCache.get(lat, lon);
  if (cached) {
    return cached;
  }
  
  // Fetch new address
  const address = short 
    ? await getShortAddressFromCoordinates(lat, lon)
    : await getAddressFromCoordinates(lat, lon);
  
  // Cache the result
  addressCache.set(lat, lon, address);
  
  return address;
};
