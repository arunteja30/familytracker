package com.mat.familytracker.activity;

import android.content.Intent;
import android.os.Bundle;
import androidx.appcompat.app.AppCompatActivity;
import android.view.View;
import android.widget.ArrayAdapter;
import android.widget.EditText;
import android.widget.Spinner;

import com.google.firebase.auth.FirebaseAuth;
import com.google.gson.Gson;
import com.mat.commonutils.FBAuth.ContryData;
import com.mat.familytracker.R;
import com.mat.familytracker.domain.FamilyMemberModel;
import com.mat.familytracker.utils.MySharedPreferences;

public class PhoneLoginActivity extends AppCompatActivity {


    private Spinner spinner;
    private EditText editText;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_phone_login);

        spinner = findViewById(R.id.spinnerCountries);
        spinner.setAdapter(new ArrayAdapter<String>(this, android.R.layout.simple_spinner_dropdown_item, ContryData.countryNames));

        for (int i = 0; i < ContryData.countryNames.length; i++) {
            if (ContryData.countryNames[i].equalsIgnoreCase("India")){
                spinner.setSelection(i,true);
            }
        }

        editText = findViewById(R.id.editTextPhone);

        findViewById(R.id.buttonContinue).setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                String code = ContryData.countryAreaCodes[spinner.getSelectedItemPosition()];

                String number = editText.getText().toString().trim();

                if (number.isEmpty() || number.length() < 10) {
                    editText.setError("Valid mobile number is required");
                    editText.requestFocus();
                    return;
                }

                String phoneNumber = "+" + code + number;

                Intent intent = new Intent(PhoneLoginActivity.this, VerifyPhoneActivity.class);
                intent.putExtra("phoneNumber", phoneNumber);
                startActivity(intent);

            }
        });
    }

    @Override
    protected void onStart() {
        super.onStart();
        checkNLogin();
    }

    @Override
    protected void onResume() {
        super.onResume();
//        checkNLogin();
    }

    private void checkNLogin() {
        String userName = MySharedPreferences.getInstance().getUserName(this);
        if (FirebaseAuth.getInstance().getCurrentUser() != null && userName != null && !userName.isEmpty()) {
            FamilyMemberModel model = new Gson().fromJson(userName, FamilyMemberModel.class);
            Intent intent = new Intent(this, AddFamilyActivity.class);
            intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
            if (model != null && model.getFamilyName() == null) {
                intent.putExtra("singleUser", true);
            }
            startActivity(intent);

        }
    }


}