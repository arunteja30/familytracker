package com.mat.commonutils.gps;

import android.location.Location;

public interface LocationTrackerListener {
    /**
     * Inform a location change
     *
     * @param oldLocation The last known location previously. Return null in case of a newly registered location provider.
     * @param newLocation The new known location apart a certain distance from old location (check "getMinDistanceChangeForUpdates" on LocationTracker).
     */
    public void onLocationChange(Location oldLocation, Location newLocation);
}
