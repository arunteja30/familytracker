package com.mat.familytracker.domain;

import com.google.firebase.database.IgnoreExtraProperties;
import java.io.Serializable;

@IgnoreExtraProperties
public class LocationDetailsModel implements Serializable {
    private double latitude;
    private double longitude;
    private long timeStamp;
    private String date;
    private int batteryPercentage;
    private String address;
    private String message;
    private String gpsStatus;

    public LocationDetailsModel() {
    }

    public String getGpsStatus() {
        return gpsStatus;
    }

    public void setGpsStatus(String gpsStatus) {
        this.gpsStatus = gpsStatus;
    }

    public String getMessage() {
        return message;
    }

    public void setMessage(String message) {
        this.message = message;
    }

    public int getBatteryPercentage() {
        return batteryPercentage;
    }

    public void setBatteryPercentage(Object batteryPercentage) {
        if (batteryPercentage == null) {
            this.batteryPercentage = 0;
        } else if (batteryPercentage instanceof Number) {
            this.batteryPercentage = ((Number) batteryPercentage).intValue();
        } else {
            try {
                String val = String.valueOf(batteryPercentage).replace("%", "").trim();
                this.batteryPercentage = Integer.parseInt(val);
            } catch (Exception e) {
                this.batteryPercentage = 0;
            }
        }
    }

    public String getDate() {
        return date;
    }

    public void setDate(String date) {
        this.date = date;
    }

    public double getLatitude() {
        return latitude;
    }

    public void setLatitude(Object latitude) {
        if (latitude == null) {
            this.latitude = 0.0;
        } else if (latitude instanceof Number) {
            this.latitude = ((Number) latitude).doubleValue();
        } else {
            try {
                this.latitude = Double.parseDouble(String.valueOf(latitude).trim());
            } catch (Exception e) {
                this.latitude = 0.0;
            }
        }
    }

    public double getLongitude() {
        return longitude;
    }

    public void setLongitude(Object longitude) {
        if (longitude == null) {
            this.longitude = 0.0;
        } else if (longitude instanceof Number) {
            this.longitude = ((Number) longitude).doubleValue();
        } else {
            try {
                this.longitude = Double.parseDouble(String.valueOf(longitude).trim());
            } catch (Exception e) {
                this.longitude = 0.0;
            }
        }
    }

    public long getTimeStamp() {
        return timeStamp;
    }

    public void setTimeStamp(Object timeStamp) {
        if (timeStamp == null) {
            this.timeStamp = 0L;
        } else if (timeStamp instanceof Number) {
            this.timeStamp = ((Number) timeStamp).longValue();
        } else {
            try {
                this.timeStamp = Long.parseLong(String.valueOf(timeStamp).trim());
            } catch (Exception e) {
                this.timeStamp = 0L;
            }
        }
    }

    public String getAddress() {
        return address;
    }

    public void setAddress(String address) {
        this.address = address;
    }
}
