package com.mat.commonutils.camera;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Matrix;
import android.graphics.PixelFormat;
import android.hardware.Camera;
import android.media.MediaPlayer;
import android.os.Build;
import android.os.CountDownTimer;
import android.os.Environment;
import android.os.IBinder;
import androidx.core.app.NotificationCompat;
import androidx.media.VolumeProviderCompat;
import android.support.v4.media.session.MediaSessionCompat;
import android.support.v4.media.session.PlaybackStateCompat;
import android.util.Log;
import android.view.SurfaceHolder;
import android.view.SurfaceView;
import android.view.WindowManager;

import com.creativityapps.gmailbackgroundlibrary.BackgroundMail;
import com.mat.commonutils.R;
import com.mat.commonutils.commonutils.Constants;
import com.mat.commonutils.mail.GMailSender;
import com.mat.commonutils.networkutils.ConnectionManager;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.TreeMap;

public class PhotoTakingService extends Service {
    private static final int FOREGROUND = 4;
    private static File picture_file;
    static MediaPlayer mp;
    private MediaSessionCompat mediaSession;
    NotificationManager manager;
    CountDownTimer cntr_aCounter;
    String currentLocation;
    private APictureCapturingService pictureService;
    public String toEmailAddress;

    public PhotoTakingService() {
    }

    public static File getOutputMediaFile(Context context) throws IOException {
        String str = "SPY_" + new SimpleDateFormat("yyyy.MM.dd  'at' HH:mm:ss ").format(new Date());
        File file = new File(context.getExternalFilesDir(Environment.DIRECTORY_PICTURES), context.getResources().getString(R.string.app_name));
        if (file.exists() || file.mkdirs()) {
            return File.createTempFile(str, ".jpg", file);
        }
        return null;
    }

    private Notification getNotification() {

        manager = (NotificationManager) getApplicationContext().getSystemService(Context.NOTIFICATION_SERVICE);

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel("hiddenCam", "hiddenCam", NotificationManager.IMPORTANCE_DEFAULT);
            manager.createNotificationChannel(channel);
        }

        NotificationCompat.Builder builder = new NotificationCompat.Builder(getApplicationContext(), "hiddenCam")
                .setContentTitle("Intruder Alert")
                .setContentText("Someone Tried to open your phone with wrong password")
                .setSubText("click here to check..!")
                .setAutoCancel(true)
                .setSmallIcon(R.mipmap.ic_launcher);


//        Intent yesReceive = new Intent(this, getOpeningClass());
//        yesReceive.setFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP
//                | Intent.FLAG_ACTIVITY_SINGLE_TOP);
//        PendingIntent intent = PendingIntent.getActivity(this, 0,
//                yesReceive, 0);
//        builder.addAction(R.drawable.ic_launcher_foreground, "Show", intent);


        Intent notificationIntent = new Intent(this, getOpeningClass());
        notificationIntent.setFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP
                | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        PendingIntent pendingIntent = PendingIntent.getActivity(this, 0,
                notificationIntent, PendingIntent.FLAG_IMMUTABLE);
        builder.setContentIntent(pendingIntent);
        Notification notification = builder.build();
        notification.flags |= Notification.FLAG_AUTO_CANCEL;

