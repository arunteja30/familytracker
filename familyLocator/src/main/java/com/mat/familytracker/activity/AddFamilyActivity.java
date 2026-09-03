package com.mat.familytracker.activity;

import android.Manifest;
import android.annotation.SuppressLint;
import android.app.ActivityManager;
import android.app.admin.DevicePolicyManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.net.Uri;
import android.os.AsyncTask;
import android.os.Build;
import android.os.Bundle;
import android.provider.ContactsContract;
import android.provider.MediaStore;
import android.provider.Settings;
import androidx.annotation.NonNull;
import com.google.android.material.floatingactionbutton.FloatingActionButton;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout;
import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.app.AppCompatActivity;
import androidx.appcompat.widget.AppCompatSpinner;
import androidx.appcompat.widget.AppCompatTextView;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import android.util.Log;
import android.view.KeyEvent;
import android.view.Menu;
import android.view.MenuItem;
import android.view.View;
import android.widget.AdapterView;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

import androidx.work.Constraints;
import androidx.work.ExistingPeriodicWorkPolicy;
import androidx.work.NetworkType;
import androidx.work.PeriodicWorkRequest;
import androidx.work.WorkManager;

import com.google.firebase.auth.FirebaseAuth;
import com.google.gson.Gson;
import com.karumi.dexter.Dexter;
import com.karumi.dexter.MultiplePermissionsReport;
import com.karumi.dexter.PermissionToken;
import com.karumi.dexter.listener.DexterError;
import com.karumi.dexter.listener.PermissionRequest;
import com.karumi.dexter.listener.PermissionRequestErrorListener;
import com.karumi.dexter.listener.multi.MultiplePermissionsListener;
import com.mat.commonutils.app.UpdateModel;
import com.mat.commonutils.commonutils.CommonListener;
import com.mat.commonutils.dialogs.AestheticDialog;
import com.mat.commonutils.networkutils.ConnectionManager;
import com.mat.commonutils.recyclerview.BaseRecyclerListener;
import com.mat.familytracker.R;
import com.mat.familytracker.domain.FamilyMemberModel;
import com.mat.familytracker.gpstracker.GPSHandler;
import com.mat.familytracker.gpstracker.GPSTrackerService;
import com.mat.familytracker.utils.CommonUtils;
import com.mat.familytracker.utils.Constants;
import com.mat.familytracker.utils.DialogListener;
import com.mat.familytracker.utils.MySharedPreferences;
import com.mat.phonesecurity.activity.IntruderPhotosActivity;
import com.mat.phonesecurity.recievers.MyDeviceAdminReceiver;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.TimeUnit;

import static com.mat.familytracker.utils.Constants.PICK_IMAGE;

public class AddFamilyActivity extends AppCompatActivity implements View.OnClickListener {
    private EditText familyNameEditText;
    private ArrayList<FamilyMemberModel> familyMemberModelList;
    BaseRecyclerListener baseRecyclerListener;
    public static final int MY_PERMISSIONS_REQUEST_LOCATION = 99;
    public static final int MY_PERMISSIONS_REQUEST_SMS = 999;
    private FrameLayout btnsLayout;
    private Button saveDetails;
    private String[] options;
    private FamilyMemberModel logginUserModel;
    private SwipeRefreshLayout swipe_refresh;
    private TextView txt_group_name_label;
    private LinearLayout main_layout;
    public static String picSelectedUser = null;
    private boolean locationPermission, mSMSPermission;
    // A reference to the service used to get location updates.
    Map<String, String> contactsMap = new HashMap<String, String>();
    private LinearLayout no_perm_layout, ll_bottomLayout;
    private FloatingActionButton fabAddMember;
    private static final int TIME_INTERVAL = 2000; // # milliseconds, desired time passed between two back presses.
    private long mBackPressed;
    DevicePolicyManager policyManager;
    ComponentName devicePolicyAdmin;
    private static final int ADMIN_REQUEST = 1232;
    private RecyclerView familyMembersListView;
    private boolean userWithoutFamily;
    private FirebaseAuth mAuth;
    private FamilyMemberListRecycleAdapter familyListAdapter;
    FamilyMemberList familyMemberList;
    private AppCompatSpinner spr_groups;
    private boolean userIsInteracting;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_add_family);
        policyManager = (DevicePolicyManager) getSystemService(Context.DEVICE_POLICY_SERVICE);
        devicePolicyAdmin = new ComponentName(this,
                MyDeviceAdminReceiver.class);

//        if (Build.BRAND.equalsIgnoreCase("xiaomi")||Build.BRAND.equalsIgnoreCase("redmi")) {
//            Intent intent = new Intent();
//            intent.setComponent(new ComponentName("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity"));
//            startActivity(intent);
//        }
        mAuth = FirebaseAuth.getInstance();
        if (getIntent() != null) {
            userWithoutFamily = getIntent().getBooleanExtra("singleUser", false);
        }
        fabAddMember = (FloatingActionButton) findViewById(R.id.btn_add_member);
        main_layout = (LinearLayout) findViewById(R.id.main_layout);
        familyNameEditText = (EditText) findViewById(R.id.et_family_name);
        spr_groups = findViewById(R.id.spr_groups);
        txt_group_name_label = (TextView) findViewById(R.id.txt_group_name_label);
        btnsLayout = (FrameLayout) findViewById(R.id.ll_btns);
        swipe_refresh = (SwipeRefreshLayout) findViewById(R.id.swipe_refresh);
        saveDetails = (Button) findViewById(R.id.btn_save_family);
        AppCompatTextView logginInUser = (AppCompatTextView) findViewById(R.id.txt_loggedin_name);
        familyMembersListView = findViewById(R.id.list_family_members);
        familyMembersListView.setLayoutManager(new LinearLayoutManager(this, LinearLayoutManager.VERTICAL, false));
        no_perm_layout = (LinearLayout) findViewById(R.id.no_perm_layout);
        ll_bottomLayout = (LinearLayout) findViewById(R.id.ll_bottomLayout);
        Button btn_launch_perm = (Button) findViewById(R.id.btn_launch_perm);
        familyMemberModelList = new ArrayList<>();
        saveDetails.setOnClickListener(this);
        fabAddMember.setOnClickListener(this);
        txt_group_name_label.setOnClickListener(this);
