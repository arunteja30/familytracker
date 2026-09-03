package com.mat.familytrack

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.BatteryManager
import android.os.Build
import android.os.IBinder
import android.os.SystemClock
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.firebase.FirebaseApp
import com.google.firebase.database.FirebaseDatabase
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class StickyTrackerService : Service(), LocationListener {

    private val TAG = "StickyTrackerService"
    private val CHANNEL_ID = "family_tracker_background_channel"
    private val NOTIFICATION_ID = 4521
    private var locationManager: LocationManager? = null

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "StickyTrackerService onCreate called")
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildForegroundNotification())
        initFirebaseAndLocation()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "StickyTrackerService onStartCommand called - START_STICKY")
        startForeground(NOTIFICATION_ID, buildForegroundNotification())
        return START_STICKY
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "FamilyTracker Safety Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Continuous background location tracking for family safety"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }

    private fun buildForegroundNotification(): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("FamilyTracker Active")
            .setContentText("Continuous live family safety tracking running in background")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun initFirebaseAndLocation() {
        try {
            if (FirebaseApp.getApps(this).isEmpty()) {
                FirebaseApp.initializeApp(this)
            }

            locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager

            try {
                locationManager?.requestLocationUpdates(
                    LocationManager.GPS_PROVIDER,
                    30000L, // 30 seconds
                    10f,    // 10 meters
                    this
                )
            } catch (e: SecurityException) {
                Log.e(TAG, "GPS permission not granted: ${e.message}")
            }

            try {
                locationManager?.requestLocationUpdates(
                    LocationManager.NETWORK_PROVIDER,
                    30000L,
                    10f,
                    this
                )
            } catch (e: SecurityException) {
                Log.e(TAG, "Network location permission not granted: ${e.message}")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error initializing background tracker: ${e.message}")
        }
    }

    override fun onLocationChanged(location: Location) {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val phone = prefs.getString("flutter.user_phone", null)

        if (phone != null && phone.isNotEmpty()) {
            val batteryManager = getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
            val batteryLevel = batteryManager?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: 0

            val now = System.currentTimeMillis()
            val dateStr = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date(now))

            val locationMap = hashMapOf<String, Any>(
                "latitude" to location.latitude,
                "longitude" to location.longitude,
                "batteryPercentage" to batteryLevel,
                "timeStamp" to now,
                "date" to dateStr,
                "address" to "Lat: ${String.format(Locale.US, "%.4f", location.latitude)}, Lon: ${String.format(Locale.US, "%.4f", location.longitude)}",
                "gpsStatus" to "Active"
            )

            try {
                val db = FirebaseDatabase.getInstance()
                db.getReference("locationList").child(phone).setValue(locationMap)
                db.getReference("LocationDetails").child(phone).setValue(locationMap)
                db.getReference("LocationHistory").child(phone).child(dateStr).child(now.toString()).setValue(locationMap)
                Log.d(TAG, "Background location pushed to Firebase for: $phone")
            } catch (e: Exception) {
                Log.e(TAG, "Failed pushing location to Firebase: ${e.message}")
            }
        }
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        Log.d(TAG, "App task removed (force killed) - scheduling auto-revive")
        val restartServiceIntent = Intent(applicationContext, StickyTrackerService::class.java).apply {
            setPackage(packageName)
        }
        val restartPendingIntent = PendingIntent.getService(
            applicationContext, 1, restartServiceIntent,
            PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
        )
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as? AlarmManager
        alarmManager?.set(
            AlarmManager.ELAPSED_REALTIME_WAKEUP,
            SystemClock.elapsedRealtime() + 3000,
            restartPendingIntent
        )
        super.onTaskRemoved(rootIntent)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        locationManager?.removeUpdates(this)
        super.onDestroy()
    }
}
