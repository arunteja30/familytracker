package com.mat.familytracker.activity;

import android.app.DatePickerDialog;
import androidx.lifecycle.Observer;
import androidx.lifecycle.ViewModelProviders;
import android.content.Context;
import android.net.ConnectivityManager;
import android.net.NetworkInfo;
import android.os.Build;
import android.os.Bundle;
import androidx.annotation.Nullable;
import androidx.appcompat.app.AppCompatActivity;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import android.util.Log;
import android.view.Menu;
import android.view.MenuItem;
import android.view.View;
import android.widget.Button;
import android.widget.DatePicker;
import android.widget.TextView;
import android.widget.Toast;

import com.mat.commonutils.commonutils.CommonListener;
import com.mat.familytracker.Database.LogsEntity;
import com.mat.familytracker.Database.Repository;
import com.mat.familytracker.R;
import com.mat.familytracker.domain.LogsActivityViewModel;
import com.mat.familytracker.gpstracker.GPSHandler;
import com.mat.familytracker.utils.LogsRecycleView;

import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.Date;
import java.util.List;
import java.util.Locale;
import java.util.Map;

public class LocationHistoryDetailsActivity extends AppCompatActivity {

    private static final String TAG = "LocationHistoryDetails";

    private RecyclerView mRecycleView;
    private LogsActivityViewModel mLogsActivityViewModel;
    private LogsRecycleView mLogsRecycleView;
    private Button btnFromDate, btnToDate, btnFilter, btnClearFilter;
    private TextView tvStatus;

    private Calendar fromDateCalendar, toDateCalendar;
    private SimpleDateFormat dateFormat;
    private SimpleDateFormat firebaseDateFormat;
    private List<LogsEntity> allLogsList;
    private List<LogsEntity> filteredLogsList;

