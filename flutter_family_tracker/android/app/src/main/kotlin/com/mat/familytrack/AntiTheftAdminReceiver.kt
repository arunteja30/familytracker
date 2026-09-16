package com.mat.familytrack

import android.app.admin.DeviceAdminReceiver
import android.app.admin.DevicePolicyManager
import android.content.Context
import android.content.Intent
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
        val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as? DevicePolicyManager
        val failedAttempts = dpm?.currentFailedPasswordAttempts ?: 1
        val threshold = AntiTheftPrefs.getFailedAttemptsThreshold(context)

        Log.w(TAG, "Lock screen password failed! Current failed count: $failedAttempts (Threshold: $threshold)")

        if (failedAttempts >= threshold && AntiTheftPrefs.isAntiTheftEnabled(context)) {
            Log.w(TAG, "🚨 Security threshold reached! Triggering intruder protocol.")

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
        Log.i(TAG, "Lock screen password SUCCEEDED. Resetting alarm.")
        if (AlarmPlayer.isPlaying) {
            AlarmPlayer.stopAlarm()
        }
    }
}
