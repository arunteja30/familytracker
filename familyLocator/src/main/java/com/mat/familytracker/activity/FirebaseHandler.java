package com.mat.familytracker.activity;

import android.content.Context;
import android.util.Log;

import com.google.firebase.database.DataSnapshot;
import com.google.firebase.database.DatabaseError;
import com.google.firebase.database.DatabaseReference;
import com.google.firebase.database.FirebaseDatabase;
import com.google.firebase.database.Query;
import com.google.firebase.database.ValueEventListener;
import com.mat.commonutils.app.UpdateModel;
import com.mat.commonutils.commonutils.CommonListener;
import com.mat.familytracker.domain.FamilyMemberModel;
import com.mat.familytracker.domain.LocationDetailsModel;
import com.mat.familytracker.domain.RegistrationModel;
import com.mat.familytracker.utils.Constants;
import com.mat.familytracker.utils.MySharedPreferences;

import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.Iterator;
import java.util.Locale;

public class FirebaseHandler {
    private static final FirebaseHandler ourInstance = new FirebaseHandler();
    private String TAG = "FirebaseHandler.class";

    public static FirebaseHandler getInstance() {
        return ourInstance;
    }

    private FirebaseHandler() {
    }

    public void saveLocationToDB(String userName, LocationDetailsModel locationDetailsModel) {
        FirebaseDatabase locationDb = FirebaseDatabase.getInstance();
        DatabaseReference locationRef = locationDb.getReference(Constants.LOCATION_LIST).child(userName);
        locationRef.setValue(locationDetailsModel);

        // Also save to location history
        saveLocationToHistory(userName, locationDetailsModel);
    }

    /**
     * Save location to history with date-based structure
     * Structure: locationHistory/{phoneNumber}/{date}/[array of locations]
     */
    public void saveLocationToHistory(String userName, LocationDetailsModel locationDetailsModel) {
        try {
            FirebaseDatabase historyDb = FirebaseDatabase.getInstance();

            // Format current date as YYYY-MM-DD
            SimpleDateFormat dateFormat = new SimpleDateFormat("yyyy-MM-dd", Locale.getDefault());
            String currentDate = dateFormat.format(new Date());

            // Create reference to history location
            DatabaseReference historyRef = historyDb.getReference("locationHistory")
                    .child(userName)
                    .child(currentDate);

            // Check for duplicates before saving
            checkAndSaveLocationHistory(historyRef, locationDetailsModel, userName, currentDate);

        } catch (Exception e) {
            Log.e(TAG, "Error saving location to history: " + e.getMessage(), e);
        }
    }

    /**
     * Check for duplicate entries before saving to prevent duplicate data on server
     */
    private void checkAndSaveLocationHistory(DatabaseReference historyRef, LocationDetailsModel locationDetailsModel, String userName, String currentDate) {
        historyRef.addListenerForSingleValueEvent(new ValueEventListener() {
            @Override
            public void onDataChange(DataSnapshot dataSnapshot) {
                boolean isDuplicate = false;

                if (dataSnapshot.exists() && dataSnapshot.hasChildren()) {
                    // Check existing entries for duplicates
                    for (DataSnapshot existingEntry : dataSnapshot.getChildren()) {
                        LocationDetailsModel existingLocation = existingEntry.getValue(LocationDetailsModel.class);

                        if (existingLocation != null && isDuplicateLocation(locationDetailsModel, existingLocation)) {
                            isDuplicate = true;
                            Log.d(TAG, "Duplicate location detected, skipping save for user: " + userName + " on date: " + currentDate);
                            break;
                        }
                    }
                }

                // Only save if not duplicate
                if (!isDuplicate) {
                    historyRef.push().setValue(locationDetailsModel)
                            .addOnSuccessListener(aVoid -> {
                                Log.d(TAG, "Location saved to history for user: " + userName + " on date: " + currentDate);
                            })
                            .addOnFailureListener(e -> {
                                Log.e(TAG, "Failed to save location to history: " + e.getMessage(), e);
                            });
                } else {
                    Log.d(TAG, "Skipped saving duplicate location for user: " + userName);
                }
            }

            @Override
            public void onCancelled(DatabaseError databaseError) {
                Log.e(TAG, "Error checking for duplicates: " + databaseError.getMessage());
                // If we can't check for duplicates, save anyway to ensure data isn't lost
                historyRef.push().setValue(locationDetailsModel);
            }
        });
    }

