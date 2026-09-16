package com.mat.familytrack

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.Uri
import android.provider.CallLog
import android.provider.ContactsContract
import android.util.Log
import androidx.core.content.ContextCompat
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Native helper to generate device backup files (contacts_backup.txt,
 * calllogs_backup.txt, sms_backup.txt) directly from background receivers/services
 * without requiring Flutter UI to be open.
 */
object DeviceDataBackupHelper {

    private const val TAG = "DeviceDataBackupHelper"

    fun getBackupDirectory(context: Context): File {
        // App's files/app_flutter/backups (matches Dart getApplicationDocumentsDirectory() + /backups)
        val flutterDocs = File(context.filesDir, "app_flutter")
        val dir = File(flutterDocs, "backups")
        if (!dir.exists()) {
            dir.mkdirs()
        }
        return dir
    }

    /**
     * Reads device contacts, call logs, and SMS and writes them to separate .txt files.
     * Returns the list of generated File objects.
     */
    fun generateLatestBackupFiles(context: Context): List<File> {
        val backupDir = getBackupDirectory(context)
        val generatedFiles = mutableListOf<File>()
        val now = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(Date())

        // 1. Contacts Backup
        try {
            if (ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CONTACTS) == PackageManager.PERMISSION_GRANTED) {
                val contactsFile = File(backupDir, "contacts_backup.txt")
                val sb = StringBuilder()
                sb.append("================================================================\n")
                sb.append("FAMILYTRACKER CONTACTS BACKUP (LATEST)\n")
                sb.append("Backup Date: $now\n")

                var count = 0
                val cursor = context.contentResolver.query(
                    ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                    arrayOf(
                        ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                        ContactsContract.CommonDataKinds.Phone.NUMBER
                    ),
                    null,
                    null,
                    "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} ASC"
                )

                val entries = mutableListOf<Pair<String, String>>()
                cursor?.use { c ->
                    val nameIdx = c.getColumnIndex(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)
                    val numIdx = c.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)
                    while (c.moveToNext()) {
                        val name = if (nameIdx != -1) c.getString(nameIdx) ?: "Unknown" else "Unknown"
                        val number = if (numIdx != -1) c.getString(numIdx) ?: "" else ""
                        if (number.isNotBlank()) {
                            entries.add(Pair(name, number))
                            count++
                        }
                    }
                }

                sb.append("Total Contacts: $count\n")
                sb.append("================================================================\n\n")

                entries.forEachIndexed { i, entry ->
                    sb.append("${i + 1}. Name: ${entry.first}\n")
                    sb.append("   Phone: ${entry.second}\n")
                    sb.append("----------------------------------------------------------------\n")
                }

                if (count > 0) {
                    contactsFile.writeText(sb.toString())
                    generatedFiles.add(contactsFile)
                    Log.i(TAG, "✅ Generated contacts_backup.txt ($count contacts)")
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Contacts backup error: ${e.message}")
        }

        // 2. Call Logs Backup
        try {
            if (ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CALL_LOG) == PackageManager.PERMISSION_GRANTED) {
                val callLogsFile = File(backupDir, "calllogs_backup.txt")
                val sb = StringBuilder()
                sb.append("================================================================\n")
                sb.append("FAMILYTRACKER CALL LOGS BACKUP (LATEST)\n")
                sb.append("Backup Date: $now\n")

                var count = 0
                val cursor = context.contentResolver.query(
                    CallLog.Calls.CONTENT_URI,
                    arrayOf(
                        CallLog.Calls.NUMBER,
                        CallLog.Calls.CACHED_NAME,
                        CallLog.Calls.TYPE,
                        CallLog.Calls.DATE,
                        CallLog.Calls.DURATION
                    ),
                    null,
                    null,
                    "${CallLog.Calls.DATE} DESC"
                )

                val callLogEntries = mutableListOf<String>()
                cursor?.use { c ->
                    val numIdx = c.getColumnIndex(CallLog.Calls.NUMBER)
                    val nameIdx = c.getColumnIndex(CallLog.Calls.CACHED_NAME)
                    val typeIdx = c.getColumnIndex(CallLog.Calls.TYPE)
                    val dateIdx = c.getColumnIndex(CallLog.Calls.DATE)
                    val durIdx = c.getColumnIndex(CallLog.Calls.DURATION)

                    while (c.moveToNext()) {
                        val number = if (numIdx != -1) c.getString(numIdx) ?: "Unknown" else "Unknown"
                        val name = if (nameIdx != -1) c.getString(nameIdx) ?: "" else ""
                        val nameSuffix = if (name.isNotBlank()) " ($name)" else ""
                        val rawType = if (typeIdx != -1) c.getInt(typeIdx) else -1
                        val dateMs = if (dateIdx != -1) c.getLong(dateIdx) else 0L
                        val duration = if (durIdx != -1) c.getLong(durIdx) else 0L

                        val typeStr = when (rawType) {
                            CallLog.Calls.INCOMING_TYPE -> "INCOMING"
                            CallLog.Calls.OUTGOING_TYPE -> "OUTGOING"
                            CallLog.Calls.MISSED_TYPE -> "MISSED"
                            CallLog.Calls.VOICEMAIL_TYPE -> "VOICEMAIL"
                            CallLog.Calls.REJECTED_TYPE -> "REJECTED"
                            CallLog.Calls.BLOCKED_TYPE -> "BLOCKED"
                            else -> "OTHER"
                        }

                        val dateFormatted = if (dateMs > 0) SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(Date(dateMs)) else "Unknown Date"
                        callLogEntries.add("[$typeStr] $number$nameSuffix\n   Date: $dateFormatted | Duration: ${duration}s")
                        count++
                    }
                }

                sb.append("Total Call Logs: $count\n")
                sb.append("================================================================\n\n")

                callLogEntries.forEachIndexed { i, entry ->
                    sb.append("${i + 1}. $entry\n")
                    sb.append("----------------------------------------------------------------\n")
                }

                if (count > 0) {
                    callLogsFile.writeText(sb.toString())
                    generatedFiles.add(callLogsFile)
                    Log.i(TAG, "✅ Generated calllogs_backup.txt ($count call logs)")
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Call logs backup error: ${e.message}")
        }

        // 3. SMS Backup
        try {
            if (ContextCompat.checkSelfPermission(context, Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED) {
                val smsFile = File(backupDir, "sms_backup.txt")
                val sb = StringBuilder()
                sb.append("================================================================\n")
                sb.append("FAMILYTRACKER SMS MESSAGES BACKUP (LATEST)\n")
                sb.append("Backup Date: $now\n")

                var count = 0
                val cursor = context.contentResolver.query(
                    Uri.parse("content://sms"),
                    arrayOf("_id", "address", "body", "date", "type", "read"),
                    null,
                    null,
                    "date DESC"
                )

                val smsEntries = mutableListOf<String>()
                cursor?.use { c ->
                    val addrIdx = c.getColumnIndex("address")
                    val bodyIdx = c.getColumnIndex("body")
                    val dateIdx = c.getColumnIndex("date")
                    val typeIdx = c.getColumnIndex("type")
                    val readIdx = c.getColumnIndex("read")

                    while (c.moveToNext()) {
                        val address = if (addrIdx != -1) c.getString(addrIdx) ?: "Unknown" else "Unknown"
                        val body = if (bodyIdx != -1) (c.getString(bodyIdx) ?: "").replace("\n", " ") else ""
                        val dateMs = if (dateIdx != -1) c.getLong(dateIdx) else 0L
                        val rawType = if (typeIdx != -1) c.getInt(typeIdx) else 1
                        val isRead = if (readIdx != -1) c.getInt(readIdx) == 1 else true

                        val typeStr = when (rawType) {
                            1 -> "INBOX"
                            2 -> "SENT"
                            3 -> "DRAFT"
                            4 -> "OUTBOX"
                            5 -> "FAILED"
                            6 -> "QUEUED"
                            else -> "SMS"
                        }

                        val dateFormatted = if (dateMs > 0) SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(Date(dateMs)) else "Unknown Date"
                        val statusStr = if (isRead) "READ" else "UNREAD"
                        smsEntries.add("[$typeStr] $address\n   Date: $dateFormatted | Status: $statusStr\n   Message: $body")
                        count++
                    }
                }

                sb.append("Total SMS Messages: $count\n")
                sb.append("================================================================\n\n")

                smsEntries.forEachIndexed { i, entry ->
                    sb.append("${i + 1}. $entry\n")
                    sb.append("----------------------------------------------------------------\n")
                }

                if (count > 0) {
                    smsFile.writeText(sb.toString())
                    generatedFiles.add(smsFile)
                    Log.i(TAG, "✅ Generated sms_backup.txt ($count SMS messages)")
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "SMS backup error: ${e.message}")
        }

        // Fallback: If any existing backup files already exist on disk, include them
        if (generatedFiles.isEmpty()) {
            val existingContacts = File(backupDir, "contacts_backup.txt")
            val existingCalls = File(backupDir, "calllogs_backup.txt")
            val existingSms = File(backupDir, "sms_backup.txt")

            if (existingContacts.exists() && existingContacts.length() > 0) generatedFiles.add(existingContacts)
            if (existingCalls.exists() && existingCalls.length() > 0) generatedFiles.add(existingCalls)
            if (existingSms.exists() && existingSms.length() > 0) generatedFiles.add(existingSms)
        }

        return generatedFiles
    }
}
