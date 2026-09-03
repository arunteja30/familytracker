package com.mat.phonesecurity.services;

import android.content.Intent;

import com.mat.commonutils.camera.PhotoTakingService;
import com.mat.commonutils.commonutils.Constants;
import com.mat.commonutils.gps.GPSHandler;
import com.mat.phonesecurity.activity.IntruderPhotosActivity;

public class PhototakingService extends PhotoTakingService {
    @Override
    public Class<?> getOpeningClass() {
        return IntruderPhotosActivity.class;
    }

    @Override
    public void onCreate() {
        setCurrentLocation(GPSHandler.getInstance().getCurrentLocationAddr());
        super.onCreate();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent != null && intent.getStringExtra(Constants.ALERT_EMAIL_ID) != null) {
            toEmailAddress = intent.getStringExtra(Constants.ALERT_EMAIL_ID);
        }
        return super.onStartCommand(intent, flags, startId);
    }
}
