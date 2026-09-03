package com.mat.familytracker.activity;

import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.content.Context;
import android.os.Build;
import androidx.annotation.NonNull;
import androidx.core.app.NotificationCompat;

import androidx.work.Worker;
import androidx.work.WorkerParameters;

import com.google.firebase.auth.FirebaseAuth;
import com.mat.familytracker.R;
import com.mat.familytracker.gpstracker.GPSHandler;
import com.mat.familytracker.gpstracker.GPSTrackerService;
import com.mat.familytracker.utils.CommonUtils;

public class MyContinuosWork extends Worker {
    Result result;

    public MyContinuosWork(@NonNull Context context, @NonNull WorkerParameters workerParams) {
        super(context, workerParams);
    }

    @NonNull
    @Override
    public Result doWork() {
        if (FirebaseAuth.getInstance() != null && FirebaseAuth.getInstance().getCurrentUser() != null && !CommonUtils.getInstance().isMyServiceRunning(getApplicationContext(), GPSTrackerService.class)) {
//            GPSHandler.getInstance().stopGPSTracker(getApplicationContext());
            GPSHandler.getInstance().startGPSTracker(getApplicationContext());
        }
//        GPSHandler.getInstance().startGPSTracker(getApplicationContext());
//        displayNotification("Hey Arun..", "This is from repetative work, should start GPSTrackingService");
        return Result.success();
    }

    private void displayNotification(String task, String desc) {

        NotificationManager manager =
                (NotificationManager) getApplicationContext().getSystemService(Context.NOTIFICATION_SERVICE);

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel("simplifiedcoding1", "simplifiedcoding1", NotificationManager.IMPORTANCE_DEFAULT);
            manager.createNotificationChannel(channel);
        }

        NotificationCompat.Builder builder = new NotificationCompat.Builder(getApplicationContext(), "simplifiedcoding1")
                .setContentTitle(task)
                .setContentText(desc)
                .setSmallIcon(R.mipmap.ic_launcher);

        manager.notify(1098, builder.build());

    }
}
