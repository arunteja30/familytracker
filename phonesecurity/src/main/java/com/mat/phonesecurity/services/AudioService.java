package com.mat.phonesecurity.services;

import android.app.KeyguardManager;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.media.MediaPlayer;
import android.os.CountDownTimer;
import android.os.IBinder;
import androidx.media.VolumeProviderCompat;
import android.support.v4.media.session.MediaSessionCompat;
import android.support.v4.media.session.PlaybackStateCompat;
import android.util.Log;

import com.mat.phonesecurity.R;
import com.mat.phonesecurity.recievers.MyDeviceAdminReceiver;

public class AudioService extends Service {
    MediaPlayer mp;

    public AudioService() {
    }

    private MediaSessionCompat mediaSession;

    @Override
    public void onCreate() {
        super.onCreate();

        mediaSession = new MediaSessionCompat(this, "PlayerService");
        mediaSession.setFlags(MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS |
                MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS);
        mediaSession.setPlaybackState(new PlaybackStateCompat.Builder()
                .setState(PlaybackStateCompat.STATE_PLAYING, 0, 0) //you simulate a player which plays something.
                .build());

        VolumeProviderCompat myVolumeProvider =
                new VolumeProviderCompat(VolumeProviderCompat.VOLUME_CONTROL_RELATIVE, /*max volume*/100, /*initial volume level*/100) {
                    @Override
                    public void onAdjustVolume(int direction) {
                        Log.e("@volume--", "@@voume..pressed");
                    }
                };

        mediaSession.setPlaybackToRemote(myVolumeProvider);
        mediaSession.setActive(true);
        startAudio(this);
    }


    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    private void startAudio(final Context context) {
        this.mp = MediaPlayer.create(context, R.raw.alarm);
//        SoundPool soundPool = new SoundPool(4, AudioManager.STREAM_MUSIC, 50);
        final KeyguardManager keyguardManager = (KeyguardManager)context.getSystemService(Context.KEYGUARD_SERVICE);
        CountDownTimer cntr_aCounter = new CountDownTimer(30000, 1000) {
            public void onTick(long millisUntilFinished) {
                if (!AudioService.this.mp.isPlaying()) {
                    AudioService.this.mp.setLooping(true);
                    AudioService.this.mp.start();
                }

//                if (keyguardManager.isKeyguardSecure()) {
//                    //phone was unlocked, do stuff here
//                    stopSelf();
//                }
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

    @Override
    public void onDestroy() {
        super.onDestroy();
        mediaSession.release();
        stopPlaying();
    }

    private void stopPlaying() {
        if (AudioService.this.mp != null) {
            AudioService.this.mp.stop();
            AudioService.this.mp.release();
            AudioService.this.mp = null;
        }
    }
}