package com.mat.familytrack

import android.app.admin.DeviceAdminReceiver
import android.app.admin.DevicePolicyManager
import android.content.Context
import android.content.Intent
import android.os.PowerManager
import android.util.Log

class AntiTheftAdminReceiver : DeviceAdminReceiver() {

    companion object {
        private const val TAG = "AntiTheftAdminReceiver"
    }

    override fun onEnabled(context: Context, intent: Intent) {
        super.onEnabled(context, intent)
        Log.i(TAG, "Device Admin: ENABLED")
        AntiTheftPrefs.setAntiTheftEnabled(context, true)
    }

    override fun onDisabled(context: Context, intent: Intent) {
        super.onDisabled(context, intent)
        Log.i(TAG, "Device Admin: DISABLED")
    }

    override fun onDisableRequested(context: Context, intent: Intent): CharSequence {
        return "Disabling Device Admin will deactivate Anti-Theft Intruder Protection and automatic alarm."
    }

    override fun onPasswordFailed(context: Context, intent: Intent) {
        super.onPasswordFailed(context, intent)

        // 1. Acquire WakeLock to keep CPU alive while phone is in locked/sleeping state
        try {
            val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            val wakeLock = pm?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "FamilyTracker:IntruderWakeLock")
            wakeLock?.acquire(15000L) // 15 seconds max
        } catch (e: Exception) {
            Log.e(TAG, "Failed to acquire wake lock", e)
        }

        val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as? DevicePolicyManager
        val dpmCount = dpm?.currentFailedPasswordAttempts ?: 0
        val internalCount = AntiTheftPrefs.incrementFailedAttempts(context)
        val failedAttempts = maxOf(dpmCount, internalCount)
        val threshold = AntiTheftPrefs.getFailedAttemptsThreshold(context)

        Log.w(TAG, "Lock screen password failed! DPM count: $dpmCount, Internal count: $internalCount, Effective: $failedAttempts (Threshold: $threshold)")

        if (failedAttempts >= threshold && AntiTheftPrefs.isAntiTheftEnabled(context)) {
            Log.w(TAG, "🚨 Security threshold reached ($failedAttempts >= $threshold)! Triggering intruder capture & alarm protocol.")

            // 1. Play Alarm Siren Sound if enabled
            if (AntiTheftPrefs.isSirenEnabled(context)) {
                AlarmPlayer.startAlarm(context, durationSeconds = 30)
            }

            // 2. Secretly capture front and back camera and email photos
            val alertEmail = AntiTheftPrefs.getAlertEmail(context)
            val dualCam = AntiTheftPrefs.isDualCamEnabled(context)

            IntruderCaptureService.start(
                context = context,
                alertEmail = alertEmail,
                captureDual = dualCam
            )
        }
    }

    override fun onPasswordSucceeded(context: Context, intent: Intent) {
        super.onPasswordSucceeded(context, intent)
        Log.i(TAG, "Lock screen password SUCCEEDED. Resetting failed attempts count and alarm.")
        AntiTheftPrefs.resetFailedAttempts(context)
        if (AlarmPlayer.isPlaying) {
            AlarmPlayer.stopAlarm()
        }
    }
}