    private String userId;
    private boolean isOnline = false;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_location_history);

        setTitle("Location History Details");

        // Initialize date formatters
        dateFormat = new SimpleDateFormat("dd/MM/yyyy HH:mm:ss", Locale.getDefault());
        firebaseDateFormat = new SimpleDateFormat("yyyy-MM-dd", Locale.getDefault());

        // Initialize calendars
        fromDateCalendar = Calendar.getInstance();
        toDateCalendar = Calendar.getInstance();

        // Initialize lists
        allLogsList = new ArrayList<>();
        filteredLogsList = new ArrayList<>();

        // Initialize views
        initializeViews();

        // Set up click listeners
        setupClickListeners();

        // Check network connectivity
        checkNetworkConnectivity();

        // Get user ID from intent
        if (getIntent() != null) {
            userId = getIntent().getStringExtra("USER");
        }

        // Load data based on connectivity
        loadLocationHistory();
    }

    private void initializeViews() {
        mRecycleView = findViewById(R.id.recycler);
        mRecycleView.setLayoutManager(new LinearLayoutManager(this));

        btnFromDate = findViewById(R.id.btnFromDate);
        btnToDate = findViewById(R.id.btnToDate);
        btnFilter = findViewById(R.id.btnFilter);
        btnClearFilter = findViewById(R.id.btnClearFilter);
        tvStatus = findViewById(R.id.tvStatus);

        mLogsRecycleView = new LogsRecycleView(this);
    }

    private void setupClickListeners() {
        btnFromDate.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                showDatePickerDialog(true);
            }
        });

        btnToDate.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                showDatePickerDialog(false);
            }
        });

        btnFilter.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                applyDateFilter();
            }
        });

        btnClearFilter.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                clearDateFilter();
            }
        });
    }

    private void checkNetworkConnectivity() {
        ConnectivityManager connectivityManager = (ConnectivityManager) getSystemService(Context.CONNECTIVITY_SERVICE);
        NetworkInfo networkInfo = connectivityManager.getActiveNetworkInfo();
        isOnline = networkInfo != null && networkInfo.isConnected();

        Log.d(TAG, "Network status: " + (isOnline ? "Online" : "Offline"));

        // Update status TextView with appropriate color and text
        updateStatusIndicator();
    }

    private void updateStatusIndicator() {
        if (tvStatus != null) {
            if (isOnline) {
                tvStatus.setText("🟢 Online Data - Firebase");
                tvStatus.setBackgroundColor(getResources().getColor(android.R.color.holo_green_dark));
                tvStatus.setTextColor(getResources().getColor(android.R.color.white));
            } else {
                tvStatus.setText("🔴 Offline Data - Local Database");
                tvStatus.setBackgroundColor(getResources().getColor(android.R.color.holo_red_dark));
                tvStatus.setTextColor(getResources().getColor(android.R.color.white));
            }
        }
    }

    private void loadLocationHistory() {
        if (userId == null || userId.isEmpty()) {
            Toast.makeText(this, "User ID not provided", Toast.LENGTH_SHORT).show();
            return;
        }

        if (isOnline) {
            loadFromFirebase();
        } else {
            loadFromLocalDatabase();
        }
    }

    private void loadFromFirebase() {
        // Update status to show loading from Firebase
        if (tvStatus != null) {
            tvStatus.setText("🟢 Loading from Firebase...");
            tvStatus.setBackgroundColor(getResources().getColor(android.R.color.holo_green_dark));
        }

        // Get last 30 days of data by default
        Calendar cal = Calendar.getInstance();
        String endDate = firebaseDateFormat.format(cal.getTime());

        cal.add(Calendar.DAY_OF_MONTH, -30);
        String startDate = firebaseDateFormat.format(cal.getTime());

        Log.d(TAG, "Loading Firebase data for user: " + userId + " from " + startDate + " to " + endDate);

        FirebaseHandler.getInstance().getLocationHistory(userId, startDate, endDate, new CommonListener() {
            @Override
            public void onTaskCompleted(Object result) {
                if (result != null) {
                    // Update status to show successful Firebase load
                    if (tvStatus != null) {
                        tvStatus.setText("🟢 Online Data - Firebase");
                    }
                    parseFirebaseData(result);
                } else {
                    Log.d(TAG, "No Firebase data found, falling back to local database");
                    // Update status to show fallback to local
                    if (tvStatus != null) {
                        tvStatus.setText("🔴 No Online Data - Using Local Database");
                        tvStatus.setBackgroundColor(getResources().getColor(android.R.color.holo_red_dark));
                    }
                    isOnline = false; // Set to offline since Firebase failed
                    loadFromLocalDatabase();
                }
            }
        });
    }

    private void parseFirebaseData(Object firebaseData) {
        parseFirebaseData(firebaseData, false);
    }

    private void parseFirebaseData(Object firebaseData, boolean isFilteredData) {
        if (isFilteredData) {
            // When filtering, clear filteredLogsList instead of allLogsList
            filteredLogsList.clear();
        } else {
            // When loading initial data, clear allLogsList
            allLogsList.clear();
        }

        List<LogsEntity> targetList = isFilteredData ? filteredLogsList : allLogsList;
        List<LogsEntity> tempList = new ArrayList<>(); // Temporary list to check for duplicates

        try {
            if (firebaseData instanceof Map) {
                Map<String, Object> dateMap = (Map<String, Object>) firebaseData;

                for (Map.Entry<String, Object> dateEntry : dateMap.entrySet()) {
                    String date = dateEntry.getKey(); // YYYY-MM-DD format
                    Object dayData = dateEntry.getValue();

                    if (dayData instanceof Map) {
                        Map<String, Object> locationsMap = (Map<String, Object>) dayData;

                        for (Map.Entry<String, Object> locationEntry : locationsMap.entrySet()) {
                            Object locationData = locationEntry.getValue();

                            if (locationData instanceof Map) {
                                Map<String, Object> locationMap = (Map<String, Object>) locationData;
                                LogsEntity logEntity = convertFirebaseToLogEntity(locationMap, date);
                                if (logEntity != null && !isDuplicate(logEntity, tempList)) {
                                    tempList.add(logEntity);
                                }
                            }
                        }
                    }
                }
                sortLogsByDate(tempList);
            }
        } catch (Exception e) {
            Log.e(TAG, "Error parsing Firebase data: " + e.getMessage(), e);
            Toast.makeText(this, "Error loading online data, switching to offline", Toast.LENGTH_SHORT).show();
            loadFromLocalDatabase();
            return;
        }

        // Add all non-duplicate entries to target list
        targetList.addAll(tempList);

        // Sort by date (newest first)
        sortLogsByDate(targetList);

        if (!isFilteredData) {
            // Update filtered list to show all data initially
            filteredLogsList.clear();
            filteredLogsList.addAll(allLogsList);
        }

        // Update UI
        updateRecyclerView();

        String message = isFilteredData ?
                "Filter applied: " + filteredLogsList.size() + " records found" :
                "Loaded " + allLogsList.size() + " records from Firebase";

        Log.d(TAG, message);
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show();
    }

    /**
     * Check if a LogsEntity is duplicate based on datetime, latitude, and longitude
     */
    private boolean isDuplicate(LogsEntity newEntity, List<LogsEntity> existingList) {
        for (LogsEntity existing : existingList) {
            // Check if datetime, latitude, and longitude are the same
            if (newEntity.getDateTime() != null &&
                    newEntity.getDateTime().equals(existing.getDateTime()) &&
                    isSameLocation(newEntity.getLatitude(), existing.getLatitude()) &&
                    isSameLocation(newEntity.getLongitude(), existing.getLongitude())) {

                Log.d(TAG, "Duplicate entry found for datetime: " + newEntity.getDateTime() +
                        " at location: " + newEntity.getLatitude() + ", " + newEntity.getLongitude());
                return true;
            }
        }
        return false;
    }

    /**
     * Compare two location coordinates (handle both String and Double types)
     */
    private boolean isSameLocation(Object coord1, Object coord2) {
        if (coord1 == null || coord2 == null) {
            return coord1 == coord2;
        }

        try {
            double val1, val2;

            if (coord1 instanceof String) {
                val1 = Double.parseDouble((String) coord1);
            } else if (coord1 instanceof Double) {
                val1 = (Double) coord1;
            } else {
                val1 = Double.parseDouble(coord1.toString());
            }

            if (coord2 instanceof String) {
                val2 = Double.parseDouble((String) coord2);
            } else if (coord2 instanceof Double) {
                val2 = (Double) coord2;
            } else {
                val2 = Double.parseDouble(coord2.toString());
            }

            // Consider coordinates same if they are within 0.000001 degrees (approximately 0.1 meters)
            return Math.abs(val1 - val2) < 0.000001;

        } catch (NumberFormatException e) {
            Log.e(TAG, "Error comparing coordinates: " + e.getMessage());
            return false;
        }
    }

    private LogsEntity convertFirebaseToLogEntity(Map<String, Object> locationMap, String date) {
        try {
            LogsEntity logEntity = new LogsEntity();

            String displayDateTime;

            // Check if timestamp is available for more precise date/time
            if (locationMap.containsKey("timeStamp")) {
                long timestamp = Long.parseLong(String.valueOf(locationMap.get("timeStamp")));
                Date timestampDate = new Date(timestamp);

                // Create a format that shows both date and time
                SimpleDateFormat dateTimeFormat = new SimpleDateFormat("dd/MM/yyyy HH:mm:ss", Locale.getDefault());
                displayDateTime = dateTimeFormat.format(timestampDate);
            } else {
                // Fallback to date only if no timestamp available
                Date firebaseDate = firebaseDateFormat.parse(date);
                displayDateTime = dateFormat.format(firebaseDate);
            }

            // Set basic location data
            logEntity.setLatitude((Double) locationMap.get("latitude"));
            logEntity.setLongitude((Double) locationMap.get("longitude"));
            logEntity.setDateTime(displayDateTime);

            GPSHandler.getInstance().getAddressFromLocation(this, logEntity.getLatitude(), logEntity.getLongitude(), new CommonListener() {
                @Override
                public void onTaskCompleted(Object value) {
                    if (value != null) {
                        logEntity.setAddress((String) value);
                        // Update UI if needed
                        updateRecyclerView();
                    }
                }
            });

            // Set user ID
            logEntity.setUserId(userId);

            // Generate a unique ID for this entry
            if (locationMap.containsKey("timeStamp")) {
                logEntity.setId(Integer.parseInt(String.valueOf(locationMap.get("timeStamp")).substring(0, 8)));
            } else {
                logEntity.setId((int) System.currentTimeMillis());
            }

            return logEntity;
        } catch (Exception e) {
            Log.e(TAG, "Error converting Firebase data to LogEntity: " + e.getMessage(), e);
            return null;
        }
    }

    private void sortLogsByDate() {
        sortLogsByDate(allLogsList);
    }

    private void sortLogsByDate(List<LogsEntity> logsList) {
        // Sort logs by date (newest first)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            logsList.sort((log1, log2) -> {
                try {
                    Date date1 = dateFormat.parse(log1.getDateTime());
                    Date date2 = dateFormat.parse(log2.getDateTime());
                    return date2.compareTo(date1); // Newest first
                } catch (ParseException e) {
                    return 0;
                }
            });
        }
    }

    private void loadFromLocalDatabase() {
        // Update status to show loading from local database
        if (tvStatus != null) {
            tvStatus.setText("🔴 Loading from Local Database...");
            tvStatus.setBackgroundColor(getResources().getColor(android.R.color.holo_red_dark));
        }

        Log.d(TAG, "Loading from local database for user: " + userId);

        mLogsActivityViewModel = ViewModelProviders.of(this).get(LogsActivityViewModel.class);

        if (userId != null && !userId.isEmpty()) {
            mLogsActivityViewModel.getUserList(userId).observe(this, new Observer<List<LogsEntity>>() {
                @Override
                public void onChanged(@Nullable List<LogsEntity> logsEntities) {
                    // Update status to show successful local load
                    if (tvStatus != null) {
                        tvStatus.setText("🔴 Offline Data - Local Database");
                    }

                    if (logsEntities != null) {
                        allLogsList.clear();
                        allLogsList.addAll(logsEntities);

                        filteredLogsList.clear();
                        filteredLogsList.addAll(allLogsList);

                        updateRecyclerView();

                        Log.d(TAG, "Loaded " + allLogsList.size() + " records from local database");
                        Toast.makeText(LocationHistoryDetailsActivity.this,
                                "Loaded " + allLogsList.size() + " records from local database",
                                Toast.LENGTH_SHORT).show();
                    } else {
                        Toast.makeText(LocationHistoryDetailsActivity.this,
                                "No offline data available", Toast.LENGTH_SHORT).show();
                    }
                }
            });
        } else {
            mLogsActivityViewModel.getpetslist().observe(this, new Observer<List<LogsEntity>>() {
                @Override
                public void onChanged(@Nullable List<LogsEntity> logsEntities) {
                    if (logsEntities != null) {
                        allLogsList.clear();
                        allLogsList.addAll(logsEntities);

                        filteredLogsList.clear();
                        filteredLogsList.addAll(allLogsList);

                        updateRecyclerView();
                    }
                }
            });
        }
    }

    private void updateRecyclerView() {
        mLogsRecycleView.add(filteredLogsList);
        mRecycleView.setAdapter(mLogsRecycleView);
    }

    private void showDatePickerDialog(final boolean isFromDate) {
        Calendar calendar = isFromDate ? fromDateCalendar : toDateCalendar;

        DatePickerDialog datePickerDialog = new DatePickerDialog(
                this,
                new DatePickerDialog.OnDateSetListener() {
                    @Override
                    public void onDateSet(DatePicker view, int year, int month, int dayOfMonth) {
                        Calendar selectedCalendar = isFromDate ? fromDateCalendar : toDateCalendar;
                        selectedCalendar.set(Calendar.YEAR, year);
                        selectedCalendar.set(Calendar.MONTH, month);
                        selectedCalendar.set(Calendar.DAY_OF_MONTH, dayOfMonth);

                        if (isFromDate) {
                            selectedCalendar.set(Calendar.HOUR_OF_DAY, 0);
                            selectedCalendar.set(Calendar.MINUTE, 0);
                            selectedCalendar.set(Calendar.SECOND, 0);
                            selectedCalendar.set(Calendar.MILLISECOND, 0);
                            btnFromDate.setText(dateFormat.format(selectedCalendar.getTime()));
                        } else {
                            selectedCalendar.set(Calendar.HOUR_OF_DAY, 23);
                            selectedCalendar.set(Calendar.MINUTE, 59);
                            selectedCalendar.set(Calendar.SECOND, 59);
                            selectedCalendar.set(Calendar.MILLISECOND, 999);
                            btnToDate.setText(dateFormat.format(selectedCalendar.getTime()));
                        }
                    }
                },
                calendar.get(Calendar.YEAR),
                calendar.get(Calendar.MONTH),
                calendar.get(Calendar.DAY_OF_MONTH)
        );

        datePickerDialog.show();
    }

    private void applyDateFilter() {
        if (btnFromDate.getText().toString().equals("Select Date") ||
                btnToDate.getText().toString().equals("Select Date")) {
            Toast.makeText(this, "Please select both from and to dates", Toast.LENGTH_SHORT).show();
            return;
        }

        if (fromDateCalendar.getTimeInMillis() > toDateCalendar.getTimeInMillis()) {
            Toast.makeText(this, "From date cannot be later than to date", Toast.LENGTH_SHORT).show();
            return;
        }

        // If online, fetch specific date range from Firebase
        if (isOnline && userId != null && !userId.isEmpty()) {
            String startDate = firebaseDateFormat.format(fromDateCalendar.getTime());
            String endDate = firebaseDateFormat.format(toDateCalendar.getTime());

            FirebaseHandler.getInstance().getLocationHistory(userId, startDate, endDate, new CommonListener() {
                @Override
                public void onTaskCompleted(Object result) {
                    if (result != null) {
                        parseFirebaseData(result, true); // Pass true to indicate this is filtered data
                    } else {
                        // No data found for the date range, clear the filtered list
                        filteredLogsList.clear();
                        updateRecyclerView();
                        Toast.makeText(LocationHistoryDetailsActivity.this,
                                "No data found for selected date range", Toast.LENGTH_SHORT).show();
                    }
                }
            });
        } else {
            // Filter local data
            filteredLogsList.clear();
            for (LogsEntity log : allLogsList) {
                if (isLogInDateRange(log)) {
                    filteredLogsList.add(log);
                }
            }
            updateRecyclerView();
            Toast.makeText(this, "Filter applied: " + filteredLogsList.size() + " records found",
                    Toast.LENGTH_SHORT).show();
        }
    }

    private boolean isLogInDateRange(LogsEntity log) {
        try {
            Date logDate = dateFormat.parse(log.getDateTime());
            if (logDate != null) {
                long logTime = logDate.getTime();
                return logTime >= fromDateCalendar.getTimeInMillis() &&
                        logTime <= toDateCalendar.getTimeInMillis();
            }
        } catch (ParseException e) {
            Log.e(TAG, "Error parsing log date: " + e.getMessage(), e);
        }
        return false;
    }

    private void clearDateFilter() {
        btnFromDate.setText("Select Date");
        btnToDate.setText("Select Date");

        fromDateCalendar = Calendar.getInstance();
        toDateCalendar = Calendar.getInstance();

        filteredLogsList.clear();
        filteredLogsList.addAll(allLogsList);

        updateRecyclerView();

        Toast.makeText(this, "Filter cleared: Showing all " + filteredLogsList.size() + " records",
                Toast.LENGTH_SHORT).show();
    }

    @Override
    public boolean onCreateOptionsMenu(Menu menu) {
        getMenuInflater().inflate(R.menu.loc_history_menu, menu);
        return true;
    }

    @Override
    public boolean onOptionsItemSelected(MenuItem item) {
        if (item.getItemId() == R.id.clear) {
            // Show confirmation dialog for clearing data
            new androidx.appcompat.app.AlertDialog.Builder(this)
                    .setTitle("Clear History Data")
                    .setMessage(isOnline ?
                            "This will clear local offline data only. Online Firebase data will remain unchanged." :
                            "This will clear all local history data for this user.")
                    .setPositiveButton("Clear All Data", (dialog, which) -> {
                        clearAllLocalData();
                    })
                    .setNeutralButton("Clear User Data Only", (dialog, which) -> {
                        if (userId != null && !userId.isEmpty()) {
                            clearUserLocalData();
                        } else {
                            Toast.makeText(this, "No specific user selected", Toast.LENGTH_SHORT).show();
                        }
                    })
                    .setNegativeButton("Cancel", null)
                    .setIcon(android.R.drawable.ic_dialog_alert)
                    .show();
        }
        return true;
    }

    /**
     * Clear all local history data
     */
    private void clearAllLocalData() {
        Repository repository = new Repository(this);
        repository.deleteTable(); // Clear all logs

        // Clear UI lists
        allLogsList.clear();
        filteredLogsList.clear();
        updateRecyclerView();

        // Update status
        if (tvStatus != null) {
            tvStatus.setText(isOnline ? "🟢 Online Data - Firebase" : "🔴 Offline Data - Local Database (Cleared)");
        }

        Toast.makeText(this, "All local history data cleared successfully", Toast.LENGTH_SHORT).show();
        Log.d(TAG, "All local history data cleared");
    }

    /**
     * Clear local data for specific user only
     */
    private void clearUserLocalData() {
        Repository repository = new Repository(this);
        repository.deleteUserHistory(userId); // Clear specific user logs

        // Clear UI lists
        allLogsList.clear();
        filteredLogsList.clear();
        updateRecyclerView();
    }
}

