package com.mat.commonutils.commonutils;

import android.Manifest;
import android.app.Activity;
import android.app.Dialog;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.content.res.TypedArray;
import android.database.Cursor;
import android.graphics.BitmapFactory;
import android.graphics.Color;
import android.net.Uri;
import android.os.BatteryManager;
import android.os.Build;
import android.os.Environment;
import android.provider.ContactsContract;
import android.provider.Settings;
import androidx.annotation.NonNull;
import androidx.core.app.NotificationCompat;
import androidx.appcompat.app.AlertDialog;
import android.util.Log;
import android.util.TypedValue;
import android.view.View;
import android.view.Window;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.Toast;

import com.androidhiddencamera.HiddenCameraUtils;
import com.google.android.gms.tasks.OnFailureListener;
import com.google.android.gms.tasks.OnSuccessListener;
import com.google.firebase.storage.FirebaseStorage;
import com.google.firebase.storage.OnProgressListener;
import com.google.firebase.storage.StorageReference;
import com.google.firebase.storage.UploadTask;
import com.karumi.dexter.Dexter;
import com.karumi.dexter.MultiplePermissionsReport;
import com.karumi.dexter.PermissionToken;
import com.karumi.dexter.listener.DexterError;
import com.karumi.dexter.listener.PermissionRequest;
import com.karumi.dexter.listener.PermissionRequestErrorListener;
import com.karumi.dexter.listener.multi.MultiplePermissionsListener;
import com.mat.commonutils.R;
import com.mat.commonutils.dialogs.FlatDialog;

import java.io.File;
import java.text.SimpleDateFormat;
import java.util.Calendar;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Pattern;

import static android.content.Context.BATTERY_SERVICE;
import static com.android.volley.VolleyLog.TAG;

public class CommonUtils {
    private static final CommonUtils ourInstance = new CommonUtils();
    private AlertDialog progressDialog;
    private NotificationManager mNotificationManager;
    private NotificationCompat.Builder mBuilder;
    private boolean isFirstNotification;
    Map<String, String> namePhoneMap = new HashMap<String, String>();

    private CommonUtils() {
    }

    public static CommonUtils getInstance() {
        return ourInstance;
    }

    public void showProgressDialog(Context context) {
        try {
            progressDialog = null;
            if (progressDialog == null) {
                progressDialog = getProgressDialog(context);
            }
            if (progressDialog != null && !progressDialog.isShowing() && !((Activity) context).isFinishing()) {
                progressDialog.show();
            }
        } catch (Exception ex) {
            ex.printStackTrace();
        }

    }

    public void closeProgressDialog() {
        try {
            if (progressDialog != null && progressDialog.isShowing()) {
                progressDialog.dismiss();
            }
        } catch (Exception ex) {
            ex.printStackTrace();
            progressDialog.dismiss();
        }

    }

    private AlertDialog getProgressDialog(Context context) {
        String message = "Loading please wait..";
        String title = "";
        final ProgressBar progressBar = new ProgressBar(
                context,
                null,
                android.R.attr.progressBarStyleHorizontal);

        progressBar.setLayoutParams(
                new LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.MATCH_PARENT,
                        LinearLayout.LayoutParams.WRAP_CONTENT));

        progressBar.setIndeterminate(true);

        final LinearLayout container =
                new LinearLayout(context);

        container.addView(progressBar);

        int padding =
                getDialogPadding(context);

        container.setPadding(
                padding, (message == null ? padding : 0), padding, 0);

