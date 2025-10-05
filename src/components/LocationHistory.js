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
  FaMapPin
} from 'react-icons/fa';
import { getCachedAddress } from '../utils/geocoding';
import { formatFamilyNameForDisplay } from '../utils/familyName';

const LocationHistory = ({ selectedFamily, user }) => {
  const [locations, setLocations] = useState({});
  const [familyMembers, setFamilyMembers] = useState({});
  const [selectedMember, setSelectedMember] = useState('');
  const [timeFilter, setTimeFilter] = useState('24h'); // 24h, 7d, 30d, all
  const [loading, setLoading] = useState(true);
  const [addresses, setAddresses] = useState({});
  const [loadingAddresses, setLoadingAddresses] = useState({});

  const isAdmin = user?.role === 'admin';

  // Function to fetch addresses for locations
  const fetchAddressesForLocations = useCallback(async (locationsData) => {
    const promises = Object.entries(locationsData).map(async ([phone, location]) => {
      if (location && location.latitude && location.longitude) {
        // Check if we already have this address
        const key = `${location.latitude.toFixed(4)},${location.longitude.toFixed(4)}`;
        if (addresses[key]) {
          return;
        }

        setLoadingAddresses(prev => ({ ...prev, [phone]: true }));
        
        try {
          const address = await getCachedAddress(location.latitude, location.longitude, false);
          setAddresses(prev => ({
            ...prev,
            [key]: address,
            [phone]: address // Also store by phone for easy access
          }));
        } catch (error) {
          console.error('Error fetching address for', phone, error);
        } finally {
          setLoadingAddresses(prev => ({ ...prev, [phone]: false }));
        }
      }
    });

    await Promise.all(promises);
  }, [addresses]);

  useEffect(() => {
    const locationsRef = ref(database, 'locationList');
    const membersRef = ref(database, 'familyMembersList');

    const unsubscribeLocations = onValue(locationsRef, (snapshot) => {
      const data = snapshot.val();
      setLocations(data || {});
      
      // Fetch addresses for new locations
      if (data) {
        fetchAddressesForLocations(data);
      }
    });

    const unsubscribeMembers = onValue(membersRef, (snapshot) => {
      const data = snapshot.val();
      setFamilyMembers(data || {});
      setLoading(false);
    });

    return () => {
      unsubscribeLocations();
      unsubscribeMembers();
    };
  }, [fetchAddressesForLocations]);

  const getFilteredMembers = () => {
    let members = Object.entries(familyMembers);
    
    // Non-admin users can only see their own family
    if (!isAdmin && user?.familyName) {
      members = members.filter(([_, member]) => member.familyName === user.familyName);
    }
    
    // Apply family filter if selected
    if (selectedFamily) {
      members = members.filter(([_, member]) => member.familyName === selectedFamily);
    }
    
    return members;
  };

  const getMemberByPhone = (phoneNumber) => {
    const memberEntry = Object.entries(familyMembers).find(([_, member]) => 
      member.mobile === phoneNumber && (!selectedFamily || member.familyName === selectedFamily)
    );
    return memberEntry ? memberEntry[1] : null;
  };

  const getFilteredLocations = () => {
    let filteredLocations = { ...locations };
    
    // Filter by selected member
    if (selectedMember) {
      filteredLocations = { [selectedMember]: locations[selectedMember] };
    } else if (selectedFamily) {
      // Filter by family
      const familyPhones = getFilteredMembers().map(([_, member]) => member.mobile);
      filteredLocations = {};
      familyPhones.forEach(phone => {
        if (locations[phone]) {
          filteredLocations[phone] = locations[phone];
        }
      });
    }

    // Filter by time
    const now = Date.now();
    let timeThreshold = 0;
    
    switch (timeFilter) {
      case '24h':
        timeThreshold = now - 24 * 60 * 60 * 1000;
        break;
      case '7d':
        timeThreshold = now - 7 * 24 * 60 * 60 * 1000;
        break;
      case '30d':
        timeThreshold = now - 30 * 24 * 60 * 60 * 1000;
        break;
      case 'all':
      default:
        timeThreshold = 0;
        break;
    }

    // Note: Current structure stores only latest location per user
    // For full history, you'd need a different data structure
    const filteredByTime = {};
    Object.entries(filteredLocations).forEach(([phone, location]) => {
      if (location.timeStamp >= timeThreshold) {
        filteredByTime[phone] = location;
      }
    });

    return filteredByTime;
  };

  const getBatteryIcon = (percentage) => {
    if (!percentage) return <FaBatteryEmpty style={{ color: '#ccc' }} />;
    if (percentage > 60) return <FaBatteryFull style={{ color: '#38a169' }} />;
    if (percentage > 30) return <FaBatteryHalf style={{ color: '#ecc94b' }} />;
    return <FaBatteryEmpty style={{ color: '#f56565' }} />;
  };

  const formatDateTime = (timestamp) => {
    return new Date(timestamp).toLocaleString();
  };

  const getTimeAgo = (timestamp) => {
    const now = Date.now();
    const diff = now - timestamp;
    
    if (diff < 60 * 1000) return 'Just now';
    if (diff < 60 * 60 * 1000) return `${Math.floor(diff / (60 * 1000))} min ago`;
    if (diff < 24 * 60 * 60 * 1000) return `${Math.floor(diff / (60 * 60 * 1000))} hours ago`;
    return `${Math.floor(diff / (24 * 60 * 60 * 1000))} days ago`;
  };

  const getBatteryColor = (percentage) => {
    if (percentage > 60) return '#38a169';
    if (percentage > 30) return '#ecc94b';
    return '#f56565';
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
  const filteredLocations = getFilteredLocations();
  const locationEntries = Object.entries(filteredLocations).sort(
    ([, a], [, b]) => b.timeStamp - a.timeStamp
  );

  return (
    <div className="card">
      <div className="card-header">
        <FaHistory className="mr-2" />
        Location History
        {selectedFamily && <span className="ml-2">- {formatFamilyNameForDisplay(selectedFamily)}</span>}
      </div>
      <div className="card-content">
        {/* Filters */}
        <div style={{ marginBottom: '2rem' }}>
          <div className="grid grid-2">
            <div className="form-group">
              <label className="form-label">
                <FaPhoneAlt className="mr-1" />
                Filter by Member
              </label>
              <select 
                className="form-select"
                value={selectedMember}
                onChange={(e) => setSelectedMember(e.target.value)}
              >
                <option value="">All Members</option>
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
                value={timeFilter}
                onChange={(e) => setTimeFilter(e.target.value)}
              >
                <option value="24h">Last 24 Hours</option>
                <option value="7d">Last 7 Days</option>
                <option value="30d">Last 30 Days</option>
                <option value="all">All Time</option>
              </select>
            </div>
          </div>
        </div>

        {/* Location History List */}
        {locationEntries.length === 0 ? (
          <div className="text-center" style={{ padding: '3rem', color: '#666' }}>
            <FaMapMarkerAlt size={48} style={{ marginBottom: '1rem', opacity: 0.3 }} />
            <p>No location data found for the selected filters</p>
            <small>
              Note: This shows the current location data structure. 
              For complete history tracking, consider implementing location history storage.
            </small>
          </div>
        ) : (
          <div>
            <div style={{ marginBottom: '1rem', color: '#666', fontSize: '0.9rem' }}>
              Showing {locationEntries.length} location record{locationEntries.length !== 1 ? 's' : ''}
            </div>
            
            <div style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
              {locationEntries.map(([phoneNumber, location]) => {
                const member = getMemberByPhone(phoneNumber);
                const isAdmin = member?.relationship === 'admin';
                
                return (
                  <div key={phoneNumber} className="card" style={{ margin: 0, borderLeft: `4px solid ${isAdmin ? '#38a169' : '#667eea'}` }}>
                    <div style={{ padding: '1.5rem' }}>
                      {/* Member Info Header */}
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '1rem' }}>
                        <div>
                          <h4 style={{ margin: 0, color: '#333' }}>
                            {member?.name || 'Unknown Member'}
                            {isAdmin && (
                              <span className="status-badge status-admin ml-2">Admin</span>
                            )}
                          </h4>
                          <div style={{ color: '#666', fontSize: '0.9rem', marginTop: '0.25rem' }}>
                            <FaPhoneAlt style={{ marginRight: '0.5rem' }} />
                            {phoneNumber}
                          </div>
                        </div>
                        <div style={{ textAlign: 'right', color: '#666', fontSize: '0.85rem' }}>
                          <div>
                            <FaClock style={{ marginRight: '0.5rem' }} />
                            {getTimeAgo(location.timeStamp)}
                          </div>
                        </div>
                      </div>

                      {/* Location Details Grid */}
                      <div className="grid grid-2" style={{ gap: '1.5rem' }}>
                        <div>
                          <div style={{ marginBottom: '0.75rem' }}>
                            <div style={{ display: 'flex', alignItems: 'center', marginBottom: '0.25rem' }}>
                              <FaMapMarkerAlt style={{ marginRight: '0.5rem', color: '#667eea' }} />
                              <strong>Location</strong>
                            </div>
                            {addresses[phoneNumber] ? (
                              <div>
                                <div style={{ 
                                  fontSize: '0.9rem', 
                                  color: '#333', 
                                  marginBottom: '0.5rem',
                                  padding: '0.5rem',
                                  backgroundColor: '#f8f9fa',
                                  borderRadius: '4px',
                                  borderLeft: '3px solid #28a745'
                                }}>
                                  <FaMapPin style={{ marginRight: '0.5rem', color: '#28a745' }} />
                                  {addresses[phoneNumber]}
                                </div>
                                <div style={{ fontSize: '0.8rem', color: '#666', fontFamily: 'monospace' }}>
                                  Coordinates: {location.latitude.toFixed(6)}, {location.longitude.toFixed(6)}
                                </div>
                              </div>
                            ) : loadingAddresses[phoneNumber] ? (
                              <div>
                                <div style={{ 
                                  fontSize: '0.9rem', 
                                  color: '#666', 
                                  marginBottom: '0.5rem',
                                  padding: '0.5rem',
                                  backgroundColor: '#f8f9fa',
                                  borderRadius: '4px',
                                  fontStyle: 'italic'
                                }}>
                                  <FaMapPin style={{ marginRight: '0.5rem', color: '#6c757d' }} />
                                  Loading address...
                                </div>
                                <div style={{ fontSize: '0.8rem', color: '#666', fontFamily: 'monospace' }}>
                                  Coordinates: {location.latitude.toFixed(6)}, {location.longitude.toFixed(6)}
                                </div>
                              </div>
                            ) : (
                              <div style={{ fontSize: '0.9rem', color: '#666', fontFamily: 'monospace' }}>
                                {location.latitude.toFixed(6)}, {location.longitude.toFixed(6)}
                              </div>
                            )}
                          </div>

                          <div>
                            <div style={{ display: 'flex', alignItems: 'center', marginBottom: '0.25rem' }}>
                              <FaSignal style={{ 
                                marginRight: '0.5rem', 
                                color: location.gpsStatus?.includes('Enabled') ? '#38a169' : '#f56565' 
                              }} />
                              <strong>GPS Status</strong>
                            </div>
                            <div style={{ fontSize: '0.9rem', color: '#666' }}>
                              {location.gpsStatus}
                            </div>
                          </div>
                        </div>

                        <div>
                          <div style={{ marginBottom: '0.75rem' }}>
                            <div style={{ display: 'flex', alignItems: 'center', marginBottom: '0.25rem' }}>
                              {getBatteryIcon(location.batteryPercentage)}
                              <strong style={{ marginLeft: '0.5rem' }}>Battery</strong>
                            </div>
                            <div style={{ fontSize: '0.9rem' }}>
                              <div style={{ 
                                display: 'inline-block', 
                                padding: '0.25rem 0.75rem',
                                backgroundColor: getBatteryColor(location.batteryPercentage),
                                color: 'white',
                                borderRadius: '12px',
                                fontSize: '0.8rem',
                                fontWeight: '600'
                              }}>
                                {location.batteryPercentage}%
                              </div>
                            </div>
                          </div>

                          <div>
                            <div style={{ display: 'flex', alignItems: 'center', marginBottom: '0.25rem' }}>
                              <FaCalendarAlt style={{ marginRight: '0.5rem', color: '#667eea' }} />
                              <strong>Date & Time</strong>
                            </div>
                            <div style={{ fontSize: '0.9rem', color: '#666' }}>
                              {formatDateTime(location.timeStamp)}
                            </div>
                          </div>
                        </div>
                      </div>

                      {/* View on Map Button */}
                      <div style={{ marginTop: '1rem', paddingTop: '1rem', borderTop: '1px solid #eee' }}>
                        <a
                          href={`https://www.google.com/maps/search/?api=1&query=${location.latitude},${location.longitude}`}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="btn btn-small"
                        >
                          <FaMapMarkerAlt style={{ marginRight: '0.5rem' }} />
                          View on Google Maps
                        </a>
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        )}

        {/* Note about data structure */}
        <div style={{ 
          marginTop: '2rem', 
          padding: '1rem', 
          backgroundColor: '#f8f9ff', 
          borderRadius: '6px',
          fontSize: '0.85rem',
          color: '#666'
        }}>
          <strong>Note:</strong> This shows current location data. For complete location history tracking, 
          consider implementing a time-series data structure that stores location updates over time.
        </div>
      </div>
    </div>
  );
};

export default LocationHistory;
