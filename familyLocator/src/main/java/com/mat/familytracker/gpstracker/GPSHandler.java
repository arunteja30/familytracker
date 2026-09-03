package com.mat.familytracker.gpstracker;

import android.app.Activity;
import android.app.ActivityManager;
import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.location.Address;
import android.location.Geocoder;
import android.location.Location;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Message;
import android.os.ResultReceiver;
import android.util.Log;

import com.mat.commonutils.commonutils.CommonListener;
import com.mat.commonutils.gps.GetAddressFromLocation;
import com.mat.commonutils.networkutils.ConnectionManager;
import com.mat.familytracker.utils.Constants;

import java.io.IOException;
import java.util.Calendar;
import java.util.List;
import java.util.Locale;


public class GPSHandler {
    private static GPSHandler ourInstance = new GPSHandler();
    private Location currentLocation;

    private GPSHandler() {
    }

    public static GPSHandler getInstance() {
        return ourInstance;
    }

    public Location getCurrentLocation() {
        return currentLocation;
    }

    public void setCurrentLocation(Location currentLocation) {
        this.currentLocation = currentLocation;
    }


    public void startGPSTracker(Context context) {
//        if (ConnectionManager.getInstance().isGpsEnableDialog(context)) {
//            if (!isMyServiceRunning(GPSTrackerService.class, context)) {
//                if (ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
//                    Intent intent = new Intent(context, GPSTrackerService.class);
//                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
//                        context.startForegroundService(intent);
//                    } else {
//                        context.startService(intent);
//                    }
//                }
//            }
//        }
        startAlarmService(context,false);
    }
    public void startGPSTracker(Context context,boolean sms) {
        startAlarmService(context,sms);
    }

