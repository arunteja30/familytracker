package com.mat.phonesecurity.recievers;

import android.app.ActivityManager;
import android.app.KeyguardManager;
import android.app.admin.DeviceAdminReceiver;
import android.app.admin.DevicePolicyManager;
import android.content.Context;
import android.content.Intent;
import android.media.MediaPlayer;
import android.os.Build;
import android.os.CountDownTimer;
import android.util.Log;
import android.view.SurfaceView;

import com.mat.commonutils.commonutils.Constants;
import com.mat.phonesecurity.R;
import com.mat.phonesecurity.common.MySecuritySharedPref;
import com.mat.phonesecurity.services.PhototakingService;

public class MyDeviceAdminReceiver extends DeviceAdminReceiver {

    private SurfaceView sv;
    private static MediaPlayer mp;

    /**
     * method to show toast
     *
     * @param context the application context on which the toast has to be displayed
     * @param msg     The message which will be displayed in the toast
     */
    private void showToast(Context context, CharSequence msg) {
        Log.e("MyDeviceAdminRec...", "::>>>>1 ");
//        Toast.makeText(context, msg, Toast.LENGTH_SHORT).show();
    }

    @Override
    public void onEnabled(Context context, Intent intent) {
        Log.e("MyDeviceAdminRec...", "::>>>>2 ");
        showToast(context, "Device Admin: enabled");

    }

    @Override
    public void onReceive(Context context, Intent intent) {
        super.onReceive(context, intent);

    }

    @Override
    public CharSequence onDisableRequested(Context context, Intent intent) {
        Log.e("MyDeviceAdminRec...", "::>>>>3 ");
        return "This is an optional message to warn the user about disabling.";
    }

    @Override
    public void onDisabled(Context context, Intent intent) {
        Log.e("MyDeviceAdminRec...", "::>>>>4 ");
        showToast(context, "Device Admin: disabled");
    }

    @Override
    public void onPasswordChanged(Context context, Intent intent) {
        Log.e("MyDeviceAdminRec...", "::>>>>5 ");
        showToast(context, "Sample Device Admin: pw changed");
    }

    @Override
    public void onPasswordFailed(Context context, Intent intent) {
        Log.e("MyDeviceAdminRec...", "::>>>>6 ");
        DevicePolicyManager mgr = (DevicePolicyManager) context.getSystemService(Context.DEVICE_POLICY_SERVICE);
        int no = mgr.getCurrentFailedPasswordAttempts();

        if (no >= 2) {
            KeyguardManager km = (KeyguardManager) context.getSystemService(Context.KEYGUARD_SERVICE);
            if (km.inKeyguardRestrictedInputMode()) {
                // is in lock screen state
                // show siren here..
                Intent mapActivity = new Intent(context, PhototakingService.class);
                mapActivity.putExtra(Constants.ALERT_EMAIL_ID, MySecuritySharedPref.getInstance().getAlertEmailId(context));
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(mapActivity);
                } else {
                    context.startService(mapActivity);
                }
            }
        } else {
            Log.e("MyDeviceAdminRec...", " failed attemts :" + no);
        }

    }

    @Override
    public void onPasswordSucceeded(Context context, Intent intent) {
        Log.e("MyDeviceAdminRec...", "::>>>>7 ");
        if (isMyServiceRunning(context, PhototakingService.class)) {
            Intent mapActivity = new Intent(context, PhototakingService.class);
            context.stopService(mapActivity);
        }
    }

    private void startAudio(final Context context) {


        MyDeviceAdminReceiver.this.mp = MediaPlayer.create(context, R.raw.alarm);
//        SoundPool soundPool = new SoundPool(4, AudioManager.STREAM_MUSIC, 50);

        CountDownTimer cntr_aCounter = new CountDownTimer(20000, 1000) {
            public void onTick(long millisUntilFinished) {
                if (!MyDeviceAdminReceiver.this.mp.isPlaying()) {
                    MyDeviceAdminReceiver.this.mp.setLooping(true);
                    MyDeviceAdminReceiver.this.mp.start();

                }
                Log.e("MyDeviceAdminRec...", "seconds remain ::" + millisUntilFinished / 1000);
            }

            public void onFinish() {
                //code fire after finish
                stopPlaying();
                Log.e("MyDeviceAdminRec...", "seconds finished");
            }
        };
        cntr_aCounter.start();
    }

    private void stopPlaying() {
        if (MyDeviceAdminReceiver.this.mp != null) {
            MyDeviceAdminReceiver.this.mp.stop();
            MyDeviceAdminReceiver.this.mp.release();
            MyDeviceAdminReceiver.this.mp = null;
        }
    }

    private boolean isMyServiceRunning(Context context, Class<?> serviceClass) {
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
