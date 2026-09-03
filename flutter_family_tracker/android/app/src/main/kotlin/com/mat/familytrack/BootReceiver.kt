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
            "com.htc.intent.action.QUICKBOOT_POWERON"
        )

        if (action in validActions) {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val isLoggedIn = prefs.getBoolean("flutter.is_logged_in", false)
            val phone = prefs.getString("flutter.user_phone", null)

            Log.d(TAG, "Boot check - isLoggedIn: $isLoggedIn, phone: $phone")

            if (isLoggedIn || !phone.isNullOrEmpty()) {
                val serviceIntent = Intent(context, StickyTrackerService::class.java)
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        ContextCompat.startForegroundService(context, serviceIntent)
                    } else {
                        context.startService(serviceIntent)
                    }
                    Log.d(TAG, "StickyTrackerService successfully launched after boot/restart")
                } catch (e: Exception) {
                    Log.e(TAG, "Failed launching background service on boot: ${e.message}")
                }
            }
        }
    }
}
