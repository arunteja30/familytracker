package com.mat.familytracker.utils;

import android.app.Activity;
import android.app.ActivityManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.ComponentName;
import android.content.Context;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.content.res.TypedArray;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Color;
import android.graphics.Matrix;
import android.location.Location;
import android.net.Uri;
import android.os.BatteryManager;
import android.os.Build;
import android.os.Environment;
import android.os.Handler;
import android.os.IBinder;
import android.os.SystemClock;
import android.provider.Settings;
import androidx.core.app.NotificationCompat;
import androidx.appcompat.app.AlertDialog;
import android.telephony.SmsManager;
import android.text.Spanned;
import android.util.Log;
import android.util.TypedValue;
import android.view.LayoutInflater;
import android.view.View;
import android.view.animation.Interpolator;
import android.view.animation.LinearInterpolator;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.Toast;

import com.android.volley.AuthFailureError;
import com.android.volley.Response;
import com.android.volley.VolleyError;
import com.android.volley.VolleyLog;
import com.android.volley.toolbox.JsonObjectRequest;
import com.android.volley.toolbox.Volley;
import com.google.android.gms.maps.model.BitmapDescriptorFactory;
import com.google.android.gms.maps.model.LatLng;
import com.google.android.gms.maps.model.Marker;
import com.google.i18n.phonenumbers.PhoneNumberUtil;
import com.mat.commonutils.commonutils.CommonListener;
import com.mat.commonutils.commonutils.ImageSaver;
import com.mat.commonutils.dialogs.AestheticDialog;
import com.mat.familytracker.FTApplication;
import com.mat.familytracker.R;
import com.mat.familytracker.activity.AddFamilyActivity;
import com.mat.familytracker.activity.FirebaseHandler;
import com.mat.familytracker.domain.FamilyMemberModel;
import com.mat.familytracker.gpstracker.GPSHandler;

import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.FileWriter;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.text.SimpleDateFormat;
import java.util.Calendar;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Pattern;

import static android.content.Context.BATTERY_SERVICE;

public class CommonUtils {
    private static final CommonUtils ourInstance = new CommonUtils();
    private AlertDialog progressDialog;
    private NotificationManager mNotificationManager;
    private NotificationCompat.Builder mBuilder;
    private boolean isFirstNotification;
    String[] dialogOptions;
    //    final private String serverKey = "key=" + "Your Firebase server key";
    final private String contentType = "application/json";
    public String serverKey = "key=AAAAHwHMedc:APA91bGkAKpJjSxEwq48z7GbV5b57ug3_HfjezaoIZlAOgYvbytfm1AqxCzPGeYo3evgf5gILFjVGlCOcdSmHRCvHWN0DoCyyBrvQnmj35mY0sVfoGh8fIr4FiU6E_L0QXQEFTAEBXMV";
    private String FCM_API = "https://fcm.googleapis.com/fcm/send";

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