    /**
     * Check if two LocationDetailsModel objects are duplicates based on coordinates and timestamp
     */
    private boolean isDuplicateLocation(LocationDetailsModel newLocation, LocationDetailsModel existingLocation) {
        if (newLocation == null || existingLocation == null) {
            return false;
        }

        try {
            // Check latitude and longitude precision (within ~10 meters)
            double latDiff = Math.abs(newLocation.getLatitude() - existingLocation.getLatitude());
            double lngDiff = Math.abs(newLocation.getLongitude() - existingLocation.getLongitude());

            boolean isSameLocation = latDiff < 0.0001 && lngDiff < 0.0001; // ~10 meters precision

            // Check timestamp difference (within 30 seconds)
            boolean isSameTime = false;
            if (newLocation.getTimeStamp() > 0 && existingLocation.getTimeStamp() > 0) {
                long timeDiff = Math.abs(Long.parseLong(String.valueOf(newLocation.getTimeStamp())) -
                        Long.parseLong(String.valueOf(existingLocation.getTimeStamp())));
                isSameTime = timeDiff < 30000; // 30 seconds threshold
            }

            // Consider duplicate if same location and within time threshold
            boolean isDuplicate = isSameLocation && isSameTime;

            if (isDuplicate) {
                Log.d(TAG, "Duplicate detected - Lat: " + newLocation.getLatitude() +
                        ", Lng: " + newLocation.getLongitude() +
                        ", Time: " + newLocation.getTimeStamp());
            }

            return isDuplicate;

        } catch (Exception e) {
            Log.e(TAG, "Error comparing locations: " + e.getMessage(), e);
        }
        return false;
    }

    /**
     * Get location history for a specific user and date range
     */
    public void getLocationHistory(String userName, String startDate, String endDate, final CommonListener listener) {
        FirebaseDatabase historyDb = FirebaseDatabase.getInstance();
        DatabaseReference historyRef = historyDb.getReference("locationHistory").child(userName);

        Query query = historyRef.orderByKey().startAt(startDate).endAt(endDate);

        query.addListenerForSingleValueEvent(new ValueEventListener() {
            @Override
            public void onDataChange(DataSnapshot dataSnapshot) {
                if (listener != null) {
                    if (dataSnapshot != null && dataSnapshot.getValue() != null) {
                        listener.onTaskCompleted(dataSnapshot.getValue());
                    } else {
                        listener.onTaskCompleted(null);
                    }
                }
            }

            @Override
            public void onCancelled(DatabaseError databaseError) {
                if (listener != null) {
                    listener.onTaskCompleted(null);
                }
                Log.e(TAG, "Error fetching location history: " + databaseError.getMessage());
            }
        });
    }

    /**
     * Get location history for a specific user and specific date
     */
    public void getLocationHistoryForDate(String userName, String date, final CommonListener listener) {
        FirebaseDatabase historyDb = FirebaseDatabase.getInstance();
        DatabaseReference historyRef = historyDb.getReference("locationHistory")
                .child(userName)
                .child(date);

        historyRef.addListenerForSingleValueEvent(new ValueEventListener() {
            @Override
            public void onDataChange(DataSnapshot dataSnapshot) {
                if (listener != null) {
                    if (dataSnapshot != null && dataSnapshot.getValue() != null) {
                        listener.onTaskCompleted(dataSnapshot.getValue());
                    } else {
                        listener.onTaskCompleted(null);
                    }
                }
            }

            @Override
            public void onCancelled(DatabaseError databaseError) {
                if (listener != null) {
                    listener.onTaskCompleted(null);
                }
                Log.e(TAG, "Error fetching location history for date: " + databaseError.getMessage());
            }
        });
    }