        AlertDialog.Builder builder =
                new AlertDialog.Builder(context).
                        setTitle(title).
                        setMessage(message).
                        setView(container);
        builder.setCancelable(false);
        return builder.create();
    }

    private int getDialogPadding(Context context) {
        int[] sizeAttr = new int[]{R.attr.dialogPreferredPadding};
        TypedArray a = context.obtainStyledAttributes((new TypedValue()).data, sizeAttr);
        int size = a.getDimensionPixelSize(0, -1);
        a.recycle();

        return size;
    }

    public String getCurrentTime() {
        Calendar cal = Calendar.getInstance();
        SimpleDateFormat sdf = new SimpleDateFormat(Constants.DATE_FORMAT);
        String strDate = sdf.format(cal.getTime());
        return strDate;
    }

    public String getCurrentTime(long millisec) {
        SimpleDateFormat sdf = new SimpleDateFormat(Constants.DATE_FORMAT);
        String strDate = sdf.format(millisec);
        return strDate;
    }

    public int getBatteryPercentage(Context context) {

        if (Build.VERSION.SDK_INT >= 21) {

            BatteryManager bm = (BatteryManager) context.getSystemService(BATTERY_SERVICE);
            return bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY);

        } else {

            IntentFilter iFilter = new IntentFilter(Intent.ACTION_BATTERY_CHANGED);
            Intent batteryStatus = context.registerReceiver(null, iFilter);

            int level = batteryStatus != null ? batteryStatus.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) : -1;
            int scale = batteryStatus != null ? batteryStatus.getIntExtra(BatteryManager.EXTRA_SCALE, -1) : -1;

            double batteryPct = level / (double) scale;

            return (int) (batteryPct * 100);
        }
    }

    public Notification getNotification(Context context) {
        String NOTIFICATION_CHANNEL_ID = "Location Updates";
        String channelName = "Background Service";

        mNotificationManager = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel chan = new NotificationChannel(NOTIFICATION_CHANNEL_ID, channelName, NotificationManager.IMPORTANCE_NONE);
            chan.setLightColor(Color.BLUE);
            chan.setLockscreenVisibility(Notification.VISIBILITY_SECRET);
            assert mNotificationManager != null;
            mNotificationManager.createNotificationChannel(chan);
        }
        mBuilder = new NotificationCompat.Builder(context, NOTIFICATION_CHANNEL_ID);
        Notification notification = mBuilder.setOngoing(true)
                .setSmallIcon(R.drawable.ic_launcher_background)
                .setOnlyAlertOnce(true)
                .setContentTitle(context.getResources().getString(R.string.app_name) + context.getString(R.string.isRunning))
                .setPriority(NotificationManager.IMPORTANCE_MIN)
                .setCategory(Notification.CATEGORY_SERVICE)
                .setLargeIcon(BitmapFactory.decodeResource(context.getResources(), R.drawable.ic_launcher_background))
                .setColor(Color.WHITE)
                .setColorized(true)
                .setContentText("Your Family is with you")
                .build();
        isFirstNotification = true;

