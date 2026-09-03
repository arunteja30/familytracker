package com.mat.phonesecurity.model;

public class IntruderModel {

    String date;
    String imagePath;
    private boolean isSelected = false;

    public IntruderModel(String date, String path) {
        this.date = date;
        this.imagePath = path;
    }

    public boolean isSelected() {
        return isSelected;
    }

    public void setSelected(boolean selected) {
        isSelected = selected;
    }

    public String getDate() {
        return date;
    }

    public void setDate(String date) {
        this.date = date;
    }

    public String getImagePath() {
        return imagePath;
    }

    public void setImagePath(String imagePath) {
        this.imagePath = imagePath;
    }

}
