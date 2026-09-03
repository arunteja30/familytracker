package com.mat.familytracker.activity;

import com.mat.familytracker.domain.FamilyMemberModel;

import java.io.Serializable;
import java.util.ArrayList;

public class FamilyMemberList implements Serializable {
    ArrayList<FamilyMemberModel> familyMembersList;

    public ArrayList<FamilyMemberModel> getFamilyMembersList() {
        return familyMembersList;
    }

    public void setFamilyMembersList(ArrayList<FamilyMemberModel> familyMembersList) {
        this.familyMembersList = familyMembersList;
    }
}
