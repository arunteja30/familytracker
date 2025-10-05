import React, { useState, useEffect } from 'react';
import { database } from '../firebase';
import { ref, onValue } from 'firebase/database';
import { FaPhoneAlt, FaSignInAlt, FaSpinner, FaUserShield, FaUsers } from 'react-icons/fa';

const Login = ({ onLogin }) => {
  const [phoneNumber, setPhoneNumber] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState('');
  const [familyMembers, setFamilyMembers] = useState({});
  const [isDataLoaded, setIsDataLoaded] = useState(false);

  // Load family members data
  useEffect(() => {
    const membersRef = ref(database, 'familyMembersList');
    const unsubscribe = onValue(membersRef, (snapshot) => {
      const data = snapshot.val();
      setFamilyMembers(data || {});
      setIsDataLoaded(true);
    }, (error) => {
      console.error('Error loading family members:', error);
      setError('Failed to load user data. Please try again.');
      setIsDataLoaded(true);
    });

    return () => unsubscribe();
  }, []);

  const handleLogin = async (e) => {
    e.preventDefault();
    
    if (!phoneNumber.trim()) {
      setError('Please enter your phone number');
      return;
    }

    if (!isDataLoaded) {
      setError('Loading user data. Please wait...');
      return;
    }

    setIsLoading(true);
    setError('');

    try {
      // Format phone number (ensure it starts with +)
      let formattedPhone = phoneNumber.trim();
      if (!formattedPhone.startsWith('+')) {
        // Assume Indian number if no country code
        if (formattedPhone.startsWith('91')) {
          formattedPhone = '+' + formattedPhone;
        } else if (formattedPhone.length === 10) {
          formattedPhone = '+91' + formattedPhone;
        } else {
          formattedPhone = '+' + formattedPhone;
        }
      }

      // Find user in familyMembersList
      const userEntry = Object.values(familyMembers).find(member => 
        member.mobile === formattedPhone || member.mobile === phoneNumber.trim()
      );

      if (userEntry) {
        // Determine user role based on member data
        // You can customize this logic based on your needs
        let role = 'member'; // default role
        
        // Check if user is admin based on specific criteria
        // For now, let's check if they have admin privileges based on their relationship or a specific flag
        if (userEntry.relationship && userEntry.relationship.toLowerCase().includes('admin')) {
          role = 'admin';
        } else if (userEntry.isAdmin === true) {
          role = 'admin';
        } else if (userEntry.name && userEntry.name.toLowerCase().includes('admin')) {
          role = 'admin';
        }
        // You could also make the first member of each family an admin
        else {
          const familyMembersList = Object.values(familyMembers).filter(m => 
            m.familyName === userEntry.familyName
          );
          if (familyMembersList.length > 0 && familyMembersList[0].mobile === userEntry.mobile) {
            role = 'admin';
          }
        }

        const userData = {
          ...userEntry,
          role,
          phoneNumber: formattedPhone
        };

        // Call the login callback with user data
        onLogin(userData);
      } else {
        setError('Phone number not found. Please contact your family administrator to add you to the system.');
      }
    } catch (error) {
      console.error('Login error:', error);
      setError('Login failed. Please try again.');
    } finally {
      setIsLoading(false);
    }
  };

  const handlePhoneChange = (e) => {
    const value = e.target.value;
    // Allow only numbers, +, and spaces
    const cleanValue = value.replace(/[^+\d\s]/g, '');
    setPhoneNumber(cleanValue);
    if (error) setError(''); // Clear error when user starts typing
  };

  if (!isDataLoaded) {
    return (
      <div className="login-container">
        <div className="login-card">
          <div className="text-center">
            <FaSpinner className="spinner" size={32} />
            <h2>Loading...</h2>
            <p>Please wait while we load the system...</p>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="login-container">
      <div className="login-card">
        <div className="login-header">
          <div className="login-icon">
            <FaPhoneAlt />
          </div>
          <h1>Family Tracker</h1>
          <p>Sign in with your registered phone number</p>
        </div>

        <form onSubmit={handleLogin} className="login-form">
          <div className="form-group">
            <label className="form-label">
              <FaPhoneAlt className="mr-1" />
              Phone Number
            </label>
            <input
              type="tel"
              className={`form-input ${error ? 'error' : ''}`}
              placeholder="+91 9999999999"
              value={phoneNumber}
              onChange={handlePhoneChange}
              disabled={isLoading}
              autoComplete="tel"
              maxLength={15}
            />
            <small className="form-hint">
              Enter your registered mobile number (with or without country code)
            </small>
          </div>

          {error && (
            <div className="error-message">
              {error}
            </div>
          )}

          <button 
            type="submit" 
            className="login-btn"
            disabled={isLoading || !phoneNumber.trim()}
          >
            {isLoading ? (
              <>
                <FaSpinner className="spinner mr-2" />
                Signing in...
              </>
            ) : (
              <>
                <FaSignInAlt className="mr-2" />
                Sign In
              </>
            )}
          </button>
        </form>

        <div className="login-info">
          <div className="info-section">
            <FaUsers className="mr-2" />
            <span>For family members</span>
          </div>
          <div className="info-section">
            <FaUserShield className="mr-2" />
            <span>Admin access available</span>
          </div>
        </div>

        <div className="login-footer">
          <p>
            Don't have access? Contact your family administrator to add your phone number to the system.
          </p>
        </div>
      </div>
    </div>
  );
};

export default Login;
