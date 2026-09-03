package com.mat.commonutils.gps;

import android.Manifest;
import android.app.AlarmManager;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.location.Location;
import android.os.Bundle;
import android.os.IBinder;
import android.os.ResultReceiver;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.core.app.ActivityCompat;
import androidx.core.app.NotificationCompat;
import android.util.Log;

import com.google.android.gms.common.ConnectionResult;
import com.google.android.gms.common.api.GoogleApiClient;
import com.google.android.gms.location.LocationListener;
import com.google.android.gms.location.LocationRequest;
import com.google.android.gms.location.LocationServices;
import com.google.gson.Gson;
import com.mat.commonutils.commonutils.CommonUtils;
import com.mat.commonutils.commonutils.Constants;
import com.mat.commonutils.model.LocationDetailsModel;
import com.mat.commonutils.networkutils.ConnectionManager;

import java.text.DateFormat;
import java.text.SimpleDateFormat;
import java.util.Calendar;
import java.util.Date;


public class GPSTrackerService extends Service implements GPSTrackerListener, GoogleApiClient.ConnectionCallbacks, GoogleApiClient.OnConnectionFailedListener, LocationListener {
//public class GPSTrackerService extends Service {

    GPSTracker gpsTracker;
    ResultReceiver resultReceiver;
    private Gson mGson;
    NotificationCompat.Builder mBuilder;
    private boolean firstTime;
    protected Location mCurrentLocation;
    private NotificationManager mNotificationManager;

    private GoogleApiClient mGoogleApiClient;
    private LocationRequest mLocationRequest;
    private String mLastUpdateTime;
    private long lastSMSTime;
    BroadcastReceiver smsReceiver = null;


    @Override
    public void onCreate() {
        super.onCreate();
        startForeground(Constants.NOTIFICATION_ID, CommonUtils.getInstance().getNotification(this));
//        mFusedLocationClient = LocationServices.getFusedLocationProviderClient(this);
        if (mGoogleApiClient == null) {
            buildGoogleApiClient();
        }
        mGson = new Gson();
    }


    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        try {
            if (CommonUtils.getInstance().getBatteryPercentage(this) > 2) {
                mGoogleApiClient.connect();
                if (mGoogleApiClient.isConnected()) {
                    startLocationUpdates();
                }
                System.out.println("raj onStartCommand");
                resultReceiver = intent.getParcelableExtra(Constants.RESULT_RECIEVER);
//                System.out.println("raj MIN_DISTANCE_CHANGE_FOR_UPDATES: " + intent.getLongExtra("MIN_DISTANCE_CHANGE_FOR_UPDATES", 0));
                System.out.println("raj MIN_TIME_BW_UPDATES: " + intent.getLongExtra("MIN_TIME_BW_UPDATES", 0));
//            gpsTracker = new GPSTracker(this, this, intent.getLongExtra("MIN_DISTANCE_CHANGE_FOR_UPDATES", 0), intent.getLongExtra("MIN_TIME_BW_UPDATES", 0), true);
//            if (gpsTracker != null) {
//                gpsTracker.startTracking();
//            }
            } else {
                // do nothing.....
            }
        } catch (Exception ex) {
            System.out.println("raj exception in onStartCommand: " + ex);
        }

