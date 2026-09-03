package com.mat.familytracker.pushNotification;

import android.app.ActivityManager;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.media.RingtoneManager;
import android.net.Uri;
import android.util.Log;

import androidx.core.app.NotificationCompat;

import com.google.firebase.messaging.FirebaseMessagingService;
import com.google.firebase.messaging.RemoteMessage;
import com.mat.familytracker.R;
import com.mat.familytracker.activity.AddFamilyActivity;
import com.mat.familytracker.gpstracker.GPSHandler;
import com.mat.familytracker.gpstracker.GPSTrackerService;
import com.mat.familytracker.utils.Constants;

import java.util.Map;

public class MyFirebaseMessagingService extends FirebaseMessagingService {
    NotificationManager notificationManager;
    NotificationCompat.Builder summaryNotificationBuilder;
    int bundleNotificationId = 100;
    int singleNotificationId = 100;

    @Override
    public void onNewToken(String token) {
        super.onNewToken(token);
        Log.d("FCM_TOKEN", "Refreshed token: " + token);
    }

    @Override
    public void onMessageReceived(RemoteMessage remoteMessage) {

        if (remoteMessage.getData().size() > 0) {
            Map<String, String> dataFromCloud = remoteMessage.getData();
            notificationGroup(dataFromCloud);
        }
    }

    private void notificationGroup(Map<String, String> message) {

        //  Create Notification
        String contentTitle = getFamilyName(message.get("title"));
        String contentText = message.get("text");
        if (contentText.contains("TEST") && !isMyServiceRunning(GPSTrackerService.class)) {
            GPSHandler.getInstance().startGPSTracker(this);
        }
        Bitmap bm = BitmapFactory.decodeResource(getApplication().getResources(),
                R.mipmap.ic_launcher);
        Uri defaultSoundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION);
        notificationManager = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);

        // Notification Group Key
        String groupKey = "bundle_notification_" + bundleNotificationId;

        //  Notification Group click intent
        Intent resultIntent = new Intent(this, AddFamilyActivity.class);
        resultIntent.putExtra("notification", "Summary Notification");
        resultIntent.putExtra("notification_id", bundleNotificationId);
        resultIntent.setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        PendingIntent resultPendingIntent = PendingIntent.getActivity(this, bundleNotificationId, resultIntent, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

        // We need to update the bundle notification every time a new notification comes up
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            if (notificationManager.getNotificationChannels().size() < 2) {
                NotificationChannel groupChannel = new NotificationChannel("bundle_channel_id", "bundle_channel_name", NotificationManager.IMPORTANCE_LOW);
                notificationManager.createNotificationChannel(groupChannel);
                NotificationChannel channel = new NotificationChannel("channel_id", "channel_name", NotificationManager.IMPORTANCE_DEFAULT);
                notificationManager.createNotificationChannel(channel);
            }
        }
        summaryNotificationBuilder = new NotificationCompat.Builder(this, "bundle_channel_id")
                .setGroup(groupKey)
                .setGroupSummary(true)
                .setContentTitle(contentTitle)
                .setContentText(contentText)
                .setSmallIcon(R.mipmap.ic_launcher_round)
                .setLargeIcon(bm)
                .setAutoCancel(true)
                .setContentIntent(resultPendingIntent);


        if (singleNotificationId == bundleNotificationId)
            singleNotificationId = bundleNotificationId + 1;
        else
            singleNotificationId++;

        //  Individual notification click intent
        resultIntent = new Intent(this, AddFamilyActivity.class);
        resultIntent.putExtra("notification", "Single Notification");
        resultIntent.putExtra("notification_id", singleNotificationId);
        resultIntent.setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        resultPendingIntent = PendingIntent.getActivity(this, singleNotificationId, resultIntent, PendingIntent.FLAG_IMMUTABLE);


        NotificationCompat.Builder notification = new NotificationCompat.Builder(this, "channel_id")
                .setGroup(groupKey)
                .setContentTitle(contentTitle)
                .setContentText(contentText)
                .setSmallIcon(R.mipmap.ic_launcher_round)
                .setLargeIcon(bm)
                .setSound(defaultSoundUri)
                .setAutoCancel(true)
                .setGroupSummary(false)
                .setContentIntent(resultPendingIntent);

        notificationManager.notify(singleNotificationId, notification.build());
        notificationManager.notify(bundleNotificationId, summaryNotificationBuilder.build());
    }

    private String getFamilyName(String familyName) {
        if (familyName != null && familyName.contains(Constants.NAME_SEPERATOR)) {
            int index = familyName.toString().lastIndexOf(Constants.NAME_SEPERATOR);
            return familyName.toString().substring(0, index);
        }
        return "";
    }

    private boolean isMyServiceRunning(Class<?> serviceClass) {
        ActivityManager manager = (ActivityManager) getSystemService(Context.ACTIVITY_SERVICE);
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