//        PendingIntent contentIntent = PendingIntent.getActivity(context, 0,
//                new Intent(context, AddFamilyActivity.class), PendingIntent.FLAG_UPDATE_CURRENT);
//        mBuilder.setContentIntent(contentIntent);
        return notification;
    }

    public void hideAppIcon(Context context, Class tClass) {
        PackageManager p = context.getPackageManager();
        ComponentName componentName = new ComponentName(context, tClass);
        p.setComponentEnabledSetting(componentName, PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP);
    }

    public void unHideAppIcon(Context context, Class tClass) {
        PackageManager p = context.getPackageManager();
        ComponentName componentName = new ComponentName(context, tClass);
        p.setComponentEnabledSetting(componentName, PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP);
    }

    public Dialog showFullScreenDialog(Context activity) {
        Dialog dialog = new Dialog(activity, android.R.style.Theme_Light);
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);
        return dialog;
    }

    public void checkPermissions(final Activity context, final CommonListener commonListener) {
        // below line is use to request
        // permission in the current activity.
        Dexter.withActivity(context)
                // below line is use to request the number of
                // permissions which are required in our app.
                .withPermissions(
                        // below is the list of permissions
                        Manifest.permission.ACCESS_FINE_LOCATION,
                        Manifest.permission.ACCESS_COARSE_LOCATION,
                        Manifest.permission.SEND_SMS,
                        Manifest.permission.WRITE_EXTERNAL_STORAGE,
                        Manifest.permission.READ_EXTERNAL_STORAGE,
                        Manifest.permission.CALL_PHONE,
                        Manifest.permission.CAMERA,
                        Manifest.permission.READ_CONTACTS)
                // after adding permissions we are
                // calling an with listener method.
                .withListener(new MultiplePermissionsListener() {
                    @Override
                    public void onPermissionsChecked(MultiplePermissionsReport multiplePermissionsReport) {
                        // this method is called when all permissions are granted
                        if (multiplePermissionsReport.areAllPermissionsGranted()) {
                            // do you work now
//                            Toast.makeText(AddFamilyActivity.this, "All the permissions are granted..", Toast.LENGTH_SHORT).show();
                            commonListener.onTaskCompleted("Allowed");
                        }
                        // check for permanent denial of any permission
                        if (multiplePermissionsReport.isAnyPermissionPermanentlyDenied()) {
                            // permission is denied permanently,
                            // we will show user a dialog message.
                            showSettingsDialog(context);
                        }

                    }

                    @Override
                    public void onPermissionRationaleShouldBeShown(List<PermissionRequest> list, PermissionToken permissionToken) {
                        // this method is called when user grants some
                        // permission and denies some of them.
                        permissionToken.continuePermissionRequest();
                        commonListener.onTaskCompleted("Denied");
                    }
                }).withErrorListener(new PermissionRequestErrorListener() {
            // this method is use to handle error
            // in runtime permissions
            @Override
            public void onError(DexterError error) {
                // we are displaying a toast message for error message.
                Toast.makeText(context, "Error in Granting Permissions! ", Toast.LENGTH_SHORT).show();
            }
        })
                // below line is use to run the permissions
                // on same thread and to check the permissions
                .onSameThread().check();
    }

    private void showSettingsDialog(final Activity activity) {
        // we are displaying an alert dialog for permissions
        AlertDialog.Builder builder = new AlertDialog.Builder(activity);

        // below line is the title
        // for our alert dialog.
        builder.setTitle("Need Permissions");

        // below line is our message for our dialog
        builder.setMessage("This app needs permission to use this feature. You can grant them in app settings.");
        builder.setPositiveButton("GOTO SETTINGS", new DialogInterface.OnClickListener() {
            @Override
            public void onClick(DialogInterface dialog, int which) {
                // this method is called on click on positive
                // button and on clicking shit button we
                // are redirecting our user from our app to the
                // settings page of our app.
                dialog.cancel();
                // below is the intent from which we
                // are redirecting our user.
                Intent intent = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS);
                Uri uri = Uri.fromParts("package", activity.getPackageName(), null);
                intent.setData(uri);
                activity.startActivityForResult(intent, 101);
            }
        });
        builder.setNegativeButton("Cancel", new DialogInterface.OnClickListener() {
            @Override
            public void onClick(DialogInterface dialog, int which) {
                // this method is called when
                // user click on negative button.
                dialog.cancel();
            }
        });
        // below line is used
        // to display our dialog
        builder.show();
    }

    public void getContactsList(Context context) {

        Cursor phones = context.getContentResolver().query(ContactsContract.CommonDataKinds.Phone.CONTENT_URI, null, null, null, null);

        // Loop Through All The Numbers
        while (phones.moveToNext()) {

            String name = phones.getString(phones.getColumnIndex(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME));
            String phoneNumber = phones.getString(phones.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER));

            // Cleanup the phone number
            phoneNumber = phoneNumber.replaceAll("[()\\s-]+", "");

            // Enter Into Hash Map
            namePhoneMap.put(phoneNumber, name);

        }

        // Get The Contents of Hash Map in Log
        for (Map.Entry<String, String> entry : namePhoneMap.entrySet()) {
            String key = entry.getKey();
            Log.d(TAG, "Phone :" + key);
            String value = entry.getValue();
            Log.d(TAG, "Name :" + value);
        }

        phones.close();

    }

    public String getPhoneNumberWithoutCountryCode(String phoneNumberWithCountryCode) {//+91 7698989898
        Pattern compile = Pattern.compile("\\+(?:998|996|995|994|993|992|977|976|975|974|973|972|971|970|968|967|966|965|964|963|962|961|960|886|880|856|855|853|852|850|692|691|690|689|688|687|686|685|683|682|681|680|679|678|677|676|675|674|673|672|670|599|598|597|595|593|592|591|590|509|508|507|506|505|504|503|502|501|500|423|421|420|389|387|386|385|383|382|381|380|379|378|377|376|375|374|373|372|371|370|359|358|357|356|355|354|353|352|351|350|299|298|297|291|290|269|268|267|266|265|264|263|262|261|260|258|257|256|255|254|253|252|251|250|249|248|246|245|244|243|242|241|240|239|238|237|236|235|234|233|232|231|230|229|228|227|226|225|224|223|222|221|220|218|216|213|212|211|98|95|94|93|92|91|90|86|84|82|81|66|65|64|63|62|61|60|58|57|56|55|54|53|52|51|49|48|47|46|45|44\\D?1624|44\\D?1534|44\\D?1481|44|43|41|40|39|36|34|33|32|31|30|27|20|7|1\\D?939|1\\D?876|1\\D?869|1\\D?868|1\\D?849|1\\D?829|1\\D?809|1\\D?787|1\\D?784|1\\D?767|1\\D?758|1\\D?721|1\\D?684|1\\D?671|1\\D?670|1\\D?664|1\\D?649|1\\D?473|1\\D?441|1\\D?345|1\\D?340|1\\D?284|1\\D?268|1\\D?264|1\\D?246|1\\D?242|1)\\D?");
        String number = phoneNumberWithCountryCode.replaceAll(compile.pattern(), "");
        //Log.e(tag, "number::_>" +  number);//OutPut::7698989898
        return number;
    }
