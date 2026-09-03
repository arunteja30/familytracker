package com.mat.commonutils.gps;

import android.location.Location;

/**
 * Created by RajeshGorantla on 3/8/2017.
 */

public interface GPSTrackerListener {

    public void onLocationFetched(Location location);
}
