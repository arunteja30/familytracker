package com.mat.commonutils.notification;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.ContextWrapper;
import android.content.Intent;
import android.graphics.BitmapFactory;
import android.graphics.Color;
import android.os.Build;
import androidx.core.app.NotificationCompat;

import com.mat.commonutils.R;

public class NotificationUtils {
    private static final String CHANNEL_ID_ONE = "appNotification";


    public void showNotification(Context ctx, String contentTitle, String contentDesc, int icon) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification builder = new NotificationCompat.Builder(ctx,
                    CHANNEL_ID_ONE)
                    .setContentTitle(contentTitle)
                    .setContentText(contentDesc)
//                    .setLargeIcon(icon)
                    .setSmallIcon(icon)
                    .build();
            NotificationManager notificationManager = (NotificationManager)
                    ctx.getSystemService(Context.NOTIFICATION_SERVICE);
            notificationManager.notify(111, builder);
        } else {
            Notification notification = new NotificationCompat.Builder(ctx)
                    .setContentTitle(contentTitle)
                    .setContentText(contentDesc)
//                    .setLargeIcon(bitmap1)
                    .setSmallIcon(icon)
//                    .addAction(R.drawable.play, "back", pi)
                    .build();
            NotificationManager notificationManager = (NotificationManager)
                    ctx.getSystemService(Context.NOTIFICATION_SERVICE);
            notificationManager.notify(111, notification);
        }
    }


    public static void cancel(Context context) {
        NotificationManager notificationManager = (NotificationManager)
                context.getSystemService(Context.NOTIFICATION_SERVICE);
        if (Build.VERSION.SDK_INT >= 5) {
            notificationManager.cancel(CHANNEL_ID_ONE, 0);
        } else {
            notificationManager.cancel(CHANNEL_ID_ONE.hashCode());
        }
    }

}