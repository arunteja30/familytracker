package com.mat.commonutils.networkutils;

import android.app.AlertDialog;
import android.content.Context;
import android.content.DialogInterface;
import android.content.Intent;
import android.location.LocationManager;
import android.net.ConnectivityManager;
import android.net.NetworkInfo;
import android.provider.Settings;


public class ConnectionManager {
    private static ConnectionManager ourInstance = new ConnectionManager();

    private ConnectionManager() {
    }

    public static ConnectionManager getInstance() {
        return ourInstance;
    }

    ///Method to check the availability of internet connection.
    public boolean isInternetAvailable(Context activity) {
        if (activity != null) {
            ConnectivityManager connectivity = (ConnectivityManager) activity.getSystemService(Context.CONNECTIVITY_SERVICE);
            if (connectivity != null) {
                if (connectivity.getActiveNetworkInfo() != null
                        && connectivity.getActiveNetworkInfo().isAvailable()
                        && connectivity.getActiveNetworkInfo().isConnected()) {
                    return true;
                } else if (isWifiEnabled(activity)) {
                    return true;
                } else {
                    return false;
                }
            }
        }
        return false;
    }

    public boolean isGpsEnableDialog(Context instance) {
        boolean gpsStatus = isGpsEnabled(instance);
        if (!gpsStatus) {
            showSettingsAlert(instance);
        }
        return gpsStatus;
    }

    public boolean isGpsEnabled(Context instance) {
        LocationManager manager = (LocationManager) instance.getSystemService(instance.LOCATION_SERVICE);
        boolean statusOfGPS = manager.isProviderEnabled(LocationManager.GPS_PROVIDER);
        boolean statusOfNetwork = manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER);
        boolean statusOfPassive = manager.isProviderEnabled(LocationManager.PASSIVE_PROVIDER);
        if (statusOfGPS || statusOfNetwork || statusOfPassive) {
            return true;
        } else {
            return false;
        }
    }

    public boolean isGpsEnable(Context instance) {
        return isGpsEnabled(instance);
    }

    public String getGpsStatus(Context instance) {
        boolean statusOfGPS = isGpsEnable(instance);
        if (!statusOfGPS) {
            return "GPS Disabled..!";
        }
        return "GPS Enabled..!";
    }

    public boolean isMobileDataEnabled(Context context) {
        try {
            boolean isMobileNetwork = false;
            if (isInternetAvailable(context)) {
                ConnectivityManager cm =
                        (ConnectivityManager) context.getSystemService(Context.CONNECTIVITY_SERVICE);

                NetworkInfo activeNetwork = cm.getActiveNetworkInfo();
                isMobileNetwork = activeNetwork.getType() == ConnectivityManager.TYPE_MOBILE;
            }
            return isMobileNetwork;
        } catch (Exception ex) {
            return false;
        }
    }

    public boolean isWifiEnabled(Context context) {
        try {
            boolean isWifi = false;
//            if (isInternetAvailable(context)) {
            ConnectivityManager cm =
                    (ConnectivityManager) context.getSystemService(Context.CONNECTIVITY_SERVICE);

            NetworkInfo activeNetwork = cm.getActiveNetworkInfo();
            isWifi = activeNetwork.getType() == ConnectivityManager.TYPE_WIFI;
//            }
            return isWifi;
        } catch (Exception ex) {
            return false;
        }
    }

    public boolean isCellularNetworkNotificationRequired(Context context) {
        boolean isDialogRequired = false;
        if (!isWifiEnabled(context) && isInternetAvailable(context) && isMobileDataEnabled(context)) {
            isDialogRequired = true;
        }
        return isDialogRequired;
        //return true;
    }

    public void showSettingsAlert(final Context mContext) {
        AlertDialog.Builder alertDialog = new AlertDialog.Builder(mContext);

        // Setting Dialog Title
        alertDialog.setTitle("Info");

        // Setting Dialog Message
        alertDialog.setMessage("GPS is not enabled.This is a location based application,without GPS app will not work. Do you want to go to settings menu to enable GPS?");

        // Setting Icon to Dialog
        //alertDialog.setIcon(R.drawable.delete);

        // On pressing Settings button
        alertDialog.setPositiveButton("Settings", new DialogInterface.OnClickListener() {
            public void onClick(DialogInterface dialog, int which) {
                Intent intent = new Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS);
                mContext.startActivity(intent);
            }
        });

        // on pressing cancel button
        alertDialog.setNegativeButton("Cancel", new DialogInterface.OnClickListener() {
            public void onClick(DialogInterface dialog, int which) {
                dialog.cancel();
            }
        });

        // Showing Alert Message
        alertDialog.show();
    }

    public boolean isDoubleCheckInternet(Context activity) {
        ConnectivityManager connectivity = (ConnectivityManager) activity.getSystemService(Context.CONNECTIVITY_SERVICE);
        if (connectivity != null) {
            NetworkInfo[] info = connectivity.getAllNetworkInfo();
            if (info != null)
                for (int i = 0; i < info.length; i++)
                    if (info[i].getState() == NetworkInfo.State.CONNECTED) {
                        return true;
                    }

        }
        return false;
    }
}
