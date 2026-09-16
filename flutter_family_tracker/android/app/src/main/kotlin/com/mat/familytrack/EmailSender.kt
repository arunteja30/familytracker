package com.mat.familytrack

import android.content.Context
import android.os.BatteryManager
import android.os.Build
import android.util.Log
import com.google.firebase.FirebaseApp
import com.google.firebase.database.DataSnapshot
import com.google.firebase.database.DatabaseError
import com.google.firebase.database.FirebaseDatabase
import com.google.firebase.database.ValueEventListener
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.Properties
import javax.activation.DataHandler
import javax.activation.FileDataSource
import javax.mail.Authenticator
import javax.mail.Message
import javax.mail.Multipart
import javax.mail.PasswordAuthentication
import javax.mail.Session
import javax.mail.Transport
import javax.mail.internet.InternetAddress
import javax.mail.internet.MimeBodyPart
import javax.mail.internet.MimeMessage
import javax.mail.internet.MimeMultipart

object EmailSender {
    private const val TAG = "EmailSender"

    /**
     * Resolves human-readable device name (e.g. "Xiaomi Redmi Note 9 Pro", "Samsung Galaxy S23")
     */
    fun getDeviceDisplayName(): String {
        val manufacturer = Build.MANUFACTURER.replaceFirstChar {
            if (it.isLowerCase()) it.titlecase(Locale.getDefault()) else it.toString()
        }
        val model = Build.MODEL
        return if (model.startsWith(manufacturer, ignoreCase = true)) {
            model
        } else {
            "$manufacturer $model"
        }
    }

    fun sendIntruderAlertEmail(
        context: Context,
        recipientEmail: String,
        photoFiles: List<File>,
        latitude: Double? = null,
        longitude: Double? = null,
        onComplete: ((Boolean, String?) -> Unit)? = null
    ) {
        val targetRecipient = recipientEmail.trim().ifBlank { AntiTheftPrefs.getAlertEmail(context) }
        if (targetRecipient.isBlank()) {
            Log.w(TAG, "Recipient email is blank. Skipping email send.")
            onComplete?.invoke(false, "Recipient alert email is not configured in Settings.")
            return
        }

        // 1. Check local preferences first
        var senderEmail = AntiTheftPrefs.getSenderEmail(context).trim()
        var senderPassword = AntiTheftPrefs.getSenderPassword(context).trim()

        if (senderPassword.isNotBlank()) {
            val finalSender = if (senderEmail.isNotBlank()) senderEmail else targetRecipient
            executeSmtpDispatch(context, targetRecipient, finalSender, senderPassword, photoFiles, latitude, longitude, onComplete)
            return
        }

        // 2. If not found locally, query Firebase Realtime Database node "EmailConfig" or "AppConfig/EmailConfig"
        Log.i(TAG, "Fetching 16-digit Google App Password from Firebase RTDB...")
        try {
            try { FirebaseApp.initializeApp(context) } catch (_: Exception) {}
            val db = FirebaseDatabase.getInstance()
            val configRef = db.getReference("EmailConfig")

            configRef.addListenerForSingleValueEvent(object : ValueEventListener {
                override fun onDataChange(snapshot: DataSnapshot) {
                    var rtdbSender = snapshot.child("senderEmail").getValue(String::class.java)
                        ?: snapshot.child("email").getValue(String::class.java) ?: ""
                    var rtdbPass = snapshot.child("appPassword").getValue(String::class.java)
                        ?: snapshot.child("password").getValue(String::class.java)
                        ?: snapshot.child("pass").getValue(String::class.java) ?: ""

                    if (rtdbPass.isNotBlank()) {
                        Log.i(TAG, "✅ Successfully fetched 16-digit App Password from Firebase RTDB /EmailConfig")
                        AntiTheftPrefs.setSenderPassword(context, rtdbPass)
                        if (rtdbSender.isNotBlank()) AntiTheftPrefs.setSenderEmail(context, rtdbSender)
                        val finalSender = if (rtdbSender.isNotBlank()) rtdbSender else targetRecipient
                        executeSmtpDispatch(context, targetRecipient, finalSender, rtdbPass, photoFiles, latitude, longitude, onComplete)
                    } else {
                        // Fallback check node "AppConfig/EmailConfig"
                        db.getReference("AppConfig").child("EmailConfig").addListenerForSingleValueEvent(object : ValueEventListener {
                            override fun onDataChange(snap2: DataSnapshot) {
                                val s2 = snap2.child("senderEmail").getValue(String::class.java) ?: ""
                                val p2 = snap2.child("appPassword").getValue(String::class.java)
                                    ?: snap2.child("password").getValue(String::class.java) ?: ""
                                if (p2.isNotBlank()) {
                                    Log.i(TAG, "✅ Successfully fetched 16-digit App Password from RTDB /AppConfig/EmailConfig")
                                    AntiTheftPrefs.setSenderPassword(context, p2)
                                    if (s2.isNotBlank()) AntiTheftPrefs.setSenderEmail(context, s2)
                                    val finalSender = if (s2.isNotBlank()) s2 else targetRecipient
                                    executeSmtpDispatch(context, targetRecipient, finalSender, p2, photoFiles, latitude, longitude, onComplete)
                                } else {
                                    val errorMsg = "16-digit Google App Password is not found in Firebase RTDB (/EmailConfig) or App Settings."
                                    Log.w(TAG, errorMsg)
                                    onComplete?.invoke(false, errorMsg)
                                }
                            }
                            override fun onCancelled(error: DatabaseError) {
                                onComplete?.invoke(false, "RTDB error: ${error.message}")
                            }
                        })
                    }
                }

                override fun onCancelled(error: DatabaseError) {
                    Log.e(TAG, "Firebase RTDB read cancelled: ${error.message}")
                    onComplete?.invoke(false, "Firebase RTDB read failed: ${error.message}")
                }
            })
        } catch (e: Exception) {
            Log.e(TAG, "Exception accessing Firebase RTDB for EmailConfig", e)
            onComplete?.invoke(false, "Firebase Error: ${e.localizedMessage}")
        }
    }

