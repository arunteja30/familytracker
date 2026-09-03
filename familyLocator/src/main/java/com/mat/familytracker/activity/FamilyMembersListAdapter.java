package com.mat.familytracker.activity;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.net.Uri;
import androidx.core.app.ActivityCompat;
import androidx.appcompat.widget.AppCompatImageView;
import androidx.appcompat.widget.AppCompatTextView;
import android.util.Log;
import android.view.View;
import android.view.ViewGroup;
import android.widget.BaseAdapter;
import android.widget.TextView;
import android.widget.Toast;

import com.android.volley.AuthFailureError;
import com.android.volley.DefaultRetryPolicy;
import com.android.volley.Request;
import com.android.volley.RequestQueue;
import com.android.volley.Response;
import com.android.volley.RetryPolicy;
import com.android.volley.VolleyError;
import com.android.volley.toolbox.JsonObjectRequest;
import com.android.volley.toolbox.Volley;
import com.bumptech.glide.Glide;
import com.google.firebase.auth.FirebaseAuth;
import com.google.firebase.auth.FirebaseUser;
import com.karumi.dexter.Dexter;
import com.karumi.dexter.PermissionToken;
import com.karumi.dexter.listener.PermissionDeniedResponse;
import com.karumi.dexter.listener.PermissionGrantedResponse;
import com.karumi.dexter.listener.PermissionRequest;
import com.karumi.dexter.listener.single.PermissionListener;
import com.mat.commonutils.commonutils.CircleTransform;
import com.mat.commonutils.commonutils.CommonListener;
import com.mat.commonutils.commonutils.ImageSaver;
import com.mat.commonutils.dialogs.AestheticDialog;
import com.mat.commonutils.networkutils.ConnectionManager;
import com.mat.familytracker.FTApplication;
import com.mat.familytracker.R;
import com.mat.familytracker.domain.FamilyMemberModel;
import com.mat.familytracker.utils.CommonUtils;
import com.mat.familytracker.utils.Constants;
import com.mat.familytracker.utils.MySharedPreferences;

import org.json.JSONException;
import org.json.JSONObject;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static com.mat.familytracker.utils.Constants.PICK_IMAGE;

public class FamilyMembersListAdapter extends BaseAdapter {
    private final List<FamilyMemberModel> mFamilyMembersList;
    private final Activity mActivity;
    Map contactsMap;
    ImageSaver fileUtils;

    public FamilyMembersListAdapter(Activity activity, List<FamilyMemberModel> familyMemberModels) {
        this.mActivity = activity;
        this.mFamilyMembersList = familyMemberModels;
        this.contactsMap = FTApplication.getContactsMap();
        this.fileUtils = new ImageSaver(activity);
    }

    @Override
    public int getCount() {
        return mFamilyMembersList.size();
    }

    @Override
    public FamilyMemberModel getItem(int i) {
        return mFamilyMembersList.get(i);
    }

    @Override
    public long getItemId(int i) {
        return i;
    }

    FamilyViewHolder viewHolder;

