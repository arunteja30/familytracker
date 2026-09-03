package com.mat.familytracker.utils;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Bundle;
import android.telephony.SmsMessage;

import com.mat.familytracker.gpstracker.GPSHandler;

public class SmsReceiver extends BroadcastReceiver {
    boolean nameCheck;
    String abcd;
    private String mSMSReceivedAction = "android.provider.Telephony.SMS_RECEIVED";

    @Override
    public void onReceive(Context context, Intent intent) {
        Bundle data = intent.getExtras();
        System.out.println("@@ check :" );
        String action = intent.getAction();
        if (action.equalsIgnoreCase(mSMSReceivedAction)) {
            Object[] pdus = (Object[]) data.get("pdus");
            for (int i = 0; i < pdus.length; i++) {
                SmsMessage smsMessage = SmsMessage.createFromPdu((byte[]) pdus[i]);
                String sender = smsMessage.getDisplayOriginatingAddress();
//                nameCheck = sender.contains(Constants.SMS_SENDER);  //Just to fetch otp sent from
                if (smsMessage != null && smsMessage.getDisplayMessageBody() != null) {
                    nameCheck = smsMessage.getDisplayMessageBody().contains(Constants.SMS_CONTENT);  //Just to fetch otp sent from
                }
                String messageBody = smsMessage.getMessageBody();
                System.out.println("@@ message body :" + messageBody);
                //Pass on the text to our listener.
                if (nameCheck) {
                    GPSHandler.getInstance().startGPSTracker(context,true);
                } else {
                    System.out.println("@@ message body :" + "not Find Buddy msg");
                }
            }
        }
    }

}
