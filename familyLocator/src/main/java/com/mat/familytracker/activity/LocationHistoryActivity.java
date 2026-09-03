package com.mat.familytracker.activity;

import android.app.DatePickerDialog;
import androidx.lifecycle.Observer;
import androidx.lifecycle.ViewModelProviders;
import android.os.AsyncTask;
import android.os.Bundle;
import androidx.annotation.Nullable;
import androidx.appcompat.app.AppCompatActivity;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import android.view.Menu;
import android.view.MenuItem;
import android.view.View;
import android.widget.Button;
import android.widget.DatePicker;
import android.widget.Toast;

import com.mat.familytracker.Database.LogsEntity;
import com.mat.familytracker.Database.Repository;
import com.mat.familytracker.R;
import com.mat.familytracker.domain.LogsActivityViewModel;
import com.mat.familytracker.utils.LogsRecycleView;

import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.Date;
import java.util.List;
import java.util.Locale;

public class LocationHistoryActivity extends AppCompatActivity {

    private RecyclerView mRecycleView;
    private LogsActivityViewModel mLogsActivityViewModel;
    private LogsRecycleView mLogsRecycleView;
    private Button btnFromDate, btnToDate, btnFilter, btnClearFilter;

    private Calendar fromDateCalendar, toDateCalendar;
    private SimpleDateFormat dateFormat;
    private List<LogsEntity> allLogsList; // Store all logs for filtering
    private List<LogsEntity> filteredLogsList; // Store filtered logs

    String userId;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_location_history);

        setTitle("Location History");

        // Initialize date formatter
        dateFormat = new SimpleDateFormat("dd/MM/yyyy", Locale.getDefault());

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

        mLogsActivityViewModel = ViewModelProviders.of(this).get(LogsActivityViewModel.class);

        if (getIntent() != null) {
            userId = getIntent().getStringExtra("USER");
            mLogsActivityViewModel.getUserList(userId).observe(this, new Observer<List<LogsEntity>>() {
                @Override
                public void onChanged(@Nullable List<LogsEntity> logsEntities) {
                    if (logsEntities != null) {
                        allLogsList.clear();
                        allLogsList.addAll(logsEntities);

                        // Initially show all logs
                        filteredLogsList.clear();
                        filteredLogsList.addAll(allLogsList);

                        mLogsRecycleView.add(filteredLogsList);
                        mRecycleView.setAdapter(mLogsRecycleView);
                    }
                }
            });
        } else {
            mLogsActivityViewModel.getpetslist().observe(this, new Observer<List<LogsEntity>>() {
                @Override
                public void onChanged(@Nullable List<LogsEntity> logsEntities) {
                    mLogsRecycleView.add(logsEntities);
                    mRecycleView.setAdapter(mLogsRecycleView);
                }
            });
        }

        mLogsRecycleView.setOnDeleteClickListener(new LogsRecycleView.OnDeleteClickListener() {
            @Override
            public void onDeleteClick(LogsEntity logsEntity, int position) {
                // Show confirmation and delete from database
                deleteLogEntry(logsEntity, position);
            }
        });