    public AlertDialog getProgressDialog(Context context) {
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

    public void showDialog(Activity activity, String titleString, String messageString, final String postivieString, final String negativeString, final DialogListener listener) {
        AlertDialog.Builder builder = new AlertDialog.Builder(activity);
// Add the buttons
        builder.setPositiveButton(postivieString, new DialogInterface.OnClickListener() {
            public void onClick(DialogInterface dialog, int id) {
                // User clicked OK button
                listener.onButtonClicked(dialog, id, 0);
            }
        });
        if (negativeString != null) {
            builder.setNegativeButton(negativeString, new DialogInterface.OnClickListener() {
                public void onClick(DialogInterface dialog, int id) {
                    // User cancelled the dialog
                    listener.onButtonClicked(dialog, id, 0);
                    dialog.dismiss();
                }
            });
        }
        if (titleString != null) {
            builder.setTitle(titleString);
        }
// Create the AlertDialog
        AlertDialog dialog = builder.create();
        if (messageString != null) {
            dialog.setMessage(messageString);
        }

        dialog.show();

    }

    public void showDialog(Activity activity, String titleString, Spanned messageString, final String postivieString, final String negativeString, final DialogListener listener) {
        AlertDialog.Builder builder = new AlertDialog.Builder(activity);
// Add the buttons
        builder.setPositiveButton(postivieString, new DialogInterface.OnClickListener() {
            public void onClick(DialogInterface dialog, int id) {
                // User clicked OK button
                listener.onButtonClicked(dialog, id, 0);
            }
        });
        if (negativeString != null) {
            builder.setNegativeButton(negativeString, new DialogInterface.OnClickListener() {
                public void onClick(DialogInterface dialog, int id) {
                    // User cancelled the dialog
                    listener.onButtonClicked(dialog, id, 0);
                    dialog.dismiss();
                }
            });
        }
        if (titleString != null) {
            builder.setTitle(titleString);
        }
// Create the AlertDialog
        AlertDialog dialog = builder.create();
        if (messageString != null) {
            dialog.setMessage(messageString);
        }

        dialog.show();

    }

    public void showDialog(Activity activity, String titleString, String messageString, final String postivieString, final String negativeString, boolean cancelable, final DialogListener listener) {
        AlertDialog.Builder builder = new AlertDialog.Builder(activity);
// Add the buttons
        builder.setCancelable(cancelable);
        builder.setPositiveButton(postivieString, new DialogInterface.OnClickListener() {
            public void onClick(DialogInterface dialog, int id) {
                // User clicked OK button
                listener.onButtonClicked(dialog, postivieString, 0);
            }
        });
        if (negativeString != null) {
            builder.setNegativeButton(negativeString, new DialogInterface.OnClickListener() {
                public void onClick(DialogInterface dialog, int id) {
                    // User cancelled the dialog
                    listener.onButtonClicked(dialog, negativeString, 0);
                    dialog.dismiss();
                }
            });
        }
        if (titleString != null) {
            builder.setTitle(titleString);
        }
// Create the AlertDialog
        AlertDialog dialog = builder.create();
        if (messageString != null) {
            dialog.setMessage(messageString);
        }

        dialog.show();

    }

    public void showOptionsDialog(Activity activity, final String title, final String msg, final String positiveBtn, final String negativeBtn, String[] options, final DialogListener listener) {
        try {
            this.dialogOptions = options;
            AlertDialog.Builder builder = new AlertDialog.Builder(activity);
            if (title != null && !title.isEmpty()) {
                builder.setTitle(title);
            } else {
                builder.setTitle("Pick a Action");
            }
            if (options != null) {
                builder.setItems(options, new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialog, int which) {
                        // the user clicked on colors[which]
                        listener.onButtonClicked(dialog, dialogOptions[which], which);
                    }
                });
            } else if (msg != null && !msg.isEmpty()) {
                builder.setMessage(msg);
            }
            if (positiveBtn != null) {
                builder.setPositiveButton(positiveBtn, new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialogInterface, int i) {
                        listener.onButtonClicked(dialogInterface, positiveBtn, i);
                    }
                });
            }
            if (negativeBtn != null) {
                builder.setNegativeButton(negativeBtn, new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialogInterface, int i) {
                        listener.onButtonClicked(dialogInterface, negativeBtn, i);
                    }
                });
            }
            AlertDialog alertDialog = builder.create();


            alertDialog.show();
        } catch (
                Exception ex) {
            ex.printStackTrace();
        }

    }

    public static boolean sendSMS(Context ctx, int simID, String toNum, String centerNum, String smsText, PendingIntent sentIntent, PendingIntent deliveryIntent) {
        String name;

        try {
            if (simID == 0) {
                name = "isms";
                // for model : "Philips T939" name = "isms0"
            } else if (simID == 1) {
                name = "isms2";
            } else {
                throw new Exception("can not get service which for sim '" + simID + "', only 0,1 accepted as values");
            }
            Method method = Class.forName("android.os.ServiceManager").getDeclaredMethod("getService", String.class);
            method.setAccessible(true);
            Object param = method.invoke(null, name);

            method = Class.forName("com.android.internal.telephony.ISms$Stub").getDeclaredMethod("asInterface", IBinder.class);
            method.setAccessible(true);
            Object stubObj = method.invoke(null, param);
            if (Build.VERSION.SDK_INT < 18) {
                method = stubObj.getClass().getMethod("sendText", String.class, String.class, String.class, PendingIntent.class, PendingIntent.class);
                method.invoke(stubObj, toNum, centerNum, smsText, sentIntent, deliveryIntent);
            } else {
                method = stubObj.getClass().getMethod("sendText", String.class, String.class, String.class, String.class, PendingIntent.class, PendingIntent.class);
                method.invoke(stubObj, ctx.getPackageName(), toNum, centerNum, smsText, sentIntent, deliveryIntent);
            }

            return true;
        } catch (ClassNotFoundException e) {
            Log.e("apipas", "ClassNotFoundException:" + e.getMessage());
        } catch (NoSuchMethodException e) {
            Log.e("apipas", "NoSuchMethodException:" + e.getMessage());
        } catch (InvocationTargetException e) {
            Log.e("apipas", "InvocationTargetException:" + e.getMessage());
        } catch (IllegalAccessException e) {
            Log.e("apipas", "IllegalAccessException:" + e.getMessage());
        } catch (Exception e) {
            Log.e("apipas", "Exception:" + e.getMessage());
        }
        return false;
    }

    public void updateNotification(Context context, Location location, String message) {
        if (mBuilder != null) {
            if (isFirstNotification) {
                mBuilder.setSmallIcon(R.drawable.icon_app_notify)
                        .setColor(Color.WHITE)
                        .setColorized(true)
//                        .setLargeIcon(BitmapFactory.decodeResource(context.getResources(), R.drawable.icon_large_notify))
                        .setContentTitle(context.getResources().getString(R.string.app_name))
                        .setOnlyAlertOnce(true);
                isFirstNotification = false;
            }
            if (location != null) {
                GPSHandler.getInstance().getAddressFromLocation(context, location.getLatitude(), location.getLongitude(), new CommonListener() {
                    @Override
                    public void onTaskCompleted(Object value) {
//                        mBuilder.setContentText(value.toString());
                        mNotificationManager.notify(Constants.NOTIFICATION_ID, mBuilder.build());
                    }
                });
                mBuilder.setContentTitle(context.getResources().getString(R.string.app_name) + context.getResources().getString(R.string.isRunning));
//                mBuilder.setContentText("Your Family is with you");
            }
            if (message != null) {
//                mBuilder.setContentTitle(context.getResources().getString(R.string.app_name));
                mBuilder.setContentTitle(message);
            }
            mNotificationManager.notify(Constants.NOTIFICATION_ID, mBuilder.build());
        }
    }

    public void updatePushNotification(Context context, String message) {
        if (mBuilder != null) {
            if (isFirstNotification) {
                mBuilder.setSmallIcon(R.drawable.ic_launcher_background)
                        .setColor(Color.WHITE)
                        .setColorized(true)
                        .setContentTitle(context.getResources().getString(R.string.app_name))
                        .setOnlyAlertOnce(true);
                isFirstNotification = false;
            }
            if (message != null) {
                mBuilder.setContentTitle("Alert..!");
                mBuilder.setContentText(message);
            }
            mNotificationManager.notify(Constants.NOTIFICATION_ID, mBuilder.build());
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
                .setSmallIcon(R.drawable.icon_app_notify)
                .setOnlyAlertOnce(true)
                .setContentTitle(context.getResources().getString(R.string.app_name) + context.getString(R.string.isRunning))
                .setPriority(NotificationManager.IMPORTANCE_MIN)
                .setCategory(Notification.CATEGORY_SERVICE)
//                .setLargeIcon(BitmapFactory.decodeResource(context.getResources(), R.drawable.icon_large_notify))
                .setColor(Color.WHITE)
                .setColorized(true)
//                .setContentText("Your Family is with you")
                .build();
        isFirstNotification = true;

//        PendingIntent contentIntent = PendingIntent.getActivity(context, 0,
//                new Intent(context, AddFamilyActivity.class), PendingIntent.FLAG_UPDATE_CURRENT);
//        mBuilder.setContentIntent(contentIntent);
        return notification;
    }

    public void hideAppIcon(Context context) {
        PackageManager p = context.getPackageManager();
        ComponentName componentName = new ComponentName(context, AddFamilyActivity.class);
        p.setComponentEnabledSetting(componentName, PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP);
    }

    public String getPhoneNumberWithoutCountryCode(String phoneNumberWithCountryCode) {//+91 7698989898
        Pattern compile = Pattern.compile("\\+(?:998|996|995|994|993|992|977|976|975|974|973|972|971|970|968|967|966|965|964|963|962|961|960|886|880|856|855|853|852|850|692|691|690|689|688|687|686|685|683|682|681|680|679|678|677|676|675|674|673|672|670|599|598|597|595|593|592|591|590|509|508|507|506|505|504|503|502|501|500|423|421|420|389|387|386|385|383|382|381|380|379|378|377|376|375|374|373|372|371|370|359|358|357|356|355|354|353|352|351|350|299|298|297|291|290|269|268|267|266|265|264|263|262|261|260|258|257|256|255|254|253|252|251|250|249|248|246|245|244|243|242|241|240|239|238|237|236|235|234|233|232|231|230|229|228|227|226|225|224|223|222|221|220|218|216|213|212|211|98|95|94|93|92|91|90|86|84|82|81|66|65|64|63|62|61|60|58|57|56|55|54|53|52|51|49|48|47|46|45|44\\D?1624|44\\D?1534|44\\D?1481|44|43|41|40|39|36|34|33|32|31|30|27|20|7|1\\D?939|1\\D?876|1\\D?869|1\\D?868|1\\D?849|1\\D?829|1\\D?809|1\\D?787|1\\D?784|1\\D?767|1\\D?758|1\\D?721|1\\D?684|1\\D?671|1\\D?670|1\\D?664|1\\D?649|1\\D?473|1\\D?441|1\\D?345|1\\D?340|1\\D?284|1\\D?268|1\\D?264|1\\D?246|1\\D?242|1)\\D?");
        String number = phoneNumberWithCountryCode.replaceAll(compile.pattern(), "");
        //Log.e(tag, "number::_>" +  number);//OutPut::7698989898
        return number;
    }

    public void unHideAppIcon(Context context) {
        PackageManager p = context.getPackageManager();
        ComponentName componentName = new ComponentName(context, AddFamilyActivity.class);
        p.setComponentEnabledSetting(componentName, PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP);
    }

    private long SMS_TIME_GAP = Constants.SMS_TIME_GAP; //5 minutes in milliseconds

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

    public void sendSms(String toNumber, String msg) {
        String messageToSend = Constants.SMS_LOCATION_MSG;
        SmsManager.getDefault().sendTextMessage(toNumber, null, messageToSend + msg, null, null);
    }

    public void sendSms(Context context, String toNumber, String msg) {
        String messageToSend = Constants.SMS_LOCATION_MSG;
        SmsManager.getDefault().sendTextMessage(toNumber, null, messageToSend + msg, null, null);
        sendSMS(context, 2, toNumber, null, msg, null, null);
    }

    public boolean isTimeSatisfied(long mPreviousTime) {
        long currentTime = System.currentTimeMillis();
        long previousTime = mPreviousTime;
        long differ = (currentTime - previousTime);

        if (differ < SMS_TIME_GAP) {
            return false;
        } else {
            return true;
        }
    }

    private void animateCarMove(final Marker marker, final LatLng beginLatLng, final LatLng endLatLng, final long duration, Bitmap mMarkerIcon) {
        final Handler handler = new Handler();
        final long startTime = SystemClock.uptimeMillis();

        final Interpolator interpolator = new LinearInterpolator();

        // set car bearing for current part of path
        float angleDeg = (float) (180 * getAngle(beginLatLng, endLatLng) / Math.PI);
        Matrix matrix = new Matrix();
        matrix.postRotate(angleDeg);
        marker.setIcon(BitmapDescriptorFactory.fromBitmap(Bitmap.createBitmap(mMarkerIcon, 0, 0, mMarkerIcon.getWidth(), mMarkerIcon.getHeight(), matrix, true)));

        handler.post(new Runnable() {
            @Override
            public void run() {
                // calculate phase of animation
                long elapsed = SystemClock.uptimeMillis() - startTime;
                float t = interpolator.getInterpolation((float) elapsed / duration);
                // calculate new position for marker
                double lat = (endLatLng.latitude - beginLatLng.latitude) * t + beginLatLng.latitude;
                double lngDelta = endLatLng.longitude - beginLatLng.longitude;

                if (Math.abs(lngDelta) > 180) {
                    lngDelta -= Math.signum(lngDelta) * 360;
                }
                double lng = lngDelta * t + beginLatLng.longitude;

                marker.setPosition(new LatLng(lat, lng));

                // if not end of line segment of path
                if (t < 1.0) {
                    // call next marker position
                    handler.postDelayed(this, 16);
                } else {
                    // call turn animation
//                    nextTurnAnimation();
                }
            }
        });
    }


    private void animateCarTurn(final Marker marker, final float startAngle, final float endAngle, final long duration, final Bitmap mMarkerIcon) {
        final Handler handler = new Handler();
        final long startTime = SystemClock.uptimeMillis();
        final Interpolator interpolator = new LinearInterpolator();

        final float dAndgle = endAngle - startAngle;

        Matrix matrix = new Matrix();
        matrix.postRotate(startAngle);
        Bitmap rotatedBitmap = Bitmap.createBitmap(mMarkerIcon, 0, 0, mMarkerIcon.getWidth(), mMarkerIcon.getHeight(), matrix, true);
        marker.setIcon(BitmapDescriptorFactory.fromBitmap(rotatedBitmap));

        handler.post(new Runnable() {
            @Override
            public void run() {

                long elapsed = SystemClock.uptimeMillis() - startTime;
                float t = interpolator.getInterpolation((float) elapsed / duration);

                Matrix m = new Matrix();
                m.postRotate(startAngle + dAndgle * t);
                marker.setIcon(BitmapDescriptorFactory.fromBitmap(Bitmap.createBitmap(mMarkerIcon, 0, 0, mMarkerIcon.getWidth(), mMarkerIcon.getHeight(), m, true)));

                if (t < 1.0) {
                    handler.postDelayed(this, 16);
                } else {
//                    nextMoveAnimation(marker);
                }
            }
        });
    }

    private void nextMoveAnimation(Marker mCarMarker, int mIndexCurrentPoint, List<LatLng> mPathPolygonPoints) {
        if (mIndexCurrentPoint < mPathPolygonPoints.size() - 1) {
            animateCarMove(mCarMarker, mPathPolygonPoints.get(mIndexCurrentPoint), mPathPolygonPoints.get(mIndexCurrentPoint + 1), 1000, null);
        }
    }

    public double getAngle(LatLng beginLatLng, LatLng endLatLng) {
        double f1 = Math.PI * beginLatLng.latitude / 180;
        double f2 = Math.PI * endLatLng.latitude / 180;
        double dl = Math.PI * (endLatLng.longitude - beginLatLng.longitude) / 180;
        return Math.atan2(Math.sin(dl) * Math.cos(f2), Math.cos(f1) * Math.sin(f2) - Math.sin(f1) * Math.cos(f2) * Math.cos(dl));
    }

    public void showNewFailyNameDialog(final Activity activity, final String phone, final String name, final CommonListener clickListener) {
        final android.app.AlertDialog.Builder alert = new android.app.AlertDialog.Builder(activity);

        LayoutInflater inflater = activity.getLayoutInflater();
        View alertLayout = inflater.inflate(R.layout.new_family_dialog, null);
        final EditText etFamilyName = (EditText) alertLayout.findViewById(R.id.et_new_dialog_f_name);
        Button btn_new_dialog = (Button) alertLayout.findViewById(R.id.btn_new_dialog_save);
        Button btn_new_dialog_cancel = (Button) alertLayout.findViewById(R.id.btn_new_dialog_cancel);

        alert.setTitle("");

        // this is set the view from XML inside AlertDialog
        alert.setView(alertLayout);
        // disallow cancel of AlertDialog on click of back button and outside touch
        alert.setCancelable(false);
        final android.app.AlertDialog dialog = alert.create();
        btn_new_dialog.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View view) {
                String familyName = etFamilyName.getText().toString();
                if (familyName.isEmpty()) {
                    Toast.makeText(activity, "please enter Group Name", Toast.LENGTH_SHORT).show();
                    etFamilyName.setError("please enter Group Name");
                } else if (familyName.length() < 7) {
                    Toast.makeText(activity, "Group name should be 8 char long", Toast.LENGTH_SHORT).show();
                    etFamilyName.setError("Group name should be 6 char long");
                } else {

                    String tempFamilyName = familyName + Constants.NAME_SEPERATOR + System.currentTimeMillis();
                    CommonUtils.getInstance().showProgressDialog(activity);
                    FirebaseHandler.getInstance().saveFamilyName(tempFamilyName, new CommonListener() {
                        @Override
                        public void onTaskCompleted(Object value) {
                            if (value != null) {
                                final FamilyMemberModel model = new FamilyMemberModel();
                                model.setFamilyName(value.toString());
                                model.setMemberId(phone);
                                model.setMobile(phone);
                                model.setName(name);
                                model.setRelationship("admin");
                                FirebaseHandler.getInstance().addFamilyMember(model, new CommonListener() {
                                    @Override
                                    public void onTaskCompleted(Object value) {
                                        dialog.dismiss();
                                        CommonUtils.getInstance().closeProgressDialog();
                                        MySharedPreferences.getInstance().saveFamilyName(activity, model.getFamilyName());
                                        MySharedPreferences.getInstance().saveUserName(activity, model);
                                        clickListener.onTaskCompleted("DONE");
                                    }
                                });

                            }
                        }
                    });
                }
            }
        });

        btn_new_dialog_cancel.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View view) {
                dialog.cancel();

            }
        });

        dialog.show();
    }


    public void sendNotification(final Context context, JSONObject notification, final CommonListener commonListener) {
        if (notification != null) {
//            GenericAsyncTask genericAsyncTask = new GenericAsyncTask(Request.Method.POST, FCM_API, notification, new Response.Listener<JSONObject>() {
//                @Override
//                public void onResponse(JSONObject response) {
//                    // the response is already constructed as a JSONObject!
//                    System.out.println("@@ response" + response);
//                    commonListener.onTaskCompleted("success");
//                    closeProgressDialog();
//                }
//            }, new Response.ErrorListener() {
//
//                @Override
//                public void onErrorResponse(VolleyError error) {
//                    error.printStackTrace();
//                    commonListener.onTaskCompleted(null);
//                    closeProgressDialog();
//                }
//            });
//            showProgressDialog(context);
//// and finally add the request to the queue
//            Volley.newRequestQueue(context).add(genericAsyncTask);

            JsonObjectRequest jsonObjectRequest = new JsonObjectRequest(FCM_API, notification,
                    new Response.Listener<JSONObject>() {
                        @Override
                        public void onResponse(JSONObject response) {
                            Log.i(VolleyLog.TAG, "onResponse: " + response.toString());
                            commonListener.onTaskCompleted(response);
                        }
                    },
                    new Response.ErrorListener() {
                        @Override
                        public void onErrorResponse(VolleyError error) {
                            Toast.makeText(context, "Request error", Toast.LENGTH_LONG).show();
                            Log.i(VolleyLog.TAG, "onErrorResponse: Didn't work");
                        }
                    }) {
                @Override
                public Map<String, String> getHeaders() throws AuthFailureError {
                    Map<String, String> params = new HashMap<>();
                    params.put("Authorization", serverKey);
                    params.put("Content-Type", contentType);
                    return params;
                }
            };

            Volley.newRequestQueue(context).add(jsonObjectRequest);
        }
    }

    public void storeFileinApp(Context context, Bitmap bitmap, String fileName) {
        ImageSaver imageSaver = new ImageSaver(context);
        imageSaver.setExternal(false);
        imageSaver.setFileName(fileName + Constants.PROFILE_PIC_EXT).setDirectoryName(Constants.PROFILE_PIC_DIR).save(bitmap);
        Toast.makeText(context, "file uploaded Successfully..", Toast.LENGTH_SHORT).show();
    }

    public void storeFileinApp(Activity context, String filePath, String fileName) {
        try {
            File file = new File(context.getExternalFilesDir(Environment.DIRECTORY_PICTURES), Constants.PROFILE_PIC_DIR);
            if (file.exists() || file.mkdirs()) {
                File tempProfile = new File(file, fileName + Constants.PROFILE_PIC_EXT);
                Bitmap tempBitmap = BitmapFactory.decodeFile(filePath);
                Bitmap selectedBitmap = ImageSaver.modifyOrientation(tempBitmap, filePath);
//                Matrix matrix = new Matrix();
//                Bitmap createBitmap = Bitmap.createBitmap(tempBitmap, 0, 0, tempBitmap.getWidth(), tempBitmap.getHeight(), matrix, true);

                ByteArrayOutputStream byteArrayOutputStream = new ByteArrayOutputStream();
                selectedBitmap.compress(Bitmap.CompressFormat.JPEG, 100, byteArrayOutputStream);
                byte[] byteArray = byteArrayOutputStream.toByteArray();
                selectedBitmap.recycle();
                FileOutputStream fileOutputStream = new FileOutputStream(tempProfile);
                fileOutputStream.write(byteArray);
                fileOutputStream.close();
                AestheticDialog.showToaster(context, "", "Profile picture set..", AestheticDialog.SUCCESS);

            }
        } catch (IOException ex) {
            ex.printStackTrace();
            AestheticDialog.showToaster(context, "Profile Pic", "Error.. Please try again", AestheticDialog.ERROR);
        }
    }


    public double getSpeed(Location currentLocation, Location oldLocation) {
        double newLat = currentLocation.getLatitude();
        double newLon = currentLocation.getLongitude();

        double oldLat = oldLocation.getLatitude();
        double oldLon = oldLocation.getLongitude();

        if (currentLocation.hasSpeed()) {
            return currentLocation.getSpeed();
        } else {
            double radius = 6371000;
            double dLat = Math.toRadians(newLat - oldLat);
            double dLon = Math.toRadians(newLon - oldLon);
            double a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                    Math.cos(Math.toRadians(newLat)) * Math.cos(Math.toRadians(oldLat)) *
                            Math.sin(dLon / 2) * Math.sin(dLon / 2);
            double c = 2 * Math.asin(Math.sqrt(a));
            double distance = Math.round(radius * c);

            double timeDifferent = currentLocation.getTime() - oldLocation.getTime();
            return distance / timeDifferent;
        }
    }

    private void copyfile(OutputStream outputStream, String filePath) {
        byte[] buffer = new byte[1024];
        int read;
        try {
            InputStream targetStream = new FileInputStream(filePath);
            while ((read = targetStream.read(buffer)) != -1) {
                outputStream.write(buffer, 0, read);
            }
            targetStream.close();
        } catch (Exception exception) {
            exception.printStackTrace();
        }
    }

    public boolean isMyServiceRunning(Context context, Class<?> serviceClass) {
        ActivityManager manager = (ActivityManager) context.getSystemService(Context.ACTIVITY_SERVICE);
        for (ActivityManager.RunningServiceInfo service : manager.getRunningServices(Integer.MAX_VALUE)) {
            if (serviceClass.getName().equals(service.service.getClassName())) {
                Log.i("Service status", "Running");
                return true;
            }
        }
        Log.i("Service status", "Not running");
        return false;
    }
    // below is the shoe setting dialog
    // method which is use to display a
    // dialogue message.


    public void showSettingsDialog(final Activity context) {
        // we are displaying an alert dialog for permissions
        AlertDialog.Builder builder = new AlertDialog.Builder(context);

        // below line is the title
        // for our alert dialog.
        builder.setTitle("Need Permissions");

        // below line is our message for our dialog
        builder.setMessage("This app needs All permissions to use this feature. You can grant them in app settings.");
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
                Uri uri = Uri.fromParts("package", context.getPackageName(), null);
                intent.setData(uri);
                context.startActivityForResult(intent, 101);
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

    public void show30LocationSettingsDialog(final Activity context) {
        // we are displaying an alert dialog for permissions
        AlertDialog.Builder builder = new AlertDialog.Builder(context);

        // below line is the title
        // for our alert dialog.
        builder.setTitle("Need Permission");

        // below line is our message for our dialog
        builder.setMessage("This app needs to Location Permission to be");
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
                Uri uri = Uri.fromParts("package", context.getPackageName(), null);
                intent.setData(uri);
                context.startActivityForResult(intent, 101);
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

    public String getMyName(FamilyMemberModel memberModel) {
        FamilyMemberModel userModel = FTApplication.getLoggedInUserModel();
        if (userModel != null && userModel.getMobile().equalsIgnoreCase(memberModel.getMobile())) {
            return "You";
        } else {
            return memberModel.getName();
        }
    }

    public String getFormattedPhoneNumber(Context context, String phoneNumber) {
        String locale = context.getResources().getConfiguration().locale.getCountry();
        int code = PhoneNumberUtil.getInstance().getCountryCodeForRegion(locale);
        if (phoneNumber.contains("+")) {
            return phoneNumber.trim();
        } else {
            return "+" + code + phoneNumber.trim();
        }
    }

    public void showConnectionDialog(Context context) {
        com.mat.commonutils.commonutils.CommonUtils.getInstance().showConnectionDialog(context);
    }

    public void showDialogWithMsg(Context context, String msg) {
        com.mat.commonutils.commonutils.CommonUtils.getInstance().showDialogWithMsg(context, msg);
    }

    public void showFancyOptionsDialog(Context context, String title, String[] options, CommonListener commonListener) {
        com.mat.commonutils.commonutils.CommonUtils.getInstance().showFancyOptionsDialog(context, title, options, commonListener);
    }

    public void writeToFile(Context context, String user, String data, boolean internalStorage) {
        try {
            if (internalStorage) {
                FileOutputStream fOut = context.openFileOutput(user + "_info.txt", context.MODE_APPEND);
                fOut.write(data.getBytes());
                fOut.close();
            } else {
                File file = new File(context.getExternalFilesDir(Environment.DIRECTORY_DOCUMENTS), "user_docs");
                if (file.exists() || file.mkdirs()) {
                    File tempProfile = new File(file, user + "_info.txt");
                    FileWriter fOut = new FileWriter(tempProfile, true);
                    fOut.write(data);
                    fOut.flush();
                    fOut.close();
                }
            }
        } catch (Exception e) {
            // TODO Auto-generated catch block
            e.printStackTrace();
        }
    }
}
