package com.mat.familytracker.activity;

import android.app.admin.DevicePolicyManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.DialogInterface;
import android.content.Intent;
import android.os.Bundle;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.appcompat.app.AppCompatActivity;
import androidx.appcompat.widget.AppCompatEditText;
import androidx.cardview.widget.CardView;
import androidx.appcompat.widget.SwitchCompat;
import android.text.Editable;
import android.text.TextWatcher;
import android.util.Log;
import android.view.MenuItem;
import android.view.View;
import android.widget.Button;
import android.widget.CompoundButton;
import android.widget.TextView;

import com.google.android.gms.tasks.OnCompleteListener;
import com.google.android.gms.tasks.Task;
import com.google.firebase.auth.FirebaseAuth;
import com.google.firebase.auth.FirebaseUser;
import com.google.firebase.auth.UserProfileChangeRequest;
import com.mat.commonutils.commonutils.CommonListener;
import com.mat.commonutils.commonutils.CommonUtils;
import com.mat.commonutils.dialogs.AestheticDialog;
import com.mat.familytracker.R;
import com.mat.familytracker.utils.DialogListener;
import com.mat.familytracker.utils.MySharedPreferences;
import com.mat.phonesecurity.recievers.MyDeviceAdminReceiver;

import java.util.regex.Pattern;

import static com.android.volley.VolleyLog.TAG;

public class SettingsActivity extends AppCompatActivity implements CompoundButton.OnCheckedChangeListener, View.OnClickListener {

