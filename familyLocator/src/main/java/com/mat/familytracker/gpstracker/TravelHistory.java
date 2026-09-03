package com.mat.familytracker.gpstracker;

import java.util.Calendar;

import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.database.sqlite.SQLiteOpenHelper;
import android.util.Log;

/**
 * This class is responsible for establishing the connection with the database,
 * keeping the history of dates that the user picked a bus.
 *
 * @version 1.0
 * @since 01.13.2016
 */
public class TravelHistory extends SQLiteOpenHelper {

    public static final int REGISTER_TIME_THRESHOLD = 1800000; // time (in milliseconds) that must be elapsed between the last bus
    // event to a new event be inserted
    private static final String DATABASE_NAME = "bus.db";
    private static final int DATABASE_VERSION = 1;
    private static final String TABLE_BUS_REGISTER = "bus";

    private SQLiteDatabase mDatabase;

    public TravelHistory(Context context) {
        super(context, DATABASE_NAME, null, DATABASE_VERSION);
        mDatabase = getWritableDatabase();
    }

    /**
     * Get the last bus register
     *
     * @return The time (in milliseconds) that the user last picked a bus up
     */
    private long getLastRegister() {
        String query = "SELECT BUS_TIME FROM " + TABLE_BUS_REGISTER + " ORDER BY BUS_TIME DESC LIMIT 1";
        Cursor cursor = mDatabase.rawQuery(query, null);
        if (cursor.moveToFirst()) {
            return cursor.getLong(0);
        } else {
            return -1;
        }
    }

    /**
     * Add a new bus register to the database
     *
     * @return If the operation was successful or not
     */
    public boolean addRegister() {
        long lastRegister = getLastRegister();
        long currentTime = Calendar.getInstance().getTimeInMillis();
        if (lastRegister < 0 || currentTime - lastRegister > REGISTER_TIME_THRESHOLD) {
            ContentValues values = new ContentValues();
            values.put("BUS_TIME", currentTime);
            mDatabase.insert(TABLE_BUS_REGISTER, null, values);
            return true;
        }
        return false;
    }

    @Override
    public void onCreate(SQLiteDatabase database) {
        database.execSQL("CREATE TABLE IF NOT EXISTS " + TABLE_BUS_REGISTER + "(BUS_TIME INTEGER PRIMARY KEY);");
    }

    @Override
    public void onUpgrade(SQLiteDatabase database, int oldVersion, int newVersion) {
        Log.w(TravelHistory.class.getName(), "Upgrading database from version " + oldVersion + " to " + newVersion + "...");
        database.execSQL("DROP TABLE IF EXISTS " + TABLE_BUS_REGISTER);
        onCreate(database);
    }

    /**
     * Close connection to database.
     */
    public void close() {
        mDatabase.close();
    }

}