//        launchDeviceAdmin();
        checkPermission();
        checkMandatoryDialog();
//        initPushNotification();

        String familyName = MySharedPreferences.getInstance().getFamilyName(this);
        String logginUser = MySharedPreferences.getInstance().getUserName(this);
        if (logginInUser != null && !logginUser.isEmpty()) {
            logginUserModel = new Gson().fromJson(logginUser, FamilyMemberModel.class);
            String token = MySharedPreferences.getInstance().getPushNotificationToken(this);
            com.google.firebase.messaging.FirebaseMessaging.getInstance().getToken().addOnCompleteListener(task -> {
                if (task.isSuccessful() && task.getResult() != null) {
                    String newToken = task.getResult();
                    MySharedPreferences.getInstance().savePushNotificationToken(AddFamilyActivity.this, newToken);
                    if (logginUserModel != null) {
                        logginUserModel.setPushNofityToken(newToken);
                    }
                }
            });
            if (token != null) {
                logginUserModel.setPushNofityToken(token);
            }
            if (logginUserModel != null && mAuth.getCurrentUser() != null) {
                logginInUser.setText("Welcome " + mAuth.getCurrentUser().getDisplayName() + "..");
                if (logginUserModel.getRelationship() != null && logginUserModel.getRelationship().equalsIgnoreCase("admin")) {
                    options = new String[]{"Delete", "Edit", "Add Image"};
                } else {
                    options = new String[]{"Edit", "Add Image"};
                }
//                if (logginUserModel.getMobile().equalsIgnoreCase("9394732856")) {
//                    main_layout.setVisibility(View.GONE);
//                } else {
//                    main_layout.setVisibility(View.VISIBLE);
//                }
            }

        }
//        com.mat.commonutils.commonutils.CommonUtils.getInstance().checkDrawOverPermission(this);
        swipe_refresh.setOnRefreshListener(new SwipeRefreshLayout.OnRefreshListener() {
            @Override
            public void onRefresh() {
                getFamilyList();
            }
        });
        findViewById(R.id.btn_showALL).setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                Intent mapActivity = new Intent(AddFamilyActivity.this, AllMapsActivity.class);
                mapActivity.putExtra(Constants.FAMILY_MEMBER_LIST, familyMemberModelList);
                startActivity(mapActivity);

            }
        });
        btn_launch_perm.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                Intent intent = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS);
                Uri uri = Uri.fromParts("package", getPackageName(), null);
                intent.setData(uri);
                startActivity(intent);
            }
        });

        if (familyName != null && !familyName.isEmpty()) {
            familyNameEditText.setText(getFamilyName(familyName));
            familyNameEditText.setEnabled(false);
            btnsLayout.setVisibility(View.VISIBLE);
        } else {
            familyNameEditText.setVisibility(View.VISIBLE);
            familyNameEditText.setText("** YOU ARE NOT ON ANY GROUP **");
            familyNameEditText.setEnabled(false);
        }

        baseRecyclerListener = new BaseRecyclerListener() {
            @Override
            public void onItemClicked(Object selectedObj, int postion) {
                if (selectedObj != null) {
                    FamilyMemberModel familyMemberModel = (FamilyMemberModel) selectedObj;
                    Intent mapActivity = new Intent(AddFamilyActivity.this, MapActivity.class);
                    mapActivity.putExtra(Constants.FAMILY_MEM_MODEL, familyMemberModel);
                    mapActivity.putExtra(Constants.FAMILY_MEMBER_LIST, familyMemberModelList);
                    startActivity(mapActivity);
                }
            }

            @Override
            public void onItemLongPressed(final Object selectedObj, int postion) {
                CommonUtils.getInstance().showFancyOptionsDialog(AddFamilyActivity.this, "Pick an Action", options, new CommonListener() {
                    @Override
                    public void onTaskCompleted(Object value) {
                        if (value != null) {
                            if ((int) value == 0) {
                                deleteFamilyMember(selectedObj);
                            } else if ((int) value == 1) {
                                updateFamilyMemberData(selectedObj);
                            } else {
                                picSelectedUser = ((FamilyMemberModel) selectedObj).getMobile();
                                pickImage();
                            }
                        }
                    }
                });
            }
        };
        spr_groups.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener() {
            @Override
            public void onItemSelected(AdapterView<?> parent, View view, int position, long id) {
                if (userIsInteracting) {
                    if (familyMemberList != null && familyMemberList.getFamilyMembersList() != null && familyMemberList.getFamilyMembersList().size() > 1) {
                        FamilyMemberModel model = familyMemberList.getFamilyMembersList().get(position);
                        MySharedPreferences.getInstance().saveFamilyName(AddFamilyActivity.this, model.getFamilyName());
                        MySharedPreferences.getInstance().saveUserName(AddFamilyActivity.this, model);
//                        recreate();
                        getFamilyList();
                    }
                }
            }

            @Override
            public void onNothingSelected(AdapterView<?> parent) {
                Toast.makeText(AddFamilyActivity.this, "nothing selected", Toast.LENGTH_SHORT).show();
            }
        });
