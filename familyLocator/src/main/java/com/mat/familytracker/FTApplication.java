package com.mat.familytracker;

import android.app.Application;
import android.content.Context;
import android.content.Intent;

import com.google.gson.Gson;
import com.mat.familytracker.domain.FamilyMemberModel;
import com.mat.familytracker.gpstracker.GPSTrackerService;
import com.mat.familytracker.utils.MySharedPreferences;

import java.util.Map;

public class FTApplication extends Application {


    private static Context context;
    private static Gson gson;
    private static Map contactsMap;
    private static FamilyMemberModel loggedInUserModel;

    public void onCreate() {
        super.onCreate();
        FTApplication.context = getApplicationContext();
    }

    public static Context getAppContext() {
        return FTApplication.context;
    }

    public static Map getContactsMap() {
        return contactsMap;
    }

    public static void setContactsMap(Map contacts) {
        contactsMap = contacts;
    }


    public static FamilyMemberModel getLoggedInUserModel() {
        String userDetails = MySharedPreferences.getInstance().getUserName(getAppContext());
        if (loggedInUserModel == null) {
            loggedInUserModel = getGson().fromJson(userDetails, FamilyMemberModel.class);
        }
        return loggedInUserModel;
    }


    private static Gson getGson() {
        if (gson == null) {
            gson = new Gson();
        }
        return gson;
    }


}