    @Override
    public View getView(int position, View view, ViewGroup viewGroup) {
        if (view == null) {

            view = mActivity.getLayoutInflater().inflate(R.layout.family_member_list_item, null);
            viewHolder = new FamilyViewHolder();
            viewHolder.mobile = (TextView) view.findViewById(R.id.family_mbr_list_mobile);
            viewHolder.name = (TextView) view.findViewById(R.id.family_mbr_list_name);
            viewHolder.relation = (TextView) view.findViewById(R.id.family_mbr_list_relation);
            viewHolder.gpsStatus = (TextView) view.findViewById(R.id.family_mbr_list_gps_status);
            viewHolder.invite = (TextView) view.findViewById(R.id.family_mbr_list_invite);
            viewHolder.profilePic = view.findViewById(R.id.family_mbr_list_profilepic);
            viewHolder.msg = view.findViewById(R.id.family_mbr_list_msg);
            viewHolder.msg.setVisibility(View.VISIBLE);
            viewHolder.call = view.findViewById(R.id.family_mbr_list_call);
            view.setTag(viewHolder);

        } else {
            viewHolder = (FamilyViewHolder) view.getTag();
        }

        final FamilyMemberModel familyMemberDetail = mFamilyMembersList.get(position);
        viewHolder.msg.setTag(familyMemberDetail.getMobile());
        viewHolder.relation.setText(familyMemberDetail.getRelationship());
        if (isItMe(familyMemberDetail.getMobile())) {
            viewHolder.name.setText("You");
            viewHolder.call.setVisibility(View.GONE);
            viewHolder.msg.setVisibility(View.GONE);
        } else {
            viewHolder.name.setText(familyMemberDetail.getName());
        }
        viewHolder.mobile.setText(familyMemberDetail.getMobile());
        if (familyMemberDetail.getGpsInfo() != null) {
            if (familyMemberDetail.getGpsInfo() != null && familyMemberDetail.getGpsInfo().contains("Disabled")) {
                viewHolder.gpsStatus.setVisibility(View.VISIBLE);
                viewHolder.gpsStatus.setText("\uD83D\uDED1 " + familyMemberDetail.getName().toUpperCase() + " " + mActivity.getResources().getString(R.string.user_gps_disable));
                viewHolder.gpsStatus.setTextColor(Color.RED);
            } else {
                viewHolder.gpsStatus.setVisibility(View.VISIBLE);
                viewHolder.gpsStatus.setText("\uD83D\uDFE2 " + familyMemberDetail.getGpsInfo());
                viewHolder.gpsStatus.setTextColor(Color.parseColor("#00B100"));
            }
        }
        viewHolder.name.setTag(viewHolder.invite);
        if (isItMe(familyMemberDetail.getMobile())) {
            viewHolder.invite.setVisibility(View.GONE);
            if (!ConnectionManager.getInstance().isGpsEnable(mActivity)) {
                viewHolder.gpsStatus.setVisibility(View.VISIBLE);
                viewHolder.gpsStatus.setText("\uD83D\uDED1 " + "Your GPS is Disabled, Your family Cannot track You");
                viewHolder.gpsStatus.setTextColor(Color.RED);
            }
        }
        String updateTime = String.valueOf(System.currentTimeMillis());
        Glide.with(mActivity).load(fileUtils.getFilePath(mActivity, familyMemberDetail.getMobile())).transform(new CircleTransform(mActivity)).placeholder(R.drawable.blank_profile_picture).signature(new com.bumptech.glide.signature.ObjectKey(updateTime)).fallback(R.drawable.blank_profile_picture).into(viewHolder.profilePic);

        if (familyMemberDetail.isRegistered()) {
            viewHolder.invite.setVisibility(View.GONE);
        }

        viewHolder.call.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                if (ActivityCompat.checkSelfPermission(mActivity, Manifest.permission.CALL_PHONE) == PackageManager.PERMISSION_GRANTED) {
                    Intent callIntent = new Intent(Intent.ACTION_CALL, Uri.parse("tel:" + familyMemberDetail.getMobile()));
                    mActivity.startActivity(callIntent);
                } else {
                    Dexter.withActivity(mActivity).withPermission(Manifest.permission.CALL_PHONE).withListener(new PermissionListener() {
                        @Override
                        public void onPermissionGranted(PermissionGrantedResponse response) {
                            Intent callIntent = new Intent(Intent.ACTION_CALL, Uri.parse("tel:" + familyMemberDetail.getMobile()));
                            mActivity.startActivity(callIntent);
                        }

                        @Override
                        public void onPermissionDenied(PermissionDeniedResponse response) {
                            Toast.makeText(mActivity, "Call Permission denied, Unable to place a call", Toast.LENGTH_SHORT).show();
                            CommonUtils.getInstance().showSettingsDialog(mActivity);
                        }

                        @Override
                        public void onPermissionRationaleShouldBeShown(PermissionRequest permission, PermissionToken token) {
                            token.continuePermissionRequest();
                        }
                    }).check();
                }
            }
        });
        viewHolder.msg.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                sendMessage(familyMemberDetail.getPushNofityToken());
            }
        });
        viewHolder.invite.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                handleShare();
            }
        });

        viewHolder.profilePic.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                if (ActivityCompat.checkSelfPermission(mActivity, Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED) {
                    AddFamilyActivity.picSelectedUser = familyMemberDetail.getMobile();
                    Intent photoPickerIntent = new Intent(Intent.ACTION_PICK);
                    photoPickerIntent.setType("image/*");
                    mActivity.startActivityForResult(photoPickerIntent, PICK_IMAGE);
                }
            }
        });
        viewHolder.name.isPressed();
        return view;
    }

    private void handleShare() {

        try {
            Intent shareIntent = new Intent(Intent.ACTION_SEND);
            shareIntent.setType("text/plain");
            shareIntent.putExtra(Intent.EXTRA_SUBJECT, mActivity.getResources().getString(R.string.app_name));
            String shareMessage = "\nDownload this App to get My location updates\n\n";
            shareMessage = shareMessage + "https://drive.google.com/file/d/1A-5n8CpPPZRX0g4UzJF6FHtvpmO1VLCD/view?usp=sharing";
            shareIntent.putExtra(Intent.EXTRA_TEXT, shareMessage);
            mActivity.startActivity(Intent.createChooser(shareIntent, "choose one"));
        } catch (Exception e) {
            //e.toString();
        }
    }

    private boolean isItMe(String mobile) {
        FamilyMemberModel userModel = FTApplication.getLoggedInUserModel();
        return userModel != null && userModel.getMobile().equalsIgnoreCase(mobile);
    }

    private void sendMessage(final String pushNofityToken) {
        com.mat.commonutils.commonutils.CommonUtils.getInstance().showBigEdittextDialog(mActivity, new CommonListener() {
            @Override
            public void onTaskCompleted(Object value) {
                if (value != null) {
                    sendFCMPush(value.toString(), pushNofityToken);
                }
            }
        });
    }


    private class FamilyViewHolder {
        TextView name;
        TextView mobile;
        TextView relation;
        TextView gpsStatus;
        TextView invite;
        AppCompatImageView profilePic;
        AppCompatTextView call, msg;
    }

    private void sendFCMPush(String msg, String pushNofityToken) {

        final String Legacy_SERVER_KEY = Constants.FIREBASE_PUSH_NOTIFY_SERVER_KEY;
        String title = mActivity.getString(R.string.app_name);
//        String token = FirebaseInstanceId.getInstance().getToken();
        String token = pushNofityToken;

        JSONObject obj = null;
        JSONObject objData = null;
        JSONObject dataobjData = null;
        String name = "";
        FirebaseUser mAuth = FirebaseAuth.getInstance().getCurrentUser();
        if (mAuth != null) {
            if (contactsMap != null && mAuth.getPhoneNumber() != null && contactsMap != null) {
                name = (String) contactsMap.get(mAuth.getPhoneNumber());
            } else {
                name = mAuth.getDisplayName();
            }
        }
        if (msg != null && !msg.isEmpty() && token != null && !token.isEmpty()) {
            String familyName = MySharedPreferences.getInstance().getFamilyName(mActivity);

            try {
                obj = new JSONObject();
                objData = new JSONObject();
                objData.put("body", name.toUpperCase() + "\n -- " + msg.trim());
                objData.put("title", title);
                if (familyName != null && !familyName.isEmpty()) {
                    objData.put("title", getFamilyName(familyName));
                }

//            objData.put("sound", "default");
//            objData.put("icon", "ic_launcher"); //   icon_name image must be there in drawable
                objData.put("tag", token);
//            objData.put("priority", "high");

                dataobjData = new JSONObject();
                dataobjData.put("text", name.toUpperCase() + ":-\n " + msg.trim());
                if (familyName != null && !familyName.isEmpty()) {
                    dataobjData.put("title", familyName);
                }
                obj.put("to", token);
                //obj.put("priority", "high");

                obj.put("notification", objData);
                obj.put("data", dataobjData);
                Log.e("!_@rj@_@@_PASS:>", obj.toString());
            } catch (JSONException e) {
                e.printStackTrace();
            }

            JsonObjectRequest jsObjRequest = new JsonObjectRequest(Request.Method.POST, Constants.FCM_PUSH_URL, obj,
                    new Response.Listener<JSONObject>() {
                        @Override
                        public void onResponse(JSONObject response) {
                            Log.e("!_@@_SUCESS", response + "");
                            AestheticDialog.showToaster(mActivity, null, "Message sent..", AestheticDialog.SUCCESS);
                        }
                    },
                    new Response.ErrorListener() {
                        @Override
                        public void onErrorResponse(VolleyError error) {
                            Log.e("!_@@_Errors--", error + "");
                            AestheticDialog.showToaster(mActivity, "message not sent", error.getMessage(), AestheticDialog.WARNING);
                        }
                    }) {
                @Override
                public Map<String, String> getHeaders() throws AuthFailureError {
                    Map<String, String> params = new HashMap<String, String>();
                    params.put("Authorization", Legacy_SERVER_KEY);
                    params.put("Content-Type", "application/json");
                    return params;
                }
            };
            RequestQueue requestQueue = Volley.newRequestQueue(mActivity);
            int socketTimeout = 1000 * 60;// 60 seconds
            RetryPolicy policy = new DefaultRetryPolicy(socketTimeout, DefaultRetryPolicy.DEFAULT_MAX_RETRIES, DefaultRetryPolicy.DEFAULT_BACKOFF_MULT);
            jsObjRequest.setRetryPolicy(policy);
            requestQueue.add(jsObjRequest);
        } else {
            Toast.makeText(mActivity, "Oops.. Something went wrong..", Toast.LENGTH_SHORT).show();
        }
    }

    private String getFamilyName(String familyName) {
        if (familyName != null && familyName.contains(Constants.NAME_SEPERATOR)) {
            int index = familyName.toString().lastIndexOf(Constants.NAME_SEPERATOR);
            return familyName.toString().substring(0, index);
        }
        return "";
    }
}
