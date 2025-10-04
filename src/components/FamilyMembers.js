import React, { useState, useEffect } from 'react';
import { database } from '../firebase';
import { ref, onValue } from 'firebase/database';
import { 
  FaUsers, 
  FaBatteryFull, 
  FaBatteryHalf, 
  FaBatteryEmpty, 
  FaMapMarkerAlt, 
  FaClock,
  FaPhoneAlt,
  FaUserShield,
  FaSignal,
  FaTimesCircle
} from 'react-icons/fa';

const FamilyMembers = ({ selectedFamily, selectedMember, onFamilyChange, onMemberSelect }) => {
  const [familyMembers, setFamilyMembers] = useState({});
  const [familyList, setFamilyList] = useState({});
  const [locations, setLocations] = useState({});
  const [loading, setLoading] = useState(true);
  const [viewMode, setViewMode] = useState('families'); // 'families' or 'members'

  useEffect(() => {
    const membersRef = ref(database, 'familyMembersList');
    const familiesRef = ref(database, 'familyList');
    const locationsRef = ref(database, 'locationList');

    const unsubscribeMembers = onValue(membersRef, (snapshot) => {
      const data = snapshot.val();
      setFamilyMembers(data || {});
    });

    const unsubscribeFamilies = onValue(familiesRef, (snapshot) => {
      const data = snapshot.val();
      setFamilyList(data || {});
    });

    const unsubscribeLocations = onValue(locationsRef, (snapshot) => {
      const data = snapshot.val();
      setLocations(data || {});
      setLoading(false);
    });

    return () => {
      unsubscribeMembers();
      unsubscribeFamilies();
      unsubscribeLocations();
    };
  }, []);

  const getFilteredMembers = () => {
    if (!selectedFamily) return Object.entries(familyMembers);
    
    return Object.entries(familyMembers).filter(([_, member]) => 
      member.familyName === selectedFamily
    );
  };

  const getFamilyMemberCount = (familyName) => {
    return Object.values(familyMembers).filter(member => member.familyName === familyName).length;
  };

  const getFamilyOnlineCount = (familyName) => {
    const members = Object.values(familyMembers).filter(member => member.familyName === familyName);
    return members.filter(member => isOnline(member)).length;
  };

  const handleFamilyClick = (familyName) => {
    onFamilyChange(familyName);
    setViewMode('members');
  };

  const handleBackToFamilies = () => {
    onFamilyChange(null);
    setViewMode('families');
  };

  const getMemberLocation = (phoneNumber) => {
    return locations[phoneNumber] || null;
  };

  const getBatteryIcon = (percentage) => {
    if (!percentage) return <FaBatteryEmpty style={{ color: '#ccc' }} />;
    if (percentage > 60) return <FaBatteryFull style={{ color: '#38a169' }} />;
    if (percentage > 30) return <FaBatteryHalf style={{ color: '#ecc94b' }} />;
    return <FaBatteryEmpty style={{ color: '#f56565' }} />;
  };

  const isOnline = (member) => {
    const location = getMemberLocation(member.mobile);
    if (!location) return false;
    
    // Consider online if location was updated within last 24 hours
    const now = Date.now();
    const locationTime = location.timeStamp;
    const timeDiff = now - locationTime;
    return timeDiff < 24 * 60 * 60 * 1000; // 24 hours
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
        <div className="card-header">Family Members</div>
        <div className="card-content">
          <div className="loading">Loading members...</div>
        </div>
      </div>
    );
  }

  const filteredMembers = getFilteredMembers();
  const familyNames = Object.keys(familyList);

  // Show families list when no family is selected
  if (!selectedFamily || viewMode === 'families') {
    return (
      <div className="card">
        <div className="card-header">
          <FaUsers className="mr-2" />
          Family Management ({familyNames.length} families)
        </div>
        <div className="card-content">
          {familyNames.length === 0 ? (
            <div className="text-center" style={{ padding: '2rem', color: '#666' }}>
              No families found
            </div>
          ) : (
            <div className="member-list">
              {familyNames.map(familyName => {
                const memberCount = getFamilyMemberCount(familyName);
                const onlineCount = getFamilyOnlineCount(familyName);
                
                return (
                  <div 
                    key={familyName}
                    className="member-card family-card"
                    onClick={() => handleFamilyClick(familyName)}
                    style={{ 
                      cursor: 'pointer',
                      transition: 'transform 0.2s ease, box-shadow 0.2s ease',
                    }}
                  >
                    <div className="member-name" style={{ fontSize: '1.2rem', fontWeight: '600' }}>
                      <FaUsers style={{ marginRight: '0.5rem', color: '#667eea' }} />
                      {familyName}
                    </div>
                    
                    <div className="member-info">
                      <FaUsers />
                      {memberCount} member{memberCount !== 1 ? 's' : ''}
                    </div>
                    
                    <div className="member-info">
                      {onlineCount > 0 ? (
                        <FaSignal style={{ color: '#38a169' }} />
                      ) : (
                        <FaTimesCircle style={{ color: '#f56565' }} />
                      )}
                      <span className={`status-badge ${onlineCount > 0 ? 'status-online' : 'status-offline'}`}>
                        {onlineCount} online
                      </span>
                    </div>

                    <div style={{
                      marginTop: '1rem',
                      padding: '0.5rem',
                      backgroundColor: '#f8f9ff',
                      color: '#667eea',
                      borderRadius: '4px',
                      fontSize: '0.85rem',
                      textAlign: 'center',
                      fontWeight: '500'
                    }}>
                      Click to view family members →
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>
      </div>
    );
  }

  // Show members of selected family
  return (
    <div className="card">
      <div className="card-header">
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <div>
            <button 
              onClick={handleBackToFamilies}
              style={{
                background: 'none',
                border: 'none',
                color: '#667eea',
                cursor: 'pointer',
                fontSize: '0.9rem',
                marginRight: '1rem',
                padding: '0.5rem',
                borderRadius: '4px',
                transition: 'background-color 0.2s ease'
              }}
              onMouseOver={(e) => e.target.style.backgroundColor = '#f8f9ff'}
              onMouseOut={(e) => e.target.style.backgroundColor = 'transparent'}
            >
              ← Back to Families
            </button>
          </div>
        </div>
        <div style={{ marginTop: '0.5rem' }}>
          <FaUsers className="mr-2" />
          {selectedFamily} - {filteredMembers.length} member{filteredMembers.length !== 1 ? 's' : ''}
        </div>
      </div>
      <div className="card-content">
        {filteredMembers.length === 0 ? (
          <div className="text-center" style={{ padding: '2rem', color: '#666' }}>
            No family members found
          </div>
        ) : (
          <div className="member-list">
            {filteredMembers.map(([memberId, member]) => {
              const location = getMemberLocation(member.mobile);
              const online = isOnline(member);
              const isAdmin = member.relationship === 'admin';
              const isSelected = selectedMember === member.mobile;
              
              return (
                <div 
                  key={memberId} 
                  className={`member-card ${!online ? 'offline' : ''} ${isAdmin ? 'admin' : ''} ${isSelected ? 'selected' : ''}`}
                  onClick={() => onMemberSelect && onMemberSelect(member.mobile)}
                  style={{ 
                    cursor: 'pointer',
                    transform: isSelected ? 'scale(1.02)' : 'scale(1)',
                    transition: 'transform 0.2s ease, box-shadow 0.2s ease',
                    boxShadow: isSelected ? '0 4px 15px rgba(102, 126, 234, 0.3)' : '0 2px 5px rgba(0,0,0,0.1)'
                  }}
                >
                  <div className="member-name">
                    {member.name || 'Unnamed Member'}
                    {isAdmin && (
                      <span className="status-badge status-admin ml-2">
                        <FaUserShield className="mr-1" />
                        Admin
                      </span>
                    )}
                  </div>
                  
                  <div className="member-info">
                    <FaPhoneAlt />
                    {member.mobile}
                  </div>
                  
                  <div className="member-info">
                    {online ? (
                      <FaSignal style={{ color: '#38a169' }} />
                    ) : (
                      <FaTimesCircle style={{ color: '#f56565' }} />
                    )}
                    <span className={`status-badge ${online ? 'status-online' : 'status-offline'}`}>
                      {online ? 'Online' : 'Offline'}
                    </span>
                  </div>

                  {location && (
                    <>
                      <div className="member-info">
                        {getBatteryIcon(location.batteryPercentage)}
                        Battery: {location.batteryPercentage || 'N/A'}%
                      </div>
                      
                      <div className="member-info">
                        <FaMapMarkerAlt style={{ 
                          color: member.gpsInfo?.includes('enabled') || member.gpsInfo?.includes('Enabled') ? '#38a169' : '#f56565' 
                        }} />
                        {member.gpsInfo || location.gpsStatus || 'GPS Unknown'}
                      </div>
                      
                      <div className="member-info">
                        <FaClock />
                        Last seen: {getTimeAgo(location.timeStamp)}
                      </div>
                    </>
                  )}

                  {!location && (
                    <div className="member-info" style={{ color: '#666', fontStyle: 'italic' }}>
                      No location data available
                    </div>
                  )}

                  {!member.registered && (
                    <div className="member-info" style={{ color: '#f56565' }}>
                      ⚠️ Not registered
                    </div>
                  )}

                  {isSelected && (
                    <div style={{ 
                      marginTop: '1rem', 
                      padding: '0.5rem', 
                      backgroundColor: '#667eea', 
                      color: 'white', 
                      borderRadius: '4px', 
                      fontSize: '0.85rem',
                      textAlign: 'center'
                    }}>
                      📍 Click "Live Map" to see location
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

export default FamilyMembers;
