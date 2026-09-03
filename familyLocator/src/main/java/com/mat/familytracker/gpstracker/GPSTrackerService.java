package com.mat.familytracker.gpstracker;

import static android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION;

import android.Manifest;
import android.annotation.SuppressLint;
import android.app.AlarmManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.location.Location;
import android.location.LocationManager;
import android.os.Build;
import android.os.Bundle;
import android.os.IBinder;
import androidx.annotation.Nullable;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;
import androidx.localbroadcastmanager.content.LocalBroadcastManager;
import android.util.Log;

import com.google.android.gms.common.ConnectionResult;
import com.google.android.gms.common.api.GoogleApiClient;
import com.google.android.gms.location.LocationListener;
import com.google.android.gms.location.LocationRequest;
import com.google.android.gms.location.LocationServices;
import com.google.firebase.auth.FirebaseAuth;
import com.google.gson.Gson;
import com.mat.commonutils.commonutils.CommonListener;
import com.mat.commonutils.networkutils.ConnectionManager;
import com.mat.familytracker.Database.LogsEntity;
import com.mat.familytracker.Database.Repository;
import com.mat.familytracker.R;
import com.mat.familytracker.activity.FirebaseHandler;
import com.mat.familytracker.domain.FamilyMemberModel;
import com.mat.familytracker.domain.LocationDetailsModel;
import com.mat.familytracker.utils.AESHandler;
import com.mat.familytracker.utils.CommonUtils;
import com.mat.familytracker.utils.Constants;
import com.mat.familytracker.utils.MySharedPreferences;

import java.text.SimpleDateFormat;
import java.util.Calendar;


