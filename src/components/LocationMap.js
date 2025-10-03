import React, { useState, useEffect, useRef, useCallback } from 'react';
import { MapContainer, TileLayer, Marker, Popup, Polyline, useMap } from 'react-leaflet';
import L from 'leaflet';
import { database } from '../firebase';
import { ref, onValue, query, orderByChild, limitToLast } from 'firebase/database';
import { FaBatteryFull, FaBatteryHalf, FaBatteryEmpty, FaMapMarkerAlt, FaClock, FaEye, FaTimes, FaRoute, FaMapPin, FaExpand, FaCompress } from 'react-icons/fa';
import { getCachedAddress, getShortAddressFromCoordinates } from '../utils/geocoding';

// Fix for default markers in react-leaflet
delete L.Icon.Default.prototype._getIconUrl;
L.Icon.Default.mergeOptions({
  iconRetinaUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-icon-2x.png',
  iconUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-icon.png',
  shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-shadow.png',
});

// Custom icon for family members
const createCustomIcon = (color = '#667eea', isSelected = false) => {
  const size = isSelected ? 32 : 20;
  const borderWidth = isSelected ? 4 : 3;
  const pulse = isSelected ? 'animation: pulse 2s infinite;' : '';
  
  return L.divIcon({
    className: 'custom-marker',
    html: `
      <div style="
        background-color: ${color}; 
        width: ${size}px; 
        height: ${size}px; 
        border-radius: 50%; 
        border: ${borderWidth}px solid white; 
        box-shadow: 0 2px 10px rgba(0,0,0,0.4);
        ${pulse}
      "></div>
      <style>
        @keyframes pulse {
          0% { box-shadow: 0 0 0 0 ${color}66; }
          70% { box-shadow: 0 0 0 10px ${color}00; }
          100% { box-shadow: 0 0 0 0 ${color}00; }
        }
      </style>
    `,
    iconSize: [size + 8, size + 8],
    iconAnchor: [(size + 8) / 2, (size + 8) / 2]
  });
};

// Component to center map on selected member
const MapController = ({ selectedMember, locations, familyMembers }) => {
  const map = useMap();
  
  useEffect(() => {
    if (selectedMember && locations[selectedMember]) {
      const location = locations[selectedMember];
      map.setView([location.latitude, location.longitude], 15, {
        animate: true,
        duration: 1
      });
    }
  }, [selectedMember, locations, map]);
  
  return null;
};