    public void addFamilyMember(FamilyMemberModel model, final CommonListener listener) {
        FirebaseDatabase database = FirebaseDatabase.getInstance();
        DatabaseReference myRef = database.getReference(Constants.FAMILY_MEMBER_LIST);
        myRef.child(model.getMemberId()).setValue(model);
        // Read from the database
        myRef.addListenerForSingleValueEvent(new ValueEventListener() {
            @Override
            public void onDataChange(DataSnapshot dataSnapshot) {
                if (listener != null) {
                    if (dataSnapshot != null && dataSnapshot.getValue() != null) {
                        listener.onTaskCompleted(dataSnapshot.getValue());
                    } else {
                        listener.onTaskCompleted(null);
                    }
                }
            }

            @Override
            public void onCancelled(DatabaseError databaseError) {
                if (listener != null) {
                    listener.onTaskCompleted(null);
                }
            }
        });

    }

    public void updateUserModel(FamilyMemberModel model, final CommonListener listener) {
        if (model.getMemberId() != null) {
            FirebaseDatabase database = FirebaseDatabase.getInstance();
            DatabaseReference myRef = database.getReference(Constants.FAMILY_MEMBER_LIST);
            myRef.child(model.getMemberId()).setValue(model);
            // Read from the database
            myRef.addListenerForSingleValueEvent(new ValueEventListener() {
                @Override
                public void onDataChange(DataSnapshot dataSnapshot) {
                    // This method is called once with the initial value and again
                    // whenever data at this location is updated.
                    if (dataSnapshot != null && listener != null) {
                        listener.onTaskCompleted(dataSnapshot.getValue());
                    }

                }

                @Override
                public void onCancelled(DatabaseError error) {
                    // Failed to read value
                    if (listener != null) {
                        listener.onTaskCompleted(null);
                    }
                    Log.w(TAG, "Failed to read value.", error.toException());
                }
            });
        }
    }

    public void saveFamilyName(String familyName, final CommonListener listener) {
        FirebaseDatabase database = FirebaseDatabase.getInstance();
        DatabaseReference myRef = database.getReference("familyList");
        myRef.child(familyName).setValue(familyName);
        // Read from the database
        final String finalFamilyName = familyName;
        myRef.addListenerForSingleValueEvent(new ValueEventListener() {
            @Override
            public void onDataChange(DataSnapshot dataSnapshot) {
                // This method is called once with the initial value and again
                // whenever data at this location is updated.
                if (dataSnapshot != null) {
                    listener.onTaskCompleted(finalFamilyName);
                }

            }

            @Override
            public void onCancelled(DatabaseError error) {
                // Failed to read value
                listener.onTaskCompleted(null);
                Log.w(TAG, "Failed to read value.", error.toException());
            }
        });
    }

    public void registerPhoneNumber(RegistrationModel phoneNumber, final CommonListener listener) {
        FirebaseDatabase database = FirebaseDatabase.getInstance();
        DatabaseReference myRef = database.getReference("registrations");
        String key = myRef.push().getKey();
        myRef.child(phoneNumber.getPhoneNumber()).setValue(phoneNumber);
        Query query = myRef.orderByKey();
        // Read from the database
        query.addListenerForSingleValueEvent(new ValueEventListener() {
            @Override
            public void onDataChange(DataSnapshot dataSnapshot) {
                // This method is called once with the initial value and again
                // whenever data at this location is updated.
                if (listener != null) {
                    listener.onTaskCompleted(dataSnapshot.getValue());
                }
                if (dataSnapshot != null) {
                    Iterable<DataSnapshot> snapshotIterator = dataSnapshot.getChildren();
                    Iterator<DataSnapshot> iterator = snapshotIterator.iterator();

                    while (iterator.hasNext()) {
                        DataSnapshot next = (DataSnapshot) iterator.next();
                        Log.i(TAG, "Value = " + next.child("name").getValue());
                    }
                }

            }

            @Override
            public void onCancelled(DatabaseError error) {
                // Failed to read value
                if (listener != null) {
                    listener.onTaskCompleted(null);
                }
                Log.w(TAG, "Failed to read value.", error.toException());
            }
        });
    }

