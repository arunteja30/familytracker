package com.mat.commonutils.camera;

import androidx.annotation.NonNull;

import com.androidhiddencamera.CameraError;

import java.io.File;

/**
 * Created by Keval on 14-Oct-16.
 *
 * @author {@link 'https://github.com/kevalpatel2106'}
 */
interface CameraCallbacks {

    void onImageCapture(@NonNull File imageFile);

    void onCameraError(@CameraError.CameraErrorCodes int errorCode);
}
