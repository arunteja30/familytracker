package com.mat.phonesecurity.common;

import android.content.Context;
import android.content.SharedPreferences;

import com.mat.commonutils.commonutils.Constants;

public class MySecuritySharedPref {

    private static final MySecuritySharedPref ourInstance = new MySecuritySharedPref();

    public static MySecuritySharedPref getInstance() {
        return ourInstance;
    }


    public void saveEmailId(Context context, String email) {
        SharedPreferences sharedpreferences = context.getSharedPreferences(Constants.SHARED_PREF, Context.MODE_PRIVATE);
        SharedPreferences.Editor editor = sharedpreferences.edit();
        editor.putString(Constants.ALERT_EMAIL_ID, email);
        editor.commit();
    }

    public String getAlertEmailId(Context context) {
        SharedPreferences sharedpreferences = context.getSharedPreferences(Constants.SHARED_PREF, Context.MODE_PRIVATE);
        return sharedpreferences.getString(Constants.ALERT_EMAIL_ID, "");
    }
}
