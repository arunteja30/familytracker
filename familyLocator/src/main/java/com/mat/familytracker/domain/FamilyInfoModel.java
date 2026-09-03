package com.mat.familytracker.domain;

import com.mat.familytracker.FTApplication;
import com.mat.familytracker.activity.FamilyMemberList;

import java.util.ArrayList;
import java.util.List;

public class FamilyInfoModel {


    String familyName;

    public String getPhoneNumber() {
        return phoneNumber;
    }


    String phoneNumber = FTApplication.getLoggedInUserModel().getMobile();


    public FamilyInfoModel(String familyName) {
        this.familyName = familyName;
    }

    public String getFamilyName() {
        return familyName;
    }

    public void setFamilyName(String familyName) {
        this.familyName = familyName;
    }
//    FamilyMemberList familyMemberList;
//    public FamilyMemberList getFamilyMemberList() {
//        return familyMemberList;
//    }
//
//    public void setFamilyMemberList(FamilyMemberList familyMemberList) {
//        this.familyMemberList = familyMemberList;
//    }

}