    private void startAlarmService(Context context,boolean sms) {
        Intent intent = new Intent(context, GPSTrackerService.class);
        if (sms) {
            intent.putExtra("isFromSMS", sms);
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent);
        } else {
            context.startService(intent);
        }
        Calendar cal = Calendar.getInstance();
        Intent repeatIntent = new Intent(context, GPSTrackerService.class);
        PendingIntent pintent = null;
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            pintent = PendingIntent
                    .getForegroundService(context, 0, repeatIntent, PendingIntent.FLAG_IMMUTABLE);
        } else {
            pintent = PendingIntent
                    .getService(context, 0, repeatIntent, PendingIntent.FLAG_IMMUTABLE);
        }

        AlarmManager alarm = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        // Start service every hour
        alarm.setRepeating(AlarmManager.RTC_WAKEUP, cal.getTimeInMillis(),
                8 * 60 * 1000, pintent);
    }

    public void startGPSTracker(Context context, long MIN_DISTANCE_CHANGE_FOR_UPDATES, long MIN_TIME_BW_UPDATES, final LocationFetchListener listener) {
        Intent intent = new Intent(context, GPSTrackerService.class);
        intent.putExtra("MIN_DISTANCE_CHANGE_FOR_UPDATES", MIN_DISTANCE_CHANGE_FOR_UPDATES);
        intent.putExtra("MIN_TIME_BW_UPDATES", MIN_TIME_BW_UPDATES);
        intent.putExtra(Constants.RESULT_RECIEVER, new ResultReceiver(new Handler()) {
            @Override
            protected void onReceiveResult(int resultCode, Bundle resultData) {
                super.onReceiveResult(resultCode, resultData);

                if (resultCode == Activity.RESULT_OK) {
                    double latitude = resultData.getDouble(Constants.LATITUDE);
                    double longitude = resultData.getDouble(Constants.LONGITUDE);
                    LatLong latLong = new LatLong();
                    latLong.setLatitude(latitude);
                    latLong.setLongitude(longitude);
                    listener.onLocationFetched(latLong);
                    System.out.println("result ok..");
                } else {
                    System.out.println("result not ok..");
                }
            }
        });
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent);
        } else {
            context.startService(intent);
        }
    }

    public void startTracking(Context context) {
        Intent intent = new Intent(context, GPSTrackerService.class);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent);
        } else {
            context.startService(intent);
        }

    }

    public void stopGPSTracker(Context context) {
        Intent intent = new Intent(context, GPSTrackerService.class);
        context.stopService(intent);
    }

    public void getCurrentLocation(Activity context, GPSTrackerListener gpsTrackerListener) {
        // showing GPS alert dialog before enabling the tracking
        Bundle loc_bundle = new Bundle();
        loc_bundle.putString("title",
                "GPS Setttings");
        loc_bundle.putString("message",
                "GPS is Not Enabled");
        loc_bundle.putString("button_one",
                "Settings");
        loc_bundle.putString("Cancel", "Cancel");
        if (ConnectionManager.getInstance().isGpsEnableDialog(context)) {
            GPSTracker gpsTracker = new GPSTracker(context, gpsTrackerListener, false);
            gpsTracker.startTracking();
        }
    }

    public LatLong getlatLong(Context context, String strAddress) {

        Geocoder coder = new Geocoder(context);
        List<Address> address;
        LatLong latLong = null;

        try {
            address = coder.getFromLocationName(strAddress, 5);
            if (address == null) {
                return null;
            }
            Address location = address.get(0);
            location.getLatitude();
            location.getLongitude();

            latLong = new LatLong();
            latLong.setLatitude(location.getLatitude());//(double) (location.getLatitude() * 1E6));
            latLong.setLongitude(location.getLongitude());//(double) (location.getLongitude() * 1E6));
        } catch (Exception ex) {

        } finally {
            return latLong;
        }
    }

    public void fetchLatLong(Context context, String strAddress, LocationFetchListener locationFetchListener) {

        Geocoder coder = new Geocoder(context);
        List<Address> address;
        LatLong latLong = null;
        Address location = null;
//        Location convertedLocation = new Location("Converted");
        try {
            address = coder.getFromLocationName(strAddress, 5);
            if (address != null && address.size() > 0) {

                location = address.get(0);
                location.getLatitude();
                location.getLongitude();

                latLong = new LatLong();
                latLong.setLatitude(location.getLatitude());//(double) (location.getLatitude() * 1E6));
                latLong.setLongitude(location.getLongitude());

//                convertedLocation.setLatitude(location.getLatitude());//(double) (location.getLatitude() * 1E6));
//                convertedLocation.setLongitude(location.getLongitude());//(double) (location.getLongitude() * 1E6));}
            }
        } catch (Exception ex) {
            ex.printStackTrace();
            locationFetchListener.onLocationFetched(null);
        } finally {
            if (latLong != null && (latLong.getLatitude() != 0 && latLong.getLongitude() != 0))
                locationFetchListener.onLocationFetched(latLong);
        }
    }

    public String getAddress(Context context, double LATITUDE, double LONGITUDE) {

        //Set Address
        try {
            Geocoder geocoder = new Geocoder(context, Locale.getDefault());
            List<Address> addresses = geocoder.getFromLocation(LATITUDE, LONGITUDE, 1);
            if (addresses != null && addresses.size() > 0) {
                String address = addresses.get(0).getAddressLine(0); // If any additional address line present than only, check with max available address lines by getMaxAddressLineIndex()
                String address1 = addresses.get(0).getAddressLine(1); // If any additional address line present than only, check with max available address lines by getMaxAddressLineIndex()
                String address2 = addresses.get(0).getAddressLine(2); // If any additional address line present than only, check with max available address lines by getMaxAddressLineIndex()
                String city = addresses.get(0).getLocality();
                String state = addresses.get(0).getAdminArea();
                String country = addresses.get(0).getCountryName();
                String postalCode = addresses.get(0).getPostalCode();
                String knownName = addresses.get(0).getFeatureName(); // Only if available else return NULL
                StringBuilder strReturnedAddress = new StringBuilder("");
                strReturnedAddress = strReturnedAddress.append(address + "\n");
                strReturnedAddress = strReturnedAddress.append(address1 + "\n");
                strReturnedAddress = strReturnedAddress.append(address2 + "\n");
                strReturnedAddress = strReturnedAddress.append(address + "\n");
                strReturnedAddress = strReturnedAddress.append(city + "\n");
                strReturnedAddress = strReturnedAddress.append(state + "\n");
                strReturnedAddress = strReturnedAddress.append(country + "\n");
                strReturnedAddress = strReturnedAddress.append(postalCode + "\n");
                strReturnedAddress = strReturnedAddress.append(knownName + "\n");
                return strReturnedAddress.toString();
            } else {
                return "Current Location Latitude : " + LATITUDE + "\n Longitude " + LONGITUDE;
            }

        } catch (IOException e) {
            e.printStackTrace();
            return "Current Location Latitude : " + LATITUDE + "\n Longitude " + LONGITUDE;
        }
    }

    public void getAddressFromLocation(Context context, double latitude, double longitude, CommonListener listerner) {
        new GetAddressFromLocation(context, latitude, longitude, listerner).execute();
    }

    public void getAddressFromLocation(final double latitude, final double longitude,
                                       final Context context, final Handler handler) {
        Thread thread = new Thread() {
            @Override
            public void run() {
                Geocoder geocoder = new Geocoder(context, Locale.getDefault());
                String result = null;
                try {
                    List<Address> addressList = geocoder.getFromLocation(
                            latitude, longitude, 1);
                    if (addressList != null && addressList.size() > 0) {
                        Address address = addressList.get(0);
                        StringBuilder sb = new StringBuilder();
                        for (int i = 0; i < 1; i++) {
                            sb.append(address.getAddressLine(i)).append("\n");
                        }
                        sb.append(address.getLocality()).append("\n");
                        sb.append(address.getPostalCode()).append("\n");
                        sb.append(address.getCountryName());
                        result = sb.toString();
                    }
                } catch (IOException e) {
                    Log.e("GEOCODER", "Unable connect to Geocoder", e);
                } finally {
                    Message message = Message.obtain();
                    message.setTarget(handler);
                    if (result != null) {
                        message.what = 1;
                        Bundle bundle = new Bundle();
//                        result = "Latitude: " + latitude + " Longitude: " + longitude +
//                                "\n\nAddress:\n" + result;
                        result = /*"Address:\n" +*/ result;
                        bundle.putString("address", result);
                        message.setData(bundle);
                    } else {
                        message.what = 1;
                        Bundle bundle = new Bundle();
                        result = "Latitude: " + latitude + " Longitude: " + longitude +
                                "\n Unable to get address for this lat-long.";
                        bundle.putString("address", result);
                        message.setData(bundle);
                    }
                    message.sendToTarget();
                }
            }
        };
        thread.start();
    }

    private boolean isMyServiceRunning(Class<?> serviceClass, Context context) {
        ActivityManager manager = (ActivityManager) context.getSystemService(Context.ACTIVITY_SERVICE);
        for (ActivityManager.RunningServiceInfo service : manager.getRunningServices(Integer.MAX_VALUE)) {
            if (serviceClass.getName().equals(service.service.getClassName())) {
                Log.i("Service status", "Running");
                return true;
            }
        }
        Log.i("Service status", "Not running");
        return false;
    }


}