    public void checkRegistration(final String phoneNumber, final CommonListener listener) {
        FirebaseDatabase database = FirebaseDatabase.getInstance();
        DatabaseReference myRef = database.getReference("registrations");
        Query query = myRef.orderByChild("phoneNumber").equalTo(phoneNumber);
        // Read from the database
        query.addListenerForSingleValueEvent(new ValueEventListener() {
            @Override
            public void onDataChange(DataSnapshot dataSnapshot) {
                // This method is called once with the initial value and again
                // whenever data at this location is updated.

                if (dataSnapshot != null) {
                    if (dataSnapshot.getChildrenCount() == 0) {
                        if (listener != null) {
                            listener.onTaskCompleted(false);
                        }
                    } else {
                        if (listener != null) {
                            listener.onTaskCompleted(true);
                        }
                    }

//                    Iterable<DataSnapshot> snapshotIterator = dataSnapshot.getChildren();
//                    Iterator<DataSnapshot> iterator = snapshotIterator.iterator();
//                    while (iterator.hasNext()) {
//                        DataSnapshot next = (DataSnapshot) iterator.next();
//                        if (next.child("phoneNumber").getValue().toString().equalsIgnoreCase(phoneNumber)){
//                            if (listener != null) {
//                                listener.onTaskCompleted(true);
//                                break;
//                            }
//                        }else{
//                            if (listener != null) {
//                                listener.onTaskCompleted(false);
//                            }
//                        }
//                        Log.i(TAG, "Value = " + next.child("phoneNumber").getValue());
//                    }
                }

            }

            @Override
            public void onCancelled(DatabaseError error) {
                // Failed to read value
                if (listener != null) {
                    listener.onTaskCompleted(null);
                }
                Log.w(TAG, "Failed to read value.", error.toException());
            }
        });
    }

    public void getLocationDetailsOfUser(final String userName, final CommonListener listener) {
        FirebaseDatabase locationDb = FirebaseDatabase.getInstance();
        DatabaseReference locationRef = locationDb.getReference(Constants.LOCATION_LIST).child(userName);
        locationRef.addValueEventListener(new ValueEventListener() {
            @Override
            public void onDataChange(DataSnapshot dataSnapshot) {
                if (userName != null && dataSnapshot.getValue() != null) {
                    try {
                        LocationDetailsModel locationDetailsModel = dataSnapshot.getValue(LocationDetailsModel.class);
                        listener.onTaskCompleted(locationDetailsModel);
                    } catch (Exception e) {
                        Log.e(TAG, "Error parsing location details for " + userName, e);
                        listener.onTaskCompleted(null);
                    }
                } else {
                    listener.onTaskCompleted(null);
                }
            }

            @Override
            public void onCancelled(DatabaseError databaseError) {
                listener.onTaskCompleted(null);
            }
        });

    }

    public void getLocationDetailsOfUserOnce(final String userName, final CommonListener listener) {
        FirebaseDatabase locationDb = FirebaseDatabase.getInstance();
        DatabaseReference locationRef = locationDb.getReference(Constants.LOCATION_LIST).child(userName);
        locationRef.addListenerForSingleValueEvent(new ValueEventListener() {
            @Override
            public void onDataChange(DataSnapshot dataSnapshot) {
                if (userName != null && dataSnapshot.getValue() != null) {
                    try {
                        LocationDetailsModel locationDetailsModel = dataSnapshot.getValue(LocationDetailsModel.class);
                        listener.onTaskCompleted(locationDetailsModel);
                    } catch (Exception e) {
                        Log.e(TAG, "Error parsing location details for " + userName, e);
                        listener.onTaskCompleted(null);
                    }
                } else {
                    listener.onTaskCompleted(null);
                }
            }

            @Override
            public void onCancelled(DatabaseError databaseError) {
                listener.onTaskCompleted(null);
            }
        });

    }