    private static final int ADMIN_REQUEST = 1232;
    DevicePolicyManager policyManager;
    ComponentName devicePolicyAdmin;
    SwitchCompat admin;
    private AppCompatEditText etName, etEmailAlerts;
    private FirebaseAuth mAuth;
    private TextView txt_username;
    private Button btn_save_email;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_settings);
        policyManager = (DevicePolicyManager) getSystemService(Context.DEVICE_POLICY_SERVICE);
        devicePolicyAdmin = new ComponentName(this,
                MyDeviceAdminReceiver.class);

        mAuth = FirebaseAuth.getInstance();

        setupActionBar();

        SwitchCompat emailAlerts = findViewById(R.id.switch_email_alerts);
        admin = findViewById(R.id.switch_admin);
        etEmailAlerts = findViewById(R.id.et_change_email);
        txt_username = findViewById(R.id.txt_name_change_description);
        CardView ll_name_change = findViewById(R.id.ll_name_change);
        btn_save_email = findViewById(R.id.btn_save_email);
        btn_save_email.setOnClickListener(this);
        admin.setOnCheckedChangeListener(this);
        emailAlerts.setOnCheckedChangeListener(this);
        ll_name_change.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                showNameDialog();
            }
        });
        if (emailAlerts.isChecked()) {
            etEmailAlerts.setVisibility(View.VISIBLE);
            btn_save_email.setVisibility(View.VISIBLE);
        } else {
            etEmailAlerts.setVisibility(View.GONE);
            btn_save_email.setVisibility(View.GONE);
        }
        if (mAuth != null && mAuth.getCurrentUser() != null && mAuth.getCurrentUser().getDisplayName() != null) {
            txt_username.setText("Your Profile Name is : " + mAuth.getCurrentUser().getDisplayName());
        }
        if (isMyDevicePolicyReceiverActive()) {
            admin.setChecked(true);
        }

        final String emailId = MySharedPreferences.getInstance().getAlertEmailId(this);
        if (emailId != null && !emailId.isEmpty()) {
            emailAlerts.setChecked(true);
            etEmailAlerts.setText(emailId);
            etEmailAlerts.setVisibility(View.VISIBLE);
        } else {
            emailAlerts.setChecked(false);
        }
        btn_save_email.setVisibility(View.GONE);
        etEmailAlerts.addTextChangedListener(new TextWatcher() {
            @Override
            public void beforeTextChanged(CharSequence s, int start, int count, int after) {

            }

            @Override
            public void onTextChanged(CharSequence s, int start, int before, int count) {

            }

            @Override
            public void afterTextChanged(Editable s) {
                if (s != null && !emailId.equalsIgnoreCase(s.toString())) {
                    btn_save_email.setVisibility(View.VISIBLE);
                }
            }
        });

        setTitle("Settings");

    }

    @Override
    public void onCheckedChanged(CompoundButton buttonView, boolean isChecked) {
        if (buttonView.isPressed()) {
            if (buttonView.getId() == R.id.switch_admin) {
                if (isChecked && !isMyDevicePolicyReceiverActive()) {
                    launchDeviceAdmin();
                } else if (isMyDevicePolicyReceiverActive()) {
                    showConfirmationDialog();
                }
            } else if (buttonView.getId() == R.id.switch_email_alerts) {
                if (isChecked) {
                    etEmailAlerts.setVisibility(View.VISIBLE);
                    btn_save_email.setVisibility(View.VISIBLE);
                    etEmailAlerts.setEnabled(true);
                    showSubscriptionActivity();
                } else {
                    etEmailAlerts.setVisibility(View.GONE);
                    btn_save_email.setVisibility(View.GONE);
                }
            }
        }
    }

    private void showSubscriptionActivity() {
        // show subscripption...
    }

    private void showConfirmationDialog() {
        com.mat.familytracker.utils.CommonUtils.getInstance().showOptionsDialog(this, "Disable", getResources().getString(R.string.disable_admin_msg), "Still Disable", "No, Keep it", null, new DialogListener() {
            @Override
            public void onButtonClicked(DialogInterface dialogInterface, Object selectedObject, int position) {
                if (selectedObject != null) {
                    if (selectedObject.equals("Still Disable")) {
                        policyManager.removeActiveAdmin(devicePolicyAdmin);
                        AestheticDialog.showToaster(SettingsActivity.this, null, "Device Administration is disabled on this App", AestheticDialog.WARNING);
                        dialogInterface.cancel();
                    } else {
                        if (isMyDevicePolicyReceiverActive()) {
                            admin.setChecked(true);
                        }
                        dialogInterface.cancel();
                    }
                }
            }
        });
    }

    private boolean isMyDevicePolicyReceiverActive() {
        return policyManager
                .isAdminActive(devicePolicyAdmin);
    }

    private void showNameDialog() {
        CommonUtils.getInstance().fancyProfileEditDialog(this, mAuth.getCurrentUser().getDisplayName(), new CommonListener() {
            @Override
            public void onTaskCompleted(Object value) {
                if (value != null) {
                    updateUserProfile(value.toString());
                }
            }
        });

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

    private void setupActionBar() {
        getSupportActionBar().setDisplayHomeAsUpEnabled(true);
        getSupportActionBar().setDisplayShowHomeEnabled(true);
    }

    @Override
    public void onClick(View v) {
        if (v.getId() == R.id.btn_save_email) {
            saveEmailDetails();
        }

    }

    private void saveEmailDetails() {
        if (etEmailAlerts != null && etEmailAlerts.getText() != null) {
            if (Pattern.matches(etEmailAlerts.getText().toString(), "[@,.,com]") && etEmailAlerts.getText().toString().isEmpty()) {
                etEmailAlerts.setError("Cannot be Empty");
            } else {
                MySharedPreferences.getInstance().saveEmailId(this, etEmailAlerts.getText().toString());
                AestheticDialog.showToaster(SettingsActivity.this, null, "Email saved..", AestheticDialog.WARNING);
            }
        }

    }

    private void updateUserProfile(final String name) {
        final FirebaseUser user = FirebaseAuth.getInstance().getCurrentUser();
        UserProfileChangeRequest profileUpdates = new UserProfileChangeRequest.Builder()
                .setDisplayName(name)
                .build();

        user.updateProfile(profileUpdates)
                .addOnCompleteListener(new OnCompleteListener<Void>() {
                    @Override
                    public void onComplete(@NonNull Task<Void> task) {
                        if (task.isSuccessful()) {
                            Log.d(TAG, "User profile updated.");
                            String name = mAuth.getCurrentUser().getDisplayName();
                            txt_username.setText("Your Profile Name is : " + name);
                            AestheticDialog.showToaster(SettingsActivity.this, null, "Profile Name is Updated..", AestheticDialog.SUCCESS);

                        }
                    }
                });
    }

    @Override
    public boolean onOptionsItemSelected(@NonNull MenuItem item) {
        if (item.getItemId() == android.R.id.home) {
            finish();
        }
        return super.onOptionsItemSelected(item);
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, @Nullable Intent data) {
        if (requestCode == ADMIN_REQUEST) {
            if (resultCode == RESULT_OK) {
                admin.setChecked(true);
            } else {
                admin.setChecked(false);
            }
        }
    }
}