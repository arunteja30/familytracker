package com.mat.commonutils.mail;

import android.app.Service;
import android.content.Intent;
import android.os.Bundle;
import android.os.IBinder;
import androidx.annotation.Nullable;

import com.creativityapps.gmailbackgroundlibrary.BackgroundMail;


public class SendMailService extends Service {


    private GMailSender sender;
    private Bundle bundle;

    @Override
    public void onCreate() {
        super.onCreate();

    }

    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {


        bundle = intent.getExtras();
        if (bundle != null) {


            new Thread(new Runnable() {
                @Override
                public void run() {
                    try {

                        sender = new GMailSender("mattechsoft@gmail.com", "matsoft@12");

//                                    sender.addAttachment(Environment.getExternalStorageDirectory().getPath()+"/image.jpg");
//                        sender.addAttachment(filePath);
                        sender.sendMail("GOT IT DUDE",
                                "aruntest..",
                                "mattechsoft@gmail.com",
                                "arunteja30@gmail.com", null, null, BackgroundMail.TYPE_PLAIN);

                    } catch (Exception ex) {
                        ex.printStackTrace();
                    }

                }
            }).start();

//
        }

        return START_REDELIVER_INTENT;
    }

}
