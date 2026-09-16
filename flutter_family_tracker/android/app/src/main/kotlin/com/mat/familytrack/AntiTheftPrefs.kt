package com.mat.familytrack

import android.content.Context
import android.content.SharedPreferences

object AntiTheftPrefs {
    private const val PREFS_NAME = "FlutterSharedPreferences"
    private const val PREFIX = "flutter."

    private const val KEY_ALERT_EMAIL = PREFIX + "antitheft_alert_email"
    private const val KEY_SENDER_EMAIL = PREFIX + "antitheft_sender_email"
    private const val KEY_SENDER_PASSWORD = PREFIX + "antitheft_sender_password"
    private const val KEY_ENABLED = PREFIX + "antitheft_enabled"
    private const val KEY_SIREN = PREFIX + "antitheft_siren_enabled"
    private const val KEY_DUAL_CAM = PREFIX + "antitheft_dual_cam_enabled"
    private const val KEY_FAILED_ATTEMPTS = PREFIX + "antitheft_failed_threshold"

    private fun getPrefs(context: Context): SharedPreferences {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    fun getAlertEmail(context: Context): String {
        return getPrefs(context).getString(KEY_ALERT_EMAIL, "") ?: ""
    }

    fun setAlertEmail(context: Context, email: String) {
        getPrefs(context).edit().putString(KEY_ALERT_EMAIL, email.trim()).apply()
    }

    fun getSenderEmail(context: Context): String {
        return getPrefs(context).getString(KEY_SENDER_EMAIL, "") ?: ""
    }

    fun setSenderEmail(context: Context, email: String) {
        getPrefs(context).edit().putString(KEY_SENDER_EMAIL, email.trim()).apply()
    }

    fun getSenderPassword(context: Context): String {
        return getPrefs(context).getString(KEY_SENDER_PASSWORD, "") ?: ""
    }

    fun setSenderPassword(context: Context, pass: String) {
        getPrefs(context).edit().putString(KEY_SENDER_PASSWORD, pass.trim().replace(" ", "")).apply()
    }

    fun isAntiTheftEnabled(context: Context): Boolean {
        return getPrefs(context).getBoolean(KEY_ENABLED, true)
    }

    fun setAntiTheftEnabled(context: Context, enabled: Boolean) {
        getPrefs(context).edit().putBoolean(KEY_ENABLED, enabled).apply()
    }

    fun isSirenEnabled(context: Context): Boolean {
        return getPrefs(context).getBoolean(KEY_SIREN, false)
    }

    fun setSirenEnabled(context: Context, enabled: Boolean) {
        getPrefs(context).edit().putBoolean(KEY_SIREN, enabled).apply()
    }

    fun isDualCamEnabled(context: Context): Boolean {
        return getPrefs(context).getBoolean(KEY_DUAL_CAM, true)
    }

    fun setDualCamEnabled(context: Context, enabled: Boolean) {
        getPrefs(context).edit().putBoolean(KEY_DUAL_CAM, enabled).apply()
    }

    fun getFailedAttemptsThreshold(context: Context): Int {
        return getPrefs(context).getInt(KEY_FAILED_ATTEMPTS, 2)
    }

    fun setFailedAttemptsThreshold(context: Context, threshold: Int) {
        getPrefs(context).edit().putInt(KEY_FAILED_ATTEMPTS, threshold).apply()
    }

    fun incrementFailedAttempts(context: Context): Int {
        val prefs = getPrefs(context)
        val count = prefs.getInt("failed_attempts_count", 0) + 1
        prefs.edit().putInt("failed_attempts_count", count).apply()
        return count
    }

    fun resetFailedAttempts(context: Context) {
        getPrefs(context).edit().putInt("failed_attempts_count", 0).apply()
    }
}
