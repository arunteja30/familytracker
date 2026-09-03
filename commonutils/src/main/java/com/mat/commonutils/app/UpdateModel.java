package com.mat.commonutils.app;

public class UpdateModel {
    private String url;
    private String message;
    private String mandatory;
    private String title;
    private float version;
    private boolean isDialogCancelable;
    private String notificationMessage;

    public String getNotificationMessage() {
        return notificationMessage;
    }

    public void setNotificationMessage(String notificationMessage) {
        this.notificationMessage = notificationMessage;
    }

    public float getVersion() {
        return version;
    }

    public void setVersion(float version) {
        this.version = version;
    }

    public String getTitle() {
        return title;
    }

    public void setTitle(String title) {
        this.title = title;
    }

    public boolean isDialogCancelable() {
        return isDialogCancelable;
    }

    public void setDialogCancelable(boolean dialogCancelable) {
        isDialogCancelable = dialogCancelable;
    }


    public String getUrl() {
        return url;
    }

    public void setUrl(String url) {
        this.url = url;
    }

    public String getMessage() {
        return message;
    }

    public void setMessage(String message) {
        this.message = message;
    }

    public String getMandatory() {
        return mandatory;
    }

    public void setMandatory(String mandatory) {
        this.mandatory = mandatory;
    }

}
