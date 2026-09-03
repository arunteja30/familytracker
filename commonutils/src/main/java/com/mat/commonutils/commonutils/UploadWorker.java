package com.mat.commonutils.commonutils;

import android.content.Context;
import androidx.annotation.NonNull;

import androidx.work.Worker;
import androidx.work.WorkerParameters;

public class UploadWorker extends Worker {

    Context mContext;
    String mobile;
    String filePath;

    public UploadWorker(@NonNull Context context, @NonNull WorkerParameters workerParams) {
        super(context, workerParams);
        this.mContext = context;
    }


    @Override
    public Result doWork() {
        String mobile = getInputData().getString("mobile");
        String filePath = getInputData().getString("filePath");
//        CommonUtils.getInstance().uploadAFile(getApplicationContext(), mobile, Uri.parse(filePath));
        return null;
    }
}
