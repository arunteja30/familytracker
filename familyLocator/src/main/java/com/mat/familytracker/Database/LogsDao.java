package com.mat.familytracker.Database;


import androidx.lifecycle.LiveData;
import androidx.room.Dao;
import androidx.room.Insert;
import androidx.room.OnConflictStrategy;
import androidx.room.Query;

import java.util.List;

@Dao
public interface LogsDao {


    @Query("select * from Logs_tbl")
    LiveData<List<LogsEntity>> getLogsList();

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    void Insert(LogsEntity logsEntity);

    @Query("DELETE FROM Logs_tbl")
    void delete();

    @Query("DELETE FROM Logs_tbl where userId = :userId")
    void deleteUserHistory(String userId);

    @Query("select * from Logs_tbl where userId = :userId ")
    LiveData<List<LogsEntity>> getUserLocation(String userId);

    @Query("DELETE FROM Logs_tbl WHERE Log_Id = :logId")
    void deleteLogEntry(int logId);

}