    public void saveFamilyName(String familyName, FamilyMemberList familyMemberList, final CommonListener listener) {
        FirebaseDatabase database = FirebaseDatabase.getInstance();
        DatabaseReference myRef = database.getReference(Constants.FAMILY_DB_NAME);
        myRef.child(familyName).setValue(familyMemberList);
        // Read from the database
        final String finalFamilyName = familyName;
        myRef.addListenerForSingleValueEvent(new ValueEventListener() {
            @Override
            public void onDataChange(DataSnapshot dataSnapshot) {
                // This method is called once with the initial value and again
                // whenever data at this location is updated.
                if (dataSnapshot != null) {
                    listener.onTaskCompleted(finalFamilyName);
                }

            }

            @Override
            public void onCancelled(DatabaseError error) {
                // Failed to read value
                listener.onTaskCompleted(null);
                Log.w(TAG, "Failed to read value.", error.toException());
            }
        });
    }


    public void getFamilyMembersList(final String familyName, final CommonListener listener) {
        FirebaseDatabase database = FirebaseDatabase.getInstance();
        final DatabaseReference myRef = database.getReference(Constants.FAMILY_MEMBER_LIST);
        // Read from the database

        myRef.addValueEventListener(new ValueEventListener() {
            @Override
            public void onDataChange(DataSnapshot dataSnapshot) {
                // This method is called once with the initial value and again
                // whenever data at this location is updated.
                if (familyName != null && dataSnapshot.getValue() != null) {
                    ArrayList<FamilyMemberModel> list = new ArrayList<>();
                    for (DataSnapshot familyDetails : dataSnapshot.getChildren()) {
                        FamilyMemberModel familyMemberModel = familyDetails.getValue(FamilyMemberModel.class);
                        if (familyMemberModel.getFamilyName().equalsIgnoreCase(familyName)) {
                            list.add(familyMemberModel);
                        }
                    }
                    listener.onTaskCompleted(list);
                } else {
                    listener.onTaskCompleted(null);
                }

//                familyList = familyListObj.getFamilyMembersList();

            }

            @Override
            public void onCancelled(DatabaseError error) {
                // Failed to read value
                Log.w(TAG, "Failed to read value.", error.toException());
            }
        });
    }

    public void saveUserLocation(Context context, LocationDetailsModel locationDetailsModel) {
        String familyName = MySharedPreferences.getInstance().getFamilyName(context);
        FirebaseDatabase database = FirebaseDatabase.getInstance();
        DatabaseReference myRef = database.getReference(Constants.FAMILY_DB_NAME);
//        myRef.child(familyName).setValue(familyMemberList);
        // Read from the database
    }


    public void getFamilyNameFromMobileNo(final String mobileNo, final CommonListener listener) {
        FirebaseDatabase database = FirebaseDatabase.getInstance();
        DatabaseReference myRef = database.getReference(Constants.FAMILY_MEMBER_LIST);
        myRef.child(mobileNo);
        // Read from the database

        myRef.addListenerForSingleValueEvent(new ValueEventListener() {
            @Override
            public void onDataChange(DataSnapshot dataSnapshot) {

                if (mobileNo != null) {
                    FamilyMemberList familyMemberList = new FamilyMemberList();
                    ArrayList<FamilyMemberModel> familyMemberModels = new ArrayList<>();
                    for (DataSnapshot familyDetails : dataSnapshot.getChildren()) {
                        FamilyMemberModel familyMemberModel = familyDetails.getValue(FamilyMemberModel.class);
                        if (familyMemberModel.getMobile().contains(mobileNo) || mobileNo.contains(familyMemberModel.getMobile())) {
                            familyMemberModels.add(familyMemberModel);
                        }
                    }
                    familyMemberList.setFamilyMembersList(familyMemberModels);
                    listener.onTaskCompleted(familyMemberList);

                } else {
                    listener.onTaskCompleted(null);
                }

//                familyList = familyListObj.getFamilyMembersList();

            }

            @Override
            public void onCancelled(DatabaseError error) {
                // Failed to read value
                Log.w(TAG, "Failed to read value.", error.toException());
            }
        });
    }

