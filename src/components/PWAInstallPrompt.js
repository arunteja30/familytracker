import React, { useState, useEffect } from 'react';
import { FaDownload, FaTimes, FaMobile } from 'react-icons/fa';

const PWAInstallPrompt = () => {
  const [deferredPrompt, setDeferredPrompt] = useState(null);
  const [showInstallPrompt, setShowInstallPrompt] = useState(false);
  const [isInstalled, setIsInstalled] = useState(false);

  useEffect(() => {
    // Check if already installed
    const checkIfInstalled = () => {
      // Check if running as installed PWA
      const isInStandaloneMode = window.matchMedia('(display-mode: standalone)').matches;
      const isInWebAppMode = window.navigator.standalone === true;
      
      if (isInStandaloneMode || isInWebAppMode) {
        setIsInstalled(true);
        return;
      }

      // Check if previously dismissed (for this session)
      const dismissed = sessionStorage.getItem('pwa-install-dismissed');
      if (dismissed) {
        return;
      }

      // Show install prompt after a delay if not installed
      setTimeout(() => {
        if (!isInstalled && deferredPrompt) {
          setShowInstallPrompt(true);
        }
      }, 3000); // Show after 3 seconds
    };

    // Listen for the beforeinstallprompt event
    const handleBeforeInstallPrompt = (e) => {
      console.log('beforeinstallprompt event fired');
      // Prevent the mini-infobar from appearing on mobile
      e.preventDefault();
      // Save the event so it can be triggered later
      setDeferredPrompt(e);
      checkIfInstalled();
    };

    // Listen for the app being installed
    const handleAppInstalled = () => {
      console.log('PWA was installed');
      setIsInstalled(true);
      setShowInstallPrompt(false);
      setDeferredPrompt(null);
    };

    window.addEventListener('beforeinstallprompt', handleBeforeInstallPrompt);
    window.addEventListener('appinstalled', handleAppInstalled);

    // Initial check
    checkIfInstalled();

    return () => {
      window.removeEventListener('beforeinstallprompt', handleBeforeInstallPrompt);
      window.removeEventListener('appinstalled', handleAppInstalled);
    };
  }, [deferredPrompt, isInstalled]);

  const handleInstallClick = async () => {
    if (!deferredPrompt) {
      return;
    }

    try {
      // Show the install prompt
      await deferredPrompt.prompt();
      
      // Wait for the user to respond to the prompt
      const { outcome } = await deferredPrompt.userChoice;
      
      console.log(`User response to the install prompt: ${outcome}`);
      
      if (outcome === 'accepted') {
        console.log('User accepted the install prompt');
        setIsInstalled(true);
      }
      
      // Reset the deferred prompt
      setDeferredPrompt(null);
      setShowInstallPrompt(false);
    } catch (error) {
      console.error('Error during PWA installation:', error);
    }
  };

  const handleDismiss = () => {
    setShowInstallPrompt(false);
    // Remember dismissal for this session
    sessionStorage.setItem('pwa-install-dismissed', 'true');
  };

  // Don't show if already installed or no prompt available
  if (isInstalled || !showInstallPrompt || !deferredPrompt) {
    return null;
  }

  return (
    <div className="pwa-install-prompt">
      <div className="pwa-install-content">
        <div className="pwa-install-header">
          <FaMobile className="pwa-install-icon" />
          <h3>Install Family Tracker</h3>
          <button 
            className="pwa-install-close" 
            onClick={handleDismiss}
            aria-label="Close"
          >
            <FaTimes />
          </button>
        </div>
        
        <div className="pwa-install-body">
          <p>Install our app for the best experience:</p>
          <ul className="pwa-install-features">
            <li>📱 Works offline</li>
            <li>🚀 Faster loading</li>
            <li>🔔 Push notifications</li>
            <li>📍 Better location access</li>
          </ul>
        </div>
        
        <div className="pwa-install-actions">
          <button 
            className="pwa-install-btn-install" 
            onClick={handleInstallClick}
          >
            <FaDownload />
            Install App
          </button>
          <button 
            className="pwa-install-btn-dismiss" 
            onClick={handleDismiss}
          >
            Not now
          </button>
        </div>
      </div>
    </div>
  );
};

export default PWAInstallPrompt;
