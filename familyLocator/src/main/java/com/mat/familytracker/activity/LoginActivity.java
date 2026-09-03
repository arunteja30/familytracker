package com.mat.familytracker.activity;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.DialogInterface;
import android.content.Intent;
import android.os.Bundle;
import androidx.core.content.ContextCompat;
import androidx.appcompat.app.AppCompatActivity;
import androidx.appcompat.widget.AppCompatEditText;
import androidx.appcompat.widget.AppCompatSpinner;
import android.view.LayoutInflater;
import android.view.View;
import android.view.Window;
import android.view.WindowManager;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.EditText;
import android.widget.TextView;
import android.widget.Toast;

import com.google.firebase.auth.FirebaseAuth;
import com.mat.commonutils.FBAuth.ContryData;
import com.mat.commonutils.commonutils.CommonListener;
import com.mat.familytracker.R;
import com.mat.familytracker.domain.FamilyMemberModel;
import com.mat.familytracker.domain.RegistrationModel;
import com.mat.familytracker.pushNotification.FirebaseIDService;
import com.mat.familytracker.utils.CommonUtils;
import com.mat.familytracker.utils.Constants;
import com.mat.familytracker.utils.DialogListener;
import com.mat.familytracker.utils.MySharedPreferences;

import java.util.ArrayList;

public class LoginActivity extends AppCompatActivity {

    EditText etFamilyName = null;
    private AppCompatEditText etEmailId, etPassword;
    private Button btnSignup, btnFind;
    private TextView login_txt_signup;
    private AppCompatSpinner countrySpinner;

    private void checkLoginDetails() {
        String email = etEmailId.getText().toString();
        String password = etPassword.getText().toString();
        if (email.isEmpty() || email.length() < 10) {
            etEmailId.setError("Valid mobile is required");
            etEmailId.requestFocus();
        } else {
            // all details Valid
            email = email.replace("+91", "");
            doLogin(email);

        }

    }


    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_login);
        etEmailId = (AppCompatEditText) findViewById(R.id.login_et_email);
        etPassword = (AppCompatEditText) findViewById(R.id.login_et_password);
        btnFind = (Button) findViewById(R.id.login_btn_find_fnds);
        btnSignup = (Button) findViewById(R.id.login_btn_signup);
        countrySpinner = findViewById(R.id.spr_ctry_code);
        login_txt_signup = (TextView) findViewById(R.id.login_txt_signup);
        countrySpinner.setAdapter(new ArrayAdapter<String>(this, android.R.layout.simple_spinner_dropdown_item, ContryData.countryNames));
        String userName = MySharedPreferences.getInstance().getUserName(this);
        if (userName != null) {
            moveToAddScreen();
        }
        Window window = getWindow();

// clear FLAG_TRANSLUCENT_STATUS flag:
        window.clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS);

// add FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS flag to the window
        window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS);

