package com.mat.familytracker.activity;

import android.app.Activity;
import android.os.Bundle;
import android.os.CountDownTimer;
import android.util.Log;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ProgressBar;
import android.widget.TextView;
import android.widget.Toast;

import androidx.annotation.NonNull;

import com.google.android.gms.tasks.OnCompleteListener;
import com.google.android.gms.tasks.Task;
import com.google.firebase.FirebaseException;
import com.google.firebase.auth.AuthResult;
import com.google.firebase.auth.FirebaseAuth;
import com.google.firebase.auth.FirebaseAuthUserCollisionException;
import com.google.firebase.auth.FirebaseUser;
import com.google.firebase.auth.PhoneAuthCredential;
import com.google.firebase.auth.PhoneAuthOptions;
import com.google.firebase.auth.PhoneAuthProvider;
import com.google.firebase.auth.UserProfileChangeRequest;
import com.mat.commonutils.commonutils.CommonListener;
import com.mat.commonutils.commonutils.CommonUtils;
import com.mat.familytracker.R;

import java.util.concurrent.TimeUnit;

public class VerifyPhoneActivity extends LoginActivity {

    private static final String TAG = "VerifyPhoneActivity";

    private String verificationId;
    private PhoneAuthProvider.ForceResendingToken resendOtpToken;
    private FirebaseAuth mAuth;
    private ProgressBar progressBar;
    private EditText editText;
    Button buttonSignIn;
    TextView resndOtp;
    private PhoneAuthProvider.OnVerificationStateChangedCallbacks
            mCallBack = new PhoneAuthProvider.OnVerificationStateChangedCallbacks() {

        @Override
        public void onCodeSent(@NonNull String s, @NonNull PhoneAuthProvider.ForceResendingToken forceResendingToken) {
            super.onCodeSent(s, forceResendingToken);
            verificationId = s;
            resendOtpToken = forceResendingToken;
            if (progressBar != null) {
                progressBar.setVisibility(View.GONE);
            }
            Toast.makeText(VerifyPhoneActivity.this, "OTP sent successfully", Toast.LENGTH_SHORT).show();
            Log.d(TAG, "OTP code sent. Verification ID: " + s);
        }

        @Override
        public void onVerificationCompleted(@NonNull PhoneAuthCredential phoneAuthCredential) {
            if (progressBar != null) {
                progressBar.setVisibility(View.GONE);
            }
            String code = phoneAuthCredential.getSmsCode();
            if (code != null) {
                editText.setText(code);
                verifyCode(code);
            }
            signInWithCredential(phoneAuthCredential);
        }

        @Override
        public void onVerificationFailed(@NonNull FirebaseException e) {
            if (progressBar != null) {
                progressBar.setVisibility(View.GONE);
            }
            Log.e(TAG, "Phone verification failed", e);
            Toast.makeText(VerifyPhoneActivity.this, "Verification failed: " + e.getMessage(), Toast.LENGTH_LONG).show();
        }
    };

    private void resendVerificationCode(String phoneNumber,
                                        PhoneAuthProvider.ForceResendingToken token) {
        if (phoneNumber == null || phoneNumber.isEmpty()) return;
        if (progressBar != null) {
            progressBar.setVisibility(View.VISIBLE);
        }
        PhoneAuthOptions.Builder builder = PhoneAuthOptions.newBuilder(mAuth)
                .setPhoneNumber(phoneNumber)
                .setTimeout(60L, TimeUnit.SECONDS)
                .setActivity(this)
                .setCallbacks(mCallBack);
        if (token != null) {
            builder.setForceResendingToken(token);
        }
        PhoneAuthProvider.verifyPhoneNumber(builder.build());
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_verify_phone);

        mAuth = FirebaseAuth.getInstance();

        progressBar = findViewById(R.id.progressbar);
        editText = findViewById(R.id.editTextCode);
        resndOtp = findViewById(R.id.txt_resend_otp);
        buttonSignIn = findViewById(R.id.buttonSignIn);

        final String phoneNumber = getIntent().getStringExtra("phoneNumber");
        if (phoneNumber != null) {
            sendVerificationCode(phoneNumber);
        } else {
            Toast.makeText(this, "Phone number is missing", Toast.LENGTH_SHORT).show();
        }

