package com.mat.familytracker.activity;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.widget.Toast;

import com.mat.familytracker.gpstracker.GPSTrackerService;
import com.mat.familytracker.utils.Constants;
import com.mat.familytracker.utils.MySharedPreferences;

public class Restarter extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
//        Toast.makeText(context, "Service restarted", Toast.LENGTH_SHORT).show();

        if (intent.getAction().equalsIgnoreCase(Intent.ACTION_BOOT_COMPLETED) && MySharedPreferences.getInstance().getFamilyName(context) != null) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(new Intent(context, GPSTrackerService.class));
            } else {
                context.startService(new Intent(context, GPSTrackerService.class));
            }
            Toast.makeText(context, "arun boot completed", Toast.LENGTH_SHORT).show();
        }
    }
}
