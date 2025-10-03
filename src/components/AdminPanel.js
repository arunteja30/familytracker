import React, { useState, useEffect } from 'react';
import { database } from '../firebase';
import { ref, onValue, set, push, remove } from 'firebase/database';
import { 
  FaUserShield, 
  FaPlus, 
  FaTrash, 
  FaEdit, 
  FaUsers,
  FaPhoneAlt,
  FaUserTag,
  FaSave,
  FaTimes
} from 'react-icons/fa';

const AdminPanel = () => {
  const [familyMembers, setFamilyMembers] = useState({});
  const [familyList, setFamilyList] = useState({});
  const [registrations, setRegistrations] = useState({});
  const [loading, setLoading] = useState(true);
  const [showAddMember, setShowAddMember] = useState(false);
  const [editingMember, setEditingMember] = useState(null);
  const [newMember, setNewMember] = useState({
    name: '',
    mobile: '',
    familyName: '',
    relationship: ''
  });
  const [newFamily, setNewFamily] = useState('');
  const [showAddFamily, setShowAddFamily] = useState(false);
  const [message, setMessage] = useState({ type: '', text: '' });

  useEffect(() => {
    const membersRef = ref(database, 'familyMembersList');
    const familiesRef = ref(database, 'familyList');
    const registrationsRef = ref(database, 'registrations');

    const unsubscribeMembers = onValue(membersRef, (snapshot) => {
      const data = snapshot.val();
      setFamilyMembers(data || {});
    });

    const unsubscribeFamilies = onValue(familiesRef, (snapshot) => {
      const data = snapshot.val();
      setFamilyList(data || {});
    });

    const unsubscribeRegistrations = onValue(registrationsRef, (snapshot) => {
      const data = snapshot.val();
      setRegistrations(data || {});
      setLoading(false);
    });

    return () => {
      unsubscribeMembers();
      unsubscribeFamilies();
      unsubscribeRegistrations();
    };
  }, []);

  const showMessage = (type, text) => {
    setMessage({ type, text });
    setTimeout(() => setMessage({ type: '', text: '' }), 5000);
  };

  const generateMemberId = (mobile, familyName) => {
    return `${mobile}_${familyName}`;
  };

  const addFamily = async () => {
    if (!newFamily.trim()) {
      showMessage('error', 'Family name is required');
      return;
    }

    const familyId = `${newFamily}_${Date.now()}`;
    
    try {
      await set(ref(database, `familyList/${familyId}`), familyId);
      setNewFamily('');
      setShowAddFamily(false);
      showMessage('success', 'Family created successfully');
    } catch (error) {
      showMessage('error', 'Failed to create family: ' + error.message);
    }
  };

  const addMember = async () => {
    const { name, mobile, familyName, relationship } = newMember;
    
    if (!name.trim() || !mobile.trim() || !familyName) {
      showMessage('error', 'Name, mobile number, and family are required');
      return;
    }

    // Validate phone number format
    if (!mobile.match(/^\+\d{10,15}$/)) {
      showMessage('error', 'Mobile number must start with + and contain 10-15 digits');
      return;
    }

    const memberId = generateMemberId(mobile, familyName);
    
    // Check if member already exists in this family
    if (familyMembers[memberId]) {
      showMessage('error', 'Member already exists in this family');
      return;
    }

    const memberData = {
      memberId,
      name: name.trim(),
      mobile,
      familyName,
      relationship: relationship || '',
      registered: !!registrations[mobile],
      gpsInfo: 'GPS status unknown'
    };

    // If user is already registered, add their UID
    if (registrations[mobile]) {
      memberData.uid = registrations[mobile].uid;
    }

    try {
      await set(ref(database, `familyMembersList/${memberId}`), memberData);
      setNewMember({ name: '', mobile: '', familyName: '', relationship: '' });
      setShowAddMember(false);
      showMessage('success', 'Member added successfully');
    } catch (error) {
      showMessage('error', 'Failed to add member: ' + error.message);
    }
  };

  const updateMember = async (memberId, updatedData) => {
    try {
      const currentMember = familyMembers[memberId];
      const memberData = { ...currentMember, ...updatedData };
      
      await set(ref(database, `familyMembersList/${memberId}`), memberData);
      setEditingMember(null);
      showMessage('success', 'Member updated successfully');
    } catch (error) {
      showMessage('error', 'Failed to update member: ' + error.message);
    }
  };

  const deleteMember = async (memberId) => {
    if (!window.confirm('Are you sure you want to remove this member?')) {
      return;
    }

    try {
      await remove(ref(database, `familyMembersList/${memberId}`));
      showMessage('success', 'Member removed successfully');
    } catch (error) {
      showMessage('error', 'Failed to remove member: ' + error.message);
    }
  };

  const deleteFamily = async (familyName) => {
    if (!window.confirm(`Are you sure you want to delete the family "${familyName}" and all its members?`)) {
      return;
    }

    try {
      // Remove all family members
      const membersToDelete = Object.entries(familyMembers).filter(
        ([_, member]) => member.familyName === familyName
      );

      for (const [memberId] of membersToDelete) {
        await remove(ref(database, `familyMembersList/${memberId}`));
      }

      // Remove family from family list
      await remove(ref(database, `familyList/${familyName}`));
      
      showMessage('success', 'Family deleted successfully');
    } catch (error) {
      showMessage('error', 'Failed to delete family: ' + error.message);
    }
  };

  if (loading) {
    return (
      <div className="card">
        <div className="card-header">Admin Panel</div>
        <div className="card-content">
          <div className="loading">Loading admin panel...</div>
        </div>
      </div>
    );
  }

  const familyNames = Object.keys(familyList);

  return (
    <div className="card">
      <div className="card-header">
        <FaUserShield className="mr-2" />
        Admin Panel
      </div>
      <div className="card-content">
        {message.text && (
          <div className={message.type === 'error' ? 'error' : 'success'}>
            {message.text}
          </div>
        )}

        {/* Family Management */}
        <div style={{ marginBottom: '2rem' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1rem' }}>
            <h3>Family Management</h3>
            <button 
              className="btn btn-small"
              onClick={() => setShowAddFamily(!showAddFamily)}
            >
              <FaPlus className="mr-1" />
              Add Family
            </button>
          </div>

          {showAddFamily && (
            <div style={{ background: '#f8f9ff', padding: '1rem', borderRadius: '6px', marginBottom: '1rem' }}>
              <div className="form-group">
                <label className="form-label">Family Name</label>
                <input
                  type="text"
                  className="form-input"
                  value={newFamily}
                  onChange={(e) => setNewFamily(e.target.value)}
                  placeholder="Enter family name"
                />
              </div>
              <div style={{ display: 'flex', gap: '10px' }}>
                <button className="btn btn-small" onClick={addFamily}>
                  <FaSave className="mr-1" />
                  Save Family
                </button>
                <button 
                  className="btn btn-small btn-danger" 
                  onClick={() => setShowAddFamily(false)}
                >
                  <FaTimes className="mr-1" />
                  Cancel
                </button>
              </div>
            </div>
          )}

          <div className="grid grid-2">
            {familyNames.map(familyName => {
              const memberCount = Object.values(familyMembers).filter(
                member => member.familyName === familyName
              ).length;

              return (
                <div key={familyName} className="card" style={{ margin: 0 }}>
                  <div style={{ padding: '1rem', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                    <div>
                      <h4 style={{ margin: 0 }}>{familyName}</h4>
                      <p style={{ margin: '0.5rem 0 0 0', color: '#666' }}>
                        {memberCount} member{memberCount !== 1 ? 's' : ''}
                      </p>
                    </div>
                    <button 
                      className="btn btn-small btn-danger"
                      onClick={() => deleteFamily(familyName)}
                    >
                      <FaTrash />
                    </button>
                  </div>
                </div>
              );
            })}
          </div>
        </div>

        {/* Member Management */}
        <div>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1rem' }}>
            <h3>Member Management</h3>
            <button 
              className="btn btn-small"
              onClick={() => setShowAddMember(!showAddMember)}
            >
              <FaPlus className="mr-1" />
              Add Member
            </button>
          </div>

          {showAddMember && (
            <div style={{ background: '#f8f9ff', padding: '1rem', borderRadius: '6px', marginBottom: '1rem' }}>
              <div className="grid grid-2">
                <div className="form-group">
                  <label className="form-label">Name</label>
                  <input
                    type="text"
                    className="form-input"
                    value={newMember.name}
                    onChange={(e) => setNewMember({ ...newMember, name: e.target.value })}
                    placeholder="Enter member name"
                  />
                </div>
                <div className="form-group">
                  <label className="form-label">Mobile Number</label>
                  <input
                    type="text"
                    className="form-input"
                    value={newMember.mobile}
                    onChange={(e) => setNewMember({ ...newMember, mobile: e.target.value })}
                    placeholder="+919999999999"
                  />
                </div>
                <div className="form-group">
                  <label className="form-label">Family</label>
                  <select
                    className="form-select"
                    value={newMember.familyName}
                    onChange={(e) => setNewMember({ ...newMember, familyName: e.target.value })}
                  >
                    <option value="">Select Family</option>
                    {familyNames.map(family => (
                      <option key={family} value={family}>{family}</option>
                    ))}
                  </select>
                </div>
                <div className="form-group">
                  <label className="form-label">Relationship</label>
                  <select
                    className="form-select"
                    value={newMember.relationship}
                    onChange={(e) => setNewMember({ ...newMember, relationship: e.target.value })}
                  >
                    <option value="">Select Relationship</option>
                    <option value="admin">Admin</option>
                    <option value="parent">Parent</option>
                    <option value="child">Child</option>
                    <option value="sibling">Sibling</option>
                    <option value="spouse">Spouse</option>
                    <option value="friend">Friend</option>
                    <option value="other">Other</option>
                  </select>
                </div>
              </div>
              <div style={{ display: 'flex', gap: '10px', marginTop: '1rem' }}>
                <button className="btn btn-small" onClick={addMember}>
                  <FaSave className="mr-1" />
                  Save Member
                </button>
                <button 
                  className="btn btn-small btn-danger" 
                  onClick={() => setShowAddMember(false)}
                >
                  <FaTimes className="mr-1" />
                  Cancel
                </button>
              </div>
            </div>
          )}

          <div className="member-list">
            {Object.entries(familyMembers).map(([memberId, member]) => (
              <div key={memberId} className={`member-card ${member.relationship === 'admin' ? 'admin' : ''}`}>
                {editingMember === memberId ? (
                  <EditMemberForm
                    member={member}
                    familyNames={familyNames}
                    onSave={(updatedData) => updateMember(memberId, updatedData)}
                    onCancel={() => setEditingMember(null)}
                  />
                ) : (
                  <>
                    <div className="member-name">
                      {member.name}
                      {member.relationship === 'admin' && (
                        <span className="status-badge status-admin ml-2">
                          <FaUserShield className="mr-1" />
                          Admin
                        </span>
                      )}
                      {!member.registered && (
                        <span className="status-badge status-offline ml-2">
                          Not Registered
                        </span>
                      )}
                    </div>
                    
                    <div className="member-info">
                      <FaPhoneAlt />
                      {member.mobile}
                    </div>
                    
                    <div className="member-info">
                      <FaUsers />
                      {member.familyName}
                    </div>
                    
                    {member.relationship && (
                      <div className="member-info">
                        <FaUserTag />
                        {member.relationship}
                      </div>
                    )}
                    
                    <div style={{ marginTop: '1rem', display: 'flex', gap: '10px' }}>
                      <button 
                        className="btn btn-small"
                        onClick={() => setEditingMember(memberId)}
                      >
                        <FaEdit className="mr-1" />
                        Edit
                      </button>
                      <button 
                        className="btn btn-small btn-danger"
                        onClick={() => deleteMember(memberId)}
                      >
                        <FaTrash className="mr-1" />
                        Remove
                      </button>
                    </div>
                  </>
                )}
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
};

const EditMemberForm = ({ member, familyNames, onSave, onCancel }) => {
  const [editData, setEditData] = useState({
    name: member.name,
    relationship: member.relationship || ''
  });

  const handleSave = () => {
    onSave(editData);
  };

  return (
    <div>
      <div className="form-group">
        <label className="form-label">Name</label>
        <input
          type="text"
          className="form-input"
          value={editData.name}
          onChange={(e) => setEditData({ ...editData, name: e.target.value })}
        />
      </div>
      
      <div className="form-group">
        <label className="form-label">Relationship</label>
        <select
          className="form-select"
          value={editData.relationship}
          onChange={(e) => setEditData({ ...editData, relationship: e.target.value })}
        >
          <option value="">Select Relationship</option>
          <option value="admin">Admin</option>
          <option value="parent">Parent</option>
          <option value="child">Child</option>
          <option value="sibling">Sibling</option>
          <option value="spouse">Spouse</option>
          <option value="friend">Friend</option>
          <option value="other">Other</option>
        </select>
      </div>
      
      <div style={{ display: 'flex', gap: '10px', marginTop: '1rem' }}>
        <button className="btn btn-small" onClick={handleSave}>
          <FaSave className="mr-1" />
          Save
        </button>
        <button className="btn btn-small btn-danger" onClick={onCancel}>
          <FaTimes className="mr-1" />
          Cancel
        </button>
      </div>
    </div>
  );
};

export default AdminPanel;
