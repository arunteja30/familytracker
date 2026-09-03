package com.mat.familytracker.domain;

import com.mat.familytracker.FTApplication;

import java.io.Serializable;
import java.util.Map;

public class FamilyMemberModel implements Serializable {


    String name;
    String mobile;
    String relationship;
    String memberId;
    String familyName;
    Map contactsMap;
    String pushNofityToken;
    String adminName;
    String password;
    String message;
    String gpsInfo;
    String uid;

    boolean isRegistered;

    public boolean isRegistered() {
        return isRegistered;
    }

    public void setRegistered(boolean registered) {
        isRegistered = registered;
    }

    public String getUid() {
        return uid;
    }

    public void setUid(String uid) {
        this.uid = uid;
    }

    public String getPushNofityToken() {
        return pushNofityToken;
    }

    public void setPushNofityToken(String pushNofityToken) {
        this.pushNofityToken = pushNofityToken;
    }


    public String getAdminName() {
        return adminName;
    }

    public void setAdminName(String adminName) {
        this.adminName = adminName;
    }


    public String getGpsInfo() {
        return gpsInfo;
    }

    public void setGpsInfo(String gpsInfo) {
        this.gpsInfo = gpsInfo;
    }


    public String getPassword() {
        return password;
    }

    public void setPassword(String password) {
        this.password = password;
    }

    public String getMessage() {
        return message;
    }

    public void setMessage(String message) {
        this.message = message;
    }

    public String getFamilyName() {
        return familyName;
    }

    public void setFamilyName(String familyName) {
        this.familyName = familyName;
    }


    public String getMemberId() {
        return memberId;
    }

    public void setMemberId(String memberId) {
        this.memberId = memberId;
    }


    public String getName() {

        return getUserName();
    }

    public void setName(String name) {
        this.name = name;
    }

    public String getMobile() {
        return mobile;
    }

    public void setMobile(String mobile) {
        this.mobile = mobile;
    }

    public String getRelationship() {
        return relationship;
    }

    public void setRelationship(String relationship) {
        this.relationship = relationship;
    }


    private String getUserName() {

        if (contactsMap == null) {
            contactsMap = FTApplication.getContactsMap();
        }
        if (contactsMap != null && contactsMap.get(getMobile()) != null) {
            return contactsMap.get(getMobile()).toString();
        }

        return name;
    }
}