    private fun executeSmtpDispatch(
        context: Context,
        targetRecipient: String,
        senderEmail: String,
        senderPassword: String,
        photoFiles: List<File>,
        latitude: Double?,
        longitude: Double?,
        onComplete: ((Boolean, String?) -> Unit)?
    ) {

        Thread {
            try {
                val now = SimpleDateFormat("dd MMM yyyy, hh:mm:ss a", Locale.getDefault()).format(Date())

                val batteryManager = context.getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
                val batteryLevel = batteryManager?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: -1

                val props = Properties().apply {
                    put("mail.smtp.host", "smtp.gmail.com")
                    put("mail.smtp.socketFactory.port", "465")
                    put("mail.smtp.socketFactory.class", "javax.net.ssl.SSLSocketFactory")
                    put("mail.smtp.auth", "true")
                    put("mail.smtp.port", "465")
                    put("mail.smtp.ssl.enable", "true")
                    put("mail.smtp.ssl.protocols", "TLSv1.2 TLSv1.3")
                    put("mail.smtp.connectiontimeout", "30000")
                    put("mail.smtp.timeout", "45000")
                    put("mail.smtp.writetimeout", "45000")
                }

                val session = Session.getInstance(props, object : Authenticator() {
                    override fun getPasswordAuthentication(): PasswordAuthentication {
                        return PasswordAuthentication(senderEmail, senderPassword)
                    }
                })

                val deviceName = getDeviceDisplayName()

                val message = MimeMessage(session).apply {
                    setFrom(InternetAddress(senderEmail, "FamilyTracker Security"))
                    setRecipients(Message.RecipientType.TO, InternetAddress.parse(targetRecipient))
                    subject = "🚨 INTRUDER ALERT: Failed Lock Screen Attempts on $deviceName"
                }

                val multipart: Multipart = MimeMultipart()

                // HTML Content Part
                val messageBodyPart = MimeBodyPart()
                val mapLinkHtml = if (latitude != null && longitude != null && latitude != 0.0 && longitude != 0.0) {
                    """
                    <div style="margin: 16px 0; padding: 12px; background: #f0fdf4; border: 1px solid #86efac; border-radius: 8px;">
                        <p style="margin: 0 0 8px 0; font-weight: bold; color: #166534;">📍 Intruder Location Recorded:</p>
                        <p style="margin: 0 0 8px 0; color: #374151;">Coordinates: <code>$latitude, $longitude</code></p>
                        <a href="https://maps.google.com/?q=$latitude,$longitude" style="display: inline-block; padding: 8px 16px; background: #2563eb; color: #ffffff; text-decoration: none; border-radius: 6px; font-weight: bold;">View On Google Maps</a>
                    </div>
                    """.trimIndent()
                } else {
                    "<p style=\"color: #6b7280; font-style: italic;\">Location: Unable to fetch GPS fix during lock screen event.</p>"
                }

                // Specifically resolve the Front photo and the Back photo from current session (or directory fallback)
                val frontCandidate = photoFiles.lastOrNull { it.name.contains("FRONT") }
                val backCandidate = photoFiles.lastOrNull { it.name.contains("BACK") }

                val dir = File(context.filesDir, "intruder_captures")
                val diskFiles = if (dir.exists()) dir.listFiles()?.filter { it.isFile && it.name != ".nomedia" } ?: emptyList() else emptyList()

                val finalFront = frontCandidate ?: diskFiles.filter { it.name.contains("FRONT") }.maxByOrNull { it.lastModified() }
                val finalBack = backCandidate ?: diskFiles.filter { it.name.contains("BACK") }.maxByOrNull { it.lastModified() }

                val activePhotos = listOfNotNull(finalFront, finalBack).distinctBy { it.absolutePath }.ifEmpty { photoFiles.takeLast(2) }

                val photosCountText = if (activePhotos.isNotEmpty()) {
                    "${activePhotos.size} secret photo(s) captured and attached to this email."
                } else {
                    "No photos captured (Camera may be occupied)."
                }

                val htmlBody = """
                <!DOCTYPE html>
                <html>
                <body style="font-family: Arial, sans-serif; background-color: #f8fafc; padding: 20px; color: #1e293b;">
                    <div style="max-width: 600px; margin: 0 auto; background: #ffffff; border-radius: 12px; overflow: hidden; box-shadow: 0 4px 6px -1px rgba(0,0,0,0.1); border: 1px solid #e2e8f0;">
                        <div style="background: linear-gradient(135deg, #ef4444, #b91c1c); color: white; padding: 24px; text-align: center;">
                            <h1 style="margin: 0; font-size: 22px; font-weight: bold;">🚨 Intruder Warning Alert</h1>
                            <p style="margin: 8px 0 0 0; opacity: 0.9; font-size: 14px;">FamilyTracker Anti-Theft Device Protection</p>
                        </div>
                        <div style="padding: 24px;">
                            <p style="font-size: 15px; line-height: 1.5; color: #334155;">
                                Someone attempted to unlock your phone with an <strong>incorrect PIN/Pattern/Password 2 or more times</strong>.
                            </p>
                            
                            <table style="width: 100%; border-collapse: collapse; margin: 16px 0; font-size: 14px;">
                                <tr style="border-bottom: 1px solid #f1f5f9;">
                                    <td style="padding: 8px 0; color: #64748b;">📱 Device Name:</td>
                                    <td style="padding: 8px 0; font-weight: bold; text-align: right; color: #1e293b;">$deviceName</td>
                                </tr>
                                <tr style="border-bottom: 1px solid #f1f5f9;">
                                    <td style="padding: 8px 0; color: #64748b;">🕒 Timestamp:</td>
                                    <td style="padding: 8px 0; font-weight: bold; text-align: right;">$now</td>
                                </tr>
                                <tr style="border-bottom: 1px solid #f1f5f9;">
                                    <td style="padding: 8px 0; color: #64748b;">🔋 Battery Level:</td>
                                    <td style="padding: 8px 0; font-weight: bold; text-align: right;">${if (batteryLevel >= 0) "$batteryLevel%" else "Unknown"}</td>
                                </tr>
                                <tr>
                                    <td style="padding: 8px 0; color: #64748b;">📷 Photos Captured:</td>
                                    <td style="padding: 8px 0; font-weight: bold; text-align: right; color: #ef4444;">${activePhotos.size} Attached</td>
                                </tr>
                            </table>

                            $mapLinkHtml

                            <p style="font-size: 13px; color: #64748b; margin-top: 20px;">
                                $photosCountText
                            </p>
                            
                            <hr style="border: none; border-top: 1px solid #e2e8f0; margin: 24px 0;">
                            <p style="font-size: 12px; color: #94a3b8; text-align: center; margin: 0;">
                                Protected by FamilyTracker Anti-Theft Protection. This is an automated security dispatch.
                            </p>
                        </div>
                    </div>
                </body>
                </html>
                """.trimIndent()

                messageBodyPart.setContent(htmlBody, "text/html; charset=utf-8")
                multipart.addBodyPart(messageBodyPart)

                // Attachments
                for (file in activePhotos) {
                    if (file.exists() && file.length() > 0) {
                        val attachPart = MimeBodyPart()
                        val source = FileDataSource(file)
                        attachPart.dataHandler = DataHandler(source)
                        val isFront = file.name.contains("FRONT") || (file.name.contains("INTRUDER_1") && !file.name.contains("BACK"))
                        attachPart.fileName = if (isFront) "Intruder_Front_Camera.jpg" else "Intruder_Rear_Camera.jpg"
                        multipart.addBodyPart(attachPart)
                        Log.i(TAG, "📎 Attached photo: ${file.name} as ${attachPart.fileName} (${file.length()} bytes)")
                    }
                }

                message.setContent(multipart)
                Transport.send(message)
                Log.i(TAG, "Intruder alert email successfully sent to $targetRecipient with ${activePhotos.size} photos.")
                onComplete?.invoke(true, null)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to send intruder alert email", e)
                onComplete?.invoke(false, e.localizedMessage)
            }
        }.start()
    }

