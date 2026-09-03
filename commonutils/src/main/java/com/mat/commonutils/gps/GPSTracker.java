package com.mat.commonutils.gps;

import android.Manifest;
import android.content.Context;
import android.content.pm.PackageManager;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Looper;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;
import android.util.Log;

import com.google.android.gms.location.FusedLocationProviderClient;
import com.google.android.gms.location.LocationCallback;
import com.google.android.gms.location.LocationRequest;
import com.google.android.gms.location.LocationResult;
import com.google.android.gms.location.LocationServices;
import com.google.android.gms.location.SettingsClient;

/**
 * Created by RajeshGorantla on 3/7/2017.
 */

public class GPSTracker implements LocationListener {

    protected LocationManager locationManager;
    boolean isGPSEnabled = false;
    boolean isNetworkEnabled = false;
    boolean canGetLocation = false;
    Location location;
    double latitude;
    double longitude;
    boolean isContinuous;
    GPSTrackerListener gpsTrackerListener;
    boolean isUsingFusedLocationProvider = false;
    private FusedLocationProviderClient mFusedLocationClient;
    private Context mContext;
    private long mMIN_DISTANCE_CHANGE_FOR_UPDATES = 0; // 0 meters
    private long mMIN_TIME_BW_UPDATES = 1000 /** 60 * 1*/
            ; // 1 minute
    private LocationCallback mLocationCallback;

    public GPSTracker(Context context, GPSTrackerListener gpsTrackerListener, long MIN_DISTANCE_CHANGE_FOR_UPDATES, long MIN_TIME_BW_UPDATES, boolean isContinuous) {
        this.mContext = context;
        this.isContinuous = isContinuous;
        this.gpsTrackerListener = gpsTrackerListener;
        this.mMIN_DISTANCE_CHANGE_FOR_UPDATES = MIN_DISTANCE_CHANGE_FOR_UPDATES; // distance in meters
        this.mMIN_TIME_BW_UPDATES = MIN_TIME_BW_UPDATES; // in seconds
        try {
            locationManager = (LocationManager) mContext
                    .getSystemService(mContext.LOCATION_SERVICE);
            isGPSEnabled = locationManager
                    .isProviderEnabled(LocationManager.GPS_PROVIDER);
            isNetworkEnabled = locationManager
                    .isProviderEnabled(LocationManager.NETWORK_PROVIDER);

            if (!isGPSEnabled && !isNetworkEnabled) {
                // no network provider is enabled
            } else {
                this.canGetLocation = true;
            }
            if (isUsingFusedLocationProvider) {
                mFusedLocationClient = LocationServices.getFusedLocationProviderClient(mContext);

            }
        } catch (Exception ex) {
            System.out.println("raj Exception in GPS tracker constructor: " + ex);
        }
    }

