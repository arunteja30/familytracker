package com.mat.familytrack

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat

class BootReceiver : BroadcastReceiver() {

    private val TAG = "BootReceiver"

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        Log.d(TAG, "Broadcast received: $action")

        val validActions = listOf(
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON",
            "android.intent.action.REBOOT"
        )

        if (action in validActions) {
            var isLoggedIn = false
            var phone: String? = null

            try {
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                isLoggedIn = prefs.getBoolean("flutter.is_logged_in", false)
                phone = prefs.getString("flutter.user_phone", null)
            } catch (e: Exception) {
                Log.w(TAG, "Standard storage locked, attempting device protected storage: ${e.message}")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    try {
                        val directBootContext = context.createDeviceProtectedStorageContext()
                        val directPrefs = directBootContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                        isLoggedIn = directPrefs.getBoolean("flutter.is_logged_in", false)
                        phone = directPrefs.getString("flutter.user_phone", null)
                    } catch (ex: Exception) {
                        Log.e(TAG, "Error accessing device protected storage: ${ex.message}")
                    }
                }
            }

            Log.d(TAG, "Boot event processed ($action) - isLoggedIn: $isLoggedIn, phone: $phone")

            if (isLoggedIn || !phone.isNullOrEmpty()) {
                val serviceIntent = Intent(context, StickyTrackerService::class.java)
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        ContextCompat.startForegroundService(context, serviceIntent)
                    } else {
                        context.startService(serviceIntent)
                    }
                    Log.d(TAG, "StickyTrackerService successfully started on boot.")
                } catch (e: Exception) {
                    Log.e(TAG, "Error starting StickyTrackerService on boot: ${e.message}", e)
                }
            } else {
                Log.d(TAG, "No logged-in user or phone found. Service start skipped.")
            }
        }
    }
}
