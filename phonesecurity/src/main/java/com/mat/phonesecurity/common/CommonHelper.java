package com.mat.phonesecurity.common;

import android.content.Context;
import android.os.Environment;

import java.io.File;

public class CommonHelper {
    private File getAbsoluteFile(String relativePath, Context context) {
        if (Environment.MEDIA_MOUNTED.equals(Environment.getExternalStorageState())) {
            return new File(context.getExternalFilesDir(null), relativePath);
        } else {
            return new File(context.getFilesDir(), relativePath);
        }
    }
}
