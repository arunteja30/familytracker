/**
 * LocationHistoryDetailed Component
 * 
 * This component displays location history for family members organized by date.
 * 
 * Current Implementation:
 * - Shows current location from 'locationList' database node
 * - Creates sample historical entries for demonstration
 * 
 * For Real Historical Tracking:
 * 1. Modify your location submission to store in: locationHistory/{phoneNumber}/{date}/[locations]
 * 2. Update the useEffect to read from locationHistory instead of creating mock data
 * 3. Each location should have: { latitude, longitude, timestamp, batteryPercentage, gpsStatus }
 * 
 * Database Structure for Real History:
 * locationHistory: {
 *   "+919999999999": {
 *     "2024-10-04": [
 *       { latitude: 18.1973, longitude: 79.3938, timestamp: 1728123456789, batteryPercentage: 85, gpsStatus: "Enabled" },
 *       { latitude: 18.1980, longitude: 79.3945, timestamp: 1728127056789, batteryPercentage: 82, gpsStatus: "Enabled" }
 *     ]
 *   }
 * }
 */
import React, { useState, useEffect, useCallback } from 'react';
import { database } from '../firebase';
import { ref, onValue } from 'firebase/database';
import { 
  FaHistory,
  FaCalendarAlt,
  FaBatteryFull,
  FaBatteryHalf, 
  FaBatteryEmpty,
  FaMapMarkerAlt,
  FaClock,
  FaSignal,
  FaPhoneAlt,
  FaMapPin,
  FaChevronDown,
  FaChevronRight,
  FaUsers
} from 'react-icons/fa';
import { getCachedAddress } from '../utils/geocoding';
import { populateTestHistoricalData } from '../utils/locationHistory';