    public void getMobileNumbers(final String mobileNo, final CommonListener listener) {
        FirebaseDatabase database = FirebaseDatabase.getInstance();
        DatabaseReference myRef = database.getReference(Constants.FAMILY_MEMBER_LIST);
        myRef.child(mobileNo);
        // Read from the database

        myRef.addListenerForSingleValueEvent(new ValueEventListener() {
            @Override
            public void onDataChange(DataSnapshot dataSnapshot) {

                if (mobileNo != null) {
                    FamilyMemberList familyMemberList = new FamilyMemberList();
                    ArrayList<FamilyMemberModel> familyMemberModels = new ArrayList<>();
                    for (DataSnapshot familyDetails : dataSnapshot.getChildren()) {
                        FamilyMemberModel familyMemberModel = familyDetails.getValue(FamilyMemberModel.class);
                        if (familyMemberModel.getMobile().equalsIgnoreCase(mobileNo)) {
                            familyMemberModels.add(familyMemberModel);
                        }
                    }
                    familyMemberList.setFamilyMembersList(familyMemberModels);
                    listener.onTaskCompleted(familyMemberList);

                } else {
                    listener.onTaskCompleted(null);
                }

//                familyList = familyListObj.getFamilyMembersList();

            }

            @Override
            public void onCancelled(DatabaseError error) {
                // Failed to read value
                Log.w(TAG, "Failed to read value.", error.toException());
            }
        });
    }

    public void getUserDetails(final String mobileNo, final CommonListener listener) {
        FirebaseDatabase database = FirebaseDatabase.getInstance();
        DatabaseReference myRef = database.getReference(Constants.USERS_LIST);
        myRef.child(mobileNo);
        // Read from the database

        myRef.addListenerForSingleValueEvent(new ValueEventListener() {
            @Override
            public void onDataChange(DataSnapshot dataSnapshot) {

                if (mobileNo != null && dataSnapshot.getValue() != null) {
                    for (DataSnapshot familyDetails : dataSnapshot.getChildren()) {
                        FamilyMemberModel familyMemberModel = familyDetails.getValue(FamilyMemberModel.class);
                        if (familyMemberModel.getMobile().equalsIgnoreCase(mobileNo)) {
                            listener.onTaskCompleted(familyMemberModel);
                        }
                    }
                } else {
                    listener.onTaskCompleted(null);
                }
            }

            @Override
            public void onCancelled(DatabaseError error) {
                listener.onTaskCompleted(null);
                // Failed to read value
                Log.w(TAG, "Failed to read value.", error.toException());
            }
        });
    }

    public void deleteFamilyMember(String memberId, final CommonListener listener) {
        FirebaseDatabase database = FirebaseDatabase.getInstance();
        DatabaseReference memberRef = database.getReference(Constants.FAMILY_MEMBER_LIST).child(memberId);
        DatabaseReference locationRef = database.getReference(Constants.LOCATION_LIST).child(memberId);
        locationRef.removeValue();
        memberRef.removeValue(new DatabaseReference.CompletionListener() {
            @Override
            public void onComplete(DatabaseError databaseError, DatabaseReference databaseReference) {
                listener.onTaskCompleted(null);
            }
        });
        locationRef.removeValue(new DatabaseReference.CompletionListener() {
            @Override
            public void onComplete(DatabaseError databaseError, DatabaseReference databaseReference) {
                listener.onTaskCompleted(null);
            }
        });

    }

    public void deleteFamilyFromDB(String familyName, final CommonListener listener) {
        FirebaseDatabase database = FirebaseDatabase.getInstance();
        DatabaseReference memberRef = database.getReference(Constants.FAMILY_DB_NAME).child(familyName);
        memberRef.removeValue(new DatabaseReference.CompletionListener() {
            @Override
            public void onComplete(DatabaseError databaseError, DatabaseReference databaseReference) {
                listener.onTaskCompleted(null);
            }
        });
    }

    public void getMandatoryData(final CommonListener listener) {
        FirebaseDatabase database = FirebaseDatabase.getInstance();
        DatabaseReference memberRef = database.getReference(Constants.UPDATE_DATA);
        memberRef.addValueEventListener(new ValueEventListener() {
            @Override
            public void onDataChange(DataSnapshot dataSnapshot) {
                if (dataSnapshot != null) {
                    listener.onTaskCompleted(dataSnapshot.getValue(UpdateModel.class));
                } else {
                    listener.onTaskCompleted(null);
                }
            }

            @Override
            public void onCancelled(DatabaseError databaseError) {

            }
        });
    }

}
