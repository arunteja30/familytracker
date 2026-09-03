package com.mat.commonutils.model;

import android.app.Application;
import androidx.lifecycle.AndroidViewModel;
import androidx.lifecycle.LiveData;
import androidx.annotation.NonNull;


import com.mat.commonutils.roomDB.LogsEntity;
import com.mat.commonutils.roomDB.Repository;

import java.util.List;

public class LogsActivityViewModel extends AndroidViewModel {

    private Repository mRepository;
    private LiveData<List<LogsEntity>> mlist;

    public LogsActivityViewModel(@NonNull Application application) {
        super(application);
        mRepository = new Repository(application);
        mlist = mRepository.getLogsList();
    }

    public LiveData<List<LogsEntity>> getpetslist() {
        return mlist;
    }

    public LiveData<List<LogsEntity>> getUserList(String userId) {
        return mRepository.getUserLocation(userId);

    }


}
