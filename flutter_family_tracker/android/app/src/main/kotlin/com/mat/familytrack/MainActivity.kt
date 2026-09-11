package com.mat.familytrack

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.ContactsContract
import android.provider.Settings
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.mat.familytrack/background_service"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startNativeStickyService" -> {
                    startNativeTrackerService()
                    result.success(true)
                }
                "requestBatteryOptimizationExemption" -> {
                    requestBatteryOptimizationExemption()
                    result.success(true)
                }
                "getDeviceContacts" -> {
                    val contactsMap = getDeviceContacts()
                    result.success(contactsMap)
                }
                "getDeviceOemInfo" -> {
                    val oemInfo = getDeviceOemInfo()
                    result.success(oemInfo)
                }
                "openOemAutoStartSettings" -> {
                    val success = openOemAutoStartSettings()
                    result.success(success)
                }
                "openLocationSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun getDeviceOemInfo(): HashMap<String, Any> {
        val manufacturer = Build.MANUFACTURER ?: ""
        val brand = Build.BRAND ?: ""
        val model = Build.MODEL ?: ""
        val mLower = manufacturer.lowercase()
        val bLower = brand.lowercase()

        val isStrictOem = mLower.contains("xiaomi") || mLower.contains("redmi") || mLower.contains("poco") ||
                mLower.contains("oppo") || mLower.contains("realme") ||
                mLower.contains("vivo") || mLower.contains("iqoo") ||
                mLower.contains("samsung") ||
                mLower.contains("oneplus") ||
                mLower.contains("huawei") || mLower.contains("honor") ||
                mLower.contains("asus") ||
                bLower.contains("xiaomi") || bLower.contains("redmi") || bLower.contains("poco") ||
                bLower.contains("oppo") || bLower.contains("realme") ||
                bLower.contains("vivo") || bLower.contains("iqoo") ||
                bLower.contains("oneplus") || bLower.contains("huawei") || bLower.contains("honor")

        val map = HashMap<String, Any>()
        map["manufacturer"] = manufacturer
        map["brand"] = brand
        map["model"] = model
        map["isStrictOem"] = isStrictOem
        map["sdkVersion"] = Build.VERSION.SDK_INT
        return map
    }

    private fun openOemAutoStartSettings(): Boolean {
        val mLower = (Build.MANUFACTURER ?: "").lowercase()
        val bLower = (Build.BRAND ?: "").lowercase()

        val intentsToTry = mutableListOf<Intent>()

        if (mLower.contains("xiaomi") || mLower.contains("redmi") || mLower.contains("poco") ||
            bLower.contains("xiaomi") || bLower.contains("redmi") || bLower.contains("poco")) {
            intentsToTry.add(Intent().setComponent(android.content.ComponentName("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity")))
            intentsToTry.add(Intent("miui.intent.action.OP_AUTO_START").addCategory(Intent.CATEGORY_DEFAULT))
            intentsToTry.add(Intent().setComponent(android.content.ComponentName("com.miui.powerkeeper", "com.miui.powerkeeper.ui.HiddenAppsConfigActivity")))
        } else if (mLower.contains("oppo") || mLower.contains("realme") || bLower.contains("oppo") || bLower.contains("realme")) {
            intentsToTry.add(Intent().setComponent(android.content.ComponentName("com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity")))
            intentsToTry.add(Intent().setComponent(android.content.ComponentName("com.coloros.safecenter", "com.coloros.safecenter.startupapp.StartupAppListActivity")))
            intentsToTry.add(Intent().setComponent(android.content.ComponentName("com.oppo.safe", "com.oppo.safe.permission.startup.StartupAppListActivity")))
            intentsToTry.add(Intent().setComponent(android.content.ComponentName("com.coloros.safecenter", "com.coloros.safecenter.permission.startupApp.StartupAppListActivity")))
            intentsToTry.add(Intent().setComponent(android.content.ComponentName("com.coloros.safecenter", "com.coloros.safecenter.permission.startup.fake.StartupScrollListActivity")))
        } else if (mLower.contains("vivo") || mLower.contains("iqoo") || bLower.contains("vivo") || bLower.contains("iqoo")) {
            intentsToTry.add(Intent().setComponent(android.content.ComponentName("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.PurviewTabActivity")))
            intentsToTry.add(Intent().setComponent(android.content.ComponentName("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity")))
            intentsToTry.add(Intent().setComponent(android.content.ComponentName("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity")))
            intentsToTry.add(Intent().setComponent(android.content.ComponentName("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.BgStartUpManager")))
        } else if (mLower.contains("samsung") || bLower.contains("samsung")) {
            intentsToTry.add(Intent().setComponent(android.content.ComponentName("com.samsung.android.lool", "com.samsung.android.sm.ui.battery.BatteryActivity")))
            intentsToTry.add(Intent().setComponent(android.content.ComponentName("com.samsung.android.sm", "com.samsung.android.sm.battery.ui.BatteryActivity")))
            intentsToTry.add(Intent().setComponent(android.content.ComponentName("com.samsung.android.sm", "com.samsung.android.sm.ui.battery.AppSleepListActivity")))
        } else if (mLower.contains("oneplus") || bLower.contains("oneplus")) {
            intentsToTry.add(Intent().setComponent(android.content.ComponentName("com.oneplus.security", "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity")))
            intentsToTry.add(Intent().setComponent(android.content.ComponentName("com.oneplus.battery", "com.oneplus.battery.BatteryStatusActivity")))
        } else if (mLower.contains("huawei") || mLower.contains("honor") || bLower.contains("huawei") || bLower.contains("honor")) {
            intentsToTry.add(Intent().setComponent(android.content.ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity")))
            intentsToTry.add(Intent().setComponent(android.content.ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.optimize.process.ProtectActivity")))
            intentsToTry.add(Intent().setComponent(android.content.ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.appcontrol.activity.StartupAppControlActivity")))
        } else if (mLower.contains("asus") || bLower.contains("asus")) {
            intentsToTry.add(Intent().setComponent(android.content.ComponentName("com.asus.mobilemanager", "com.asus.mobilemanager.autostart.AutoStartActivity")))
        }

        // Generic / Fallback intents
        val appDetailsIntent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:$packageName")
        }
        val batteryOptIntent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)

        intentsToTry.add(appDetailsIntent)
        intentsToTry.add(batteryOptIntent)

        for (intent in intentsToTry) {
            try {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                return true
            } catch (e: Exception) {
                // Try next candidate
            }
        }
        return false
    }

    private fun startNativeTrackerService() {
        val serviceIntent = Intent(this, StickyTrackerService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            ContextCompat.startForegroundService(this, serviceIntent)
        } else {
            startService(serviceIntent)
        }
    }

    private fun requestBatteryOptimizationExemption() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
            if (powerManager != null && !powerManager.isIgnoringBatteryOptimizations(packageName)) {
                try {
                    val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                        data = Uri.parse("package:$packageName")
                    }
                    startActivity(intent)
                } catch (e: Exception) {
                    val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                    startActivity(intent)
                }
            }
        }
    }

    private fun getDeviceContacts(): HashMap<String, String> {
        val contactsMap = HashMap<String, String>()
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CONTACTS) == PackageManager.PERMISSION_GRANTED) {
            var cursor: Cursor? = null
            try {
                cursor = contentResolver.query(
                    ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                    arrayOf(
                        ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                        ContactsContract.CommonDataKinds.Phone.NUMBER
                    ),
                    null,
                    null,
                    null
                )

                if (cursor != null) {
                    val nameIndex = cursor.getColumnIndex(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)
                    val numberIndex = cursor.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)

                    while (cursor.moveToNext()) {
                        val name = cursor.getString(nameIndex)
                        val number = cursor.getString(numberIndex)
                        if (!number.isNullOrEmpty() && !name.isNullOrEmpty()) {
                            // Strip spaces, dashes, etc.
                            val cleanNumber = number.replace(Regex("[^0-9+]"), "")
                            contactsMap[cleanNumber] = name

                            // Also index last 10 digits
                            val digitsOnly = number.replace(Regex("[^0-9]"), "")
                            if (digitsOnly.length >= 10) {
                                val last10 = digitsOnly.substring(digitsOnly.length - 10)
                                contactsMap[last10] = name
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                e.printStackTrace()
            } finally {
                cursor?.close()
            }
        }
        return contactsMap
    }
}