        return START_STICKY;
    }

    @Override
    public void onDestroy() {

        System.out.println("raj Stopped GPS tracking...");
        if (gpsTracker != null) {
            gpsTracker.stopUsingGPS();
        }
        if (mGoogleApiClient != null && mGoogleApiClient.isConnected()) {
            stopLocationUpdates();
        }
        smsReceiver = null;
        restartService();
        super.onDestroy();
    }

    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public void onLocationFetched(final Location location) {
        System.out.println("raj onLocationFetched: " + location.getLongitude());
    }

    private void pushLocationToDB(final Location location) {
        int batteryPercentage = CommonUtils.getInstance().getBatteryPercentage(this);
        final LocationDetailsModel locationDetailsModel = new LocationDetailsModel();
        locationDetailsModel.setLatitude(location.getLatitude());
        locationDetailsModel.setLongitude(location.getLongitude());
        locationDetailsModel.setLongitude(location.getLongitude());
        locationDetailsModel.setBatteryPercentage(batteryPercentage);
        locationDetailsModel.setTimeStamp(location.getTime());
        locationDetailsModel.setGpsStatus(ConnectionManager.getInstance().getGpsStatus(GPSTrackerService.this));
//        locationDetailsModel.setTimeStamp(getCurrentTime());
        locationDetailsModel.setDate(getCurrentTime(location.getTime()));
//        if (ConnectionManager.getInstance().isInternetAvailable(this)) {
//            FamilyMemberList familyList = MySharedPreferences.getInstance().getFamilyNames(this);
//            if (familyList != null && !familyList.getFamilyMembersList().isEmpty()) {
//                for (FamilyMemberModel family : familyList.getFamilyMembersList()) {
//                    if (family != null && family.getMemberId() != null && family.getMobile() != null && family.getMobile().equalsIgnoreCase(familyModel.getMobile())) {
//                        FirebaseHandler.getInstance().saveLocationToDB(family.getMemberId(), locationDetailsModel);
//                    }
//                }
//            }
//
//        } else {
//            if (ContextCompat.checkSelfPermission(this,
//                    Manifest.permission.SEND_SMS)
//                    == PackageManager.PERMISSION_GRANTED && mCurrentLocation != null && CommonUtils.getInstance().isTimeSatisfied(lastSMSTime)) {
//                MySharedPreferences.getInstance().setDateSmsSentDate(this, System.currentTimeMillis());
////                String msg = "Latitiude :" + mCurrentLocation.getLatitude() + "\n" + "longitude :" + mCurrentLocation.getLongitude() + "\n Battery :" + batteryPercentage
//                String msg = "Phone Battery :" + batteryPercentage
//                        + "\nClick Here to view " + familyModel.getName() + " location on Map : " + "https://www.google.com/maps/search/?api=1&query=" + mCurrentLocation.getLatitude() + "," + mCurrentLocation.getLongitude();
//                String encrypted = AESHandler.getInstance().getEncryptedData(msg);
//                System.out.println("@@arun" + encrypted);
//                CommonUtils.getInstance().sendSms("9700567735", msg);
//
//            }
//        }
    }

    private String getCurrentTime() {
        Calendar cal = Calendar.getInstance();
        SimpleDateFormat sdf = new SimpleDateFormat(Constants.DATE_FORMAT);
        String strDate = sdf.format(cal.getTime());
        return strDate;
    }

    private String getCurrentTime(long millisec) {
        SimpleDateFormat sdf = new SimpleDateFormat(Constants.DATE_FORMAT);
        String strDate = sdf.format(millisec);
        return strDate;
    }

    @Override
    public void onTaskRemoved(Intent rootIntent) {
        super.onTaskRemoved(rootIntent);

        System.out.println("@@arun ontaskRemoved...");
//        Toast.makeText(this, "Task Removed", Toast.LENGTH_LONG).show();
        restartService();
    }

    private void restartService() {
        PendingIntent service = PendingIntent.getService(getApplicationContext(),
                1001,
                new Intent(getApplicationContext(), GPSTrackerService.class),
                PendingIntent.FLAG_IMMUTABLE);

        AlarmManager alarmManager = (AlarmManager) getSystemService(Context.ALARM_SERVICE);
        alarmManager.set(AlarmManager.ELAPSED_REALTIME_WAKEUP, 10000, service);
    }

    protected synchronized void buildGoogleApiClient() {
        Log.i("@arunn", "Building GoogleApiClient");
        mGoogleApiClient = new GoogleApiClient.Builder(this)
                .addConnectionCallbacks(GPSTrackerService.this)
                .addOnConnectionFailedListener(this)
                .addApi(LocationServices.API)
                .build();
        createLocationRequest();

    }

    @Override
    public void onConnected(@Nullable Bundle bundle) {
        // If the initial location was never previously requested, we use
        // FusedLocationApi.getLastLocation() to get it. If it was previously requested, we store
        // its value in the Bundle and check for it in onCreate(). We
        // do not request it again unless the user specifically requests location updates by pressing
        // the Start Updates button.
        //
        // Because we cache the value of the initial location in the Bundle, it means that if the
        // user launches the activity,
        // moves to a new location, and then changes the device orientation, the original location
        // is displayed as the activity is re-created.
        if (mCurrentLocation == null) {
            if (ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
                // TODO: Consider calling
                //    ActivityCompat#requestPermissions
                // here to request the missing permissions, and then overriding
                //   public void onRequestPermissionsResult(int requestCode, String[] permissions,
                //                                          int[] grantResults)
                // to handle the case where the user grants the permission. See the documentation
                // for ActivityCompat#requestPermissions for more details.
                return;
            }
            mCurrentLocation = LocationServices.FusedLocationApi.getLastLocation(mGoogleApiClient);
            mLastUpdateTime = DateFormat.getTimeInstance().format(new Date());
//            Toast.makeText(getApplicationContext(),"Hello Babe",Toast.LENGTH_SHORT).show();
        }

        // If the user presses the Start Updates button before GoogleApiClient connects, we set
        // mRequestingLocationUpdates to true (see startUpdatesButtonHandler()). Here, we check
        // the value of mRequestingLocationUpdates and if it is true, we start location updates.
        startLocationUpdates();
    }

    @Override
    public void onConnectionSuspended(int i) {
        // The connection to Google Play services was lost for some reason. We call connect() to
        // attempt to re-establish the connection.
        Log.i("@Arunn", "Connection suspended");
        mGoogleApiClient.connect();
    }

    @Override
    public void onConnectionFailed(@NonNull ConnectionResult connectionResult) {
        // Refer to the javadoc for ConnectionResult to see what error codes might be returned in
        // onConnectionFailed.
        Log.i("@arun", "Connection failed: ConnectionResult.getErrorCode() = " + connectionResult.getErrorCode());
    }

    protected void createLocationRequest() {
        mLocationRequest = new LocationRequest();
        mLocationRequest.setSmallestDisplacement(Constants.MIN_DISTANCE_OF_TRACKING);
        // Sets the desired interval for active location updates. This interval is
        // inexact. You may not receive updates at all if no location sources are available, or
        // you may receive them slower than requested. You may also receive updates faster than
        // requested if other applications are requesting location at a faster interval.
        mLocationRequest.setInterval(Constants.MIN_TIME_OF_TRACKING);
//        mLocationRequest.setInterval(Constants.MIN_TIME_OF_TRACKING * 60);

        // Sets the fastest rate for active location updates. This interval is exact, and your
        // application will never receive updates faster than this value.
        mLocationRequest.setFastestInterval(Constants.MIN_TIME_OF_TRACKING / 2);
//        mLocationRequest.setFastestInterval(0);

        mLocationRequest.setPriority(LocationRequest.PRIORITY_HIGH_ACCURACY);
    }

    /**
     * Requests location updates from the FusedLocationApi.
     */
    protected void startLocationUpdates() {
        // The final argument to {@code requestLocationUpdates()} is a LocationListener
        // (http://developer.android.com/reference/com/google/android/gms/location/LocationListener.html).
        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
            LocationServices.FusedLocationApi.requestLocationUpdates(mGoogleApiClient, mLocationRequest, this);
        }

    }

    protected void stopLocationUpdates() {
        // It is a good practice to remove location requests when the activity is in a paused or
        // stopped state. Doing so helps battery performance and is especially
        // recommended in applications that request frequent location updates.

        // The final argument to {@code requestLocationUpdates()} is a LocationListener
        // (http://developer.android.com/reference/com/google/android/gms/location/LocationListener.html).
        LocationServices.FusedLocationApi.removeLocationUpdates(mGoogleApiClient, (LocationListener) this);
    }

    @Override
    public void onLocationChanged(Location location) {
        if (location != null) {
            mCurrentLocation = location;
            onLocationFetched(location);
        }
    }


}