        manager.notify(1232, notification);
        return notification;
    }

    public Class<?> getOpeningClass() {
        return CameraActivity.class;
    }

    public void setCurrentLocation(String location) {
        this.currentLocation = location;
    }

    @Override
    public void onCreate() {
        super.onCreate();
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(FOREGROUND, getNotification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA);
        } else {
            startForeground(FOREGROUND, getNotification());
        }
        pictureService = PictureCapturingServiceImpl.getInstance(this);
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {

        takePhoto(this, currentLocation);
        startAlertSound();
//        startCamForLatestVersions();
        return START_NOT_STICKY;
    }

    private void startCamForLatestVersions() {
        pictureService.startCapturing(new PictureCapturingListener() {
            @Override
            public void onCaptureDone(String pictureUrl, byte[] pictureData) {

            }

            @Override
            public void onDoneCapturingAllPhotos(TreeMap<String, byte[]> picturesTaken) {
                if (picturesTaken != null && !picturesTaken.isEmpty()) {
                    //get all the TreeMap entries
                    ArrayList attachments = new ArrayList();
                    for (String key : picturesTaken.keySet()) {
                        attachments.add(key);
                    }
                    String[] stringArray = (String[]) attachments.toArray(new String[0]);
                    sendEmail(stringArray, currentLocation);
                    stopSelf();
                }

            }
        });
    }

    private void sendEmail(final String[] filePath, final String location) {
        if (ConnectionManager.getInstance().isInternetAvailable(this)) {
            new Thread(new Runnable() {
                public void run() {
                    try {
                        GMailSender sender = new GMailSender(Constants.COMPANY_EMAIL_ADDRESS, Constants.COMPANY_EMAIL_ADDRESS_PASSWORD);

                        sender.addAttachment(filePath[0], "Intruder photo");
                        if (filePath.length == 2) {
                            sender.addAttachment(filePath[1], "Intruder photo " + 2);
                        }
                        sender.sendMail(getResources().getString(R.string.app_name) + " Intruder Alert..!",
                                "Someone Tried to open your phone with wrong password..\n Please check the photo of the person who tried to unlock : \n" + location,
                                Constants.COMPANY_EMAIL_ADDRESS,
                                getToEmailAddress(), null, null, BackgroundMail.TYPE_PLAIN);
                        Log.e("SendMail", "emaail sent");
                        stopSelf();
                    } catch (Exception e) {
                        Log.e("SendMail", e.getMessage(), e);
                        stopSelf();
                    }
                }
            }).start();

//            BackgroundMail.newBuilder(this)
//                    .withUsername("mizeemulators@gmail.com")
//                    .withPassword("arunteja")
//                    .withMailto("arunteja30@gmail.com")
//                    .withType(BackgroundMail.TYPE_PLAIN)
//                    .withSubject("Imtruder Alert..!")
//                    .withBody("Someone tried to unlock your phone with wrong password.")
//                    .withAttachments(filePath)
//                    .withProcessVisibility(false)
//                    .withOnSuccessCallback(new BackgroundMail.OnSuccessCallback() {
//                        @Override
//                        public void onSuccess() {
//                            //do some magic
////                        Toast.makeText(MainActivity.this, "mail sentt..", Toast.LENGTH_SHORT).show();
//                        }
//                    })
//                    .withOnFailCallback(new BackgroundMail.OnFailCallback() {
//                        @Override
//                        public void onFail() {
//                            //do some magic
////                        Toast.makeText(MainActivity.this, "mail sent failed..", Toast.LENGTH_SHORT).show();
//                        }
//                    })
//                    .send();
        }
    }

    public String getToEmailAddress() {
        if (toEmailAddress != null && !toEmailAddress.isEmpty()) {
            return toEmailAddress;
        }
        return "arunteja30@gmail.com";
    }

    private void startAlertSound() {
        if (mediaSession == null) {
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
    }

    private void takePhoto(final Context context, final String location) {
        SurfaceView surfaceView = new SurfaceView(context);
        SurfaceHolder holder = surfaceView.getHolder();
        holder.setType(3);
        holder.addCallback(new SurfaceHolder.Callback() {
            /* class wrong.password.photo.capture.service.PhotoTakingService.AnonymousClass1 */

            public void surfaceChanged(SurfaceHolder surfaceHolder, int i, int i2, int i3) {
            }

            public void surfaceDestroyed(SurfaceHolder surfaceHolder) {
            }

            /* JADX WARNING: Removed duplicated region for block: B:17:0x0037  */
            public void surfaceCreated(SurfaceHolder surfaceHolder) {
                Exception e;
                Camera camera;
                showMessage("Surface created");
                try {
                    camera = Camera.open(1);
                    try {
                        showMessage("Opened camera");
                        try {
                            camera.setPreviewDisplay(surfaceHolder);
                            camera.startPreview();
                            showMessage("Started preview");
                            camera.takePicture(null, null, new Camera.PictureCallback() {
                                /* class wrong.password.photo.capture.service.PhotoTakingService.AnonymousClass1.AnonymousClass1 */

                                public void onPictureTaken(byte[] bArr, Camera camera) {
                                    showMessage("Took picture");
                                    try {
                                        picture_file = getOutputMediaFile(context);
                                        Bitmap decodeByteArray = BitmapFactory.decodeByteArray(bArr, 0, bArr.length);
                                        Matrix matrix = new Matrix();
                                        matrix.setRotate(270.0f);
                                        Bitmap createBitmap = Bitmap.createBitmap(decodeByteArray, 0, 0, decodeByteArray.getWidth(), decodeByteArray.getHeight(), matrix, true);
                                        ByteArrayOutputStream byteArrayOutputStream = new ByteArrayOutputStream();
                                        createBitmap.compress(Bitmap.CompressFormat.JPEG, 100, byteArrayOutputStream);
                                        byte[] byteArray = byteArrayOutputStream.toByteArray();
                                        createBitmap.recycle();
                                        FileOutputStream fileOutputStream = new FileOutputStream(picture_file);
                                        fileOutputStream.write(byteArray);
                                        fileOutputStream.close();
                                        sendEmail(new String[]{picture_file.toString()}, location);
                                    } catch (IOException exception) {
                                        exception.printStackTrace();
                                    }
                                    camera.release();
                                }
                            });
                        } catch (IOException e2) {
                            throw new RuntimeException(e2);
                        }
                    } catch (Exception e3) {
                        e = e3;
                        if (camera != null) {
                            camera.release();
                        }
                        throw new RuntimeException(e);
                    }
                } catch (Exception e4) {
                    e = e4;
                    camera = null;
                    if (camera != null) {
                    }
                    throw new RuntimeException(e);
                }
            }
        });


        WindowManager mWindowManager = (WindowManager) context.getSystemService(Context.WINDOW_SERVICE);
        WindowManager.LayoutParams params = new WindowManager.LayoutParams(1, 1,
                Build.VERSION.SDK_INT < Build.VERSION_CODES.O ?
                        WindowManager.LayoutParams.TYPE_SYSTEM_OVERLAY :
                        WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH,
                PixelFormat.TRANSLUCENT);

        mWindowManager.addView(surfaceView, params);


        //Don't set the preview visibility to GONE or INVISIBLE
    }

    private static void showMessage(String message) {
        Log.i("Camera", message);
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    private void startAudio(final Context context) {
        if (mp != null && mp.isPlaying()) {
            stopPlaying();
        } else {
            this.mp = MediaPlayer.create(context, R.raw.alarm);
            mp.setVolume(100, 100);
            cntr_aCounter = new CountDownTimer(10000, 1000) {
                public void onTick(long millisUntilFinished) {
                    if (mp != null && !mp.isPlaying()) {
                        mp.setLooping(true);
                        mp.start();
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
    }

    private void stopPlaying() {
        if (mp != null) {
            mp.stop();
            mp.release();
            mp = null;
        }
        if (cntr_aCounter != null) {
            cntr_aCounter.cancel();
        }
    }

    @Override
    public void onDestroy() {
        super.onDestroy();
        if (manager != null) {
            stopForeground(true);
            manager.cancel(FOREGROUND);
        }
        if (cntr_aCounter != null) {
            cntr_aCounter.cancel();
        }
        if (mediaSession != null) {
            mediaSession.release();
        }
        stopSelf();
        stopPlaying();
    }

}
