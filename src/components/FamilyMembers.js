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

  return (
    <div className="card">
      <div className="card-header">
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <div>
            <FaUsers className="mr-2" />
            Family Members ({filteredMembers.length})
          </div>
          {familyNames.length > 1 && (
            <select 
              value={selectedFamily || ''} 
              onChange={(e) => onFamilyChange(e.target.value || null)}
              className="form-select"
              style={{ width: 'auto', minWidth: '200px' }}
            >
              <option value="">All Families</option>
              {familyNames.map(family => (
                <option key={family} value={family}>{family}</option>
              ))}
            </select>
          )}
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