//        FileInputStream fin = null;
//        try {
//            fin = this.openFileInput(userId+"_info.txt");
//            int c;
//            String temp = "";
//
//            while ((c = fin.read()) != -1) {
//                temp = temp + Character.toString((char) c);
//            }
//            Log.e("mesage", temp);
//        } catch (FileNotFoundException e) {
//            e.printStackTrace();
//        } catch (IOException e) {
//            e.printStackTrace();
//        }

    }

    private void initializeViews() {
        mRecycleView = findViewById(R.id.recycler);
        mRecycleView.setLayoutManager(new LinearLayoutManager(this));

        btnFromDate = findViewById(R.id.btnFromDate);
        btnToDate = findViewById(R.id.btnToDate);
        btnFilter = findViewById(R.id.btnFilter);
        btnClearFilter = findViewById(R.id.btnClearFilter);

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

        filteredLogsList.clear();

        for (LogsEntity log : allLogsList) {
            if (isLogInDateRange(log)) {
                filteredLogsList.add(log);
            }
        }

        mLogsRecycleView.add(filteredLogsList);
        mRecycleView.setAdapter(mLogsRecycleView);

        Toast.makeText(this, "Filter applied: " + filteredLogsList.size() + " records found",
                Toast.LENGTH_SHORT).show();
    }

    private boolean isLogInDateRange(LogsEntity log) {
        try {
            // Parse the log date string to Date object
            Date logDate = dateFormat.parse(log.getDateTime());
            if (logDate != null) {
                long logTime = logDate.getTime();
                return logTime >= fromDateCalendar.getTimeInMillis() &&
                        logTime <= toDateCalendar.getTimeInMillis();
            }
        } catch (ParseException e) {
            e.printStackTrace();
            // If parsing fails, try to use the date as is for comparison
            String logDateStr = log.getDateTime();
            String fromDateStr = dateFormat.format(fromDateCalendar.getTime());
            String toDateStr = dateFormat.format(toDateCalendar.getTime());

            // Simple string comparison as fallback
            return logDateStr.compareTo(fromDateStr) >= 0 && logDateStr.compareTo(toDateStr) <= 0;
        }
        return false;
    }

    private void clearDateFilter() {
        // Reset button texts
        btnFromDate.setText("Select Date");
        btnToDate.setText("Select Date");

        // Reset calendars to current date
        fromDateCalendar = Calendar.getInstance();
        toDateCalendar = Calendar.getInstance();

        // Show all logs
        filteredLogsList.clear();
        filteredLogsList.addAll(allLogsList);

        mLogsRecycleView.add(filteredLogsList);
        mRecycleView.setAdapter(mLogsRecycleView);

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
            Repository repository = new Repository(LocationHistoryActivity.this);
            if (userId != null && !userId.isEmpty()) {
                repository.deleteUserHistory(userId);
            }
        }

        return true;
    }

    private void deleteLogEntry(final LogsEntity logsEntity, final int position) {
        // Show confirmation dialog
        new androidx.appcompat.app.AlertDialog.Builder(this)
                .setTitle("Delete Entry")
                .setMessage("Are you sure you want to delete this entry?")
                .setPositiveButton(android.R.string.yes, new android.content.DialogInterface.OnClickListener() {
                    public void onClick(android.content.DialogInterface dialog, int which) {
                        // Delete the log entry
                        new DeleteLogTask().execute(logsEntity);

                        // Remove from RecyclerView with animation
                        mLogsRecycleView.removeItem(position);

                        Toast.makeText(LocationHistoryActivity.this, "Entry deleted", Toast.LENGTH_SHORT).show();
                    }
                })
                .setNegativeButton(android.R.string.no, null)
                .setIcon(android.R.drawable.ic_dialog_alert)
                .show();
    }

    private class DeleteLogTask extends AsyncTask<LogsEntity, Void, LogsEntity> {
        @Override
        protected LogsEntity doInBackground(LogsEntity... logsEntities) {
            // Delete log from database using the correct method
            Repository repository = new Repository(LocationHistoryActivity.this);
            LogsEntity logToDelete = logsEntities[0];
            repository.deleteLogEntry(logToDelete.getId());
            return logToDelete;
        }

        @Override
        protected void onPostExecute(LogsEntity deletedLog) {
            super.onPostExecute(deletedLog);
            // Remove from local lists as well to keep them in sync
            for (int i = allLogsList.size() - 1; i >= 0; i--) {
                LogsEntity log = allLogsList.get(i);
                if (log.getId() == deletedLog.getId()) {
                    allLogsList.remove(i);
                    break;
                }
            }

            for (int i = filteredLogsList.size() - 1; i >= 0; i--) {
                LogsEntity log = filteredLogsList.get(i);
                if (log.getId() == deletedLog.getId()) {
                    filteredLogsList.remove(i);
                    break;
                }
            }
        }
    }
}