// finally change the color
        window.setStatusBarColor(ContextCompat.getColor(this, R.color.colorPrimaryDark));
        btnSignup.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View view) {
                checkSignUpDetails();
            }
        });
        btnFind.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View view) {
                checkLoginDetails();
            }
        });
        login_txt_signup.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View view) {
                login_txt_signup.setText("Sign In");
                if (etPassword.getVisibility() == View.VISIBLE) {
                    etPassword.setVisibility(View.GONE);
                    btnFind.setVisibility(View.VISIBLE);
                    btnSignup.setVisibility(View.GONE);
                } else {
                    etPassword.setVisibility(View.VISIBLE);
                    btnFind.setVisibility(View.GONE);
                    btnSignup.setVisibility(View.VISIBLE);
                }
            }
        });


    }

    private void checkSignUpDetails() {
        String phone = etEmailId.getText().toString();
        String name = etPassword.getText().toString();
        if (phone.isEmpty() || phone.length() < 10 || (int) (phone.charAt(0)) < 6) {
            etEmailId.setError("Valid mobile is required");
            etEmailId.requestFocus();
        } else if (name.isEmpty() || name.length() < 4) {
            etPassword.setError("please enter your name");
            etPassword.requestFocus();
        } else {
            phone = phone.replace("+91", "");
            registerNumber(phone, name);
            return;
        }

    }

    public void registerNumber(final String phone, final String name, String uid) {
        CommonUtils.getInstance().showProgressDialog(this);
        FirebaseHandler.getInstance().registerPhoneNumber(new RegistrationModel(phone, name, uid), new CommonListener() {
            @Override
            public void onTaskCompleted(Object value) {
                CommonUtils.getInstance().closeProgressDialog();
                if (value != null) {
                    checkNumberAlreadyExists(phone, name);
                }
            }
        });

    }

    private void registerNumber(final String phone, final String name) {
        CommonUtils.getInstance().showProgressDialog(this);
        FirebaseHandler.getInstance().registerPhoneNumber(new RegistrationModel(phone, name, null), new CommonListener() {
            @Override
            public void onTaskCompleted(Object value) {
                CommonUtils.getInstance().closeProgressDialog();
                if (value != null) {
                    checkNumberAlreadyExists(phone, name);
                }
            }
        });

    }

    protected void checkNumberAlreadyExists(final String phone, final String name) {
        CommonUtils.getInstance().showProgressDialog(this);
        FirebaseHandler.getInstance().getFamilyNameFromMobileNo(phone, new CommonListener() {
            @Override
            public void onTaskCompleted(Object value) {
                CommonUtils.getInstance().closeProgressDialog();
                if (value != null) {
                    FamilyMemberList familyMemberList = (FamilyMemberList) value;
                    ArrayList<FamilyMemberModel> list = familyMemberList.getFamilyMembersList();
                    if (list != null && !list.isEmpty()) {
                        String[] familyNames = getFamilyNamesArray(list, phone);
                        if (familyNames != null && familyNames.length > 0) {
                            CommonUtils.getInstance().showOptionsDialog(LoginActivity.this, "Select", "Your family is waiting for you in the below group(s), select one",
                                    null, "create new group", familyNames, new DialogListener() {
                                        @Override
                                        public void onButtonClicked(DialogInterface dialogInterface, Object selectedObject, int pos) {

                                            if (selectedObject.toString().equalsIgnoreCase("create new group")) {
                                                MySharedPreferences.getInstance().firstLaunch(LoginActivity.this, true);
                                                dialogInterface.cancel();
                                                showFancyFamilyDialog(phone, name);
//                                        showFailyNameDialog(phone, name);
                                                return;
                                            } else {
                                                dialogInterface.cancel();
                                                doLogin(phone);
                                            }

                                        }
                                    });
                        }
                    } else {
//                        showFailyNameDialog(phone, name);
                        showFancyFamilyDialog(phone, name);
                    }

                }
            }
        });
    }

    private void showFancyFamilyDialog(final String phone, final String name) {
        com.mat.commonutils.commonutils.CommonUtils.getInstance().fancyFamilyNameDialog(this, new CommonListener() {
            @Override
            public void onTaskCompleted(Object value) {
                if (value != null) {
                    final String tempFamilyName = value.toString() + Constants.NAME_SEPERATOR + System.currentTimeMillis();
                    CommonUtils.getInstance().showProgressDialog(LoginActivity.this);
                    FirebaseHandler.getInstance().saveFamilyName(tempFamilyName, new CommonListener() {
                        @Override
                        public void onTaskCompleted(Object value) {
                            if (value != null) {
                                final FamilyMemberModel model = new FamilyMemberModel();
                                model.setFamilyName(value.toString());
                                model.setMemberId(phone + Constants.NAME_SEPERATOR + tempFamilyName);
                                model.setMobile(phone);
                                model.setName(name);
                                model.setRegistered(true);
                                model.setUid(FirebaseAuth.getInstance().getCurrentUser().getUid());
                                model.setRelationship("admin");
                                FirebaseHandler.getInstance().addFamilyMember(model, new CommonListener() {
                                    @Override
                                    public void onTaskCompleted(Object value) {
                                        CommonUtils.getInstance().closeProgressDialog();
                                        MySharedPreferences.getInstance().saveFamilyName(LoginActivity.this, model.getFamilyName());
                                        MySharedPreferences.getInstance().saveUserName(LoginActivity.this, model);
                                        moveToAddScreen();
                                    }
                                });

                            }
                        }

                    });

                } else {
                    singleUser(phone, name);
                }
            }
        });
    }

    private void singleUser(String phone, String name) {
        final FamilyMemberModel model = new FamilyMemberModel();
        model.setFamilyName(null);
        model.setMemberId(null);
        model.setMobile(phone);
        model.setName(name);
        model.setRegistered(true);
        model.setUid(FirebaseAuth.getInstance().getCurrentUser().getUid());
        MySharedPreferences.getInstance().saveUserName(LoginActivity.this, model);
        Intent intent = new Intent(LoginActivity.this, AddFamilyActivity.class);
        intent.putExtra("singleUser", true);
        startActivity(intent);
    }

    private String[] getFamilyNamesArray(ArrayList<FamilyMemberModel> list, String phone) {
        String[] familyNames = new String[list.size()];
        for (int index = 0; index < list.size(); index++) {
            if (list.get(index).getMobile().contains(phone)) {
                familyNames[index] = getFamilyName(list.get(index).getFamilyName());
            }
        }
        return familyNames;
    }

    private void showFailyNameDialog(final String phone, final String name) {
        final AlertDialog.Builder alert = new AlertDialog.Builder(this);

        LayoutInflater inflater = getLayoutInflater();
        View alertLayout = inflater.inflate(R.layout.new_family_dialog, null);
        etFamilyName = (EditText) alertLayout.findViewById(R.id.et_new_dialog_f_name);
        Button btn_new_dialog = (Button) alertLayout.findViewById(R.id.btn_new_dialog_save);
        Button btn_new_dialog_cancel = (Button) alertLayout.findViewById(R.id.btn_new_dialog_cancel);

        alert.setTitle("");

        // this is set the view from XML inside AlertDialog
        alert.setView(alertLayout);
        // disallow cancel of AlertDialog on click of back button and outside touch
        alert.setCancelable(false);
        final AlertDialog dialog = alert.create();
        btn_new_dialog.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View view) {
                String familyName = etFamilyName.getText().toString();
                if (familyName.isEmpty()) {
                    Toast.makeText(LoginActivity.this, "please enter Group Name", Toast.LENGTH_SHORT).show();
                    etFamilyName.setError("please enter Group Name");
                } else if (familyName.length() < 7) {
                    Toast.makeText(LoginActivity.this, "Group name should be 8 char long", Toast.LENGTH_SHORT).show();
                    etFamilyName.setError("Group name should be 6 char long");
                } else {

                    final String tempFamilyName = familyName + Constants.NAME_SEPERATOR + System.currentTimeMillis();
                    CommonUtils.getInstance().showProgressDialog(LoginActivity.this);
                    FirebaseHandler.getInstance().saveFamilyName(tempFamilyName, new CommonListener() {
                        @Override
                        public void onTaskCompleted(Object value) {
                            if (value != null) {
                                final FamilyMemberModel model = new FamilyMemberModel();
                                model.setFamilyName(value.toString());
                                model.setMemberId(phone + Constants.NAME_SEPERATOR + tempFamilyName);
                                model.setMobile(phone);
                                model.setName(name);
                                model.setRegistered(true);
                                model.setUid(FirebaseAuth.getInstance().getCurrentUser().getUid());
                                model.setRelationship("admin");
                                FirebaseHandler.getInstance().addFamilyMember(model, new CommonListener() {
                                    @Override
                                    public void onTaskCompleted(Object value) {
                                        dialog.dismiss();
                                        CommonUtils.getInstance().closeProgressDialog();
                                        MySharedPreferences.getInstance().saveFamilyName(LoginActivity.this, model.getFamilyName());
                                        MySharedPreferences.getInstance().saveUserName(LoginActivity.this, model);
                                        moveToAddScreen();
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

    private void moveToAddScreen() {
        // need to check mobile number in any family names
        // if mobile exists then redirect to family list by getting family details..
        // if mobile name is in multiple family names..
        // show family names and select and go.....
        Intent service = new Intent(this, FirebaseIDService.class);
        startService(service);
        Intent intent = new Intent(this, AddFamilyActivity.class);
        intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
        startActivity(intent);
        finish();
    }

    public void doLogin(final String mobileNo) {
        CommonUtils.getInstance().showProgressDialog(this);
        FirebaseHandler.getInstance().getFamilyNameFromMobileNo(mobileNo, new CommonListener() {
            @Override
            public void onTaskCompleted(Object value) {
                CommonUtils.getInstance().closeProgressDialog();
                if (value != null) {
                    final FamilyMemberList familyMemberList = (FamilyMemberList) value;
                    if (familyMemberList.getFamilyMembersList() != null && familyMemberList.getFamilyMembersList().size() > 0) {
                        MySharedPreferences.getInstance().saveFamilyNames(LoginActivity.this, familyMemberList);
                        String[] familyNames = getFamilyNamesArray(familyMemberList.getFamilyMembersList(), mobileNo);
                        if (familyNames != null && familyNames.length > 1) {
                            CommonUtils.getInstance().showOptionsDialog(getActivity(), "Join or Create", null, null, "Cancel", familyNames, new DialogListener() {
                                @Override
                                public void onButtonClicked(DialogInterface dialogInterface, Object selectedObject, int pos) {
                                    if (selectedObject.toString().equalsIgnoreCase("Cancel")) {
                                        dialogInterface.cancel();
                                        singleUser(mobileNo, familyMemberList.getFamilyMembersList().get(0).getName());
                                    } else {
                                        FamilyMemberModel model = familyMemberList.getFamilyMembersList().get(pos);
                                        if (FirebaseAuth.getInstance().getCurrentUser()!=null) {
                                            model.setUid(FirebaseAuth.getInstance().getCurrentUser().getUid());
                                        }
                                        model.setRegistered(true);
                                        MySharedPreferences.getInstance().saveFamilyName(LoginActivity.this, model.getFamilyName());
                                        MySharedPreferences.getInstance().saveUserName(LoginActivity.this, model);
                                        dialogInterface.cancel();
                                        moveToAddScreen();
                                    }


                                }
                            });
                        } else {
                            FamilyMemberModel model = familyMemberList.getFamilyMembersList().get(0);
                            model.setUid(FirebaseAuth.getInstance().getCurrentUser().getUid());
                            model.setRegistered(true);
                            MySharedPreferences.getInstance().saveFamilyName(LoginActivity.this, model.getFamilyName());
                            MySharedPreferences.getInstance().saveUserName(LoginActivity.this, model);
                            moveToAddScreen();
                        }
                    } else {
                        CommonUtils.getInstance().showDialogWithMsg(LoginActivity.this, "Number not Registered please SignUp to continue");
                    }
                }
            }
        });
    }

    public Activity getActivity() {
        return this;
    }

    private String getFamilyName(String familyName) {
        if (familyName != null && familyName.contains(Constants.NAME_SEPERATOR)) {
            int index = familyName.toString().lastIndexOf(Constants.NAME_SEPERATOR);
            return familyName.toString().substring(0, index);
        }
        return "";
    }
}