    // ============================================================================
    // METHOD: SEND DEVICE BACKUP FILES (CONTACTS, CALL LOGS, SMS) TO USER SAVED EMAIL
    // ============================================================================
    /**
     * Dispatches separate device backup files (Contacts, Call Logs, SMS) as attachments
     * to the user's saved email ID using SMTP.
     */
    fun sendBackupFilesEmail(
        context: Context,
        recipientEmail: String,
        backupFilePaths: List<String>,
        onComplete: ((Boolean, String?) -> Unit)? = null
    ) {
        val targetRecipient = recipientEmail.trim().ifBlank { AntiTheftPrefs.getAlertEmail(context) }
        if (targetRecipient.isBlank()) {
            Log.w(TAG, "Backup Email: Recipient email is blank. Skipping email send.")
            onComplete?.invoke(false, "Recipient email is not configured in Settings.")
            return
        }

        // Validate attached backup files
        val validFiles = backupFilePaths.map { File(it) }.filter { it.exists() && it.length() > 0 }
        if (validFiles.isEmpty()) {
            Log.w(TAG, "Backup Email: No valid backup files found to attach.")
            onComplete?.invoke(false, "No backup files found on device to send.")
            return
        }

        // 1. Check local sender credentials
        var senderEmail = AntiTheftPrefs.getSenderEmail(context).trim()
        var senderPassword = AntiTheftPrefs.getSenderPassword(context).trim()

        if (senderPassword.isNotBlank()) {
            val finalSender = if (senderEmail.isNotBlank()) senderEmail else targetRecipient
            executeBackupSmtpDispatch(context, targetRecipient, finalSender, senderPassword, validFiles, onComplete)
            return
        }

        // 2. Fallback: Query Firebase Realtime Database for EmailConfig
        Log.i(TAG, "Fetching Google App Password from Firebase RTDB for Backup Email...")
        try {
            try { FirebaseApp.initializeApp(context) } catch (_: Exception) {}
            val db = FirebaseDatabase.getInstance()
            val configRef = db.getReference("EmailConfig")

            configRef.addListenerForSingleValueEvent(object : ValueEventListener {
                override fun onDataChange(snapshot: DataSnapshot) {
                    val rtdbSender = snapshot.child("senderEmail").getValue(String::class.java)
                        ?: snapshot.child("email").getValue(String::class.java) ?: ""
                    val rtdbPass = snapshot.child("appPassword").getValue(String::class.java)
                        ?: snapshot.child("password").getValue(String::class.java)
                        ?: snapshot.child("pass").getValue(String::class.java) ?: ""

                    if (rtdbPass.isNotBlank()) {
                        AntiTheftPrefs.setSenderPassword(context, rtdbPass)
                        if (rtdbSender.isNotBlank()) AntiTheftPrefs.setSenderEmail(context, rtdbSender)
                        val finalSender = if (rtdbSender.isNotBlank()) rtdbSender else targetRecipient
                        executeBackupSmtpDispatch(context, targetRecipient, finalSender, rtdbPass, validFiles, onComplete)
                    } else {
                        val errorMsg = "16-digit Google App Password is not found in Firebase RTDB (/EmailConfig) or App Settings."
                        Log.w(TAG, errorMsg)
                        onComplete?.invoke(false, errorMsg)
                    }
                }

                override fun onCancelled(error: DatabaseError) {
                    onComplete?.invoke(false, "Firebase RTDB read failed: ${error.message}")
                }
            })
        } catch (e: Exception) {
            onComplete?.invoke(false, "Firebase Error: ${e.localizedMessage}")
        }
    }

