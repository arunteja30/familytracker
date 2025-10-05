import React, { useState, useEffect } from 'react';
import { BrowserRouter as Router, Routes, Route, Link, Navigate, useNavigate, useLocation } from 'react-router-dom';
import LocationMap from './components/LocationMap';
import FamilyMembers from './components/FamilyMembers';
import AdminPanel from './components/AdminPanel';
import LocationHistory from './components/LocationHistory';
import LocationHistoryDetailed from './components/LocationHistoryDetailed';
import PWAInstallPrompt from './components/PWAInstallPrompt';
import Login from './components/Login';

import { 
  FaMapMarkerAlt, 
  FaUsers, 
  FaUserShield, 
  FaHistory, 
  FaBars,
  FaTimes,
  FaWifi,
  FaCalendarAlt,
  FaSignOutAlt
} from 'react-icons/fa';

// Component wrapper to access useNavigate hook
function AppContent() {
  const [selectedFamily, setSelectedFamily] = useState(null);
  const [selectedMember, setSelectedMember] = useState(null);
  const [user, setUser] = useState(null);
  const [isLoggedIn, setIsLoggedIn] = useState(false);
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);
  const [isOnline, setIsOnline] = useState(navigator.onLine);
  const navigate = useNavigate();
  const location = useLocation();

  // Check for saved user session on app load
  useEffect(() => {
    const savedUser = localStorage.getItem('familyTracker_user');
    if (savedUser) {
      try {
        const userData = JSON.parse(savedUser);
        setUser(userData);
        setIsLoggedIn(true);
        // Set selected family based on user's family
        if (userData.familyName) {
          setSelectedFamily(userData.familyName);
        }
      } catch (error) {
        console.error('Error parsing saved user data:', error);
        localStorage.removeItem('familyTracker_user');
      }
    }
  }, []);

  useEffect(() => {
    const handleOnlineStatus = () => {
      setIsOnline(navigator.onLine);
    };

    window.addEventListener('online', handleOnlineStatus);
    window.addEventListener('offline', handleOnlineStatus);

    return () => {
      window.removeEventListener('online', handleOnlineStatus);
      window.removeEventListener('offline', handleOnlineStatus);
    };
  }, []);

  const handleFamilyChange = (family) => {
    setSelectedFamily(family);
    setSelectedMember(null);
  };

  const handleMemberSelect = (memberPhone, navigateToMap = true) => {
    setSelectedMember(memberPhone);
    // Navigate to map when member is selected
    if (memberPhone && navigateToMap) {
      navigate('/map');
    }
  };

  const toggleMobileMenu = () => {
    setMobileMenuOpen(!mobileMenuOpen);
  };

  const handleLogin = (userData) => {
    setUser(userData);
    setIsLoggedIn(true);
    localStorage.setItem('familyTracker_user', JSON.stringify(userData));
    
    // Set selected family based on user's family
    if (userData.familyName) {
      setSelectedFamily(userData.familyName);
    }
    
    // Navigate to appropriate default page based on role
    if (userData.role === 'admin') {
      navigate('/admin');
    } else {
      navigate('/map');
    }
  };

  const handleLogout = () => {
    setUser(null);
    setIsLoggedIn(false);
    setSelectedFamily(null);
    setSelectedMember(null);
    localStorage.removeItem('familyTracker_user');
    navigate('/');
  };

  // If not logged in, show login page
  if (!isLoggedIn) {
    return <Login onLogin={handleLogin} />;
  }

  // Get user role for navigation
  const isAdmin = user?.role === 'admin';

  return (
      <div className="App">
        {/* Header */}
        <header className="header">
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <div>
              <h1>Family Tracker</h1>
              <div style={{ fontSize: '0.85rem', opacity: 0.9, marginTop: '2px' }}>
                Welcome, {user?.name || 'User'} ({user?.role === 'admin' ? 'Admin' : 'Member'})
              </div>
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: '1rem' }}>
              {/* Online Status */}
              <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                <FaWifi style={{ color: isOnline ? '#38a169' : '#f56565' }} />
                <span style={{ fontSize: '0.85rem' }}>
                  {isOnline ? 'Online' : 'Offline'}
                </span>
              </div>

              {/* Logout Button */}
              <button
                onClick={handleLogout}
                style={{
                  background: 'rgba(255,255,255,0.2)',
                  border: '1px solid rgba(255,255,255,0.3)',
                  color: 'white',
                  padding: '6px 12px',
                  borderRadius: '6px',
                  cursor: 'pointer',
                  fontSize: '0.85rem',
                  display: 'flex',
                  alignItems: 'center',
                  gap: '6px'
                }}
                title="Sign Out"
              >
                <FaSignOutAlt />
                Sign Out
              </button>
              
              {/* Mobile Menu Toggle - Hidden on mobile, shown on small tablets */}
              <button
                onClick={toggleMobileMenu}
                style={{
                  background: 'none',
                  border: 'none',
                  color: 'white',
                  fontSize: '1.2rem',
                  cursor: 'pointer',
                  display: 'none'
                }}
                className="mobile-menu-toggle"
              >
                {mobileMenuOpen ? <FaTimes /> : <FaBars />}
              </button>
            </div>
          </div>
        </header>

        {/* Desktop Navigation */}
        <nav className={`nav desktop-nav ${mobileMenuOpen ? 'nav-open' : ''}`}>
          <ul className="nav-list">
            <li className="nav-item">
              <Link 
                to="/map" 
                className="nav-link"
                onClick={() => setMobileMenuOpen(false)}
              >
                <FaMapMarkerAlt style={{ marginRight: '0.5rem' }} />
                Live Map
              </Link>
            </li>
            <li className="nav-item">
              <Link 
                to="/members" 
                className="nav-link"
                onClick={() => setMobileMenuOpen(false)}
              >
                <FaUsers style={{ marginRight: '0.5rem' }} />
                Members
              </Link>
            </li>
            <li className="nav-item">
              <Link 
                to="/history" 
                className="nav-link"
                onClick={() => setMobileMenuOpen(false)}
              >
                <FaHistory style={{ marginRight: '0.5rem' }} />
                History
              </Link>
            </li>
            <li className="nav-item">
              <Link 
                to="/detailed-history" 
                className="nav-link"
                onClick={() => setMobileMenuOpen(false)}
              >
                <FaHistory style={{ marginRight: '0.5rem' }} />
                Daily History
              </Link>
            </li>
            {isAdmin && (
              <li className="nav-item">
                <Link 
                  to="/admin" 
                  className="nav-link"
                  onClick={() => setMobileMenuOpen(false)}
                >
                  <FaUserShield style={{ marginRight: '0.5rem' }} />
                  Admin
                </Link>
              </li>
            )}
          </ul>
        </nav>

        {/* Main Content */}
        <main className="container">
          {!isOnline && (
            <div className="error" style={{ marginBottom: '1rem' }}>
              <FaWifi style={{ marginRight: '0.5rem' }} />
              You are currently offline. Some features may not work properly.
            </div>
          )}

          <Routes>
            <Route path="/" element={<Navigate to={isAdmin ? "/admin" : "/map"} replace />} />
            <Route 
              path="/map" 
              element={
                <LocationMap 
                  selectedFamily={selectedFamily}
                  selectedMember={selectedMember}
                  onMemberSelect={handleMemberSelect}
                  user={user}
                />
              } 
            />
            <Route 
              path="/members" 
              element={
                <FamilyMembers 
                  selectedFamily={selectedFamily}
                  selectedMember={selectedMember}
                  onFamilyChange={handleFamilyChange}
                  onMemberSelect={handleMemberSelect}
                  user={user}
                />
              } 
            />
            <Route 
              path="/history" 
              element={
                <LocationHistory 
                  selectedFamily={selectedFamily}
                  user={user}
                />
              } 
            />
            <Route 
              path="/detailed-history" 
              element={
                <LocationHistoryDetailed 
                  selectedFamily={selectedFamily}
                  user={user}
                />
              } 
            />
            <Route 
              path="/admin" 
              element={
                isAdmin ? (
                  <AdminPanel user={user} />
                ) : (
                  <div className="card">
                    <div className="card-content">
                      <div style={{ textAlign: 'center', padding: '2rem' }}>
                        <FaUserShield size={48} style={{ color: '#f56565', marginBottom: '1rem' }} />
                        <h3>Access Denied</h3>
                        <p>You don't have administrator privileges to access this page.</p>
                        <button 
                          className="btn"
                          onClick={() => navigate('/map')}
                          style={{ marginTop: '1rem' }}
                        >
                          Go to Map
                        </button>
                      </div>
                    </div>
                  </div>
                )
              } 
            />
          </Routes>
        </main>

        {/* Mobile Bottom Navigation */}
        <nav className="bottom-nav mobile-nav">
          <div className="bottom-nav-container">
            <Link 
              to="/map" 
              className={`bottom-nav-item ${location.pathname === '/map' ? 'active' : ''}`}
            >
              <FaMapMarkerAlt className="bottom-nav-icon" />
              <span className="bottom-nav-label">Map</span>
            </Link>
            <Link 
              to="/members" 
              className={`bottom-nav-item ${location.pathname === '/members' ? 'active' : ''}`}
            >
              <FaUsers className="bottom-nav-icon" />
              <span className="bottom-nav-label">Members</span>
            </Link>
            <Link 
              to="/history" 
              className={`bottom-nav-item ${location.pathname === '/history' ? 'active' : ''}`}
            >
              <FaHistory className="bottom-nav-icon" />
              <span className="bottom-nav-label">History</span>
            </Link>
            <Link 
              to="/detailed-history" 
              className={`bottom-nav-item ${location.pathname === '/detailed-history' ? 'active' : ''}`}
            >
              <FaCalendarAlt className="bottom-nav-icon" />
              <span className="bottom-nav-label">Details</span>
            </Link>
            {isAdmin && (
              <Link 
                to="/admin" 
                className={`bottom-nav-item ${location.pathname === '/admin' ? 'active' : ''}`}
              >
                <FaUserShield className="bottom-nav-icon" />
                <span className="bottom-nav-label">Admin</span>
              </Link>
            )}
          </div>
        </nav>

        {/* Mobile responsive styles */}
        <style>{`
          /* Bottom Navigation for Mobile */
          .bottom-nav {
            display: none;
            position: fixed;
            bottom: 0;
            left: 0;
            right: 0;
            background: white;
            border-top: 1px solid #e5e7eb;
            box-shadow: 0 -2px 10px rgba(0,0,0,0.1);
            z-index: 1000;
            padding: env(safe-area-inset-bottom, 0) 0 0 0;
          }
          
          .bottom-nav-container {
            display: flex;
            justify-content: space-around;
            align-items: center;
            padding: 0.5rem 0;
            max-width: 100%;
          }
          
          .bottom-nav-item {
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            text-decoration: none;
            color: #6b7280;
            padding: 0.5rem;
            transition: color 0.2s ease;
            min-width: 60px;
            flex: 1;
            max-width: 80px;
          }
          
          .bottom-nav-item.active {
            color: #667eea;
          }
          
          .bottom-nav-icon {
            font-size: 1.25rem;
            margin-bottom: 0.25rem;
          }
          
          .bottom-nav-label {
            font-size: 0.75rem;
            font-weight: 500;
            text-align: center;
            line-height: 1;
          }
          
          /* Mobile Styles */
          @media (max-width: 768px) {
            /* Hide desktop navigation on mobile */
            .desktop-nav {
              display: none !important;
            }
            
            /* Show bottom navigation on mobile */
            .bottom-nav.mobile-nav {
              display: block !important;
            }
            
            /* Add bottom padding to main content to account for bottom nav */
            .container {
              padding-bottom: 80px !important;
            }
            
            /* Hide mobile menu toggle since we're using bottom nav */
            .mobile-menu-toggle {
              display: none !important;
            }
          }
          
          /* Desktop Styles */
          @media (min-width: 769px) {
            /* Show desktop navigation */
            .desktop-nav {
              display: block !important;
            }
            
            .nav-list {
              display: flex !important;
            }
            
            /* Hide bottom navigation on desktop */
            .bottom-nav.mobile-nav {
              display: none !important;
            }
            
            /* Hide mobile menu toggle on desktop */
            .mobile-menu-toggle {
              display: none !important;
            }
            
            /* Mobile menu styles for desktop when needed */
            .nav-open .nav-list {
              display: flex !important;
            }
          }
          
          /* Ensure proper stacking */
          .bottom-nav {
            z-index: 1001;
          }
          
          /* Safe area for iOS devices with home indicator */
          @supports (padding: max(0px)) {
            .bottom-nav {
              padding-bottom: max(0.5rem, env(safe-area-inset-bottom));
            }
          }
          
          /* Extra small screens - make navigation more compact */
          @media (max-width: 480px) {
            .bottom-nav-item {
              padding: 0.25rem;
              min-width: 50px;
            }
            
            .bottom-nav-icon {
              font-size: 1rem;
              margin-bottom: 0.15rem;
            }
            
            .bottom-nav-label {
              font-size: 0.65rem;
            }
          }
        `}</style>

        {/* PWA Install Prompt */}
        <PWAInstallPrompt />
      </div>
  );
}

// Main App component with Router
function App() {
  return (
    <Router>
      <AppContent />
    </Router>
  );
}

export default App;
