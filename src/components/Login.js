import React, { useState, useEffect } from 'react';
import { database } from '../firebase';
import { ref, onValue, set } from 'firebase/database';
import { FaPhoneAlt, FaSignInAlt, FaSpinner, FaUserShield, FaUsers, FaLock, FaEye, FaEyeSlash } from 'react-icons/fa';

const Login = ({ onLogin }) => {
  const [phoneNumber, setPhoneNumber] = useState('');
  const [password, setPassword] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState('');
  const [familyMembers, setFamilyMembers] = useState({});
  const [isDataLoaded, setIsDataLoaded] = useState(false);
  const [loginStep, setLoginStep] = useState('phone'); // 'phone', 'password', 'create-password'
  const [userEntry, setUserEntry] = useState(null);
  const [showPassword, setShowPassword] = useState(false);
  const [savedCredentials, setSavedCredentials] = useState(null);

  // Check for saved credentials on component mount
  useEffect(() => {
    const savedCreds = localStorage.getItem('familyTracker_credentials');
    if (savedCreds) {
      try {
        const credentials = JSON.parse(savedCreds);
        setSavedCredentials(credentials);
        setPhoneNumber(credentials.phoneNumber || '');
        // If user has saved credentials with password, go straight to password input
        if (credentials.hasPassword) {
          setLoginStep('password');
        }
      } catch (error) {
        console.error('Error parsing saved credentials:', error);
        localStorage.removeItem('familyTracker_credentials');
      }
    }
  }, []);

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

    if (loginStep === 'password' && !password.trim()) {
      setError('Please enter your password');
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
      const foundUserEntry = Object.values(familyMembers).find(member => 
        member.mobile === formattedPhone || member.mobile === phoneNumber.trim()
      );

      if (foundUserEntry) {
        // Check login step
        if (loginStep === 'phone') {
          // First time login or phone verification
          setUserEntry(foundUserEntry);
          
          // Check if user already has a password
          if (foundUserEntry.password) {
            setLoginStep('password');
            // Clear any existing password input to force user to re-enter
            setPassword('');
          } else {
            setLoginStep('create-password');
          }
          setIsLoading(false);
          return;
        } else if (loginStep === 'password') {
          // Verify password
          if (foundUserEntry.password !== password) {
            setError('Incorrect password. Please try again.');
            setIsLoading(false);
            return;
          }
        } else if (loginStep === 'create-password') {
          // Create new password
          if (!password.trim() || password.length < 4) {
            setError('Password must be at least 4 characters long');
            setIsLoading(false);
            return;
          }

          // Save password to Firebase
          const userRef = ref(database, `familyMembersList/${foundUserEntry.memberId}`);
          await set(userRef, {
            ...foundUserEntry,
            password: password,
            lastPasswordUpdate: Date.now()
          });

          // Update local user entry
          foundUserEntry.password = password;
        }

        // Determine user role
        let role = 'member';
        if (foundUserEntry.relationship && foundUserEntry.relationship.toLowerCase().includes('admin')) {
          role = 'admin';
        } else if (foundUserEntry.isAdmin === true) {
          role = 'admin';
        } else if (foundUserEntry.name && foundUserEntry.name.toLowerCase().includes('admin')) {
          role = 'admin';
        } else {
          const familyMembersList = Object.values(familyMembers).filter(m => 
            m.familyName === foundUserEntry.familyName
          );
          if (familyMembersList.length > 0 && familyMembersList[0].mobile === foundUserEntry.mobile) {
            role = 'admin';
          }
        }

        const userData = {
          ...foundUserEntry,
          role,
          phoneNumber: formattedPhone
        };

        // Save credentials locally
        const credentials = {
          phoneNumber: formattedPhone,
          hasPassword: true
        };
        localStorage.setItem('familyTracker_credentials', JSON.stringify(credentials));

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

  const handlePasswordChange = (e) => {
    setPassword(e.target.value);
    if (error) setError(''); // Clear error when user starts typing
  };

  const handleBackToPhone = () => {
    setLoginStep('phone');
    setPassword('');
    setUserEntry(null);
    setError('');
  };

  const togglePasswordVisibility = () => {
    setShowPassword(!showPassword);
  };

  const clearSavedCredentials = () => {
    localStorage.removeItem('familyTracker_credentials');
    setSavedCredentials(null);
    setPhoneNumber('');
    setLoginStep('phone');
    setError('');
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
          <div className="login-logo">
            <img 
              src="/logo512.png" 
              alt="Family Tracker Logo" 
              loading="eager"
              onError={(e) => {
                // Fallback if logo fails to load
                e.target.style.display = 'none';
                e.target.parentNode.innerHTML = '<div style="width:100%;height:100%;display:flex;align-items:center;justify-content:center;background:#667eea;border-radius:12px;color:white;font-size:2rem;"><i class="fa fa-map-marker-alt"></i></div>';
              }}
            />
          </div>
          <h1>Family Tracker</h1>
          <p>Sign in with your registered phone number</p>
        </div>

        <form onSubmit={handleLogin} className="login-form">
          {/* Phone Number Input */}
          <div className="form-group">
            <label className="form-label">
              <FaPhoneAlt className="mr-1" />
              Phone Number
            </label>
            <div style={{ display: 'flex', gap: '0.5rem', alignItems: 'flex-end' }}>
              <div style={{ flex: 1 }}>
                <input
                  type="tel"
                  className={`form-input ${error ? 'error' : ''}`}
                  placeholder="+91 9999999999"
                  value={phoneNumber}
                  onChange={handlePhoneChange}
                  disabled={isLoading || loginStep !== 'phone'}
                  autoComplete="tel"
                  maxLength={15}
                  autoFocus={loginStep === 'phone'}
                  inputMode="tel"
                  pattern="[+]*[0-9\s]*"
                  aria-describedby="phone-hint"
                  required
                />
                {loginStep === 'phone' && (
                  <small className="form-hint" id="phone-hint">
                    Enter your registered mobile number (with or without country code)
                  </small>
                )}
              </div>
              {savedCredentials && loginStep === 'password' && (
                <button
                  type="button"
                  className="btn btn-small"
                  onClick={clearSavedCredentials}
                  style={{ marginLeft: '0.5rem', padding: '8px 12px' }}
                  title="Use different phone number"
                >
                  Change
                </button>
              )}
            </div>
          </div>

          {/* Password Input */}
          {(loginStep === 'password' || loginStep === 'create-password') && (
            <div className="form-group">
              <label className="form-label">
                <FaLock className="mr-1" />
                {loginStep === 'create-password' ? 'Create Password' : 'Password'}
              </label>
              <div className="password-input-container">
                <input
                  type={showPassword ? 'text' : 'password'}
                  className={`form-input ${error ? 'error' : ''}`}
                  placeholder={loginStep === 'create-password' ? 'Create a new password' : 'Enter your password'}
                  value={password}
                  onChange={handlePasswordChange}
                  disabled={isLoading}
                  autoComplete={loginStep === 'create-password' ? 'new-password' : 'current-password'}
                  minLength={4}
                  autoFocus={loginStep !== 'phone'}
                  required
                />
                <button
                  type="button"
                  className="password-toggle"
                  onClick={togglePasswordVisibility}
                  aria-label={showPassword ? 'Hide password' : 'Show password'}
                >
                  {showPassword ? <FaEyeSlash /> : <FaEye />}
                </button>
              </div>
              <small className="form-hint">
                {loginStep === 'create-password' 
                  ? 'Create a password (minimum 4 characters) for future logins'
                  : 'Enter the password you created for your account'
                }
              </small>
            </div>
          )}

          {/* Back Button */}
          {loginStep !== 'phone' && (
            <div style={{ marginBottom: '1rem' }}>
              <button
                type="button"
                className="btn btn-secondary"
                onClick={handleBackToPhone}
                disabled={isLoading}
                style={{ width: '100%', marginBottom: '1rem' }}
              >
                ← Back to Phone Number
              </button>
            </div>
          )}

          {error && (
            <div className="error-message">
              {error}
            </div>
          )}

          <button 
            type="submit" 
            className="login-btn"
            disabled={isLoading || !phoneNumber.trim() || ((loginStep === 'password' || loginStep === 'create-password') && !password.trim())}
          >
            {isLoading ? (
              <>
                <FaSpinner className="spinner mr-2" />
                {loginStep === 'phone' ? 'Verifying...' : 
                 loginStep === 'create-password' ? 'Creating Account...' : 'Signing in...'}
              </>
            ) : (
              <>
                <FaSignInAlt className="mr-2" />
                {loginStep === 'phone' ? 'Continue' : 
                 loginStep === 'create-password' ? 'Create Password & Sign In' : 'Sign In'}
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
          {loginStep === 'create-password' && (
            <div className="info-section" style={{ color: '#667eea' }}>
              <FaLock className="mr-2" />
              <span>First time setup - create your password</span>
            </div>
          )}
        </div>

        <div className="login-footer">
          <p>
            {loginStep === 'create-password' 
              ? "You'll create a password for future logins. This password will be saved securely."
              : loginStep === 'password'
              ? "Enter the password you created during your first login."
              : "Don't have access? Contact your family administrator to add your phone number to the system."
            }
          </p>
        </div>
      </div>
    </div>
  );
};

export default Login;
