package com.mat.workmanager;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.os.Bundle;
import androidx.appcompat.app.AppCompatActivity;
import android.view.View;
import android.widget.Button;
import android.widget.ImageView;

import androidx.work.Constraints;
import androidx.work.Data;
import androidx.work.NetworkType;

import java.util.ArrayList;
import java.util.TreeMap;

public class MainActivity extends AppCompatActivity implements PictureCapturingListener {

    public static final String KEY_TASK_DESC = "key_task_desc";
    ImageView front, back;
    private APictureCapturingService pictureTake;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        Data data = new Data.Builder()
                .putString(KEY_TASK_DESC, "Hey I am sending the work data")
                .build();
        Constraints constraints = new Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build();
        back = (ImageView) findViewById(R.id.backIV);
        front = (ImageView) findViewById(R.id.frontIV);
        final Button btn = (Button) findViewById(R.id.startCaptureBtn);
        pictureTake = PictureCapturingServiceImpl.getInstance(MainActivity.this);
//        final OneTimeWorkRequest request = new OneTimeWorkRequest.Builder(MyWorker.class)
//                .setInputData(data)
//                .setConstraints(constraints)
//                .build();
//        final PeriodicWorkRequest periodicWorkRequest =
//                new PeriodicWorkRequest.Builder(MyContinuosWork.class, 2, TimeUnit.MINUTES)
//                        .addTag("periodic-work-request")
//                        .build();

        btn.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View view) {
//                WorkManager.getInstance().enqueue(request);
//                WorkManager.getInstance().enqueue(periodicWorkRequest);
                pictureTake.startCapturing(MainActivity.this);

            }
        });


//        WorkManager.getInstance().getWorkInfoByIdLiveData(periodicWorkRequest.getId())
//                .observe(this, new Observer<WorkInfo>() {
//                    @Override
//                    public void onChanged(@Nullable WorkInfo workInfo) {
//
//                        if (workInfo != null) {
//
//                            if (workInfo.getState().isFinished()) {
//
//                                Data data = workInfo.getOutputData();
//
//                                String output = data.getString(MyWorker.KEY_TASK_OUTPUT);
//
//                                textView.append(output + "\n");
//                            }
//
//                            String status = workInfo.getState().name();
//                            textView.append(status + "\n");
//                        }
//                    }
//                });

    }

    @Override
    public void onCaptureDone(final String pictureUrl, final byte[] pictureData) {
        if (pictureData != null && pictureUrl != null) {
            runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    final Bitmap bitmap = BitmapFactory.decodeByteArray(pictureData, 0, pictureData.length);
                    final int nh = (int) (bitmap.getHeight() * (512.0 / bitmap.getWidth()));
                    final Bitmap scaled = Bitmap.createScaledBitmap(bitmap, 512, nh, true);
                    if (pictureUrl.contains("SPY_0")) {
                        back.setImageBitmap(scaled);
                    } else {
                        front.setImageBitmap(scaled);
                    }
                }
            });
        }

    }

    @Override
    public void onDoneCapturingAllPhotos(TreeMap<String, byte[]> picturesTaken) {
        ArrayList attachments = new ArrayList();
    }
}