    public void startTracking() {
        try {
            if (Build.VERSION.SDK_INT >= 23 &&
                    ContextCompat.checkSelfPermission(mContext, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED &&
                    ContextCompat.checkSelfPermission(mContext, Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
                return;
            }
            if (isUsingFusedLocationProvider)
                getLocationFromFusedProvider();
            else {

                if (this.canGetLocation = true) {

                    if (isNetworkEnabled) {
                        locationManager.requestLocationUpdates(
                                LocationManager.NETWORK_PROVIDER,
                                mMIN_TIME_BW_UPDATES,
                                mMIN_DISTANCE_CHANGE_FOR_UPDATES, this);
                        Log.i("raj", "Network");
                        if (locationManager != null) {
                            location = locationManager
                                    .getLastKnownLocation(LocationManager.NETWORK_PROVIDER);
                            if (location != null) {
                                latitude = location.getLatitude();
                                longitude = location.getLongitude();
//                            System.out.println("raj Network lat: "+location.getLatitude());
//                            System.out.println("raj Network lon: "+location.getLongitude());
                            }
                        }
                    }

                    if (isGPSEnabled) {
                        if (location == null) {
                            locationManager.requestLocationUpdates(
                                    LocationManager.GPS_PROVIDER,
                                    mMIN_TIME_BW_UPDATES,
                                    mMIN_DISTANCE_CHANGE_FOR_UPDATES, this);
                            Log.i("raj", "GPS Enabled");
                            if (locationManager != null) {
                                location = locationManager
                                        .getLastKnownLocation(LocationManager.GPS_PROVIDER);
                                if (location != null) {
                                    latitude = location.getLatitude();
                                    longitude = location.getLongitude();
//                                System.out.println("raj GPS lat: "+location.getLatitude());
//                                System.out.println("raj GPS lon: "+location.getLongitude());
                                }
                            }
                        }
                    }
                }
            }

        } catch (Exception e) {
            e.printStackTrace();
            System.out.println("raj Exception in start tracking location: " + e);
        }
    }

    private void getLocationFromFusedProvider() {
        long FASTEST_UPDATE_INTERVAL_IN_MILLISECONDS =
                mMIN_TIME_BW_UPDATES / 2;

        SettingsClient mSettingsClient = LocationServices.getSettingsClient(mContext);

        LocationRequest mLocationRequest = new LocationRequest();

        mLocationRequest.setInterval(mMIN_TIME_BW_UPDATES);

        mLocationRequest.setFastestInterval(FASTEST_UPDATE_INTERVAL_IN_MILLISECONDS);

        mLocationRequest.setPriority(LocationRequest.PRIORITY_HIGH_ACCURACY);

        mLocationCallback = new LocationCallback() {
            @Override
            public void onLocationResult(LocationResult locationResult) {
                super.onLocationResult(locationResult);

                location = locationResult.getLastLocation();
                if (gpsTrackerListener != null) {
                    gpsTrackerListener.onLocationFetched(location);
                }
                if (!isContinuous) {
                    stopUsingGPS();
                }
//                mLastUpdateTime = DateFormat.getTimeInstance().format(new Date());
            }
        };

        if (ActivityCompat.checkSelfPermission(mContext, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED && ActivityCompat.checkSelfPermission(mContext, Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            // TODO: Consider calling
            //    ActivityCompat#requestPermissions
            // here to request the missing permissions, and then overriding
            //   public void onRequestPermissionsResult(int requestCode, String[] permissions,
            //                                          int[] grantResults)
            // to handle the case where the user grants the permission. See the documentation
            // for ActivityCompat#requestPermissions for more details.
            return;
        }
        mFusedLocationClient.requestLocationUpdates(mLocationRequest,
                mLocationCallback, Looper.myLooper());


    }

    @Override
    public void onLocationChanged(Location loc) {
        location = loc;
        System.out.println("raj lat: " + loc.getLatitude());
        if (gpsTrackerListener != null) {
            gpsTrackerListener.onLocationFetched(loc);
        }
        if (!isContinuous) {
            stopUsingGPS();
        }
//        System.out.println("raj lat: "+loc.getLatitude());
//        System.out.println("raj lon: "+loc.getLongitude());

    }

    @Override
    public void onStatusChanged(String provider, int status, Bundle extras) {
        System.out.println("raj onStatusChanged: " + status);
    }

    @Override
    public void onProviderEnabled(String provider) {
        System.out.println("raj onProviderEnabled: " + provider);
    }

    @Override
    public void onProviderDisabled(String provider) {
        System.out.println("raj onProviderDisabled: " + provider);
    }

    public void stopUsingGPS() {
        try {
            if (Build.VERSION.SDK_INT >= 23 &&
                    ContextCompat.checkSelfPermission(mContext, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED &&
                    ContextCompat.checkSelfPermission(mContext, Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
                return;
            }
            if (isUsingFusedLocationProvider) {
                mFusedLocationClient.removeLocationUpdates(mLocationCallback);
            }
            if (locationManager != null) {
                locationManager.removeUpdates(GPSTracker.this);
                System.out.println("raj removed GPS updates");
            }
        } catch (Exception ex) {
            System.out.println("raj Exception in stoping GPS Tracking: " + ex);
        }
    }

    public boolean canGetLocation() {
        return this.canGetLocation;
    }

    public double getLatitude() {
        if (location != null) {
            latitude = location.getLatitude();
        }
        return latitude;
    }

    public double getLongitude() {
        if (location != null) {
            longitude = location.getLongitude();
        }
        return longitude;
    }

    public Location getLocation() {
        return location;
    }
}