const LocationMap = ({ selectedFamily, selectedMember, onMemberSelect }) => {
  const [locations, setLocations] = useState({});
  const [familyMembers, setFamilyMembers] = useState({});
  const [loading, setLoading] = useState(true);
  const [trackingMode, setTrackingMode] = useState(false);
  const [locationHistory, setLocationHistory] = useState({});
  const [showPath, setShowPath] = useState(true);
  const [addresses, setAddresses] = useState({});
  const [loadingAddresses, setLoadingAddresses] = useState({});
  const [isFullScreen, setIsFullScreen] = useState(false);
  const [showGestureHelp, setShowGestureHelp] = useState(false);
  const mapRef = useRef();
  const mapContainerRef = useRef();

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
          const address = await getCachedAddress(location.latitude, location.longitude, true);
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

  // Full-screen toggle functions
  const toggleFullScreen = () => {
    if (!isFullScreen) {
      // Enter full-screen mode
      if (mapContainerRef.current?.requestFullscreen) {
        mapContainerRef.current.requestFullscreen();
      } else if (mapContainerRef.current?.webkitRequestFullscreen) {
        mapContainerRef.current.webkitRequestFullscreen();
      } else if (mapContainerRef.current?.msRequestFullscreen) {
        mapContainerRef.current.msRequestFullscreen();
      }
      setIsFullScreen(true);
      
      // Show gesture help on mobile for first few seconds
      if (window.innerWidth <= 768) {
        setShowGestureHelp(true);
        setTimeout(() => setShowGestureHelp(false), 4000);
      }
    } else {
      // Exit full-screen mode
      if (document.exitFullscreen) {
        document.exitFullscreen();
      } else if (document.webkitExitFullscreen) {
        document.webkitExitFullscreen();
      } else if (document.msExitFullscreen) {
        document.msExitFullscreen();
      }
      setIsFullScreen(false);
      setShowGestureHelp(false);
    }
  };

  // Handle full-screen change events
  useEffect(() => {
    const handleFullScreenChange = () => {
      setIsFullScreen(!!document.fullscreenElement);
    };

    document.addEventListener('fullscreenchange', handleFullScreenChange);
    document.addEventListener('webkitfullscreenchange', handleFullScreenChange);
    document.addEventListener('msfullscreenchange', handleFullScreenChange);

    return () => {
      document.removeEventListener('fullscreenchange', handleFullScreenChange);
      document.removeEventListener('webkitfullscreenchange', handleFullScreenChange);
      document.removeEventListener('msfullscreenchange', handleFullScreenChange);
    };
  }, []);

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

  // Auto-refresh for selected member tracking and history
  useEffect(() => {
    let refreshInterval;
    
    if (selectedMember) {
      setTrackingMode(true);
      
      // Load location history for selected member
      const loadLocationHistory = () => {
        // In real app, this would query location history
        // For now, we'll simulate by storing recent locations
        const memberLocationRef = ref(database, `locationList/${selectedMember}`);
        onValue(memberLocationRef, (snapshot) => {
          const data = snapshot.val();
          if (data) {
            setLocations(prev => ({
              ...prev,
              [selectedMember]: data
            }));
            
            // Add to history for path tracking
            setLocationHistory(prev => {
              const memberHistory = prev[selectedMember] || [];
              const newLocation = {
                lat: data.latitude,
                lng: data.longitude,
                timestamp: data.timeStamp,
                date: data.date
              };
              
              // Keep only last 20 points for performance
              const updatedHistory = [...memberHistory, newLocation].slice(-20);
              
              return {
                ...prev,
                [selectedMember]: updatedHistory
              };
            });
          }
        });
      };
      
      // Load initial history
      loadLocationHistory();
      
      // Refresh every 5 seconds for live tracking
      refreshInterval = setInterval(loadLocationHistory, 5000);
    } else {
      setTrackingMode(false);
    }

    return () => {
      if (refreshInterval) {
        clearInterval(refreshInterval);
      }
    };
  }, [selectedMember]);

  const getFilteredLocations = () => {
    if (!selectedFamily) return locations;
    
    const filteredLocations = {};
    Object.entries(familyMembers).forEach(([memberId, member]) => {
      if (member.familyName === selectedFamily) {
        const phone = member.mobile;
        if (locations[phone]) {
          filteredLocations[phone] = locations[phone];
        }
      }
    });
    return filteredLocations;
  };

  const getMemberInfo = (phoneNumber) => {
    const memberEntry = Object.entries(familyMembers).find(([_, member]) => 
      member.mobile === phoneNumber && (!selectedFamily || member.familyName === selectedFamily)
    );
    return memberEntry ? memberEntry[1] : null;
  };

  const getBatteryIcon = (percentage) => {
    if (percentage > 60) return <FaBatteryFull style={{ color: '#38a169' }} />;
    if (percentage > 30) return <FaBatteryHalf style={{ color: '#ecc94b' }} />;
    return <FaBatteryEmpty style={{ color: '#f56565' }} />;
  };

  const formatDate = (timestamp) => {
    return new Date(timestamp).toLocaleString();
  };

  const getTimeAgo = (timestamp) => {
    if (!timestamp) return 'Never';
    
    const now = Date.now();
    const diff = now - timestamp;
    
    if (diff < 60 * 1000) return 'Just now';
    if (diff < 60 * 60 * 1000) return `${Math.floor(diff / (60 * 1000))} min ago`;
    if (diff < 24 * 60 * 60 * 1000) return `${Math.floor(diff / (60 * 60 * 1000))} hours ago`;
    return `${Math.floor(diff / (24 * 60 * 60 * 1000))} days ago`;
  };

  if (loading) {
    return (
      <div className="card">
        <div className="card-header">Real-time Location Map</div>
        <div className="card-content">
          <div className="loading">Loading map...</div>
        </div>
      </div>
    );
  }

  const filteredLocations = getFilteredLocations();
  const locationEntries = Object.entries(filteredLocations);

  // Default center (India)
  const defaultCenter = [20.5937, 78.9629];
  let mapCenter = defaultCenter;
  let mapZoom = 6;

  // If there's a selected member, center on them
  if (selectedMember && filteredLocations[selectedMember]) {
    const location = filteredLocations[selectedMember];
    mapCenter = [location.latitude, location.longitude];
    mapZoom = 15;
  }
  // Otherwise, if there are locations, center on the first one
  else if (locationEntries.length > 0) {
    const firstLocation = locationEntries[0][1];
    mapCenter = [firstLocation.latitude, firstLocation.longitude];
    mapZoom = 13;
  }

  // Get selected member info
  const selectedMemberInfo = selectedMember ? getMemberInfo(selectedMember) : null;
  const selectedMemberLocation = selectedMember ? filteredLocations[selectedMember] : null;

  return (
    <div className="card">
      <div className="card-header">
        <FaMapMarkerAlt className="mr-2" />
        Real-time Location Map
        {selectedFamily && <span className="ml-2">- {selectedFamily}</span>}
      </div>
      <div className="card-content">
        {/* Selected Member Tracking Panel */}
        {selectedMember && selectedMemberInfo && (
          <div style={{ marginBottom: '1rem' }}>
            {/* Main tracking panel */}
            <div style={{ 
              padding: '1rem', 
              backgroundColor: '#667eea', 
              color: 'white', 
              borderRadius: '8px 8px 0 0',
              display: 'flex',
              justifyContent: 'space-between',
              alignItems: 'center'
            }}>
              <div style={{ display: 'flex', alignItems: 'center' }}>
                <FaEye style={{ marginRight: '0.5rem' }} />
                <span>
                  Tracking: <strong>{selectedMemberInfo.name || 'Unknown'}</strong>
                  {selectedMemberLocation && (
                    <span style={{ marginLeft: '1rem', opacity: 0.9 }}>
                      Last update: {getTimeAgo(selectedMemberLocation.timeStamp)}
                    </span>
                  )}
                </span>
              </div>
              <button 
                onClick={() => onMemberSelect && onMemberSelect(null)}
                style={{ 
                  background: 'rgba(255,255,255,0.2)', 
                  border: 'none', 
                  color: 'white', 
                  padding: '0.5rem', 
                  borderRadius: '4px',
                  cursor: 'pointer'
                }}
              >
                <FaTimes />
              </button>
            </div>
            
            {/* Path controls */}
            <div style={{ 
              padding: '0.75rem 1rem', 
              backgroundColor: '#f8f9fa', 
              borderRadius: '0 0 8px 8px',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
              borderTop: '1px solid #e9ecef'
            }}>
              <div style={{ display: 'flex', alignItems: 'center' }}>
                <FaRoute style={{ marginRight: '0.5rem', color: '#667eea' }} />
                <span style={{ fontSize: '0.9rem', color: '#495057' }}>
                  Movement Path: 
                  {locationHistory[selectedMember] && (
                    <span style={{ marginLeft: '0.5rem', fontWeight: 'bold' }}>
                      {locationHistory[selectedMember].length} points
                    </span>
                  )}
                </span>
              </div>
              <label style={{ 
                display: 'flex', 
                alignItems: 'center', 
                fontSize: '0.9rem', 
                color: '#495057',
                cursor: 'pointer'
              }}>
                <input 
                  type="checkbox" 
                  checked={showPath}
                  onChange={(e) => setShowPath(e.target.checked)}
                  style={{ marginRight: '0.5rem' }}
                />
                Show Path
              </label>
            </div>
          </div>
        )}

        {locationEntries.length === 0 ? (
          <div className="text-center" style={{ padding: '2rem', color: '#666' }}>
            No location data available
            {selectedFamily && ' for this family'}
          </div>
        ) : (
          <div 
            ref={mapContainerRef}
            className={`map-container ${isFullScreen ? 'fullscreen' : ''}`}
          >
            {/* Full-screen toggle button */}
            <button
              onClick={toggleFullScreen}
              className="fullscreen-toggle"
              title={isFullScreen ? 'Exit Full Screen' : 'Enter Full Screen'}
            >
              {isFullScreen ? <FaCompress /> : <FaExpand />}
            </button>

            {/* Mobile full-screen controls */}
            {isFullScreen && (
              <>
                <div className="mobile-map-controls">
                  <button
                    onClick={toggleFullScreen}
                    className="mobile-close-btn"
                    title="Close Full Screen"
                  >
                    <FaTimes />
                  </button>
                  <div className="mobile-zoom-controls">
                    <button
                      onClick={() => mapRef.current?.setZoom(mapRef.current.getZoom() + 1)}
                      className="mobile-zoom-btn"
                      title="Zoom In"
                    >
                      +
                    </button>
                    <button
                      onClick={() => mapRef.current?.setZoom(mapRef.current.getZoom() - 1)}
                      className="mobile-zoom-btn"
                      title="Zoom Out"
                    >
                      -
                    </button>
                  </div>
                </div>

                {/* Gesture help overlay */}
                {showGestureHelp && window.innerWidth <= 768 && (
                  <div className="gesture-help-overlay">
                    <div className="gesture-help-content">
                      <h3>Map Gestures</h3>
                      <div className="gesture-instructions">
                        <div>🤏 Pinch to zoom in/out</div>
                        <div>👆 Drag to move around</div>
                        <div>👆👆 Double tap to zoom in</div>
                        <div>👆 Tap marker for details</div>
                      </div>
                      <button
                        onClick={() => setShowGestureHelp(false)}
                        className="got-it-btn"
                      >
                        Got it!
                      </button>
                    </div>
                  </div>
                )}
              </>
            )}
            
            <MapContainer
              ref={mapRef}
              center={mapCenter}
              zoom={mapZoom}
              style={{ height: '100%', width: '100%' }}
              zoomControl={!isFullScreen} // Hide default zoom controls in fullscreen
              touchZoom={true}
              doubleClickZoom={true}
              scrollWheelZoom={true}
              dragging={true}
              keyboard={true}
              boxZoom={true}
              tap={true}
              tapTolerance={15}
              zoomSnap={0.5}
              zoomDelta={0.5}
              wheelPxPerZoomLevel={100}
              maxZoom={20}
              minZoom={2}
            >
              <TileLayer
                attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
                url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
              />
              
              {/* Map Controller for centering on selected member */}
              <MapController 
                selectedMember={selectedMember} 
                locations={filteredLocations}
                familyMembers={familyMembers}
              />
              
              {locationEntries.map(([phoneNumber, location]) => {
                const member = getMemberInfo(phoneNumber);
                const isAdmin = member?.relationship === 'admin';
                const isSelected = phoneNumber === selectedMember;
                const iconColor = isSelected ? '#ff6b6b' : (isAdmin ? '#38a169' : '#667eea');
                
                return (
                  <Marker
                    key={phoneNumber}
                    position={[location.latitude, location.longitude]}
                    icon={createCustomIcon(iconColor, isSelected)}
                    eventHandlers={{
                      click: () => onMemberSelect && onMemberSelect(phoneNumber)
                    }}
                  >
                    <Popup>
                      <div style={{ minWidth: '200px' }}>
                        <h3 style={{ margin: '0 0 10px 0', color: '#333' }}>
                          {member?.name || 'Unknown'} 
                          {isAdmin && <span style={{ color: '#38a169' }}> (Admin)</span>}
                          {isSelected && <span style={{ color: '#ff6b6b' }}> (Tracking)</span>}
                        </h3>
                        <div style={{ marginBottom: '8px' }}>
                          <strong>Phone:</strong> {phoneNumber}
                        </div>
                        {addresses[phoneNumber] && (
                          <div style={{ marginBottom: '8px', padding: '8px', backgroundColor: '#f8f9fa', borderRadius: '4px', border: '1px solid #e9ecef' }}>
                            <div style={{ display: 'flex', alignItems: 'flex-start', gap: '8px' }}>
                              <FaMapPin style={{ color: '#28a745', marginTop: '2px', fontSize: '0.9rem' }} />
                              <div>
                                <strong style={{ fontSize: '0.85rem', color: '#495057' }}>Location:</strong>
                                <div style={{ fontSize: '0.85rem', color: '#6c757d', lineHeight: '1.3', marginTop: '2px' }}>
                                  {addresses[phoneNumber]}
                                </div>
                              </div>
                            </div>
                          </div>
                        )}
                        {loadingAddresses[phoneNumber] && (
                          <div style={{ marginBottom: '8px', padding: '8px', backgroundColor: '#f8f9fa', borderRadius: '4px', border: '1px solid #e9ecef' }}>
                            <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                              <FaMapPin style={{ color: '#6c757d', fontSize: '0.9rem' }} />
                              <span style={{ fontSize: '0.85rem', color: '#6c757d', fontStyle: 'italic' }}>
                                Loading address...
                              </span>
                            </div>
                          </div>
                        )}
                        <div style={{ marginBottom: '8px', display: 'flex', alignItems: 'center' }}>
                          <strong style={{ marginRight: '8px' }}>Battery:</strong>
                          {getBatteryIcon(location.batteryPercentage)}
                          <span style={{ marginLeft: '5px' }}>{location.batteryPercentage}%</span>
                        </div>
                        <div style={{ marginBottom: '8px' }}>
                          <strong>GPS:</strong> 
                          <span style={{ 
                            color: location.gpsStatus?.includes('Enabled') ? '#38a169' : '#f56565',
                            marginLeft: '5px'
                          }}>
                            {location.gpsStatus}
                          </span>
                        </div>
                        <div style={{ display: 'flex', alignItems: 'center', fontSize: '0.85em', color: '#666', marginBottom: '10px' }}>
                          <FaClock style={{ marginRight: '5px' }} />
                          {location.date}
                        </div>
                        {!isSelected && (
                          <button 
                            onClick={(e) => {
                              e.stopPropagation();
                              onMemberSelect && onMemberSelect(phoneNumber);
                            }}
                            style={{
                              background: '#667eea',
                              color: 'white',
                              border: 'none',
                              padding: '0.5rem 1rem',
                              borderRadius: '4px',
                              cursor: 'pointer',
                              fontSize: '0.85rem'
                            }}
                          >
                            <FaEye style={{ marginRight: '0.5rem' }} />
                            Track Member
                          </button>
                        )}
                      </div>
                    </Popup>
                  </Marker>
                );
              })}
              
              {/* Movement Path for Selected Member */}
              {selectedMember && showPath && locationHistory[selectedMember] && locationHistory[selectedMember].length > 1 && (
                <Polyline
                  positions={locationHistory[selectedMember].map(point => [point.lat, point.lng])}
                  pathOptions={{
                    color: '#ff6b6b',
                    weight: 4,
                    opacity: 0.8,
                    dashArray: '10, 10'
                  }}
                />
              )}
              
              {/* Start and End markers for path */}
              {selectedMember && showPath && locationHistory[selectedMember] && locationHistory[selectedMember].length > 1 && (
                <>
                  {/* Start marker */}
                  <Marker
                    position={[
                      locationHistory[selectedMember][0].lat,
                      locationHistory[selectedMember][0].lng
                    ]}
                    icon={L.divIcon({
                      className: 'path-marker start-marker',
                      html: `
                        <div style="
                          background-color: #38a169; 
                          width: 16px; 
                          height: 16px; 
                          border-radius: 50%; 
                          border: 3px solid white; 
                          box-shadow: 0 2px 8px rgba(0,0,0,0.3);
                        "></div>
                      `,
                      iconSize: [22, 22],
                      iconAnchor: [11, 11]
                    })}
                  >
                    <Popup>
                      <div>
                        <strong>Journey Start</strong><br/>
                        {locationHistory[selectedMember][0].date}
                      </div>
                    </Popup>
                  </Marker>
                  
                  {/* End marker (current position) */}
                  <Marker
                    position={[
                      locationHistory[selectedMember][locationHistory[selectedMember].length - 1].lat,
                      locationHistory[selectedMember][locationHistory[selectedMember].length - 1].lng
                    ]}
                    icon={L.divIcon({
                      className: 'path-marker end-marker',
                      html: `
                        <div style="
                          background-color: #f56565; 
                          width: 20px; 
                          height: 20px; 
                          border-radius: 50%; 
                          border: 4px solid white; 
                          box-shadow: 0 2px 8px rgba(0,0,0,0.3);
                          animation: pulse-end 2s infinite;
                        "></div>
                        <style>
                          @keyframes pulse-end {
                            0% { box-shadow: 0 0 0 0 #f5656566; }
                            70% { box-shadow: 0 0 0 10px #f5656500; }
                            100% { box-shadow: 0 0 0 0 #f5656500; }
                          }
                        </style>
                      `,
                      iconSize: [28, 28],
                      iconAnchor: [14, 14]
                    })}
                  >
                    <Popup>
                      <div>
                        <strong>Current Position</strong><br/>
                        {locationHistory[selectedMember][locationHistory[selectedMember].length - 1].date}
                      </div>
                    </Popup>
                  </Marker>
                </>
              )}
            </MapContainer>
          </div>
        )}
      </div>
    </div>
  );
};

export default LocationMap;