const LocationHistoryDetailed = ({ selectedFamily }) => {
  const [familyMembers, setFamilyMembers] = useState({});
  const [familyList, setFamilyList] = useState({});
  const [localSelectedFamily, setLocalSelectedFamily] = useState(selectedFamily || '');
  const [selectedMember, setSelectedMember] = useState('');
  const [selectedDateRange, setSelectedDateRange] = useState('7d');
  const [customStartDate, setCustomStartDate] = useState('');
  const [customEndDate, setCustomEndDate] = useState('');
  const [loading, setLoading] = useState(true);
  const [locationHistory, setLocationHistory] = useState([]);
  const [availableDates, setAvailableDates] = useState([]);
  const [addresses, setAddresses] = useState({});
  const [loadingAddresses, setLoadingAddresses] = useState({});
  const [expandedDates, setExpandedDates] = useState(new Set());
  const [isPopulatingTestData, setIsPopulatingTestData] = useState(false);

  // Fetch addresses for locations
  const fetchAddressesForLocations = useCallback(async (locations) => {
    const promises = locations.map(async (location) => {
      if (location && location.latitude && location.longitude) {
        const key = `${location.latitude.toFixed(4)},${location.longitude.toFixed(4)}`;
        if (addresses[key]) return;

        setLoadingAddresses(prev => ({ ...prev, [key]: true }));
        
        try {
          const address = await getCachedAddress(location.latitude, location.longitude, false);
          setAddresses(prev => ({ ...prev, [key]: address }));
        } catch (error) {
          console.error('Error fetching address:', error);
        } finally {
          setLoadingAddresses(prev => ({ ...prev, [key]: false }));
        }
      }
    });

    await Promise.all(promises);
  }, [addresses]);

  // Load family members and family list
  useEffect(() => {
    const membersRef = ref(database, 'familyMembersList');
    const familiesRef = ref(database, 'familyList');

    const unsubscribeMembers = onValue(membersRef, (snapshot) => {
      const data = snapshot.val();
      setFamilyMembers(data || {});
    });

    const unsubscribeFamilies = onValue(familiesRef, (snapshot) => {
      const data = snapshot.val();
      setFamilyList(data || {});
      setLoading(false);
    });

    return () => {
      unsubscribeMembers();
      unsubscribeFamilies();
    };
  }, []);

  // Update local family selection when prop changes
  useEffect(() => {
    if (selectedFamily !== localSelectedFamily) {
      setLocalSelectedFamily(selectedFamily || '');
      setSelectedMember(''); // Reset member selection when family changes
    }
  }, [selectedFamily, localSelectedFamily]);

  // Load location history when member or date range changes
  useEffect(() => {
    if (!selectedMember) {
      setLocationHistory([]);
      setAvailableDates([]);
      return;
    }

    // Calculate date range based on selected option
    const endDate = customEndDate || new Date().toISOString().split('T')[0];
    let startDate;
    
    switch (selectedDateRange) {
      case '1d':
        startDate = endDate;
        break;
      case '7d':
        startDate = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString().split('T')[0];
        break;
      case '30d':
        startDate = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString().split('T')[0];
        break;
      case 'custom':
        startDate = customStartDate || new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString().split('T')[0];
        break;
      default:
        startDate = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString().split('T')[0];
    }

    // Get real location history from locationHistory database node
    const historyRef = ref(database, `locationHistory/${selectedMember}`);
    const unsubscribeHistory = onValue(historyRef, (snapshot) => {
      const historyData = snapshot.val();
      const allHistory = [];
      const availableDatesSet = new Set();

      if (historyData) {
        // Process each date's locations
        Object.entries(historyData).forEach(([date, dayLocations]) => {
          // Filter by date range
          if (date >= startDate && date <= endDate) {
            availableDatesSet.add(date);
            
            // Process locations for this date
            if (dayLocations && typeof dayLocations === 'object') {
              Object.entries(dayLocations).forEach(([locationId, location]) => {
                if (location && location.latitude && location.longitude) {
                  allHistory.push({
                    ...location,
                    id: locationId,
                    date: date,
                    // Ensure timestamp exists
                    timestamp: location.timestamp || location.timeStamp || Date.now(),
                    // Ensure gpsStatus exists
                    gpsStatus: location.gpsStatus || location.gpsInfo || 'Unknown'
                  });
                }
              });
            }
          }
        });
      }

      // If no historical data exists, try to get current location as fallback
      if (allHistory.length === 0) {
        const currentLocationRef = ref(database, `locationList/${selectedMember}`);
        onValue(currentLocationRef, (currentSnapshot) => {
          const currentLocation = currentSnapshot.val();
          if (currentLocation && currentLocation.latitude && currentLocation.longitude) {
            const todayDate = new Date().toISOString().split('T')[0];
            const currentLocationEntry = {
              ...currentLocation,
              timestamp: currentLocation.timeStamp || currentLocation.timestamp || Date.now(),
              id: `${selectedMember}_current`,
              date: todayDate,
              gpsStatus: currentLocation.gpsStatus || currentLocation.gpsInfo || 'Enabled'
            };
            
            setLocationHistory([currentLocationEntry]);
            setAvailableDates([todayDate]);
            fetchAddressesForLocations([currentLocationEntry]);
          } else {
            setLocationHistory([]);
            setAvailableDates([]);
          }
        });
      } else {
        // Sort by timestamp (newest first)
        allHistory.sort((a, b) => b.timestamp - a.timestamp);
        
        setLocationHistory(allHistory);
        setAvailableDates([...availableDatesSet].sort().reverse());
        fetchAddressesForLocations(allHistory);
      }
    });

    return () => {
      unsubscribeHistory();
    };
  }, [selectedMember, selectedDateRange, customStartDate, customEndDate, fetchAddressesForLocations]);

  // Auto-expand all dates when location history changes
  useEffect(() => {
    if (locationHistory.length > 0) {
      const dates = [...new Set(locationHistory.map(location => {
        const dateObj = new Date(location.timestamp);
        return dateObj.toISOString().split('T')[0];
      }))];
      setExpandedDates(new Set(dates));
    }
  }, [locationHistory]);

  // Function to populate test historical data
  const handlePopulateTestData = async () => {
    if (!selectedMember) {
      alert('Please select a member first');
      return;
    }

    setIsPopulatingTestData(true);
    
    try {
      // Get current location as base for test data
      const currentLocationRef = ref(database, `locationList/${selectedMember}`);
      const snapshot = await new Promise((resolve) => {
        onValue(currentLocationRef, resolve, { onlyOnce: true });
      });
      
      const currentLocation = snapshot.val();
      if (!currentLocation || !currentLocation.latitude || !currentLocation.longitude) {
        alert('No current location found for this member. Please ensure they have shared their location first.');
        setIsPopulatingTestData(false);
        return;
      }

      const success = await populateTestHistoricalData(selectedMember, currentLocation);
      
      if (success) {
        alert('Test historical data populated successfully! Refresh will show the new data.');
      } else {
        alert('Failed to populate test data. Check console for errors.');
      }
    } catch (error) {
      console.error('Error populating test data:', error);
      alert('Error populating test data: ' + error.message);
    }
    
    setIsPopulatingTestData(false);
  };

  // Group locations by date
  const locationsByDate = locationHistory.reduce((acc, location) => {
    let date;
    if (location.timestamp) {
      // Create date from timestamp
      const dateObj = new Date(location.timestamp);
      date = dateObj.toISOString().split('T')[0]; // YYYY-MM-DD format
    } else if (location.date) {
      // If date exists, try to parse it
      const dateObj = new Date(location.date);
      if (!isNaN(dateObj.getTime())) {
        date = dateObj.toISOString().split('T')[0];
      } else {
        date = new Date().toISOString().split('T')[0]; // Fallback to today
      }
    } else {
      date = new Date().toISOString().split('T')[0]; // Fallback to today
    }
    
    if (!acc[date]) acc[date] = [];
    acc[date].push(location);
    return acc;
  }, {});

  const getFilteredMembers = () => {
    if (!localSelectedFamily) return Object.entries(familyMembers);
    return Object.entries(familyMembers).filter(([_, member]) => 
      member.familyName === localSelectedFamily
    );
  };

  const handleFamilyChange = (familyName) => {
    setLocalSelectedFamily(familyName);
    setSelectedMember(''); // Reset member selection when family changes
    // Clear location history when changing families
    setLocationHistory([]);
    setAvailableDates([]);
  };

  const getFamilyNames = () => {
    return Object.keys(familyList);
  };

  const toggleDateExpansion = (date) => {
    const newExpanded = new Set(expandedDates);
    if (newExpanded.has(date)) {
      newExpanded.delete(date);
    } else {
      newExpanded.add(date);
    }
    setExpandedDates(newExpanded);
  };

  const getBatteryIcon = (percentage) => {
    if (!percentage) return <FaBatteryEmpty style={{ color: '#ccc' }} />;
    if (percentage > 60) return <FaBatteryFull style={{ color: '#38a169' }} />;
    if (percentage > 30) return <FaBatteryHalf style={{ color: '#ecc94b' }} />;
    return <FaBatteryEmpty style={{ color: '#f56565' }} />;
  };

  const formatTime = (timestamp) => {
    return new Date(timestamp).toLocaleTimeString('en-US', {
      hour: '2-digit',
      minute: '2-digit',
      hour12: true
    });
  };

  const formatDate = (dateString) => {
    const date = new Date(dateString + 'T00:00:00'); // Add time to avoid timezone issues
    if (isNaN(date.getTime())) {
      return 'Invalid Date';
    }
    
    const today = new Date().toISOString().split('T')[0];
    const yesterday = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString().split('T')[0];
    
    if (dateString === today) {
      return 'Today - ' + date.toLocaleDateString('en-US', { 
        weekday: 'long', 
        month: 'long', 
        day: 'numeric' 
      });
    } else if (dateString === yesterday) {
      return 'Yesterday - ' + date.toLocaleDateString('en-US', { 
        weekday: 'long', 
        month: 'long', 
        day: 'numeric' 
      });
    } else {
      return date.toLocaleDateString('en-US', {
        weekday: 'long',
        year: 'numeric',
        month: 'long',
        day: 'numeric'
      });
    }
  };

  if (loading) {
    return (
      <div className="card">
        <div className="card-header">Location History</div>
        <div className="card-content">
          <div className="loading">Loading location history...</div>
        </div>
      </div>
    );
  }

  const filteredMembers = getFilteredMembers();

  return (
    <div className="card">
      <div className="card-header">
        <FaHistory className="mr-2" />
        Detailed Location History
        {localSelectedFamily && <span className="ml-2">- {localSelectedFamily}</span>}
        {selectedMember && filteredMembers.length > 0 && (
          <span className="ml-2">
            ({filteredMembers.find(([_, member]) => member.mobile === selectedMember)?.[1]?.name || 'Member'})
          </span>
        )}
      </div>
      <div className="card-content">
        {/* Filters */}
        <div style={{ marginBottom: '2rem' }}>
          <div className="grid grid-3">
            {/* Family Selection */}
            <div className="form-group">
              <label className="form-label">
                <FaUsers className="mr-1" />
                Select Family
              </label>
              <select 
                className="form-select"
                value={localSelectedFamily}
                onChange={(e) => handleFamilyChange(e.target.value)}
              >
                <option value="">All Families</option>
                {getFamilyNames().map(familyName => (
                  <option key={familyName} value={familyName}>
                    {familyName}
                  </option>
                ))}
              </select>
            </div>

            {/* Member Selection */}
            <div className="form-group">
              <label className="form-label">
                <FaPhoneAlt className="mr-1" />
                Select Member
              </label>
              <select 
                className="form-select"
                value={selectedMember}
                onChange={(e) => setSelectedMember(e.target.value)}
                disabled={!localSelectedFamily && getFamilyNames().length > 1}
              >
                <option value="">
                  {!localSelectedFamily && getFamilyNames().length > 1 
                    ? 'Select a family first' 
                    : 'Choose a member'}
                </option>
                {filteredMembers.map(([_, member]) => (
                  <option key={member.mobile} value={member.mobile}>
                    {member.name || 'Unnamed'} ({member.mobile})
                  </option>
                ))}
              </select>
            </div>
            
            {/* Time Period Selection */}
            <div className="form-group">
              <label className="form-label">
                <FaCalendarAlt className="mr-1" />
                Time Period
              </label>
              <select 
                className="form-select"
                value={selectedDateRange}
                onChange={(e) => setSelectedDateRange(e.target.value)}
              >
                <option value="1d">Today</option>
                <option value="7d">Last 7 Days</option>
                <option value="30d">Last 30 Days</option>
                <option value="custom">Custom Range</option>
              </select>
            </div>
          </div>

          {/* Custom Date Range */}
          {selectedDateRange === 'custom' && (
            <div style={{ marginTop: '1rem' }}>
              <div className="grid grid-2">
                <div className="form-group">
                  <label className="form-label">Start Date</label>
                  <input
                    type="date"
                    className="form-input"
                    value={customStartDate}
                    onChange={(e) => setCustomStartDate(e.target.value)}
                  />
                </div>
                <div className="form-group">
                  <label className="form-label">End Date</label>
                  <input
                    type="date"
                    className="form-input"
                    value={customEndDate}
                    onChange={(e) => setCustomEndDate(e.target.value)}
                  />
                </div>
              </div>
            </div>
          )}
        </div>



        {/* Selection Info */}
        {(localSelectedFamily || selectedMember) && (
          <div style={{ 
            marginBottom: '1rem', 
            padding: '0.75rem', 
            backgroundColor: '#f8f9ff', 
            border: '1px solid #e3f2fd', 
            borderRadius: '6px',
            fontSize: '0.9rem',
            color: '#1976d2'
          }}>
            <strong>Current Selection:</strong>{' '}
            {localSelectedFamily && <span>Family: {localSelectedFamily}</span>}
            {localSelectedFamily && selectedMember && <span> | </span>}
            {selectedMember && (
              <span>
                Member: {filteredMembers.find(([_, member]) => member.mobile === selectedMember)?.[1]?.name || 'Unknown'} 
                ({selectedMember})
              </span>
            )}
            {localSelectedFamily && !selectedMember && (
              <span> | {filteredMembers.length} member{filteredMembers.length !== 1 ? 's' : ''} available</span>
            )}
          </div>
        )}

        {/* Results */}
        {!selectedMember ? (
          <div className="text-center" style={{ padding: '3rem', color: '#666' }}>
            <FaPhoneAlt size={48} style={{ marginBottom: '1rem', opacity: 0.3 }} />
            <p>
              {getFamilyNames().length > 1 && !localSelectedFamily 
                ? 'Please select a family and then a member to view location history'
                : 'Please select a member to view their location history'}
            </p>
            {localSelectedFamily && filteredMembers.length > 0 && (
              <div style={{ marginTop: '1rem', fontSize: '0.9rem' }}>
                Available members in {localSelectedFamily}: {filteredMembers.length}
              </div>
            )}
          </div>
        ) : Object.keys(locationsByDate).length === 0 ? (
          <div className="text-center" style={{ padding: '3rem', color: '#666' }}>
            <FaMapMarkerAlt size={48} style={{ marginBottom: '1rem', opacity: 0.3 }} />
            <p>No location history found for the selected period</p>
            {availableDates.length > 0 ? (
              <small>Available dates: {availableDates.slice(0, 5).join(', ')}{availableDates.length > 5 ? '...' : ''}</small>
            ) : (
              <div style={{ marginTop: '1rem' }}>
                <p style={{ fontSize: '0.9rem', marginBottom: '1rem' }}>
                  To see historical data here, your location submission should store data in:<br />
                  <code style={{ backgroundColor: '#f5f5f5', padding: '0.25rem' }}>
                    locationHistory/{`{phoneNumber}`}/{`{date}`}/[locations]
                  </code>
                </p>
                {selectedMember && (
                  <button
                    className="btn btn-small"
                    onClick={handlePopulateTestData}
                    disabled={isPopulatingTestData}
                  >
                    {isPopulatingTestData ? 'Creating Test Data...' : '📊 Generate Sample Data for Testing'}
                  </button>
                )}
              </div>
            )}
          </div>
        ) : (
          <div>
            <div style={{ marginBottom: '1rem', color: '#666', fontSize: '0.9rem' }}>
              Showing history for {Object.keys(locationsByDate).length} day{Object.keys(locationsByDate).length !== 1 ? 's' : ''} 
              ({locationHistory.length} total records)
            </div>
            
            {Object.entries(locationsByDate)
              .sort(([a], [b]) => b.localeCompare(a))
              .map(([date, dayLocations]) => {
                const isExpanded = expandedDates.has(date);
                const sortedLocations = dayLocations.sort((a, b) => b.timestamp - a.timestamp);
                
                return (
                  <div key={date} className="card" style={{ margin: '0 0 1rem 0' }}>
                    <div 
                      className="card-header" 
                      style={{ 
                        cursor: 'pointer',
                        display: 'flex',
                        justifyContent: 'space-between',
                        alignItems: 'center'
                      }}
                      onClick={() => toggleDateExpansion(date)}
                    >
                      <div>
                        <FaCalendarAlt className="mr-2" />
                        {formatDate(date)}
                        <span style={{ marginLeft: '1rem', fontSize: '0.9rem', opacity: 0.8 }}>
                          {dayLocations.length} location{dayLocations.length !== 1 ? 's' : ''}
                        </span>
                      </div>
                      {isExpanded ? <FaChevronDown /> : <FaChevronRight />}
                    </div>
                    
                    {isExpanded && (
                      <div className="card-content">
                        <div style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
                          {sortedLocations.map((location, index) => {
                            const addressKey = `${location.latitude.toFixed(4)},${location.longitude.toFixed(4)}`;
                            
                            return (
                              <div 
                                key={location.id || index}
                                style={{ 
                                  padding: '1rem',
                                  backgroundColor: '#f8f9fa',
                                  borderRadius: '6px',
                                  borderLeft: '3px solid #667eea'
                                }}
                              >
                                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '1rem' }}>
                                  <div style={{ fontSize: '1rem', fontWeight: '600', color: '#333' }}>
                                    <FaClock style={{ marginRight: '0.5rem', color: '#667eea' }} />
                                    {formatTime(location.timestamp)}
                                  </div>
                                  <div style={{ display: 'flex', gap: '1rem', alignItems: 'center' }}>
                                    {getBatteryIcon(location.batteryPercentage)}
                                    <span style={{ fontSize: '0.9rem' }}>{location.batteryPercentage || 'N/A'}%</span>
                                  </div>
                                </div>

                                <div className="grid grid-2" style={{ gap: '1rem' }}>
                                  <div>
                                    <div style={{ display: 'flex', alignItems: 'center', marginBottom: '0.5rem' }}>
                                      <FaMapPin style={{ marginRight: '0.5rem', color: '#28a745' }} />
                                      <strong>Location</strong>
                                    </div>
                                    {addresses[addressKey] ? (
                                      <div style={{ fontSize: '0.9rem', color: '#333' }}>
                                        {addresses[addressKey]}
                                      </div>
                                    ) : loadingAddresses[addressKey] ? (
                                      <div style={{ fontSize: '0.9rem', color: '#666', fontStyle: 'italic' }}>
                                        Loading address...
                                      </div>
                                    ) : (
                                      <div style={{ fontSize: '0.9rem', color: '#666' }}>
                                        {location.latitude.toFixed(6)}, {location.longitude.toFixed(6)}
                                      </div>
                                    )}
                                  </div>
                                  
                                  <div>
                                    <div style={{ display: 'flex', alignItems: 'center', marginBottom: '0.5rem' }}>
                                      <FaSignal style={{ 
                                        marginRight: '0.5rem', 
                                        color: location.gpsStatus?.includes('Enabled') ? '#38a169' : '#f56565' 
                                      }} />
                                      <strong>GPS Status</strong>
                                    </div>
                                    <div style={{ fontSize: '0.9rem', color: '#666' }}>
                                      {location.gpsStatus || location.gpsInfo || 'Unknown'}
                                    </div>
                                  </div>
                                </div>

                                <div style={{ marginTop: '1rem', paddingTop: '1rem', borderTop: '1px solid #eee' }}>
                                  <a
                                    href={`https://www.google.com/maps/search/?api=1&query=${location.latitude},${location.longitude}`}
                                    target="_blank"
                                    rel="noopener noreferrer"
                                    className="btn btn-small"
                                    style={{ textDecoration: 'none' }}
                                  >
                                    <FaMapMarkerAlt style={{ marginRight: '0.5rem' }} />
                                    View on Google Maps
                                  </a>
                                </div>
                              </div>
                            );
                          })}
                        </div>
                      </div>
                    )}
                  </div>
                );
              })}
          </div>
        )}
      </div>
    </div>
  );
};

export default LocationHistoryDetailed;