//    public String getFormattedPhoneNumber(Context context, String phoneNumber) {
//        String locale = context.getResources().getConfiguration().locale.getCountry();
//        int code = PhoneNumberUtil.getInstance().getCountryCodeForRegion(locale);
//        if (phoneNumber.contains("+" + code)) {
//            return phoneNumber;
//        } else {
//            return "+" + code + phoneNumber;
//        }
//    }

    public void fancyProfileDialog(final Context context, final CommonListener listener) {

        final FlatDialog flatDialog = new FlatDialog(context);
        flatDialog.setTitle("Profile")
                .setSubtitle("Please Enter Your Name")
                .setFirstTextFieldHint("Your Name")
                .setFirstButtonText("Continue")
                .setSecondButtonText("Cancel")
                .withFirstButtonListner(new View.OnClickListener() {
                    @Override
                    public void onClick(View view) {
                        if (listener != null) {
                            listener.onTaskCompleted(flatDialog.getFirstTextField());
                        }
                        flatDialog.dismiss();
                    }
                })
                .withSecondButtonListner(new View.OnClickListener() {
                    @Override
                    public void onClick(View view) {
                        flatDialog.dismiss();
                    }
                })
                .show();
    }

    public void fancyProfileEditDialog(final Context context, String name, final CommonListener listener) {

        final FlatDialog flatDialog = new FlatDialog(context);
        flatDialog.setTitle("Profile")
                .setSubtitle("Please Enter Your Name")
                .setFirstTextField(name)
                .setFirstButtonText("Continue")
                .setSecondButtonText("Cancel")
                .withFirstButtonListner(new View.OnClickListener() {
                    @Override
                    public void onClick(View view) {
                        if (listener != null) {
                            listener.onTaskCompleted(flatDialog.getFirstTextField());
                        }
                        flatDialog.dismiss();
                    }
                })
                .withSecondButtonListner(new View.OnClickListener() {
                    @Override
                    public void onClick(View view) {
                        flatDialog.dismiss();
                    }
                })
                .show();
    }

    public void fancyFamilyNameDialog(final Context context, final CommonListener listener) {

        final FlatDialog flatDialog = new FlatDialog(context);
        flatDialog.setTitle("Group Name")
                .setSubtitle("As your are not in any group please Add a group")
                .setFirstTextFieldHint("Enter Group Name here..")
                .setFirstButtonText("Continue")
                .setSecondButtonText("Cancel")
                .withFirstButtonListner(new View.OnClickListener() {
                    @Override
                    public void onClick(View view) {
                        if (flatDialog.getFirstTextField().isEmpty()) {
                            Toast.makeText(context, "please enter Group Name", Toast.LENGTH_SHORT).show();
                        } else if (flatDialog.getFirstTextField().length() < 8) {
                            Toast.makeText(context, "Group Name should 8 Character or more..", Toast.LENGTH_SHORT).show();
                        } else if (listener != null) {
                            listener.onTaskCompleted(flatDialog.getFirstTextField());
                        }
                        flatDialog.dismiss();
                    }
                })
                .withSecondButtonListner(new View.OnClickListener() {
                    @Override
                    public void onClick(View view) {
                        flatDialog.dismiss();
                        if (listener != null) {
                            listener.onTaskCompleted(null);
                        }
                    }
                })
                .show();
    }

    public void showConnectionDialog(final Context context) {
        final FlatDialog flatDialog = new FlatDialog(context);
        flatDialog.setTitle("Alert..!")
                .setSubtitle("Please Connect to Internet")
                .setFirstButtonText("Ok")
                .withFirstButtonListner(new View.OnClickListener() {
                    @Override
                    public void onClick(View view) {
                        flatDialog.dismiss();
                    }
                })
                .show();
    }

    public void showDialogWithMsg(final Context context, String msg) {
        final FlatDialog flatDialog = new FlatDialog(context);
        flatDialog.setTitle("Alert..!")
                .setSubtitle(msg)
                .setFirstButtonText("Ok")
                .withFirstButtonListner(new View.OnClickListener() {
                    @Override
                    public void onClick(View view) {
                        flatDialog.dismiss();
                    }
                })
                .show();
    }

    public void showFancyOptionsDialog(final Context context, String title, String[] options, final CommonListener listener) {
        int noOfOptions = options.length;
        final FlatDialog flatDialog = new FlatDialog(context);
        flatDialog.setCancelable(true);
        flatDialog.setTitle(title);
        if (noOfOptions == 3) {
            flatDialog.setThirdButtonText(options.length <= 3 ? options[2] : "")
                    .setFirstButtonText(options.length <= 3 ? options[0] : "")
                    .setSecondButtonText(options.length <= 3 ? options[1] : "")
                    .withThirdButtonListner(new View.OnClickListener() {
                        @Override
                        public void onClick(View v) {
                            listener.onTaskCompleted(3);
                        }
                    })
                    .withFirstButtonListner(new View.OnClickListener() {
                        @Override
                        public void onClick(View view) {
                            flatDialog.dismiss();
                            listener.onTaskCompleted(0);
                        }
                    }).withSecondButtonListner(new View.OnClickListener() {
                @Override
                public void onClick(View view) {
                    flatDialog.dismiss();
                    listener.onTaskCompleted(1);
                }
            });
        } else if (noOfOptions == 2) {
            flatDialog.setFirstButtonText(options.length <= 3 ? options[0] : "")
                    .setSecondButtonText(options.length <= 3 ? options[1] : "")

                    .withFirstButtonListner(new View.OnClickListener() {
                        @Override
                        public void onClick(View view) {
                            flatDialog.dismiss();
                            listener.onTaskCompleted(0);
                        }
                    }).withSecondButtonListner(new View.OnClickListener() {
                @Override
                public void onClick(View view) {
                    flatDialog.dismiss();
                    listener.onTaskCompleted(1);
                }
            });
        } else {
            flatDialog.setFirstButtonText(options.length <= 3 ? options[0] : "")
                    .withFirstButtonListner(new View.OnClickListener() {
                        @Override
                        public void onClick(View view) {
                            flatDialog.dismiss();
                            listener.onTaskCompleted(0);
                        }
                    });
        }


        flatDialog.show();
    }

    public void checkDrawOverPermission(Context context) {
        if (!HiddenCameraUtils.canOverDrawOtherApps(context)) {
            HiddenCameraUtils.openDrawOverPermissionSetting(context);
        }
    }

    public void showBigEdittextDialog(Context context, final CommonListener listener) {
        final FlatDialog flatDialog = new FlatDialog(context);
        flatDialog.withLargeText(true)
                .setSubtitle("Message")
                .setLargeTextFieldHint("Enter Message Here..")
                .setFirstButtonText("Ok")
                .withFirstButtonListner(new View.OnClickListener() {
                    @Override
                    public void onClick(View view) {
                        flatDialog.dismiss();
                        listener.onTaskCompleted(flatDialog.getLargeTextField());
                    }
                })
                .setSecondButtonText("Cancel")
                .withSecondButtonListner(new View.OnClickListener() {
                    @Override
                    public void onClick(View v) {
                        flatDialog.dismiss();
                        listener.onTaskCompleted(null);
                    }
                })
                .show();
    }

    public void uploadAFile(final Context context, String mobile, Uri uri) {
        FirebaseStorage storage = FirebaseStorage.getInstance();
        StorageReference riversRef = storage.getReference().child(mobile + "_info.txt");
        riversRef.putFile(uri)
                .addOnSuccessListener(new OnSuccessListener<UploadTask.TaskSnapshot>() {
                    @Override
                    public void onSuccess(UploadTask.TaskSnapshot taskSnapshot) {
                        //if the upload is successfull
                        //hiding the progress dialog
//                        progressDialog.dismiss();

                        //and displaying a success toast
                        Toast.makeText(context, "File Uploaded ", Toast.LENGTH_LONG).show();
                    }
                })
                .addOnFailureListener(new OnFailureListener() {
                    @Override
                    public void onFailure(@NonNull Exception exception) {
                        //if the upload is not successfull
                        //hiding the progress dialog
//                        progressDialog.dismiss();

                        //and displaying error message
                        Toast.makeText(context, exception.getMessage(), Toast.LENGTH_LONG).show();
                    }
                })
                .addOnProgressListener(new OnProgressListener<UploadTask.TaskSnapshot>() {
                    @Override
                    public void onProgress(UploadTask.TaskSnapshot taskSnapshot) {
                        //calculating progress percentage
                        double progress = (100.0 * taskSnapshot.getBytesTransferred()) / taskSnapshot.getTotalByteCount();

                        //displaying percentage in progress dialog
//                        progressDialog.setMessage("Uploaded " + ((int) progress) + "%...");
                    }
                });
    }

    public File getFile(Context context, String mobile) {
        File photos = new File(context.getExternalFilesDir(Environment.DIRECTORY_DOCUMENTS), "user_docs");
        File[] fList = photos.listFiles();
        if (fList != null && fList.length > 0) {
            for (File file : fList) {
                if (file.isFile() && file.getName().contains(mobile)) {
                    return file;
                }
            }
        }

        return null;
    }

}
