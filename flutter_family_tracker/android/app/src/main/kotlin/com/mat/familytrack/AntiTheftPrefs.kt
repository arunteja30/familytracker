package com.mat.familytrack

import android.content.Context
import android.content.SharedPreferences

object AntiTheftPrefs {
    private const val PREFS_NAME = "FlutterSharedPreferences"
    private const val PREFIX = "flutter."

    private const val KEY_ALERT_EMAIL = PREFIX + "antitheft_alert_email"
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

    fun isAntiTheftEnabled(context: Context): Boolean {
        return getPrefs(context).getBoolean(KEY_ENABLED, true)
    }

    fun setAntiTheftEnabled(context: Context, enabled: Boolean) {
        getPrefs(context).edit().putBoolean(KEY_ENABLED, enabled).apply()
    }

    fun isSirenEnabled(context: Context): Boolean {
        return getPrefs(context).getBoolean(KEY_SIREN, true)
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
}
