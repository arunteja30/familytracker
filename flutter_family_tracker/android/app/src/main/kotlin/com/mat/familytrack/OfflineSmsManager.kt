package com.mat.familytrack

import android.Manifest
import android.content.Context
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.location.Location
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import android.telephony.SmsManager
import android.util.Log
import androidx.core.content.ContextCompat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object OfflineSmsManager {

    private const val TAG = "OfflineSmsManager"
    private const val PREFS_NAME = "FlutterSharedPreferences"
    private const val PREFIX = "flutter."

    const val KEY_OFFLINE_SMS_ENABLED = PREFIX + "offline_sms_enabled"
    const val KEY_OFFLINE_SMS_PHONE = PREFIX + "offline_sms_phone"
    const val KEY_LAST_OFFLINE_SMS_TIME = "last_offline_sms_sent_time"
    const val OFFLINE_SMS_INTERVAL_MS = 15 * 60 * 1000L // 15 minutes

    private fun getPrefs(context: Context): SharedPreferences {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    fun isOfflineSmsEnabled(context: Context): Boolean {
        return getPrefs(context).getBoolean(KEY_OFFLINE_SMS_ENABLED, true)
    }

    fun setOfflineSmsEnabled(context: Context, enabled: Boolean) {
        getPrefs(context).edit().putBoolean(KEY_OFFLINE_SMS_ENABLED, enabled).apply()
    }

    fun getOfflineSmsPhone(context: Context): String {
        return getPrefs(context).getString(KEY_OFFLINE_SMS_PHONE, "") ?: ""
    }

    fun setOfflineSmsPhone(context: Context, phone: String) {
        getPrefs(context).edit().putString(KEY_OFFLINE_SMS_PHONE, phone.trim()).apply()
    }

    fun getLastOfflineSmsTime(context: Context): Long {
        return getPrefs(context).getLong(KEY_LAST_OFFLINE_SMS_TIME, 0L)
    }

    private fun setLastOfflineSmsTime(context: Context, timestamp: Long) {
        getPrefs(context).edit().putLong(KEY_LAST_OFFLINE_SMS_TIME, timestamp).apply()
    }

    fun isInternetAvailable(context: Context): Boolean {
        return try {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                ?: return false
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val activeNetwork = cm.activeNetwork ?: return false
                val capabilities = cm.getNetworkCapabilities(activeNetwork) ?: return false
                capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                        capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
            } else {
                @Suppress("DEPRECATION")
                val netInfo = cm.activeNetworkInfo
                @Suppress("DEPRECATION")
                netInfo != null && netInfo.isConnected
            }
        } catch (e: Exception) {
            Log.w(TAG, "Error checking internet connectivity: ${e.message}")
            false
        }
    }

    fun checkAndSendOfflineLocationSms(
        context: Context,
        location: Location?,
        force: Boolean = false,
        onResult: ((Boolean, String?) -> Unit)? = null
    ) {
        if (!isOfflineSmsEnabled(context) && !force) {
            Log.d(TAG, "Offline SMS location tracking is disabled in settings.")
            onResult?.invoke(false, "Offline SMS is disabled in Settings.")
            return
        }

        // If internet is available and not forced, let normal Firebase syncing handle it
        if (!force && isInternetAvailable(context)) {
            Log.d(TAG, "Internet is active. Skipping offline SMS dispatch.")
            onResult?.invoke(false, "Internet is connected. Offline SMS not needed.")
            return
        }

        val targetPhone = getOfflineSmsPhone(context).trim()
        if (targetPhone.isBlank()) {
            Log.w(TAG, "No emergency/family phone number configured for offline SMS.")
            onResult?.invoke(false, "No offline SMS recipient phone number configured.")
            return
        }

        if (ContextCompat.checkSelfPermission(context, Manifest.permission.SEND_SMS) != PackageManager.PERMISSION_GRANTED) {
            Log.w(TAG, "SEND_SMS permission is not granted.")
            onResult?.invoke(false, "SEND_SMS permission not granted on device.")
            return
        }

        val now = System.currentTimeMillis()
        val lastSent = getLastOfflineSmsTime(context)
        val elapsed = now - lastSent

        if (!force && elapsed < OFFLINE_SMS_INTERVAL_MS) {
            val remainingSec = (OFFLINE_SMS_INTERVAL_MS - elapsed) / 1000
            Log.d(TAG, "Offline SMS interval not reached ($remainingSec seconds remaining).")
            onResult?.invoke(false, "Interval not reached ($remainingSec s remaining).")
            return
        }

        val lat = location?.latitude ?: 0.0
        val lng = location?.longitude ?: 0.0

        if (lat == 0.0 && lng == 0.0) {
            Log.w(TAG, "No valid GPS location available to send via SMS.")
            onResult?.invoke(false, "No valid GPS location available.")
            return
        }

        val batteryManager = context.getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
        val battery = batteryManager?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: -1
        val timeFormatted = SimpleDateFormat("dd MMM, hh:mm a", Locale.getDefault()).format(Date(now))

        val mapUrl = "https://maps.google.com/?q=$lat,$lng"
        val message = "[FamilyTracker Offline Alert]\nTime: $timeFormatted\nBattery: ${if (battery >= 0) "$battery%" else "N/A"}\nLocation: $mapUrl"

        try {
            val smsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                context.getSystemService(SmsManager::class.java)
            } else {
                @Suppress("DEPRECATION")
                SmsManager.getDefault()
            }

            val parts = smsManager.divideMessage(message)
            if (parts.size > 1) {
                smsManager.sendMultipartTextMessage(targetPhone, null, parts, null, null)
            } else {
                smsManager.sendTextMessage(targetPhone, null, message, null, null)
            }

            setLastOfflineSmsTime(context, now)
            Log.i(TAG, "✅ Successfully sent offline location SMS to $targetPhone (lat: $lat, lng: $lng, battery: $battery%)")
            onResult?.invoke(true, null)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to send offline location SMS to $targetPhone", e)
            onResult?.invoke(false, e.localizedMessage ?: "Unknown SMS sending error")
        }
    }
}
