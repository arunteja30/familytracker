package com.mat.commonutils.gps;

import android.content.Context;
import android.location.Address;
import android.location.Geocoder;
import android.location.Location;
import android.os.AsyncTask;

import com.mat.commonutils.commonutils.CommonListener;

import java.util.List;
import java.util.Locale;


public class GetAddressFromLocation extends AsyncTask<Location, Void, String> {
    private Context mContext;
    private CommonListener mListner;
    private double mLatitude, mLongitude;

    public GetAddressFromLocation(Context context, double latitude, double longitude, CommonListener listener) {
        this.mContext = context;
        this.mListner = listener;
        this.mLatitude = latitude;
        this.mLongitude = longitude;
    }

    @Override
    protected void onPreExecute() {
        super.onPreExecute();
//        CommonUtils.getInstance().showProgressDialog(mContext);
    }

    @Override
    protected String doInBackground(Location... params) {
        Geocoder geocoder = new Geocoder(mContext, Locale.getDefault());

        List<Address> addresses = null;
        try {
            addresses = geocoder.getFromLocation(mLatitude,
                    mLongitude, 1);
        } catch (Exception e1) {
            e1.printStackTrace();
            return "No address found " + "\n current Latitude :" + mLatitude + "\n Longitude :" + mLongitude;
        }
        if (addresses != null && addresses.size() > 0) {
            Address address = addresses.get(0);
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < 1; i++) {
                sb.append(address.getAddressLine(i)).append("\n");
            }
            sb.append(address.getLocality() + " ");
            sb.append(address.getPostalCode() + " ");
            sb.append(address.getCountryName() + " ");
            sb.append("\n Latitude :" + mLatitude + "\n Longitude :" + mLongitude);
            return sb.toString();
        } else {
            return "No address found " + "\n current Latitude :" + mLatitude + "\n Longitude :" + mLongitude;
        }

    }

    @Override
    protected void onPostExecute(String address) {
//        Toast.makeText(mContext, address, Toast.LENGTH_SHORT).show();
        System.out.println("arun.......! address : " + address);
        System.out.println("arun.......! latitude : " + mLatitude + " longitude : " + mLongitude);
//        CommonUtils.getInstance().closeProgressDialog();
        if (mListner != null) {
            mListner.onTaskCompleted(address);
        }
    }
}
