package com.mat.familytracker.domain;

public class RegistrationModel {

    String phoneNumber;
    String name;
    String UID;

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public String getUID() {
        return UID;
    }

    public void setUID(String UID) {
        this.UID = UID;
    }


    public RegistrationModel(String phoneNumber,String name,String uid) {
        this.phoneNumber = phoneNumber;
        this.name = name;
        this.UID = uid;
    }

    public String getPhoneNumber() {
        return phoneNumber;
    }

    public void setPhoneNumber(String phoneNumber) {
        this.phoneNumber = phoneNumber;
    }

}