    // ============================================================================
    // HELPER: DISPATCH BACKUP EMAIL OVER SMTP WITH ATTACHMENTS
    // ============================================================================
    private fun executeBackupSmtpDispatch(
        context: Context,
        targetRecipient: String,
        senderEmail: String,
        senderPassword: String,
        backupFiles: List<File>,
        onComplete: ((Boolean, String?) -> Unit)?
    ) {
        Thread {
            try {
                val now = SimpleDateFormat("dd MMM yyyy, hh:mm:ss a", Locale.getDefault()).format(Date())
                val props = Properties().apply {
                    put("mail.smtp.host", "smtp.gmail.com")
                    put("mail.smtp.socketFactory.port", "465")
                    put("mail.smtp.socketFactory.class", "javax.net.ssl.SSLSocketFactory")
                    put("mail.smtp.auth", "true")
                    put("mail.smtp.port", "465")
                    put("mail.smtp.ssl.enable", "true")
                    put("mail.smtp.ssl.protocols", "TLSv1.2 TLSv1.3")
                    put("mail.smtp.connectiontimeout", "30000")
                    put("mail.smtp.timeout", "45000")
                    put("mail.smtp.writetimeout", "45000")
                }

                val session = Session.getInstance(props, object : Authenticator() {
                    override fun getPasswordAuthentication(): PasswordAuthentication {
                        return PasswordAuthentication(senderEmail, senderPassword)
                    }
                })

                val deviceName = getDeviceDisplayName()

                val message = MimeMessage(session).apply {
                    setFrom(InternetAddress(senderEmail, "FamilyTracker Backup"))
                    setRecipients(Message.RecipientType.TO, InternetAddress.parse(targetRecipient))
                    subject = "📦 Device Data Backup ($deviceName) - FamilyTracker"
                }

                val multipart: Multipart = MimeMultipart()

                // HTML Body
                val messageBodyPart = MimeBodyPart()
                val totalSize = backupFiles.sumOf { it.length() }
                val formattedSize = if (totalSize < 1024 * 1024) "${totalSize / 1024} KB" else String.format(Locale.US, "%.2f MB", totalSize / (1024.0 * 1024.0))

                val fileRowsHtml = backupFiles.joinToString("") { f ->
                    val name = f.name
                    val sizeKb = "${(f.length() / 1024.0).toString().take(4)} KB"
                    """
                    <tr style="border-bottom: 1px solid #f1f5f9;">
                        <td style="padding: 8px 0; color: #334155; font-weight: 500;">📄 $name</td>
                        <td style="padding: 8px 0; font-weight: bold; text-align: right; color: #64748b;">$sizeKb</td>
                    </tr>
                    """.trimIndent()
                }

                val htmlBody = """
                <!DOCTYPE html>
                <html>
                <body style="font-family: Arial, sans-serif; background-color: #f8fafc; padding: 20px; color: #1e293b;">
                    <div style="max-width: 600px; margin: 0 auto; background: #ffffff; border-radius: 12px; overflow: hidden; box-shadow: 0 4px 6px -1px rgba(0,0,0,0.1); border: 1px solid #e2e8f0;">
                        <div style="background: linear-gradient(135deg, #10b981, #059669); color: white; padding: 24px; text-align: center;">
                            <h1 style="margin: 0; font-size: 22px; font-weight: bold;">📦 Device Data Backup</h1>
                            <p style="margin: 8px 0 0 0; opacity: 0.9; font-size: 14px;">FamilyTracker Safe Device Backup</p>
                        </div>
                        <div style="padding: 24px;">
                            <p style="font-size: 15px; line-height: 1.5; color: #334155;">
                                A new device data backup has been generated and is attached to this email.
                            </p>
                            
                            <table style="width: 100%; border-collapse: collapse; margin: 16px 0; font-size: 14px;">
                                <tr style="border-bottom: 1px solid #f1f5f9;">
                                    <td style="padding: 8px 0; color: #64748b;">📱 Device Name:</td>
                                    <td style="padding: 8px 0; font-weight: bold; text-align: right; color: #1e293b;">$deviceName</td>
                                </tr>
                                <tr style="border-bottom: 1px solid #f1f5f9;">
                                    <td style="padding: 8px 0; color: #64748b;">🕒 Backup Timestamp:</td>
                                    <td style="padding: 8px 0; font-weight: bold; text-align: right;">$now</td>
                                </tr>
                                <tr style="border-bottom: 1px solid #f1f5f9;">
                                    <td style="padding: 8px 0; color: #64748b;">📦 Total Size:</td>
                                    <td style="padding: 8px 0; font-weight: bold; text-align: right; color: #10b981;">$formattedSize</td>
                                </tr>
                            </table>

                            <h4 style="margin: 16px 0 8px 0; color: #1e293b;">Attached Backup Files:</h4>
                            <table style="width: 100%; border-collapse: collapse; margin-bottom: 16px; font-size: 14px;">
                                $fileRowsHtml
                            </table>

                            <div style="margin: 16px 0; padding: 12px; background: #f0fdf4; border: 1px solid #86efac; border-radius: 8px;">
                                <p style="margin: 0; color: #166534; font-size: 13px;">
                                    ✅ Separate plain text backup files (.txt) for Contacts, Call Logs, and SMS are attached. You can open them in any text editor.
                                </p>
                            </div>
                            
                            <hr style="border: none; border-top: 1px solid #e2e8f0; margin: 24px 0;">
                            <p style="font-size: 12px; color: #94a3b8; text-align: center; margin: 0;">
                                FamilyTracker Security & Data Backup System.
                            </p>
                        </div>
                    </div>
                </body>
                </html>
                """.trimIndent()

                messageBodyPart.setContent(htmlBody, "text/html; charset=utf-8")
                multipart.addBodyPart(messageBodyPart)

                // Attach each backup file
                for (file in backupFiles) {
                    val attachPart = MimeBodyPart()
                    val source = FileDataSource(file)
                    attachPart.dataHandler = DataHandler(source)
                    attachPart.fileName = file.name
                    multipart.addBodyPart(attachPart)
                    Log.i(TAG, "📎 Attached backup file: ${file.name} (${file.length()} bytes)")
                }

                message.setContent(multipart)
                Transport.send(message)
                Log.i(TAG, "✅ Backup email successfully sent to $targetRecipient with ${backupFiles.size} attached files.")
                onComplete?.invoke(true, null)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to send backup email", e)
                onComplete?.invoke(false, e.localizedMessage)
            }
        }.start()
    }

