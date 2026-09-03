package com.mat.familytracker.utils;

import android.app.Activity;
import android.content.Context;
import android.content.SharedPreferences;

import com.google.gson.Gson;
import com.google.gson.reflect.TypeToken;
import com.mat.familytracker.FTApplication;
import com.mat.familytracker.activity.FamilyMemberList;
import com.mat.familytracker.domain.FamilyMemberModel;
import com.mat.phonesecurity.common.MySecuritySharedPref;

import java.util.HashMap;
import java.util.Map;

public class MySharedPreferences extends MySecuritySharedPref {
    private static final MySharedPreferences ourInstance = new MySharedPreferences();

    public static MySharedPreferences getInstance() {
        return ourInstance;
    }


    public void saveFamilyName(Activity context, String familyName) {
        SharedPreferences sharedpreferences = context.getSharedPreferences(Constants.SHARED_PREF, Context.MODE_PRIVATE);
        SharedPreferences.Editor editor = sharedpreferences.edit();
        editor.putString(Constants.FAMILY_NAME, familyName);
        editor.commit();
    }

    public void saveFamilyNames(Activity context, FamilyMemberList familyNames) {
        SharedPreferences sharedpreferences = context.getSharedPreferences(Constants.SHARED_PREF, Context.MODE_PRIVATE);
        SharedPreferences.Editor editor = sharedpreferences.edit();
        editor.putString(Constants.FAMILY_NAMES_LIST, new Gson().toJson(familyNames));
        editor.commit();
    }

    public FamilyMemberList getFamilyNames(Context context) {
        SharedPreferences sharedpreferences = context.getSharedPreferences(Constants.SHARED_PREF, Context.MODE_PRIVATE);
        return new Gson().fromJson(sharedpreferences.getString(Constants.FAMILY_NAMES_LIST, null), FamilyMemberList.class);
    }

    public void firstLaunch(Activity context, boolean value) {
        SharedPreferences sharedpreferences = context.getSharedPreferences(Constants.SHARED_PREF, Context.MODE_PRIVATE);
        SharedPreferences.Editor editor = sharedpreferences.edit();
        editor.putBoolean(Constants.FIRST_LAUNCH, value);
        editor.commit();
    }

    public boolean isFirstLaunch(Activity context) {
        SharedPreferences sharedpreferences = context.getSharedPreferences(Constants.SHARED_PREF, Context.MODE_PRIVATE);
        return sharedpreferences.getBoolean(Constants.FIRST_LAUNCH, false);
    }

    public void saveUserName(Activity context, FamilyMemberModel userModel) {
        String familyModel = null;
        if (userModel != null) {
            familyModel = new Gson().toJson(userModel);
        }
        SharedPreferences sharedpreferences = context.getSharedPreferences(Constants.SHARED_PREF, Context.MODE_PRIVATE);
        SharedPreferences.Editor editor = sharedpreferences.edit();
        editor.putString(Constants.USERNAME, familyModel);
        editor.commit();
    }

    public String getUserName(Context context) {
        SharedPreferences sharedpreferences = context.getSharedPreferences(Constants.SHARED_PREF, Context.MODE_PRIVATE);
        return sharedpreferences.getString(Constants.USERNAME, null);
    }

    public String getFamilyName(Context context) {
        SharedPreferences sharedpreferences = context.getSharedPreferences(Constants.SHARED_PREF, Context.MODE_PRIVATE);
        return sharedpreferences.getString(Constants.FAMILY_NAME, null);
    }

    public void clearPreferences(Context context) {
        SharedPreferences sharedpreferences = context.getSharedPreferences(Constants.SHARED_PREF, Context.MODE_PRIVATE);
        SharedPreferences.Editor editor = sharedpreferences.edit();
        editor.clear();
        editor.commit();
    }

    public void setDateSmsSentDate(Context context, long time) {
        SharedPreferences sharedpreferences = context.getSharedPreferences(Constants.SHARED_PREF, Context.MODE_PRIVATE);
        SharedPreferences.Editor editor = sharedpreferences.edit();
        editor.putLong(Constants.LAST_SMS_SENT_TIME, time);
        editor.commit();
    }

    public long getDateSmsSentDate(Context context) {
        SharedPreferences sharedpreferences = context.getSharedPreferences(Constants.SHARED_PREF, Context.MODE_PRIVATE);
        return sharedpreferences.getLong(Constants.LAST_SMS_SENT_TIME, 0);
    }

    public String getPushNotificationToken(Context context) {
        SharedPreferences sharedpreferences = context.getSharedPreferences(Constants.SHARED_PREF, Context.MODE_PRIVATE);
        return sharedpreferences.getString(Constants.PUSH_NOTIFY_TOKEN, "");
    }

    public void savePushNotificationToken(Context context, String token) {
        SharedPreferences sharedpreferences = context.getSharedPreferences(Constants.SHARED_PREF, Context.MODE_PRIVATE);
        SharedPreferences.Editor editor = sharedpreferences.edit();
        editor.putString(Constants.PUSH_NOTIFY_TOKEN, token);
        editor.commit();
    }

    public void saveContacts(Context context, Map contactsMap) {
        FTApplication.setContactsMap(contactsMap);
        SharedPreferences sharedpreferences = context.getSharedPreferences(Constants.SHARED_PREF, Context.MODE_PRIVATE);
        SharedPreferences.Editor editor = sharedpreferences.edit();
        editor.putString(Constants.CONTACTS_LIST, new Gson().toJson(contactsMap));
        editor.commit();
    }

    public Map getContactsList(Context context) {
        SharedPreferences sharedpreferences = context.getSharedPreferences(Constants.SHARED_PREF, Context.MODE_PRIVATE);
        java.lang.reflect.Type type = new TypeToken<HashMap<String, String>>() {
        }.getType();
        Map<String, String> contactHashMap = new Gson().fromJson(sharedpreferences.getString(Constants.CONTACTS_LIST, null), type);
        return contactHashMap;
    }


}