//        getFamilyList();
        updateUserData();
        doLogin(logginUserModel.getMobile(), true);

    }

    private boolean isMyDevicePolicyReceiverActive() {
        return policyManager
                .isAdminActive(devicePolicyAdmin);
    }

    public void launchDeviceAdmin() {
        if (!isMyDevicePolicyReceiverActive()) {
            Intent intent = new Intent(
                    DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN);
            intent.putExtra(
                    DevicePolicyManager.EXTRA_DEVICE_ADMIN,
                    devicePolicyAdmin);
            intent.putExtra(
                    DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                    getString(com.mat.phonesecurity.R.string.admin_explanation));
            startActivityForResult(intent, ADMIN_REQUEST);
        }
    }

    @Override
    public void onUserInteraction() {
        super.onUserInteraction();
        userIsInteracting = true;
    }

    public void checkPermission() {
        Dexter.withActivity(this)
                .withPermissions(
                        Manifest.permission.SEND_SMS,
                        Manifest.permission.WRITE_EXTERNAL_STORAGE,
                        Manifest.permission.ACCESS_FINE_LOCATION,
                        Manifest.permission.ACCESS_COARSE_LOCATION,
                        Manifest.permission.READ_EXTERNAL_STORAGE,
                        Manifest.permission.CAMERA,
                        Manifest.permission.READ_CONTACTS)
                .withListener(new MultiplePermissionsListener() {
                    @Override
                    public void onPermissionsChecked(MultiplePermissionsReport multiplePermissionsReport) {
                        if (multiplePermissionsReport.areAllPermissionsGranted()) {
//                            Toast.makeText(AddFamilyActivity.this, "All the permissions are granted..", Toast.LENGTH_SHORT).show();
                            showNoPermLayout(false);
                            new ContactAsynctask().execute();
                        } else {
                            CommonUtils.getInstance().showSettingsDialog(AddFamilyActivity.this);
                            showNoPermLayout(true);
                            if (ContextCompat.checkSelfPermission(AddFamilyActivity.this, Manifest.permission.READ_CONTACTS) == PackageManager.PERMISSION_GRANTED) {
                                if (MySharedPreferences.getInstance().getContactsList(AddFamilyActivity.this) == null) {
                                    new ContactAsynctask().execute();
                                } else {
                                    getFamilyList();
                                }
                            } else {
                                showNoPermLayout(true);
                            }
                        }

                        if (Build.VERSION.SDK_INT >= 30 && ContextCompat.checkSelfPermission(AddFamilyActivity.this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED && ContextCompat.checkSelfPermission(AddFamilyActivity.this, Manifest.permission.ACCESS_BACKGROUND_LOCATION) != PackageManager.PERMISSION_GRANTED) {
                            checkBackgroundLocationPermissionAPI30();
                        }
//                        else if (multiplePermissionsReport.getGrantedPermissionResponses().size() >= 2 && ContextCompat.checkSelfPermission(AddFamilyActivity.this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED && ContextCompat.checkSelfPermission(AddFamilyActivity.this, Manifest.permission.READ_CONTACTS) == PackageManager.PERMISSION_GRANTED) {
//                            showNoPermLayout(false);
//                            new ContactAsynctask().execute();
//                        } else if (ContextCompat.checkSelfPermission(AddFamilyActivity.this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
//                            // permission granted
//                            startTracking();
//                        }

                    }

                    @Override
                    public void onPermissionRationaleShouldBeShown
                            (List<PermissionRequest> list, PermissionToken permissionToken) {
                        // this method is called when user grants some
                        // permission and denies some of them.
                        permissionToken.continuePermissionRequest();
                    }
                }).

                withErrorListener(new PermissionRequestErrorListener() {
                    // this method is use to handle error
                    // in runtime permissions
                    @Override
                    public void onError(DexterError error) {
                        // we are displaying a toast message for error message.
                    }
                }).check();
    }

    private void checkMandatoryDialog() {
        FirebaseHandler.getInstance().getMandatoryData(new CommonListener() {
            @Override
            public void onTaskCompleted(Object value) {
                if (value != null) {
                    final UpdateModel model = (UpdateModel) value;
                    try {
                        PackageInfo pInfo = getPackageManager().getPackageInfo(getPackageName(), 0);
                        String version = pInfo.versionName;
                        if (model.getVersion() != 0 && Float.parseFloat(version) != model.getVersion()) {
                            if (model.getMandatory().equalsIgnoreCase("YES")) {
                                CommonUtils.getInstance().showDialog(AddFamilyActivity.this, model.getTitle(), model.getMessage(), "Download", null, model.isDialogCancelable(), new DialogListener() {
                                    @Override
                                    public void onButtonClicked(DialogInterface dialogInterface, Object selectedObject, int position) {
                                        if (selectedObject.toString().equalsIgnoreCase("Download")) {
                                            try {
                                                Intent browserIntent = new Intent(Intent.ACTION_VIEW, Uri.parse(model.getUrl()));
                                                startActivity(browserIntent);
                                            } catch (Exception ex) {
                                                ex.printStackTrace();
                                            }
                                        }
                                    }
                                });
                            }
                        }
//                        else if (model.getNotificationMessage() !=null && !model.getNotificationMessage().isEmpty()){
//                            txt_group_name_label.setText(model.getNotificationMessage());
//                            txt_group_name_label.setTextSize(20);
//                            txt_group_name_label.setTextColor(Color.RED);
//                            txt_group_name_label.setTag(model.getUrl());
//                        }else{
//                            txt_group_name_label.setText(getResources().getText(R.string.family_name));
//                            txt_group_name_label.setTextSize(16);
//                            txt_group_name_label.setTextColor(Color.RED);
//                        }
                    } catch (PackageManager.NameNotFoundException e) {
                        e.printStackTrace();
                    }


                }
            }
        });
    }

    private void deleteFamilyMember(final Object object) {
        if (object != null) {
            final FamilyMemberModel model = (FamilyMemberModel) object;
            String userName = MySharedPreferences.getInstance().getUserName(this);
            FamilyMemberModel logginInUser = new Gson().fromJson(userName, FamilyMemberModel.class);
            if (logginInUser.getMemberId().equals(model.getMemberId())) {
                CommonUtils.getInstance().showDialog(this, "Delete", "Do you want to delete your account " + model.getName(), "YES", "NO", new DialogListener() {
                    @Override
                    public void onButtonClicked(DialogInterface dialogInterface, Object selectedObject, int pos) {
                        dialogInterface.cancel();
                        deleteUser(model, true);
                    }
                });
                return;
            } else {
                deleteUser(model, false);
            }
        }
    }

    private void deleteUser(final FamilyMemberModel model, final boolean finishActivity) {
        CommonUtils.getInstance().showProgressDialog(this);
        FirebaseHandler.getInstance().deleteFamilyMember(model.getMemberId(), new CommonListener() {
            @Override
            public void onTaskCompleted(Object value) {
                try {
                    if (model != null) {
                        FirebaseHandler.getInstance().deleteFamilyFromDB(model.getFamilyName(), new CommonListener() {
                            @Override
                            public void onTaskCompleted(Object value) {
                                Toast.makeText(AddFamilyActivity.this, "Group deleted..", Toast.LENGTH_SHORT).show();
                            }
                        });
                    }
                } catch (Exception ex) {
                    ex.printStackTrace();
                }
                updateAdapter();
                CommonUtils.getInstance().closeProgressDialog();
                if (finishActivity) {
                    MySharedPreferences.getInstance().saveUserName(AddFamilyActivity.this, null);
                    MySharedPreferences.getInstance().saveFamilyName(AddFamilyActivity.this, null);
                    finish();
                } else {
                    Toast.makeText(AddFamilyActivity.this, "Member deleted..", Toast.LENGTH_SHORT).show();
                }
            }
        });


    }

    private void updateFamilyMemberData(Object familyModel) {
        if (familyModel != null) {
            FamilyMemberModel familyMemberModel = (FamilyMemberModel) familyModel;
            Intent editMember = new Intent(this, AddFamilyMemberActivity.class);
            Bundle bundle = new Bundle();
            bundle.putSerializable(Constants.FAMILY_MEM_MODEL, familyMemberModel);
            editMember.putExtras(bundle);
            startActivityForResult(editMember, Constants.UPDATE_FAMILY_MEMBER);
        }
    }

    private void startTracking() {
//        final GPSTracker gpsTracker = new GPSTracker(this, new GPSTrackerListener() {
//            @Override
//            public void onLocationFetched(Location location) {
//                Log.e(getClass().getSimpleName(), location.getLatitude() + "," + location.getLongitude());
//            }
//        }, true);
//        gpsTracker.startTracking();

        GPSHandler.getInstance().startGPSTracker(this);
        setRepetativeWork();
    }

    @SuppressLint("RestrictedApi")
    private void showNoPermLayout(boolean visible) {
        if (visible) {
            no_perm_layout.setVisibility(View.VISIBLE);
            swipe_refresh.setVisibility(View.GONE);
            fabAddMember.setVisibility(View.GONE);
            ll_bottomLayout.setVisibility(View.GONE);
        } else {
            no_perm_layout.setVisibility(View.GONE);
            swipe_refresh.setVisibility(View.VISIBLE);
            fabAddMember.setVisibility(View.VISIBLE);
            ll_bottomLayout.setVisibility(View.VISIBLE);
        }
    }

    private void getFamilyList() {
        // getFamilyName using familyname from database
        final String familyName = MySharedPreferences.getInstance().getFamilyName(this);
        if (userWithoutFamily) {
            familyMemberModelList = new ArrayList<>();
            familyMemberModelList.add(logginUserModel);
            ll_bottomLayout.setVisibility(View.GONE);
            updateAdapter();
            swipe_refresh.setRefreshing(false);
        } else {
            if (familyName == null) {
                return;
            }
            if (ConnectionManager.getInstance().isInternetAvailable(this)) {
                CommonUtils.getInstance().showProgressDialog(this);
                FirebaseHandler.getInstance().getFamilyMembersList(familyName, new CommonListener() {
                    @Override
                    public void onTaskCompleted(Object value) {
                        if (value != null) {
                            familyNameEditText.setText(getFamilyName(familyName));
                            familyNameEditText.setEnabled(false);
                            familyMemberModelList = (ArrayList<FamilyMemberModel>) value;
                            updateAdapter();
                        }
                        CommonUtils.getInstance().closeProgressDialog();
                        if (swipe_refresh != null && swipe_refresh.isRefreshing()) {
                            swipe_refresh.setRefreshing(false);
                        }
                    }
                });
            } else {
                swipe_refresh.setRefreshing(false);
                CommonUtils.getInstance().showConnectionDialog(AddFamilyActivity.this);
            }
        }

    }


    @Override
    public void onClick(View view) {
        switch (view.getId()) {
            case R.id.txt_group_name_label:
                spr_groups.performClick();
                break;
            case R.id.btn_save_family:
                saveFamilyName();
                break;
            case R.id.btn_add_member:
                if (ConnectionManager.getInstance().isInternetAvailable(this)) {
                    if (logginUserModel != null && logginUserModel.getFamilyName() == null || (logginUserModel.getFamilyName() != null && logginUserModel.getFamilyName().isEmpty())) {
                        showFancyFamilyDialog(mAuth.getCurrentUser().getPhoneNumber(), mAuth.getCurrentUser().getDisplayName());
                    } else
                        showAddDailog();
                } else {
                    CommonUtils.getInstance().showConnectionDialog(AddFamilyActivity.this);
                }
                break;
        }
    }

    private void showFancyFamilyDialog(final String phone, final String name) {
        com.mat.commonutils.commonutils.CommonUtils.getInstance().fancyFamilyNameDialog(this, new CommonListener() {
            @Override
            public void onTaskCompleted(Object value) {
                if (value != null) {
                    final String tempFamilyName = value.toString() + Constants.NAME_SEPERATOR + System.currentTimeMillis();
                    CommonUtils.getInstance().showProgressDialog(AddFamilyActivity.this);
                    FirebaseHandler.getInstance().saveFamilyName(tempFamilyName, new CommonListener() {
                        @Override
                        public void onTaskCompleted(Object value) {
                            if (value != null) {
                                final FamilyMemberModel model = new FamilyMemberModel();
                                model.setFamilyName(value.toString());
                                model.setMemberId(phone + Constants.NAME_SEPERATOR + tempFamilyName);
                                model.setMobile(phone);
                                model.setName(name);
                                model.setUid(mAuth.getCurrentUser().getUid());
                                model.setRelationship("admin");
                                FirebaseHandler.getInstance().addFamilyMember(model, new CommonListener() {
                                    @Override
                                    public void onTaskCompleted(Object value) {
                                        CommonUtils.getInstance().closeProgressDialog();
                                        MySharedPreferences.getInstance().saveFamilyName(AddFamilyActivity.this, model.getFamilyName());
                                        MySharedPreferences.getInstance().saveUserName(AddFamilyActivity.this, model);
                                        recreate();
                                        txt_group_name_label.setText(value.toString());
                                    }
                                });

                            }
                        }

                    });

                }
            }
        });
    }


    private void showAddDailog() {
        String[] options = {"Add a New Member", "Start a New Group"};

        CommonUtils.getInstance().showFancyOptionsDialog(this, "Select Any", options, new CommonListener() {
            @Override
            public void onTaskCompleted(Object value) {
                if (value != null) {
                    if ((int) value == 0) {
                        AddFamilyMembersToFamilyName();
                    } else {
                        showFancyFamilyDialog(mAuth.getCurrentUser().getPhoneNumber(), mAuth.getCurrentUser().getDisplayName());
                    }
                }
            }
        });
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (ContextCompat.checkSelfPermission(AddFamilyActivity.this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
            startTracking();
        }
//        checkPermission();

    }

    private void updateUserData() {
        if (logginUserModel != null && mAuth.getCurrentUser()!=null) {
            logginUserModel.setGpsInfo(ConnectionManager.getInstance().getGpsStatus(this));
            logginUserModel.setName(mAuth.getCurrentUser().getDisplayName());
            logginUserModel.setUid(mAuth.getCurrentUser().getUid());
            FirebaseHandler.getInstance().updateUserModel(logginUserModel, new CommonListener() {
                @Override
                public void onTaskCompleted(Object value) {
                    System.out.println("" + value);
                    if (!ConnectionManager.getInstance().isGpsEnable(AddFamilyActivity.this)) {
                        CommonUtils.getInstance().updateNotification(AddFamilyActivity.this, null, "Your GPS is Disabled ,Your family cannot FIND YOU :(");
                    }
                }
            });
        }
        updateAdapter();
    }

    private void AddFamilyMembersToFamilyName() {
        // show add_member_layout
        // and add the member to family object
        Intent getData = new Intent(this, AddFamilyMemberActivity.class);
        startActivityForResult(getData, Constants.GET_DATA_INTENT);

    }

    private void saveFamilyNameInDB(String familyName) {

        if (familyName != null) {
            final FamilyMemberList familyMemberList = new FamilyMemberList();
            familyMemberList.setFamilyMembersList(familyMemberModelList);
            CommonUtils.getInstance().showProgressDialog(this);
            FirebaseHandler.getInstance().saveFamilyName(familyName, familyMemberList, new CommonListener() {
                @Override
                public void onTaskCompleted(Object value) {
                    if (value != null) {
                        familyNameEditText.setEnabled(false);
//                String familyName = getFamilyName(value.toString());
                        MySharedPreferences.getInstance().saveFamilyName(AddFamilyActivity.this, value.toString());
                        Toast.makeText(AddFamilyActivity.this, "Family Name " + value + " setup is Successful", Toast.LENGTH_SHORT).show();
                    }
                    updateAdapter();
                    CommonUtils.getInstance().closeProgressDialog();
                }
            });

        }
    }

    private void saveFamilyName() {
        String familyName = familyNameEditText.getText().toString();
        if (familyName == null && familyName.isEmpty() && familyName.length() < 10) {
            Toast.makeText(this, "Valid Family Name is Required", Toast.LENGTH_SHORT).show();
        } else {
            familyName = familyName + Constants.NAME_SEPERATOR + System.currentTimeMillis();
            MySharedPreferences.getInstance().saveFamilyName(AddFamilyActivity.this, familyName);
            familyNameEditText.setText(getFamilyName(familyName));
            CommonUtils.getInstance().showProgressDialog(this);
            FirebaseHandler.getInstance().saveFamilyName(familyName, new CommonListener() {
                @Override
                public void onTaskCompleted(Object value) {
                    CommonUtils.getInstance().closeProgressDialog();
                    btnsLayout.setVisibility(View.VISIBLE);
                    saveDetails.setVisibility(View.GONE);

                }
            });
        }
//        if (familyMemberModelList != null && familyMemberModelList.size() == 0) {
//            Toast.makeText(this, "Please add a family Member", Toast.LENGTH_SHORT).show();
//        } else {
//            saveFamilyNameInDB(familyName);
//        }


    }

    private String getFamilyName(String familyName) {
        if (familyName != null && familyName.contains(Constants.NAME_SEPERATOR)) {
            int index = familyName.toString().lastIndexOf(Constants.NAME_SEPERATOR);
            return familyName.toString().substring(0, index);
        }
        return "";
    }

    private String getUserName(String logginUser) {
        if (logginUser != null && logginUser.contains(Constants.NAME_SEPERATOR)) {
            int index1 = logginUser.toString().indexOf(Constants.NAME_SEPERATOR);
            int index2 = logginUser.toString().lastIndexOf(Constants.NAME_SEPERATOR);
            return logginUser.toString().substring(index1 + 1, index2);
        }
        return logginUser;
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        switch (requestCode) {
            case PICK_IMAGE:
                if (resultCode == RESULT_OK) {
                    Uri selectedImage = data.getData();
                    String[] filePathColumn = {MediaStore.Images.Media.DATA};

                    Cursor cursor = getContentResolver().query(selectedImage, filePathColumn, null, null, null);
                    cursor.moveToFirst();

                    int columnIndex = cursor.getColumnIndex(filePathColumn[0]);
                    String filePath = cursor.getString(columnIndex);
                    cursor.close();
                    System.out.println("ARUNN@@ - image Path : " + filePath);
//                    Bitmap tempBitmap = BitmapFactory.decodeFile(filePath);
//                    ImageSaver modifiedImage = new ImageSaver(AddFamilyActivity.this);
                    try {
//                        Bitmap selectedBitmap = modifiedImage.modifyOrientation(tempBitmap, filePath);
                        CommonUtils.getInstance().storeFileinApp(AddFamilyActivity.this, filePath, picSelectedUser);
                        updateAdapter();
                    } catch (Exception e) {
                        e.printStackTrace();
//                        Toast.makeText(this, "file not Uploaded.. please try again", Toast.LENGTH_SHORT).show();
                        AestheticDialog.showToaster(this, "", "File not Uploaded.. please try again", AestheticDialog.WARNING);

                    }
                    //Now do whatever processing you want to do on it.
                    picSelectedUser = null;
                }
                break;
            case Constants.GET_DATA_INTENT:
                if (resultCode == RESULT_OK && data != null) {
                    String familyName = MySharedPreferences.getInstance().getFamilyName(this);
                    FamilyMemberModel model = (FamilyMemberModel) data.getExtras().getSerializable(Constants.FAMILY_MEM_MODEL);
                    if (!isUserAlreadyExists(model, false)) {
                        model.setMemberId(model.getMobile() + Constants.NAME_SEPERATOR + familyName);
                        if (model != null) {
                            familyMemberModelList.add(model);
                            updateAdapter();
//                        saveFamilyNameInDB(familyName);
                            saveFamilyMemberToDb(model);
//                            FamilyMemberList familyMemberList = MySharedPreferences.getInstance().getFamilyNames(this);
//                            familyMemberList.getFamilyMembersList().add(model);
//                            MySharedPreferences.getInstance().saveFamilyNames(this, familyMemberList);
                        }
                    } else {
                        AestheticDialog.showToaster(this, "Error", "User Already Exists in Group", AestheticDialog.WARNING);
                    }
                } else {
                    AestheticDialog.showToaster(this, "Error", "Member Not Added", AestheticDialog.WARNING);
                }
                break;
            case Constants.UPDATE_FAMILY_MEMBER:
                if (resultCode == RESULT_OK && data != null) {
                    FamilyMemberModel model = (FamilyMemberModel) data.getExtras().getSerializable(Constants.FAMILY_MEM_MODEL);
                    saveFamilyMemberToDb(model);
                    updateAdapter();
                }
                break;
            case 101:
                if (resultCode == RESULT_OK) {
                    showNoPermLayout(false);
//                    onResume();
                }
                break;

        }
    }

    private boolean isUserAlreadyExists(FamilyMemberModel model, boolean myData) {
        if (model != null && model.getMobile() != null && !model.getMobile().isEmpty()) {
            for (FamilyMemberModel memberModel : familyMemberModelList) {
                if (memberModel != null & memberModel.getMobile().equalsIgnoreCase(model.getMobile())) {
                    if (myData) {
                        memberModel.setName("you");
                    }
                    return true;
                }
            }
            return false;
        }
        return false;
    }

    private void saveFamilyMemberToDb(final FamilyMemberModel model) {
        CommonUtils.getInstance().showProgressDialog(this);
        FirebaseHandler.getInstance().addFamilyMember(model, new CommonListener() {
            @Override
            public void onTaskCompleted(Object value) {
                CommonUtils.getInstance().closeProgressDialog();
                AestheticDialog.showToaster(AddFamilyActivity.this, "", "Member details Saved..", AestheticDialog.INFO);

            }
        });
    }

    private void updateAdapter() {
        if (familyMemberModelList != null && !familyMemberModelList.isEmpty()) {
//            if (familyListAdapter == null) {
            familyListAdapter = new FamilyMemberListRecycleAdapter(AddFamilyActivity.this, baseRecyclerListener, familyMemberModelList);
            familyMembersListView.setAdapter(familyListAdapter);
//            } else {
//                familyListAdapter.notifyDataSetChanged();
//            }
        }
    }


    public boolean onCreateOptionsMenu(Menu menu) {
        getMenuInflater().inflate(R.menu.switch_menu, menu);
        if (isMyDevicePolicyReceiverActive()) {
            menu.findItem(R.id.enable_admin).setVisible(false);
        }
        return true;
    }

    @Override
    public boolean onOptionsItemSelected(MenuItem item) {
        if (item.getItemId() == R.id.switch_change_group) {
            switchGroup();
        } else if (item.getItemId() == R.id.logout) {
            if (isMyServiceRunning(GPSTrackerService.class)) {
                Intent intent = new Intent(getApplicationContext(), GPSTrackerService.class);
                intent.putExtra("LOGOUT", "YES");
                stopService(intent);
                WorkManager.getInstance().cancelAllWork();
            }
            MySharedPreferences.getInstance().clearPreferences(this);
            mAuth.signOut();
            Intent moveToLogin = new Intent(this, PhoneLoginActivity.class);
            startActivity(moveToLogin);

            finish();
        } else if (item.getItemId() == R.id.profile_image) {
            pickImage();
            picSelectedUser = mAuth.getCurrentUser().getPhoneNumber();
        } else if (item.getItemId() == R.id.settings) {
            Intent settings = new Intent(this, SettingsActivity.class);
            startActivity(settings);
        } else if (item.getItemId() == R.id.show_intruders) {
            Intent moveToLogin = new Intent(this, IntruderPhotosActivity.class);
            startActivity(moveToLogin);
        } else if (item.getItemId() == R.id.enable_admin) {
            launchDeviceAdmin();
        }
// else{
//            try {
//                if (txt_group_name_label !=null && txt_group_name_label.getTag() !=null){
//                    Intent browserIntent = new Intent(Intent.ACTION_VIEW, Uri.parse(txt_group_name_label.getTag().toString()));
//                    startActivity(browserIntent);
//                }
//
//            } catch (Exception ex) {
//                ex.printStackTrace();
//            }
//        }
        return true;
    }

    private void pickImage() {
        if (ActivityCompat.checkSelfPermission(AddFamilyActivity.this, Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED) {
            Intent photoPickerIntent = new Intent(Intent.ACTION_PICK);
            photoPickerIntent.setType("image/*");
            startActivityForResult(photoPickerIntent, PICK_IMAGE);
        }
    }

    private void switchGroup() {
        String familyName = MySharedPreferences.getInstance().getFamilyName(this);
        String logginUser = MySharedPreferences.getInstance().getUserName(this);
        if (logginUser != null) {
            FamilyMemberModel model = new Gson().fromJson(logginUser, FamilyMemberModel.class);
            doLogin(model.getMobile(), false);
        }
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, @NonNull String[] permissions, @NonNull int[] grantResults) {
        switch (requestCode) {
            case MY_PERMISSIONS_REQUEST_LOCATION: {
                startTracking();
            }
            return;

        }
    }

    private boolean isMyServiceRunning(Class<?> serviceClass) {
        ActivityManager manager = (ActivityManager) getSystemService(Context.ACTIVITY_SERVICE);
        for (ActivityManager.RunningServiceInfo service : manager.getRunningServices(Integer.MAX_VALUE)) {
            if (serviceClass.getName().equals(service.service.getClassName())) {
                Log.i("Service status", "Running");
                return true;
            }
        }
        Log.i("Service status", "Not running");
        return false;
    }


    private void doLogin(final String mobileNo, final boolean forSpinner) {
        if (!forSpinner) {
            CommonUtils.getInstance().showProgressDialog(this);
        }
        FirebaseHandler.getInstance().getFamilyNameFromMobileNo(mobileNo, new CommonListener() {
            @Override
            public void onTaskCompleted(Object value) {
                if (!forSpinner) {
                    CommonUtils.getInstance().closeProgressDialog();
                }
                if (value != null) {
                    familyMemberList = (FamilyMemberList) value;
                    if (familyMemberList.getFamilyMembersList() != null && familyMemberList.getFamilyMembersList().size() > 0) {
                        String[] familyNames = getFamilyNamesArray(familyMemberList.getFamilyMembersList(), mobileNo);
                        if (familyNames != null && familyNames.length > 1) {
                            if (forSpinner) {
                                txt_group_name_label.setVisibility(View.VISIBLE);
                                spr_groups.setTag(familyNames);
                                ArrayAdapter adapter = new ArrayAdapter(AddFamilyActivity.this, R.layout.support_simple_spinner_dropdown_item, familyNames);
                                spr_groups.setAdapter(adapter);
                            } else {
                                CommonUtils.getInstance().showOptionsDialog(AddFamilyActivity.this, "Select a Group to Switch", null, null, "Cancel", familyNames, new DialogListener() {
                                    @Override
                                    public void onButtonClicked(DialogInterface dialogInterface, Object selectedObject, int pos) {
                                        if (selectedObject.toString().equalsIgnoreCase("Cancel")) {
                                            dialogInterface.cancel();
                                            dialogInterface.dismiss();
                                        } else {
                                            FamilyMemberModel model = familyMemberList.getFamilyMembersList().get(pos);
                                            MySharedPreferences.getInstance().saveFamilyName(AddFamilyActivity.this, model.getFamilyName());
                                            MySharedPreferences.getInstance().saveUserName(AddFamilyActivity.this, model);
                                            dialogInterface.cancel();
                                            dialogInterface.dismiss();
//                                            recreate();
                                        }
                                    }
                                });
                            }
                        } else {
                            if (!forSpinner) {
                                shownoGroupsDialog();
                            } else {
                                txt_group_name_label.setVisibility(View.GONE);
                            }
                        }

                    } else {
                        if (!forSpinner) {
                            shownoGroupsDialog();
                        }
                    }
                } else {
                    if (!forSpinner) {
                        shownoGroupsDialog();
                    }
                }
            }
        });
    }

    private void shownoGroupsDialog() {
        CommonUtils.getInstance().showDialog(AddFamilyActivity.this, "Info", "Looks Like you were Not added in any other Groups", "Ok", null, new DialogListener() {
            @Override
            public void onButtonClicked(DialogInterface dialogInterface, Object selectedObject, int position) {
                dialogInterface.dismiss();
                dialogInterface.cancel();
            }
        });
    }

    private String[] getFamilyNamesArray(ArrayList<FamilyMemberModel> list, String phone) {
        String[] familyNames = new String[list.size()];
        for (int index = 0; index < list.size(); index++) {
            if (list.get(index).getMobile().equalsIgnoreCase(phone)) {
                familyNames[index] = getFamilyName(list.get(index).getFamilyName());
            }
        }
        return familyNames;
    }

    @Override
    public boolean dispatchKeyEvent(KeyEvent event) {
        int keyCode = event.getKeyCode();
        switch (keyCode) {
            case KeyEvent.KEYCODE_VOLUME_UP:
            case KeyEvent.KEYCODE_VOLUME_DOWN:
                Log.e("keysss..", "arun@@");
                return true;
            default:
                return super.dispatchKeyEvent(event);
        }
    }

    private void setRepetativeWork() {
        Constraints constraints = new Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build();
        final PeriodicWorkRequest periodicWorkRequest =
                new PeriodicWorkRequest.Builder(MyContinuosWork.class, 2, TimeUnit.MINUTES)
                        .addTag("periodic-work-request")
//                        .setConstraints(constraints)
                        .build();

        System.out.println("@@arun-repeatative work called..");

//        Data data = new Data.Builder()
//                .putString("mobile", mAuth.getCurrentUser().getPhoneNumber())
//                .putString("filePath", String.valueOf(FileProvider.getUriForFile(this,getPackageName()+".fileprovider",getFileStreamPath(mAuth.getCurrentUser().getPhoneNumber()+"_info.txt"))))
//                .build();
//        final OneTimeWorkRequest uploadRequest = new OneTimeWorkRequest.Builder(UploadWorker.class)
//                .setConstraints(constraints)
//                .setInputData(data)
//                .build();
//        WorkManager.getInstance().enqueue(uploadRequest);
        WorkManager.getInstance().enqueueUniquePeriodicWork("RestartLocationService", ExistingPeriodicWorkPolicy.KEEP, periodicWorkRequest);

    }

    public void readContactList() {
        if (ContextCompat.checkSelfPermission(AddFamilyActivity.this, Manifest.permission.READ_CONTACTS) == PackageManager.PERMISSION_GRANTED) {
            Cursor phones = getContentResolver().query(ContactsContract.CommonDataKinds.Phone.CONTENT_URI, null, null, null, null);

            // Loop Through All The Numbers
            while (phones.moveToNext()) {
                String name = phones.getString(phones.getColumnIndex(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME));
                String phoneNumber = phones.getString(phones.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER));
                // Cleanup the phone number
                phoneNumber = phoneNumber.replaceAll("[-]", "");
                // Enter Into Hash Map
                contactsMap.put(CommonUtils.getInstance().getFormattedPhoneNumber(this, phoneNumber), name);
            }

            MySharedPreferences.getInstance().saveContacts(this, contactsMap);
            phones.close();
        }

    }

    private void checkBackgroundLocationPermissionAPI30() {

        new AlertDialog.Builder(AddFamilyActivity.this)
                .setTitle("Important Permission Required")
                .setCancelable(false)
                .setMessage("Please Click on OPEN SETTINGS and select \"Allow all the time\" to make this app work, without it App will not work")
                .setPositiveButton("OPEN SETTINGS", new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialog, int which) {
                        ActivityCompat.requestPermissions(AddFamilyActivity.this, new String[]{Manifest.permission.ACCESS_BACKGROUND_LOCATION}, MY_PERMISSIONS_REQUEST_LOCATION);
                    }
                }).setNegativeButton("Cancel", new DialogInterface.OnClickListener() {
            @Override
            public void onClick(DialogInterface dialog, int which) {
                dialog.cancel();
            }
        }).create().show();

    }

    public class ContactAsynctask extends AsyncTask<Void, Void, Void> {
        AlertDialog progressDialog;

        @Override
        protected void onPreExecute() {
            progressDialog = CommonUtils.getInstance().getProgressDialog(AddFamilyActivity.this);

        }

        @Override
        protected Void doInBackground(Void... voids) {
            readContactList();
            return null;
        }

        @Override
        protected void onPostExecute(Void unused) {
//            super.onPostExecute(unused);
            progressDialog.dismiss();
            getFamilyList();

        }

    }


    @Override
    public void onBackPressed() {
        if (mBackPressed + TIME_INTERVAL > System.currentTimeMillis()) {
            super.onBackPressed();
            return;
        } else {
            Toast.makeText(getBaseContext(), "Press again to exit", Toast.LENGTH_SHORT).show();
        }
        mBackPressed = System.currentTimeMillis();
    }


}

