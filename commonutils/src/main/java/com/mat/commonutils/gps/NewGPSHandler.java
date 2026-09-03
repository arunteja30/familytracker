//package com.mat.commonutils.gps;
//
//import android.content.Context;
//
//import com.example.easywaylocation.EasyWayLocation;
//import com.example.easywaylocation.Listener;
//import com.example.easywaylocation.draw_path.DirectionUtil;
//import com.google.android.gms.location.LocationRequest;
//import com.mat.commonutils.commonutils.CommonListener;
//
//public class NewGPSHandler {
//
//
//    public EasyWayLocation getLocationManger() {
//        return easyWayLocation;
//    }
//
//    public void setEasyWayLocation(EasyWayLocation easyWayLocation) {
//        this.easyWayLocation = easyWayLocation;
//    }
//
//    private EasyWayLocation easyWayLocation;
//
//    public void initGps(Context context, Listener listener) {
//        if (easyWayLocation == null) {
//            easyWayLocation = new EasyWayLocation(context, true, false, listener);
//        }
//        setEasyWayLocation(easyWayLocation);
//
//    }
//
//
//    public void stopLocationUpdates() {
//        if (easyWayLocation != null) {
//            easyWayLocation.endUpdates();
//        }
//    }
//
//    public void startUpdates() {
//        if (easyWayLocation != null) {
//            easyWayLocation.startLocation();
//        }
//    }
//
//    public void initLocation(Context context, Listener listener) {
//        LocationRequest request = new LocationRequest();
//        request.setInterval(10000);
//        request.setPriority(LocationRequest.PRIORITY_BALANCED_POWER_ACCURACY);
//        easyWayLocation = new EasyWayLocation(context, request, false, false, listener);
//    }
//
//    public double getDistance(double startLatitude, double startLongitude, double endLatitude, double endLongitude) {
//        if (easyWayLocation != null) {
//            return easyWayLocation.calculateDistance(startLatitude, startLongitude, endLatitude, endLongitude);
//        } else {
//            return 0;
//        }
//    }
//
//    public double getDistanceByPoints(double startLatitude, double startLongitude, double endLatitude, double endLongitude) {
//        EasyWayLocation.Point startPoint = new EasyWayLocation.Point(startLatitude, startLongitude);
//        EasyWayLocation.Point endPoint = new EasyWayLocation.Point(endLatitude, endLongitude);
//        if (easyWayLocation != null) {
//            return easyWayLocation.calculateDistance(startPoint, endPoint);
//        } else {
//            return 0;
//        }
//    }
//
//    public void getAddressFromLocation(Context context, double latitude, double longitude, CommonListener listerner) {
//        new GetAddressFromLocation(context, latitude, longitude, listerner).execute();
//    }
//}