        resndOtp.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                if (phoneNumber != null) {
                    resendVerificationCode(phoneNumber, resendOtpToken);
                    resendOTPTimer(phoneNumber);
                }
            }
        });

        buttonSignIn.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                String code = editText.getText().toString().trim();

                if (code.isEmpty() || code.length() < 6) {
                    editText.setError("Enter 6-digit code...");
                    editText.requestFocus();
                    return;
                }
                verifyCode(code);
            }
        });
    }

    private void updateUserProfile(final String name) {
        final FirebaseUser user = FirebaseAuth.getInstance().getCurrentUser();
        if (user == null) return;
        UserProfileChangeRequest profileUpdates = new UserProfileChangeRequest.Builder()
                .setDisplayName(name)
                .build();

        user.updateProfile(profileUpdates)
                .addOnCompleteListener(new OnCompleteListener<Void>() {
                    @Override
                    public void onComplete(@NonNull Task<Void> task) {
                        if (task.isSuccessful()) {
                            Log.d(TAG, "User profile updated.");
                            if (mAuth.getCurrentUser() != null) {
                                String phone = mAuth.getCurrentUser().getPhoneNumber();
                                String uid = mAuth.getCurrentUser().getUid();
                                registerNumber(phone, name, uid);
                                checkNumberAlreadyExists(phone, name);
                            }
                        }
                    }
                });
    }

    private void showNameDialog() {
        CommonUtils.getInstance().fancyProfileDialog(this, new CommonListener() {
            @Override
            public void onTaskCompleted(Object value) {
                if (value != null) {
                    updateUserProfile(value.toString());
                }
            }
        });
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
    }

    @Override
    public void onBackPressed() {
        super.onBackPressed();
        finish();
    }

    private void verifyCode(String code) {
        if (verificationId != null) {
            if (progressBar != null) {
                progressBar.setVisibility(View.VISIBLE);
            }
            PhoneAuthCredential credential = PhoneAuthProvider.getCredential(verificationId, code);
            signInWithCredential(credential);
        } else {
            Toast.makeText(this, "Verification ID not ready. Please resend OTP.", Toast.LENGTH_SHORT).show();
        }
    }

    private void signInWithCredential(PhoneAuthCredential credential) {
        mAuth.signInWithCredential(credential)
                .addOnCompleteListener(new OnCompleteListener<AuthResult>() {
                    @Override
                    public void onComplete(@NonNull Task<AuthResult> task) {
                        if (progressBar != null) {
                            progressBar.setVisibility(View.GONE);
                        }
                        if (task.isSuccessful()) {
                            if (mAuth.getCurrentUser() != null) {
                                FirebaseHandler.getInstance().checkRegistration(mAuth.getCurrentUser().getPhoneNumber(), new CommonListener() {
                                    @Override
                                    public void onTaskCompleted(Object value) {
                                        if (value != null && (boolean) value) {
                                            doLogin(mAuth.getCurrentUser().getPhoneNumber());
                                        } else {
                                            showNameDialog();
                                        }
                                    }
                                });
                            }
                        } else {
                            if (task.getException() instanceof FirebaseAuthUserCollisionException) {
                                Toast.makeText(VerifyPhoneActivity.this,
                                        "User already Registered.", Toast.LENGTH_SHORT).show();
                            } else {
                                String msg = task.getException() != null ? task.getException().getMessage() : "Authentication failed";
                                Toast.makeText(VerifyPhoneActivity.this, msg, Toast.LENGTH_LONG).show();
                            }
                        }
                    }
                });
    }

    private void sendVerificationCode(final String number) {
        if (progressBar != null) {
            progressBar.setVisibility(View.VISIBLE);
        }
        PhoneAuthOptions options = PhoneAuthOptions.newBuilder(mAuth)
                .setPhoneNumber(number)
                .setTimeout(60L, TimeUnit.SECONDS)
                .setActivity(this)
                .setCallbacks(mCallBack)
                .build();
        PhoneAuthProvider.verifyPhoneNumber(options);
        resendOTPTimer(number);
    }

    private void resendOTPTimer(final String number) {
        new CountDownTimer(90000, 1000) {

            public void onTick(long millisUntilFinished) {
                resndOtp.setVisibility(View.VISIBLE);
                resndOtp.setText("Resending OTP in " + millisUntilFinished / 1000 + " seconds..");
            }

            public void onFinish() {
                resndOtp.setText("Resend OTP");
            }

        }.start();
    }

    @Override
    public Activity getActivity() {
        return this;
    }
}

