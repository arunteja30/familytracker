package com.mat.commonutils.roomDB;


import androidx.room.ColumnInfo;
import androidx.room.Entity;
import androidx.room.Ignore;
import androidx.room.PrimaryKey;

@Entity(tableName = "Logs_tbl")
public class LogsEntity {

    @PrimaryKey(autoGenerate = true)
    @ColumnInfo(name = "Log_Id")
    private int id;

    @ColumnInfo(name = "latitude")
    private Double latitude;

    @ColumnInfo(name = "longitude")
    private Double longitude;

    @ColumnInfo(name = "DateTime")
    private String DateTime;

    @ColumnInfo(name = "Location_Status")
    private String Location_Status;

    @ColumnInfo(name = "address")
    private String address;

    @ColumnInfo(name = "userId")
    private String userId;

    @Ignore
    public LogsEntity(int id, Double latitude, Double longitude, String DateTime, String Location_Status) {
        this.id = id;
        this.latitude = latitude;
        this.longitude = longitude;
        this.DateTime = DateTime;
        this.Location_Status = Location_Status;
    }


    public LogsEntity(Double latitude, Double longitude, String DateTime, String Location_Status, String address, String userId) {
        this.latitude = latitude;
        this.longitude = longitude;
        this.DateTime = DateTime;
        this.address = address;
        this.userId = userId;
        this.Location_Status = Location_Status;
    }

    public String getLocation_Status() {
        return Location_Status;
    }

    public void setLocation_Status(String location_Status) {
        Location_Status = location_Status;
    }

    public String getAddress() {
        return address;
    }

    public void setAddress(String address) {
        this.address = address;
    }

    public int getId() {
        return id;
    }

    public void setId(int id) {
        this.id = id;
    }

    public Double getLatitude() {
        return latitude;
    }

    public void setLatitude(Double latitude) {
        this.latitude = latitude;
    }

    public Double getLongitude() {
        return longitude;
    }

    public void setLongitude(Double longitude) {
        this.longitude = longitude;
    }

    public String getDateTime() {
        return DateTime;
    }

    public void setDateTime(String dateTime) {
        DateTime = dateTime;
    }

    public String getUserId() {
        return userId;
    }

    public void setUserId(String userId) {
        this.userId = userId;
    }
}
