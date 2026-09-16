package com.mat.familytrack

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.google.firebase.FirebaseApp
import com.google.firebase.database.FirebaseDatabase
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class StickyTrackerService : Service(), LocationListener {

    private val TAG = "StickyTrackerService"
    private val CHANNEL_ID = "family_tracker_single_channel"
    private val NOTIFICATION_ID = 1001
    private var locationManager: LocationManager? = null
    private var gpsStateReceiver: BroadcastReceiver? = null
    private var isGpsCurrentlyOff = false

    companion object {
        var activeSosTitle: String? = null
        var activeSosText: String? = null
        var isSosCurrentlyActive: Boolean = false

        fun updateStickyNotificationFromFlutter(context: Context, title: String?, text: String?, isSosActive: Boolean) {
            activeSosTitle = title
            activeSosText = text
            isSosCurrentlyActive = isSosActive

            val serviceIntent = Intent(context, StickyTrackerService::class.java).apply {
                action = "ACTION_UPDATE_SOS_STATUS"
                putExtra("EXTRA_SOS_TITLE", title)
                putExtra("EXTRA_SOS_TEXT", text)
                putExtra("EXTRA_SOS_ACTIVE", isSosActive)
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    ContextCompat.startForegroundService(context, serviceIntent)
                } else {
                    context.startService(serviceIntent)
                }
            } catch (e: Exception) {
                Log.w("StickyTrackerService", "Failed to send update intent to StickyTrackerService: ${e.message}")
            }
        }
    }

    private var offlineCheckHandler: android.os.Handler? = null
    private val offlineSmsCheckRunnable = object : Runnable {
        override fun run() {
            try {
                if (!OfflineSmsManager.isInternetAvailable(this@StickyTrackerService)) {
                    val lastLoc = getLastKnownLocation()
                    OfflineSmsManager.checkAndSendOfflineLocationSms(this@StickyTrackerService, lastLoc)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error in offlineSmsCheckRunnable: ${e.message}")
            }
            offlineCheckHandler?.postDelayed(this, 60_000L) // Checks every 60s
        }
    }

    private fun getLastKnownLocation(): Location? {
        val lm = locationManager ?: (getSystemService(Context.LOCATION_SERVICE) as? LocationManager)
        return try {
            val lastGps = lm?.getLastKnownLocation(LocationManager.GPS_PROVIDER)
            val lastNet = lm?.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
            lastGps ?: lastNet
        } catch (_: SecurityException) {
            null
        } catch (_: Exception) {
            null
        }
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "StickyTrackerService onCreate called")
        createNotificationChannel()
        locationManager = getSystemService(Context.LOCATION_SERVICE) as? LocationManager

        checkAndUpdateGpsState()
        val defaultText = if (isSosCurrentlyActive && !activeSosText.isNullOrEmpty()) activeSosText!! else (if (isGpsCurrentlyOff) "GPS is OFF 🙁 • Tap to turn ON" else "Live family safety tracking active")
        promoteToForeground(defaultText)
        initFirebaseAndLocation()
        registerGpsProviderReceiver()

        offlineCheckHandler = android.os.Handler(android.os.Looper.getMainLooper())
        offlineCheckHandler?.postDelayed(offlineSmsCheckRunnable, 10_000L)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "StickyTrackerService onStartCommand called - START_STICKY")
        if (intent != null && intent.action == "ACTION_UPDATE_SOS_STATUS") {
            isSosCurrentlyActive = intent.getBooleanExtra("EXTRA_SOS_ACTIVE", false)
            activeSosTitle = intent.getStringExtra("EXTRA_SOS_TITLE")
            activeSosText = intent.getStringExtra("EXTRA_SOS_TEXT")
        }

        checkAndUpdateGpsState()
        val defaultText = if (isSosCurrentlyActive && !activeSosText.isNullOrEmpty()) activeSosText!! else (if (isGpsCurrentlyOff) "GPS is OFF 🙁 • Tap to turn ON" else "Live family safety tracking active")
        promoteToForeground(defaultText)
        return START_STICKY
    }

    private fun registerGpsProviderReceiver() {
        if (gpsStateReceiver == null) {
            gpsStateReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) {
                    if (intent.action == LocationManager.PROVIDERS_CHANGED_ACTION) {
                        Log.d(TAG, "Location provider changed broadcast received")
                        handleGpsStateChange()
                    }
                }
            }
            val filter = IntentFilter(LocationManager.PROVIDERS_CHANGED_ACTION)
            registerReceiver(gpsStateReceiver, filter)
        }
    }

    private fun checkAndUpdateGpsState(): Boolean {
        val lm = locationManager ?: (getSystemService(Context.LOCATION_SERVICE) as? LocationManager)
        val isGpsEnabled = lm?.isProviderEnabled(LocationManager.GPS_PROVIDER) == true ||
                lm?.isProviderEnabled(LocationManager.NETWORK_PROVIDER) == true
        isGpsCurrentlyOff = !isGpsEnabled
        return isGpsEnabled
    }

    private fun handleGpsStateChange() {
        val isGpsEnabled = checkAndUpdateGpsState()
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val phone = prefs.getString("flutter.user_phone", null)

        if (!isGpsEnabled) {
            Log.w(TAG, "Device GPS is OFF")
            updateNotification("GPS is OFF 🙁 • Tap to turn ON")
            if (!phone.isNullOrEmpty()) {
                pushGpsStatusToFirebase(phone, "OFF")
                fetchAndPushIpLocation(phone)
            }
        } else {
            Log.d(TAG, "Device GPS turned back ON")
            updateNotification("Live family safety tracking active")
            restartLocationUpdates()
            if (!phone.isNullOrEmpty()) {
                pushGpsStatusToFirebase(phone, "Active")
            }
        }
    }

    private fun fetchAndPushIpLocation(phone: String) {
        Thread {
            try {
                val url = java.net.URL("http://ip-api.com/json?fields=status,country,regionName,city,lat,lon")
                val conn = url.openConnection() as java.net.HttpURLConnection
                conn.connectTimeout = 5000
                conn.readTimeout = 5000
                conn.requestMethod = "GET"

                if (conn.responseCode == 200) {
                    val stream = conn.inputStream.bufferedReader()
                    val responseText = stream.use { it.readText() }
                    val json = org.json.JSONObject(responseText)

                    if (json.optString("status") == "success") {
                        val lat = json.optDouble("lat", 0.0)
                        val lon = json.optDouble("lon", 0.0)
                        val city = json.optString("city", "")
                        val region = json.optString("regionName", "")
                        val country = json.optString("country", "")
                        val addressParts = listOf(city, region, country).filter { it.isNotEmpty() }
                        val address = if (addressParts.isNotEmpty()) {
                            "${addressParts.joinToString(", ")} (Approx IP - GPS OFF)"
                        } else {
                            "Approximate IP Location (GPS OFF)"
                        }

                        val now = System.currentTimeMillis()
                        val dateStr = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date(now))
                        val batteryManager = getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
                        val batteryLevel = batteryManager?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: 0

                        if (lat != 0.0 && lon != 0.0) {
                            val updates = hashMapOf<String, Any>(
                                "latitude" to lat,
                                "longitude" to lon,
                                "address" to address,
                                "gpsStatus" to "IP (Approx - GPS OFF)",
                                "batteryPercentage" to batteryLevel,
                                "timeStamp" to now,
                                "date" to dateStr
                            )

                            val db = FirebaseDatabase.getInstance()
                            db.getReference("locationList").child(phone).updateChildren(updates)
                            db.getReference("LocationDetails").child(phone).updateChildren(updates)
                            Log.d(TAG, "Pushed IP-based approximate location to Firebase: $lat, $lon ($address)")
                        }
                    }
                }
                conn.disconnect()
            } catch (e: Exception) {
                Log.w(TAG, "IP Geolocation fallback failed: ${e.message}")
            }
        }.start()
    }

    private fun pushGpsStatusToFirebase(phone: String, status: String) {
        try {
            if (FirebaseApp.getApps(this).isEmpty()) {
                FirebaseApp.initializeApp(this)
            }
            val db = FirebaseDatabase.getInstance()
            val now = System.currentTimeMillis()
            val updates = hashMapOf<String, Any>(
                "gpsStatus" to status,
                "timeStamp" to now
            )
            db.getReference("locationList").child(phone).updateChildren(updates)
            db.getReference("LocationDetails").child(phone).updateChildren(updates)
            Log.d(TAG, "Pushed GPS status '$status' to Firebase for: $phone")
        } catch (e: Exception) {
            Log.e(TAG, "Error pushing GPS status: ${e.message}")
        }
    }

    private fun promoteToForeground(statusText: String) {
        val notification = buildForegroundNotification(statusText)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
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

    private fun buildForegroundNotification(statusText: String): Notification {
        val isGpsOff = isGpsCurrentlyOff
        val isSos = isSosCurrentlyActive && !activeSosTitle.isNullOrEmpty()

        val contentPendingIntent: PendingIntent = if (isGpsOff && !isSos) {
            val settingsIntent = Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            PendingIntent.getActivity(
                this, 2, settingsIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        } else {
            val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
            PendingIntent.getActivity(
                this, 0, launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        val title = if (isSos) {
            activeSosTitle ?: "🚨 SOS DISTRESS ALERT"
        } else if (isGpsOff) {
            "⚠️ FamilyTracker: GPS is OFF"
        } else {
            "FamilyTracker Active"
        }

        val text = if (isSos && !activeSosText.isNullOrEmpty()) activeSosText!! else statusText

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setContentIntent(contentPendingIntent)
            .setPriority(if (isSos) NotificationCompat.PRIORITY_MAX else (if (isGpsOff) NotificationCompat.PRIORITY_HIGH else NotificationCompat.PRIORITY_LOW))
            .setOnlyAlertOnce(!isSos && !isGpsOff)

        if (isSos) {
            builder.setCategory(NotificationCompat.CATEGORY_ALARM)
            val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
            val mapPendingIntent = PendingIntent.getActivity(
                this, 4, launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            builder.addAction(
                android.R.drawable.ic_dialog_map,
                "OPEN EMERGENCY MAP",
                mapPendingIntent
            )
        } else if (isGpsOff) {
            val settingsIntent = Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            val settingsPendingIntent = PendingIntent.getActivity(
                this, 3, settingsIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            builder.addAction(
                android.R.drawable.ic_menu_mylocation,
                "TURN ON GPS",
                settingsPendingIntent
            )
        }

        return builder.build()
    }

    private fun updateNotification(statusText: String) {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
        notificationManager?.notify(NOTIFICATION_ID, buildForegroundNotification(statusText))
    }

    private fun initFirebaseAndLocation() {
        try {
            if (FirebaseApp.getApps(this).isEmpty()) {
                FirebaseApp.initializeApp(this)
            }
            restartLocationUpdates()
        } catch (e: Exception) {
            Log.e(TAG, "Error initializing background tracker: ${e.message}")
        }
    }

    private fun restartLocationUpdates() {
        locationManager = getSystemService(Context.LOCATION_SERVICE) as? LocationManager

        try {
            locationManager?.removeUpdates(this)
        } catch (_: Exception) {}

        try {
            locationManager?.requestLocationUpdates(
                LocationManager.GPS_PROVIDER,
                30000L, // 30 seconds
                40f,    // 40 meters
                this
            )
        } catch (e: SecurityException) {
            Log.e(TAG, "GPS permission not granted: ${e.message}")
        } catch (e: Exception) {
            Log.w(TAG, "GPS provider request failed: ${e.message}")
        }

        try {
            locationManager?.requestLocationUpdates(
                LocationManager.NETWORK_PROVIDER,
                30000L,
                40f,    // 40 meters
                this
            )
        } catch (e: SecurityException) {
            Log.e(TAG, "Network location permission not granted: ${e.message}")
        } catch (e: Exception) {
            Log.w(TAG, "Network provider request failed: ${e.message}")
        }

        // Push last known location immediately on launch so Firebase is updated instantly
        try {
            val lastGps = locationManager?.getLastKnownLocation(LocationManager.GPS_PROVIDER)
            val lastNet = locationManager?.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
            val best = lastGps ?: lastNet
            if (best != null) {
                onLocationChanged(best)
            }
        } catch (_: Exception) {}
    }

    override fun onLocationChanged(location: Location) {
        isGpsCurrentlyOff = false
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val phone = prefs.getString("flutter.user_phone", null)

        val batteryManager = getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
        val batteryLevel = batteryManager?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: 0

        val now = System.currentTimeMillis()
        val timeFormatted = SimpleDateFormat("hh:mm a", Locale.getDefault()).format(Date(now))
        val dateStr = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date(now))

        // Update single notification with latest status
        if (isSosCurrentlyActive && !activeSosText.isNullOrEmpty()) {
            updateNotification(activeSosText!!)
        } else {
            updateNotification("Updated $timeFormatted • Battery $batteryLevel%")
        }

        if (phone != null && phone.isNotEmpty()) {
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

        // Check if device is offline -> Trigger 15-minute SMS location alert
        if (!OfflineSmsManager.isInternetAvailable(this)) {
            OfflineSmsManager.checkAndSendOfflineLocationSms(this, location)
        }
    }

    override fun onProviderDisabled(provider: String) {
        Log.w(TAG, "Location provider disabled: $provider")
        handleGpsStateChange()
    }

    override fun onProviderEnabled(provider: String) {
        Log.d(TAG, "Location provider enabled: $provider")
        handleGpsStateChange()
    }

    @Deprecated("Deprecated in Java")
    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}

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
        offlineCheckHandler?.removeCallbacks(offlineSmsCheckRunnable)
        locationManager?.removeUpdates(this)
        gpsStateReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {}
            gpsStateReceiver = null
        }
        super.onDestroy()
    }
}
