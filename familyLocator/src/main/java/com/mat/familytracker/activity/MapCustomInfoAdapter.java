package com.mat.familytracker.activity;

import android.app.Activity;
import android.content.Context;
import android.view.View;
import android.widget.ProgressBar;
import android.widget.TextView;

import com.google.android.gms.maps.GoogleMap;
import com.google.android.gms.maps.model.Marker;
import com.google.android.gms.maps.model.MarkerOptions;
import com.mat.familytracker.R;
import com.mat.familytracker.domain.LocationDetailsModel;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.HashMap;

public class MapCustomInfoAdapter implements GoogleMap.InfoWindowAdapter {
    private Context context;
    private LocationDetailsModel mLocationDetails;
    private MarkerOptions mMarkerOptions;
    HashMap<Marker, LocationDetailsModel> mUsersPoints;

    public MapCustomInfoAdapter(Context ctx, LocationDetailsModel locationDetailsModel) {
        context = ctx;
        this.mLocationDetails = locationDetailsModel;
    }

    public MapCustomInfoAdapter(Context ctx, HashMap<Marker, LocationDetailsModel> markerPoints) {
        context = ctx;
        this.mUsersPoints = markerPoints;
    }

    @Override
    public View getInfoWindow(Marker marker) {
        return null;
    }

    @Override
    public View getInfoContents(final Marker marker) {
        View view = ((Activity) context).getLayoutInflater()
                .inflate(R.layout.map_custom_infowindow, null);

        TextView name_tv = view.findViewById(R.id.map_info_item_name);
        final TextView details_tv = view.findViewById(R.id.map_info_item_address);
        TextView details_date = view.findViewById(R.id.map_info_item_date);
        TextView battery = view.findViewById(R.id.map_info_item_battery);
        final ProgressBar progressBar = view.findViewById(R.id.map_info_item_progress);
        name_tv.setText(marker.getTitle());
        details_tv.setText(marker.getSnippet());
        if (mUsersPoints != null && !mUsersPoints.isEmpty()) {
            mLocationDetails = mUsersPoints.get(marker);
        }
        if (mLocationDetails != null) {
            String dateString = String.valueOf((mLocationDetails.getDate()));
            String time = new SimpleDateFormat("dd-MM-yyyy hh:mm:ss a").format(new Date(mLocationDetails.getTimeStamp()));
            if (time != null && !time.isEmpty()) {
                details_date.setText("Date : " + time);
            }
            battery.setText("Battery : " + mLocationDetails.getBatteryPercentage() + "%");
            if (dateString != null && !dateString.isEmpty() && !dateString.equalsIgnoreCase("null")) {
                details_date.setText("Date : " + dateString);
            }
        }
//        progressBar.setVisibility(View.VISIBLE);


//        InfoWindowData infoWindowData = (InfoWindowData) marker.getTag();


        return view;
    }


}