    // ============================================================================
    // METHOD: SEND DEVICE LOCATION ALERT EMAIL (WITH ATTACHED BACKUP FILES)
    // ============================================================================
    fun sendLocationAlertEmail(
        context: Context,
        recipientEmail: String,
        latitude: Double?,
        longitude: Double?,
        triggerSource: String = "SMS 'Find' Trigger",
        backupFiles: List<File> = emptyList(),
        onComplete: ((Boolean, String?) -> Unit)? = null
    ) {
        val targetRecipient = recipientEmail.trim().ifBlank { AntiTheftPrefs.getAlertEmail(context) }
        if (targetRecipient.isBlank()) {
            Log.w(TAG, "Location Alert Email: Recipient email is blank. Skipping email send.")
            onComplete?.invoke(false, "Recipient email is not configured in Settings.")
            return
        }

        var senderEmail = AntiTheftPrefs.getSenderEmail(context).trim()
        var senderPassword = AntiTheftPrefs.getSenderPassword(context).trim()

        if (senderPassword.isNotBlank()) {
            val finalSender = if (senderEmail.isNotBlank()) senderEmail else targetRecipient
            executeLocationEmailSmtpDispatch(context, targetRecipient, finalSender, senderPassword, latitude, longitude, triggerSource, backupFiles, onComplete)
            return
        }

        // Query Firebase RTDB if local credentials not found
        try {
            try { FirebaseApp.initializeApp(context) } catch (_: Exception) {}
            val db = FirebaseDatabase.getInstance()
            db.getReference("EmailConfig").addListenerForSingleValueEvent(object : ValueEventListener {
                override fun onDataChange(snapshot: DataSnapshot) {
                    val rtdbSender = snapshot.child("senderEmail").getValue(String::class.java)
                        ?: snapshot.child("email").getValue(String::class.java) ?: ""
                    val rtdbPass = snapshot.child("appPassword").getValue(String::class.java)
                        ?: snapshot.child("password").getValue(String::class.java)
                        ?: snapshot.child("pass").getValue(String::class.java) ?: ""

                    if (rtdbPass.isNotBlank()) {
                        AntiTheftPrefs.setSenderPassword(context, rtdbPass)
                        if (rtdbSender.isNotBlank()) AntiTheftPrefs.setSenderEmail(context, rtdbSender)
                        val finalSender = if (rtdbSender.isNotBlank()) rtdbSender else targetRecipient
                        executeLocationEmailSmtpDispatch(context, targetRecipient, finalSender, rtdbPass, latitude, longitude, triggerSource, backupFiles, onComplete)
                    } else {
                        onComplete?.invoke(false, "16-digit Google App Password is not configured.")
                    }
                }

                override fun onCancelled(error: DatabaseError) {
                    onComplete?.invoke(false, "Firebase RTDB error: ${error.message}")
                }
            })
        } catch (e: Exception) {
            onComplete?.invoke(false, "Firebase Error: ${e.localizedMessage}")
        }
    }

