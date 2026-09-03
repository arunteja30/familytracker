package com.mat.familytracker.gpstracker;

import java.util.ArrayList;
import java.util.Calendar;
import java.util.List;

import android.location.Location;
import android.util.Pair;

/**
 * This class associates the location of the user to the current time to maintain
 * a history which can be later browsed to check how many meters were traveled in a
 * given interval of time and then make predictions about which mean of transport the
 * user is using.
 *
 * @version 1.0
 * @since 01.12.2016
 */
public class LocationHistory {

    public static final int TIME_INTERVAL = 1800000;            // time interval to consider (in milliseconds)
    public static final int DISTANCE_TRAVELED_THRESHOLD = 3000; // distance that must be traveled (in meters) within the
    // time interval previously defined for the user to be considered
    // as currently using a bus

    private List<Pair<Calendar, Location>> mHistory;

    public LocationHistory() {
        mHistory = new ArrayList<Pair<Calendar, Location>>();
    }

    /**
     * Add a new register to the history
     *
     * @param newLocation A new location of the user
     * @return If the operation was successful or not
     */
    public boolean addRegister(Location newLocation) {
        return mHistory.add(new Pair<Calendar, Location>(Calendar.getInstance(), newLocation));
    }

    /**
     * Clear the entire history
     */
    public void clear() {
        mHistory.clear();
    }

    /**
     * Get the distance (in meters) that the user traveled since the last 'x' milliseconds
     *
     * @param pastMilliseconds Beginning of time interval to be considered
     * @return The distance (in meters) that the user traveled within the time interval
     */
    int getDistanceTraveledSinceLast(int pastMilliseconds) {
        Calendar startTime = Calendar.getInstance();
        startTime.add(Calendar.MILLISECOND, -pastMilliseconds);
        int distanceTraveled = 0;
        for (int i = mHistory.size() - 1; i > 0; i--) {
            if (mHistory.get(i).first.before(startTime)) break;
            distanceTraveled += mHistory.get(i).second.distanceTo(mHistory.get(i - 1).second);
        }
        return distanceTraveled;
    }

    /**
     * Given the history of locations, predict weither the user is using a bus or not.
     * Currently, it only checks if the distance traveled in a given interval of time is
     * above the DISTANCE_TRAVELED_THRESHOLD constant.
     *
     * @return
     */
    public boolean isUsingBus() {
        return getDistanceTraveledSinceLast(TIME_INTERVAL) >= DISTANCE_TRAVELED_THRESHOLD;
    }

}