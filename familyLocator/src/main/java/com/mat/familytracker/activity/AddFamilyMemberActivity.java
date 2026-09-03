package com.mat.familytracker.activity;

import android.content.ContentResolver;
import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.os.Bundle;
import android.provider.ContactsContract;
import androidx.appcompat.app.AppCompatActivity;
import android.util.Log;
import android.view.MenuItem;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ImageButton;
import android.widget.Toast;

import com.mat.commonutils.commonutils.CommonUtils;
import com.mat.familytracker.R;
import com.mat.familytracker.domain.FamilyMemberModel;
import com.mat.familytracker.utils.Constants;
import com.mat.familytracker.utils.MySharedPreferences;

public class AddFamilyMemberActivity extends AppCompatActivity {

    private EditText addMobile;
    private EditText addName;
    private EditText addRelation;
    private final int PICK_CONTACT = 1265;
    private ImageButton ib_contacts;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.add_member_layout);
        getSupportActionBar().setDisplayShowHomeEnabled(true);
        getSupportActionBar().setHomeButtonEnabled(true);
        getSupportActionBar().setTitle("Add Member");
        addMobile = (EditText) findViewById(R.id.et_add_member_mobile);
        addName = (EditText) findViewById(R.id.et_add_member_name);
        addRelation = (EditText) findViewById(R.id.et_add_member_relation);
        addRelation.setVisibility(View.GONE);
        ib_contacts = (ImageButton) findViewById(R.id.ib_contacts);
        Button save = (Button) findViewById(R.id.btn_save_family_membr);
        save.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View view) {
                String mobileNo = addMobile.getText().toString();

                String name = addName.getText().toString();
                if (mobileNo.isEmpty() || mobileNo.length() < 10) {
                    Toast.makeText(AddFamilyMemberActivity.this, "Valid mobile no is required", Toast.LENGTH_SHORT).show();
                } else if (name.isEmpty() || name.length() < 4) {
                    Toast.makeText(AddFamilyMemberActivity.this, "Valid name is required", Toast.LENGTH_SHORT).show();
                } else {
                    saveFamilyMember();
                }
            }
        });
        ib_contacts.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View view) {
                getContacts();
            }
        });
        if (getIntent().getExtras() != null) {
            Bundle bundle = getIntent().getExtras();
            if (bundle.containsKey(Constants.FAMILY_MEM_MODEL) && bundle.getSerializable(Constants.FAMILY_MEM_MODEL) != null) {
                FamilyMemberModel model = (FamilyMemberModel) bundle.getSerializable(Constants.FAMILY_MEM_MODEL);
                addMobile.setText(model.getMobile());
                addMobile.setTag(model.getGpsInfo());
                addMobile.setEnabled(false);
                addName.setText(model.getName());
                addName.setTag(model.getMemberId());
                addRelation.setText(model.getRelationship());
            }

        }
    }

    private void getContacts() {
        Intent pickContactIntent = new Intent(Intent.ACTION_PICK, Uri.parse("content://contacts"));
        pickContactIntent.setType(ContactsContract.CommonDataKinds.Phone.CONTENT_TYPE); // Show user only contacts w/ phone numbers
        startActivityForResult(pickContactIntent, PICK_CONTACT);

        CommonUtils.getInstance().getContactsList(this);
    }

    @Override
    protected void onResume() {
        super.onResume();
    }

    private void saveFamilyMember() {
        String mobileNo = addMobile.getText().toString().replaceAll("[-, ]","");
        String name = addName.getText().toString();
        FamilyMemberModel familyMemberModel = new FamilyMemberModel();
        boolean firstLaunch = MySharedPreferences.getInstance().isFirstLaunch(this);
        String familyName = MySharedPreferences.getInstance().getFamilyName(this);
        familyMemberModel.setMobile(com.mat.familytracker.utils.CommonUtils.getInstance().getFormattedPhoneNumber(this,mobileNo.trim()));
        familyMemberModel.setName(name);
        familyMemberModel.setFamilyName(familyName);

        if (addName != null && addName.getTag() != null) {
            familyMemberModel.setMemberId((String) addName.getTag());
        }
        if (addMobile != null && addMobile.getTag() != null) {
            familyMemberModel.setGpsInfo((String) addMobile.getTag());
        }
        familyMemberModel.setRelationship(addRelation.getText().toString());
        Intent familyMemData = new Intent();
        Bundle bundle = new Bundle();
        bundle.putSerializable(Constants.FAMILY_MEM_MODEL, familyMemberModel);
        familyMemData.putExtras(bundle);
        setResult(RESULT_OK, familyMemData);
        finish();

    }

    public void onActivityResult(int reqCode, int resultCode, Intent data) {
        super.onActivityResult(reqCode, resultCode, data);
        switch (reqCode) {
            case (PICK_CONTACT):
                if (data != null) {
                    // Get the URI that points to the selected contact
                    Uri contactUri = data.getData();
                    // We only need the NUMBER column, because there will be only one row in the result
                    String[] projection = {ContactsContract.CommonDataKinds.Phone.NUMBER, ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME};

                    // Perform the query on the contact to get the NUMBER column
                    // We don't need a selection or sort order (there's only one result for the given URI)
                    // CAUTION: The query() method should be called from a separate thread to avoid blocking
                    // your app's UI thread. (For simplicity of the sample, this code doesn't do that.)
                    // Consider using CursorLoader to perform the query.
                    Cursor cursor = getContentResolver()
                            .query(contactUri, projection, null, null, null);
                    cursor.moveToFirst();

                    // Retrieve the phone number from the NUMBER column
                    int column = cursor.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER);
                    int contactName = cursor.getColumnIndex(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME);
                    String number = cursor.getString(column);
                    String name = cursor.getString(contactName);
                    addMobile.setText(number.trim().replace("[()\\s-]+", ""));
                    addName.setText(name);
                }
                break;
        }

    }

    @Override
    public boolean onOptionsItemSelected(MenuItem item) {
        switch (item.getItemId()) {
            case android.R.id.home:
                finish();
                return true;
            default:
                return super.onOptionsItemSelected(item);
        }
    }


}