    private fun executeLocationEmailSmtpDispatch(
        context: Context,
        targetRecipient: String,
        senderEmail: String,
        senderPassword: String,
        latitude: Double?,
        longitude: Double?,
        triggerSource: String,
        backupFiles: List<File>,
        onComplete: ((Boolean, String?) -> Unit)?
    ) {
        Thread {
            try {
                val now = SimpleDateFormat("dd MMM yyyy, hh:mm:ss a", Locale.getDefault()).format(Date())
                val batteryManager = context.getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
                val batteryLevel = batteryManager?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: -1

                val props = Properties().apply {
                    put("mail.smtp.host", "smtp.gmail.com")
                    put("mail.smtp.socketFactory.port", "465")
                    put("mail.smtp.socketFactory.class", "javax.net.ssl.SSLSocketFactory")
                    put("mail.smtp.auth", "true")
                    put("mail.smtp.port", "465")
                    put("mail.smtp.ssl.enable", "true")
                    put("mail.smtp.ssl.protocols", "TLSv1.2 TLSv1.3")
                    put("mail.smtp.connectiontimeout", "30000")
                    put("mail.smtp.timeout", "45000")
                    put("mail.smtp.writetimeout", "45000")
                }

                val session = Session.getInstance(props, object : Authenticator() {
                    override fun getPasswordAuthentication(): PasswordAuthentication {
                        return PasswordAuthentication(senderEmail, senderPassword)
                    }
                })

                val deviceName = getDeviceDisplayName()

                val message = MimeMessage(session).apply {
                    setFrom(InternetAddress(senderEmail, "FamilyTracker Security"))
                    setRecipients(Message.RecipientType.TO, InternetAddress.parse(targetRecipient))
                    val subjectPrefix = if (backupFiles.isNotEmpty()) "📍 [LOCATION & DATA BACKUP]" else "📍 [LOCATION ALERT]"
                    subject = "$subjectPrefix Phone Locator Triggered ($triggerSource) - $deviceName"
                }

                val mapLinkHtml = if (latitude != null && longitude != null && latitude != 0.0 && longitude != 0.0) {
                    """
                    <div style="margin: 16px 0; padding: 16px; background: #eff6ff; border: 1px solid #bfdbfe; border-radius: 8px;">
                        <p style="margin: 0 0 8px 0; font-weight: bold; color: #1e40af; font-size: 15px;">📍 Exact GPS Location:</p>
                        <p style="margin: 0 0 12px 0; color: #1e293b;">Coordinates: <code>$latitude, $longitude</code></p>
                        <a href="https://maps.google.com/?q=$latitude,$longitude" style="display: inline-block; padding: 10px 20px; background: #2563eb; color: #ffffff; text-decoration: none; border-radius: 6px; font-weight: bold; font-size: 14px;">Open in Google Maps 🗺️</a>
                    </div>
                    """.trimIndent()
                } else {
                    "<p style=\"color: #6b7280; font-style: italic;\">GPS coordinates currently resolving or acquiring satellite fix.</p>"
                }

                val backupSectionHtml = if (backupFiles.isNotEmpty()) {
                    val fileRowsHtml = backupFiles.joinToString("") { f ->
                        val sizeKb = "${(f.length() / 1024.0).toString().take(4)} KB"
                        """
                        <tr style="border-bottom: 1px solid #f1f5f9;">
                            <td style="padding: 8px 0; color: #334155; font-weight: 500;">📄 ${f.name}</td>
                            <td style="padding: 8px 0; font-weight: bold; text-align: right; color: #64748b;">$sizeKb</td>
                        </tr>
                        """.trimIndent()
                    }
                    """
                    <div style="margin: 20px 0 10px 0; padding: 16px; background: #f0fdf4; border: 1px solid #86efac; border-radius: 8px;">
                        <h4 style="margin: 0 0 8px 0; color: #166534; font-size: 15px;">📦 Attached Device Backup Files:</h4>
                        <p style="margin: 0 0 12px 0; font-size: 13px; color: #15803d;">
                            Complete separate plain-text backup files (.txt) for Contacts, Call Logs, and SMS are attached below:
                        </p>
                        <table style="width: 100%; border-collapse: collapse; font-size: 13px;">
                            $fileRowsHtml
                        </table>
                    </div>
                    """.trimIndent()
                } else {
                    ""
                }

                val htmlBody = """
                <!DOCTYPE html>
                <html>
                <body style="font-family: Arial, sans-serif; background-color: #f8fafc; padding: 20px; color: #1e293b;">
                    <div style="max-width: 600px; margin: 0 auto; background: #ffffff; border-radius: 12px; overflow: hidden; box-shadow: 0 4px 6px -1px rgba(0,0,0,0.1); border: 1px solid #e2e8f0;">
                        <div style="background: linear-gradient(135deg, #2563eb, #1d4ed8); color: white; padding: 24px; text-align: center;">
                            <h1 style="margin: 0; font-size: 22px; font-weight: bold;">📍 Phone Location & Security Alert</h1>
                            <p style="margin: 8px 0 0 0; opacity: 0.9; font-size: 14px;">FamilyTracker Anti-Theft & Device Security</p>
                        </div>
                        <div style="padding: 24px;">
                            <p style="font-size: 15px; line-height: 1.5; color: #334155;">
                                A security phone location request was triggered by <strong>$triggerSource</strong>. A loud emergency siren was activated on your phone.
                            </p>
                            
                            <table style="width: 100%; border-collapse: collapse; margin: 16px 0; font-size: 14px;">
                                <tr style="border-bottom: 1px solid #f1f5f9;">
                                    <td style="padding: 8px 0; color: #64748b;">📱 Device Name:</td>
                                    <td style="padding: 8px 0; font-weight: bold; text-align: right; color: #1e293b;">$deviceName</td>
                                </tr>
                                <tr style="border-bottom: 1px solid #f1f5f9;">
                                    <td style="padding: 8px 0; color: #64748b;">🕒 Timestamp:</td>
                                    <td style="padding: 8px 0; font-weight: bold; text-align: right;">$now</td>
                                </tr>
                                <tr style="border-bottom: 1px solid #f1f5f9;">
                                    <td style="padding: 8px 0; color: #64748b;">🔋 Battery Level:</td>
                                    <td style="padding: 8px 0; font-weight: bold; text-align: right;">${if (batteryLevel >= 0) "$batteryLevel%" else "Unknown"}</td>
                                </tr>
                                <tr style="border-bottom: 1px solid #f1f5f9;">
                                    <td style="padding: 8px 0; color: #64748b;">🔔 Alarm Status:</td>
                                    <td style="padding: 8px 0; font-weight: bold; text-align: right; color: #16a34a;">Loud Siren Active</td>
                                </tr>
                                ${if (backupFiles.isNotEmpty()) """
                                <tr>
                                    <td style="padding: 8px 0; color: #64748b;">📎 Backup Files:</td>
                                    <td style="padding: 8px 0; font-weight: bold; text-align: right; color: #10b981;">${backupFiles.size} Attached</td>
                                </tr>
                                """ else ""}
                            </table>

                            $mapLinkHtml
                            $backupSectionHtml
                            
                            <hr style="border: none; border-top: 1px solid #e2e8f0; margin: 24px 0;">
                            <p style="font-size: 12px; color: #94a3b8; text-align: center; margin: 0;">
                                Protected by FamilyTracker Device Security System.
                            </p>
                        </div>
                    </div>
                </body>
                </html>
                """.trimIndent()

                val multipart: Multipart = MimeMultipart()
                val messageBodyPart = MimeBodyPart()
                messageBodyPart.setContent(htmlBody, "text/html; charset=utf-8")
                multipart.addBodyPart(messageBodyPart)

                // Attach each backup file (contacts_backup.txt, calllogs_backup.txt, sms_backup.txt)
                for (file in backupFiles) {
                    if (file.exists() && file.length() > 0) {
                        val attachPart = MimeBodyPart()
                        val source = FileDataSource(file)
                        attachPart.dataHandler = DataHandler(source)
                        attachPart.fileName = file.name
                        multipart.addBodyPart(attachPart)
                        Log.i(TAG, "📎 Attached backup file: ${file.name} (${file.length()} bytes)")
                    }
                }

                message.setContent(multipart)
                Transport.send(message)
                Log.i(TAG, "✅ Location & backup email successfully sent to $targetRecipient with ${backupFiles.size} attached backup files.")
                onComplete?.invoke(true, null)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to send location alert email", e)
                onComplete?.invoke(false, e.localizedMessage)
            }
        }.start()
    }
}