public class GPSTrackerService extends Service implements
        GoogleApiClient.ConnectionCallbacks, GoogleApiClient.OnConnectionFailedListener,
        LocationListener {

    public static final String ACTION_LOCATION_BROADCAST = GPSTrackerService.class.getName() + "LocationBroadcast";
    public static final String EXTRA_LATITUDE = "extra_latitude";
    public static final String EXTRA_LONGITUDE = "extra_longitude";
    private static final String TAG = GPSTrackerService.class.getSimpleName();
    public Location mCurrentLocation;
    GoogleApiClient mLocationClient;
    String gpsStatus;

    private FamilyMemberModel familyModel;
    private long lastSMSTime;
    LocationRequest mLocationRequest;

    BroadcastReceiver gpsReciever = new GpsReceiver(new GpsReceiver.LocationCallBack() {
        @Override
        public void turnedOn() {
            Log.e("gpsreciever", "gps ON");
            gpsStatus = "GPS is enabled..!";
            CommonUtils.getInstance().updateNotification(GPSTrackerService.this, null, getResources().getString(R.string.app_name) + getResources().getString(R.string.isRunning));
            updateUserData(gpsStatus);
        }

        @Override
        public void turnedOff() {
            Log.e("gpsreciever", "gps OFF");
            gpsStatus = "GPS is disabled..!";
            updateUserData(gpsStatus);
            CommonUtils.getInstance().updateNotification(GPSTrackerService.this, null, "Your GPS is Disabled ,Your family cannot FIND YOU :(");
        }
    });
    private boolean sendSmSTrue;


    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (mLocationClient == null) {
            mLocationClient = new GoogleApiClient.Builder(this)
                    .addConnectionCallbacks(this)
                    .addOnConnectionFailedListener(this)
                    .addApi(LocationServices.API)
                    .build();
        }

        if (intent !=null && intent.hasExtra("isFromSMS")){
            sendSmSTrue = true;
        }

        if (mLocationRequest == null) {
            mLocationRequest = new LocationRequest();
        }


        mLocationRequest.setInterval(Constants.MIN_TIME_OF_TRACKING);
        mLocationRequest.setFastestInterval(Constants.FASTEST_INTERVAL_OF_TRACKING);
        mLocationRequest.setSmallestDisplacement(Constants.MIN_DISTANCE_OF_TRACKING);


        int priority = LocationRequest.PRIORITY_BALANCED_POWER_ACCURACY; //by default
        //PRIORITY_BALANCED_POWER_ACCURACY, PRIORITY_LOW_POWER, PRIORITY_NO_POWER are the other priority modes


        mLocationRequest.setPriority(priority);
        mLocationClient.connect();
        Log.d(TAG, "== on start command");
        @SuppressLint("MissingPermission") Location locationOld = LocationServices.FusedLocationApi.getLastLocation(mLocationClient);
        if (locationOld != null)
            Log.d(TAG, "@@arunl - lastLoc : " + locationOld.getLatitude() + ", " + locationOld.getLongitude());
        //Make it stick to the notification panel so it is less prone to get cancelled by the Operating System.
        return START_STICKY;
    }

    private void updateUserData(String gpsStatus) {
        if (familyModel != null & gpsStatus != null && !gpsStatus.isEmpty()) {
            familyModel.setGpsInfo(gpsStatus);
            FirebaseHandler.getInstance().updateUserModel(familyModel, null);
        }
    }

    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    /*
     * LOCATION CALLBACKS
     */
    @Override
    public void onConnected(Bundle dataBundle) {
        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED && ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            // TODO: Consider calling
            //    ActivityCompat#requestPermissions
            // here to request the missing permissions, and then overriding
            //   public void onRequestPermissionsResult(int requestCode, String[] permissions,
            //                                          int[] grantResults)
            // to handle the case where the user grants the permission. See the documentation
            // for ActivityCompat#requestPermissions for more details.

            Log.d(TAG, "== Error On onConnected() Permission not granted");
            //Permission not granted by user so cancel the further execution.

            return;
        }
        LocationServices.FusedLocationApi.requestLocationUpdates(mLocationClient, mLocationRequest, this);


        Log.d(TAG, "Connected to Google API");
    }

    /*
     * Called by Location Services if the connection to the
     * location client drops because of an error.
     */
    @Override
    public void onConnectionSuspended(int i) {
        Log.d(TAG, "Connection suspended");
    }

    //to get the location change
    @Override
    public void onLocationChanged(final Location location) {
        Log.d(TAG, "Location changed");


        if (location != null) {

            if (mCurrentLocation != null) {
                System.out.println("@@arun distance : " + mCurrentLocation.distanceTo(location));
                double speed = CommonUtils.getInstance().getSpeed(location, mCurrentLocation);
                System.out.println("@@arun speed : " + speed);
            }
            Log.d(TAG, "== location != null");
            Log.d(TAG, "location:" + location);
            mCurrentLocation = location;
            if (ConnectionManager.getInstance().isInternetAvailable(this)) {
                GPSHandler.getInstance().getAddressFromLocation(this, location.getLatitude(), location.getLongitude(), new CommonListener() {
                    @Override
                    public void onTaskCompleted(Object value) {
                        String mobile;
                        if (FirebaseAuth.getInstance().getCurrentUser() !=null){
                          mobile =  FirebaseAuth.getInstance().getCurrentUser().getPhoneNumber();
                        }else{
                            mobile =familyModel.getMobile();
                        }

                        Repository repository = new Repository(GPSTrackerService.this);
                        repository.Insert(new LogsEntity(location.getLatitude(), location.getLongitude(),
                                CommonUtils.getInstance().getCurrentTime(location.getTime()), ConnectionManager.getInstance().getGpsStatus(GPSTrackerService.this),
                                value.toString(),mobile ));

//                        String logentity = new Gson().toJson(new LogsEntity(location.getLatitude(), location.getLongitude(),
//                                CommonUtils.getInstance().getCurrentTime(location.getTime()), ConnectionManager.getInstance().getGpsStatus(GPSTrackerService.this),
//                                value.toString(), FirebaseAuth.getInstance().getCurrentUser().getPhoneNumber()));
                        String html = "https://www.google.com/maps/search/?api=1&query=" + location.getLatitude() + "," + location.getLongitude();
                        String msg = "Location Details:" +
//                                " " + "\n Latitude : " + location.getLatitude() +
//                                "\n Longitude : " + location.getLongitude() +
                                "\n Date : " + CommonUtils.getInstance().getCurrentTime(location.getTime()) +
                                "\n GPS Status : " + ConnectionManager.getInstance().getGpsStatus(GPSTrackerService.this) +
                                "\n Address : " + value.toString() +
                                "\n" + html + "\n \n ";

                        CommonUtils.getInstance().writeToFile(GPSTrackerService.this, mobile, msg, true);
                    }
                });
            } else {
                String mobile;
                if (FirebaseAuth.getInstance().getCurrentUser() !=null){
                    mobile =  FirebaseAuth.getInstance().getCurrentUser().getPhoneNumber();
                }else{
                    mobile =familyModel.getMobile();
                }
                Repository repository = new Repository(GPSTrackerService.this);
                repository.Insert(new LogsEntity(location.getLatitude(), location.getLongitude(),
                        CommonUtils.getInstance().getCurrentTime(location.getTime()), ConnectionManager.getInstance().getGpsStatus(GPSTrackerService.this),
                        "unable to Fetch", mobile));
                String html = "https://www.google.com/maps/search/?api=1&query=" + location.getLatitude() + "," + location.getLongitude();
                String msg = "Location Details:" +
                        " " + "\n Latitude : " + location.getLatitude() +
                        "\n Longitude : " + location.getLongitude() +
                        "\n Date : " + CommonUtils.getInstance().getCurrentTime(location.getTime()) +
                        "\n GPS Status : " + ConnectionManager.getInstance().getGpsStatus(GPSTrackerService.this) +
                        "\n Address : " + "Not Available" +
                        "\n" + html + "\n \n ";

//                String logentity = new Gson().toJson(new LogsEntity(location.getLatitude(), location.getLongitude(),
//                        CommonUtils.getInstance().getCurrentTime(location.getTime()), ConnectionManager.getInstance().getGpsStatus(GPSTrackerService.this),
//                        "Not Availble", FirebaseAuth.getInstance().getCurrentUser().getPhoneNumber()));

                CommonUtils.getInstance().writeToFile(GPSTrackerService.this, mobile, msg, true);

            }
            pushLocationToDB(location);
            //Send result to activities
//            sendMessageToUI(String.valueOf(location.getLatitude()), String.valueOf(location.getLongitude()));
        }
    }

    private void sendMessageToUI(String lat, String lng) {

        Log.d(TAG, "Sending info...");

        Intent intent = new Intent(ACTION_LOCATION_BROADCAST);
        intent.putExtra(EXTRA_LATITUDE, lat);
        intent.putExtra(EXTRA_LONGITUDE, lng);
        LocalBroadcastManager.getInstance(this).sendBroadcast(intent);
    }

    @Override
    public void onConnectionFailed(ConnectionResult connectionResult) {
        Log.d(TAG, "Failed to connect to Google API");

    }


    private String getCurrentTime() {
        Calendar cal = Calendar.getInstance();
        SimpleDateFormat sdf = new SimpleDateFormat(Constants.DATE_FORMAT);
        String strDate = sdf.format(cal.getTime());
        return strDate;
    }

    public String getCurrentTime(long millisec) {
        SimpleDateFormat sdf = new SimpleDateFormat(Constants.DATE_FORMAT);
        String strDate = sdf.format(millisec);
        return strDate;
    }

    @Override
    public void onTaskRemoved(Intent rootIntent) {
        restartService();
        super.onTaskRemoved(rootIntent);

        System.out.println("@@arun ontaskRemoved...");
//        Toast.makeText(this, "Task Removed", Toast.LENGTH_LONG).show();
    }

    private void restartService() {

        Calendar cal = Calendar.getInstance();
        Intent repeatIntent = new Intent(this, GPSTrackerService.class);
        PendingIntent pintent = PendingIntent
                .getService(this, 0, repeatIntent, PendingIntent.FLAG_IMMUTABLE);

        AlarmManager alarm = (AlarmManager) this.getSystemService(Context.ALARM_SERVICE);
        // Start service every hour
        alarm.setRepeating(AlarmManager.RTC_WAKEUP, cal.getTimeInMillis(),
                1000, pintent);

    }

    public void pushLocationToDB(Location location) {
        int batteryPercentage = CommonUtils.getInstance().getBatteryPercentage(this);
        final LocationDetailsModel locationDetailsModel = new LocationDetailsModel();
        locationDetailsModel.setLatitude(location.getLatitude());
        locationDetailsModel.setLongitude(location.getLongitude());
        locationDetailsModel.setLongitude(location.getLongitude());
        locationDetailsModel.setBatteryPercentage(batteryPercentage);
        locationDetailsModel.setTimeStamp(location.getTime());
        locationDetailsModel.setGpsStatus(ConnectionManager.getInstance().getGpsStatus(this));
//        locationDetailsModel.setTimeStamp(getCurrentTime());
        locationDetailsModel.setDate(getCurrentTime(location.getTime()));
        if (ConnectionManager.getInstance().isInternetAvailable(this) && !sendSmSTrue) {
            if (FirebaseAuth.getInstance().getCurrentUser()!=null) {
                FirebaseHandler.getInstance().saveLocationToDB(FirebaseAuth.getInstance().getCurrentUser().getPhoneNumber(), locationDetailsModel);
            }else {
                FirebaseHandler.getInstance().saveLocationToDB(familyModel.getMobile(), locationDetailsModel);
            }

        } else {
            if (ContextCompat.checkSelfPermission(this,
                    Manifest.permission.SEND_SMS)
                    == PackageManager.PERMISSION_GRANTED && mCurrentLocation != null && (CommonUtils.getInstance().isTimeSatisfied(lastSMSTime)) || sendSmSTrue) {
                MySharedPreferences.getInstance().setDateSmsSentDate(this, System.currentTimeMillis());
//                String msg = "Latitiude :" + mCurrentLocation.getLatitude() + "\n" + "longitude :" + mCurrentLocation.getLongitude() + "\n Battery :" + batteryPercentage
                String msg = "Phone Battery :" + batteryPercentage
                        + "\nClick Here to view " + familyModel.getName() + " location on Map : " + "https://www.google.com/maps/search/?api=1&query=" + mCurrentLocation.getLatitude() + "," + mCurrentLocation.getLongitude();
                String encrypted = AESHandler.getInstance().getEncryptedData(msg);
                System.out.println("@@arun" + encrypted);
                CommonUtils.getInstance().sendSms("+919700567735", msg);

            }
        }
    }


    @Override
    public void onCreate() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(Constants.NOTIFICATION_ID, CommonUtils.getInstance().getNotification(this), FOREGROUND_SERVICE_TYPE_LOCATION);
        } else {
            startForeground(Constants.NOTIFICATION_ID, CommonUtils.getInstance().getNotification(this));
        }
        registerReceiver(gpsReciever, new IntentFilter(LocationManager.PROVIDERS_CHANGED_ACTION));
        lastSMSTime = MySharedPreferences.getInstance().getDateSmsSentDate(this);
        if (familyModel == null) {
            String userName = MySharedPreferences.getInstance().getUserName(GPSTrackerService.this);
            familyModel = new Gson().fromJson(userName, FamilyMemberModel.class);
        }
        super.onCreate();

    }

    @Override
    public void onDestroy() {
        super.onDestroy();
        unregisterReceiver(gpsReciever);
    }
}