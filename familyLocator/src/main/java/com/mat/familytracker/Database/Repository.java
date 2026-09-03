package com.mat.familytracker.Database;

import androidx.lifecycle.LiveData;
import android.content.Context;

import com.mat.familytracker.utils.AppExecutor;

import java.util.List;

public class Repository {


    private LiveData<List<LogsEntity>> mLogsList;
    private LiveData<List<LogsEntity>> userLogList;
    private AppDatabase mAppDatabase;
    private AppExecutor mAppExecutor;


    public Repository(Context context) {
        this.mAppExecutor = new AppExecutor();
        this.mAppDatabase = AppDatabase.getInstance(context);
        this.mLogsList = mAppDatabase.getLogsDao().getLogsList();
    }


    public void Insert(final LogsEntity logsEntity) {

        mAppExecutor.diskIO().execute(new Runnable() {
            @Override
            public void run() {
                mAppDatabase.getLogsDao().Insert(logsEntity);
            }
        });


    }

    public void deleteTable() {

        mAppExecutor.diskIO().execute(new Runnable() {
            @Override
            public void run() {
                mAppDatabase.getLogsDao().delete();
            }
        });
    }

    public void deleteUserHistory(final String userId) {

        mAppExecutor.diskIO().execute(new Runnable() {
            @Override
            public void run() {
                mAppDatabase.getLogsDao().deleteUserHistory(userId);
            }
        });
    }

    public LiveData<List<LogsEntity>> getUserLocation(final String userId) {

        return mAppDatabase.getLogsDao().getUserLocation(userId);
    }

    public LiveData<List<LogsEntity>> getLogsList() {
        return mLogsList;
    }

    public void deleteLogEntry(final int logId) {
        mAppExecutor.diskIO().execute(new Runnable() {
            @Override
            public void run() {
                mAppDatabase.getLogsDao().deleteLogEntry(logId);
            }
        });
    }

}
