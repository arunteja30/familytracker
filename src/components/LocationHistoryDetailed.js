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
  FaChevronRight
} from 'react-icons/fa';
import { getCachedAddress } from '../utils/geocoding';
import { getLocationHistory, getAvailableDates } from '../utils/locationHistory';

const LocationHistoryDetailed = ({ selectedFamily }) => {
  const [familyMembers, setFamilyMembers] = useState({});
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

  // Load family members
  useEffect(() => {
    const membersRef = ref(database, 'familyMembersList');
    const unsubscribe = onValue(membersRef, (snapshot) => {
      const data = snapshot.val();
      setFamilyMembers(data || {});
      setLoading(false);
    });

    return () => unsubscribe();
  }, []);

  // Load location history when member or date range changes
  useEffect(() => {
    if (!selectedMember) {
      setLocationHistory([]);
      setAvailableDates([]);
      return;
    }

    // Get available dates for this member
    const unsubscribeDates = getAvailableDates(selectedMember, (dates) => {
      setAvailableDates(dates);
    });

    // Calculate date range
    const endDate = new Date().toISOString().split('T')[0];
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
        startDate = customStartDate || endDate;
        break;
      default:
        startDate = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString().split('T')[0];
    }

    // Get location history
    const unsubscribeHistory = getLocationHistory(
      selectedMember, 
      startDate, 
      customEndDate || endDate,
      (history) => {
        setLocationHistory(history);
        fetchAddressesForLocations(history);
      }
    );

    return () => {
      unsubscribeDates();
      unsubscribeHistory();
    };
  }, [selectedMember, selectedDateRange, customStartDate, customEndDate, fetchAddressesForLocations]);

  // Group locations by date
  const locationsByDate = locationHistory.reduce((acc, location) => {
    const date = location.date ? location.date.split(',')[0] : new Date(location.timestamp).toISOString().split('T')[0];
    if (!acc[date]) acc[date] = [];
    acc[date].push(location);
    return acc;
  }, {});

  const getFilteredMembers = () => {
    if (!selectedFamily) return Object.entries(familyMembers);
    return Object.entries(familyMembers).filter(([_, member]) => 
      member.familyName === selectedFamily
    );
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
    return new Date(timestamp).toLocaleTimeString();
  };

  const formatDate = (dateString) => {
    return new Date(dateString).toLocaleDateString('en-US', {
      weekday: 'long',
      year: 'numeric',
      month: 'long',
      day: 'numeric'
    });
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
        {selectedFamily && <span className="ml-2">- {selectedFamily}</span>}
      </div>
      <div className="card-content">
        {/* Filters */}
        <div style={{ marginBottom: '2rem' }}>
          <div className="grid grid-3">
            <div className="form-group">
              <label className="form-label">
                <FaPhoneAlt className="mr-1" />
                Select Member
              </label>
              <select 
                className="form-select"
                value={selectedMember}
                onChange={(e) => setSelectedMember(e.target.value)}
              >
                <option value="">Choose a member</option>
                {filteredMembers.map(([_, member]) => (
                  <option key={member.mobile} value={member.mobile}>
                    {member.name || 'Unnamed'} ({member.mobile})
                  </option>
                ))}
              </select>
            </div>
            
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

            {selectedDateRange === 'custom' && (
              <div className="form-group">
                <label className="form-label">Date Range</label>
                <div style={{ display: 'flex', gap: '0.5rem' }}>
                  <input
                    type="date"
                    className="form-input"
                    value={customStartDate}
                    onChange={(e) => setCustomStartDate(e.target.value)}
                    style={{ flex: 1 }}
                  />
                  <input
                    type="date"
                    className="form-input"
                    value={customEndDate}
                    onChange={(e) => setCustomEndDate(e.target.value)}
                    style={{ flex: 1 }}
                  />
                </div>
              </div>
            )}
          </div>
        </div>

        {/* Results */}
        {!selectedMember ? (
          <div className="text-center" style={{ padding: '3rem', color: '#666' }}>
            <FaPhoneAlt size={48} style={{ marginBottom: '1rem', opacity: 0.3 }} />
            <p>Please select a member to view their location history</p>
          </div>
        ) : Object.keys(locationsByDate).length === 0 ? (
          <div className="text-center" style={{ padding: '3rem', color: '#666' }}>
            <FaMapMarkerAlt size={48} style={{ marginBottom: '1rem', opacity: 0.3 }} />
            <p>No location history found for the selected period</p>
            {availableDates.length > 0 && (
              <small>Available dates: {availableDates.slice(0, 5).join(', ')}{availableDates.length > 5 ? '...' : ''}</small>
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
