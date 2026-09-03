package com.mat.phonesecurity.activity;

import android.Manifest;
import android.app.admin.DevicePolicyManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.location.Location;
import android.location.LocationManager;
import android.os.Bundle;
import androidx.core.content.ContextCompat;
import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.app.AppCompatActivity;
import android.widget.Toast;

import com.mat.commonutils.commonutils.CommonListener;
import com.mat.commonutils.commonutils.CommonUtils;
import com.mat.commonutils.commonutils.Constants;
import com.mat.commonutils.gps.GPSHandler;
import com.mat.commonutils.gps.LatLong;
import com.mat.commonutils.gps.LocationFetchListener;
import com.mat.phonesecurity.R;
import com.mat.phonesecurity.recievers.MyDeviceAdminReceiver;

import java.util.List;

public class MainActivity extends AppCompatActivity {
    DevicePolicyManager policyManager;
    ComponentName devicePolicyAdmin;
    private static final int ADMIN_REQUEST = 1232;


    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        policyManager = (DevicePolicyManager) getSystemService(Context.DEVICE_POLICY_SERVICE);
        devicePolicyAdmin = new ComponentName(this,
                MyDeviceAdminReceiver.class);

//        launchDeviceAdmin();

    }

    public void checkPermission() {
        CommonUtils.getInstance().checkPermissions(this, new CommonListener() {
            @Override
            public void onTaskCompleted(Object value) {
                if (value.toString().equalsIgnoreCase("allowed")) {
                    GPSHandler.getInstance().startGPSTracker(MainActivity.this, Constants.MIN_DISTANCE_OF_TRACKING, Constants.MIN_TIME_OF_TRACKING, new LocationFetchListener() {
                        @Override
                        public void onLocationFetched(final LatLong latLong) {
                            GPSHandler.getInstance().getAddressFromLocation(MainActivity.this, latLong.getLatitude(), latLong.getLongitude(), new CommonListener() {
                                @Override
                                public void onTaskCompleted(Object value) {
                                    GPSHandler.getInstance().setCurrentLocationAddress(value.toString());
                                    Location temp = new Location(LocationManager.GPS_PROVIDER);
                                    temp.setLatitude(latLong.getLatitude());
                                    temp.setLongitude(latLong.getLongitude());
                                    GPSHandler.getInstance().setCurrentLocation(temp);
                                }
                            });
                        }
                    });
                }
            }
        });
    }


    public void launchDeviceAdmin() {
        if (!isMyDevicePolicyReceiverActive()) {
            Intent intent = new Intent(
                    DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN);
            intent.putExtra(
                    DevicePolicyManager.EXTRA_DEVICE_ADMIN,
                    devicePolicyAdmin);
            intent.putExtra(
                    DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                    getString(R.string.admin_explanation));
            startActivityForResult(intent, ADMIN_REQUEST);
        }
    }

    private boolean isMyDevicePolicyReceiverActive() {
        return policyManager
                .isAdminActive(devicePolicyAdmin);
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode == ADMIN_REQUEST && (requestCode == RESULT_OK || requestCode != RESULT_OK)) {
//            onBackPressed();
        }
        super.onActivityResult(requestCode, resultCode, data);
    }

    public void showDialog(Context activity) {
        AlertDialog.Builder builder = new AlertDialog.Builder(activity);
// Add the buttons
        builder.setPositiveButton("OK", new DialogInterface.OnClickListener() {
            public void onClick(DialogInterface dialog, int id) {
                // User clicked OK button
                dialog.dismiss();
            }
        });

        builder.setTitle("Alert..!");
// Create the AlertDialog
        AlertDialog dialog = builder.create();
        dialog.setMessage("Your Are Trying to unlock the phone with the wrong Password..\n Please stop otherwise Phone trigger a siren..");


        dialog.show();

    }
}