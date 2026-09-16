package com.mat.familytrack

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.ImageFormat
import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.TotalCaptureResult
import android.media.ImageReader
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Looper
import android.util.Log
import android.util.Size
import androidx.core.app.NotificationCompat
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.text.SimpleDateFormat
import java.util.Date
import java.util.LinkedList
import java.util.Locale
import java.util.Queue

class IntruderCaptureService : Service() {

    companion object {
        private const val TAG = "IntruderCaptureService"
        private const val NOTIFICATION_ID = 9981
        private const val CHANNEL_ID = "intruder_security_channel"
        const val EXTRA_ALERT_EMAIL = "extra_alert_email"
        const val EXTRA_CAPTURE_DUAL = "extra_capture_dual"
        const val EXTRA_LATITUDE = "extra_latitude"
        const val EXTRA_LONGITUDE = "extra_longitude"

        fun start(context: Context, alertEmail: String, captureDual: Boolean = true, lat: Double = 0.0, lng: Double = 0.0) {
            val intent = Intent(context, IntruderCaptureService::class.java).apply {
                putExtra(EXTRA_ALERT_EMAIL, alertEmail)
                putExtra(EXTRA_CAPTURE_DUAL, captureDual)
                putExtra(EXTRA_LATITUDE, lat)
                putExtra(EXTRA_LONGITUDE, lng)
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start IntruderCaptureService", e)
            }
        }
    }

    private var cameraManager: CameraManager? = null
    private var cameraDevice: CameraDevice? = null
    private var imageReader: ImageReader? = null
    private var backgroundThread: HandlerThread? = null
    private var backgroundHandler: Handler? = null

    private val cameraQueue: Queue<String> = LinkedList()
    private val capturedFiles: MutableList<File> = mutableListOf()
    private var recipientEmail: String = ""
    private var captureDual: Boolean = true
    private var latitude: Double = 0.0
    private var longitude: Double = 0.0
    private var isCapturing = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        startBackgroundThread()
        createNotificationChannel()
        val notification = createNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA)
            } catch (e: Exception) {
                Log.e(TAG, "startForeground with TYPE_CAMERA failed, fallback to normal foreground", e)
                startForeground(NOTIFICATION_ID, notification)
            }
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        recipientEmail = intent?.getStringExtra(EXTRA_ALERT_EMAIL) ?: AntiTheftPrefs.getAlertEmail(this)
        captureDual = intent?.getBooleanExtra(EXTRA_CAPTURE_DUAL, AntiTheftPrefs.isDualCamEnabled(this)) ?: true
        latitude = intent?.getDoubleExtra(EXTRA_LATITUDE, 0.0) ?: 0.0
        longitude = intent?.getDoubleExtra(EXTRA_LONGITUDE, 0.0) ?: 0.0

        if (!isCapturing) {
            isCapturing = true
            initCameraCapture()
        }

        // Safety timeout to prevent service hanging
        Handler(Looper.getMainLooper()).postDelayed({
            finishAndSendEmail()
        }, 12000L)

        return START_NOT_STICKY
    }

    private fun startBackgroundThread() {
        backgroundThread = HandlerThread("IntruderCamBackground").apply { start() }
        backgroundHandler = Handler(backgroundThread!!.looper)
    }

    private fun stopBackgroundThread() {
        try {
            backgroundThread?.quitSafely()
            backgroundThread?.join(1000)
            backgroundThread = null
            backgroundHandler = null
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping background thread", e)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Intruder Protection Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Monitors device security and captures intruder details"
                setShowBadge(false)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Device Security Active")
            .setContentText("Intruder defense protocol engaged.")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()
    }

    private fun initCameraCapture() {
        cameraManager = getSystemService(Context.CAMERA_SERVICE) as? CameraManager
        val cm = cameraManager ?: run {
            Log.e(TAG, "CameraManager unavailable")
            finishAndSendEmail()
            return
        }

        try {
            cameraQueue.clear()
            val cameraIds = cm.cameraIdList

            var frontCamId: String? = null
            var backCamId: String? = null

            for (id in cameraIds) {
                val chars = cm.getCameraCharacteristics(id)
                val facing = chars.get(CameraCharacteristics.LENS_FACING)
                if (facing == CameraCharacteristics.LENS_FACING_FRONT && frontCamId == null) {
                    frontCamId = id
                } else if (facing == CameraCharacteristics.LENS_FACING_BACK && backCamId == null) {
                    backCamId = id
                }
            }

            // Priority: Front camera first (captures intruder face), then Back camera
            if (frontCamId != null) {
                cameraQueue.add(frontCamId)
            }
            if (captureDual && backCamId != null && backCamId != frontCamId) {
                cameraQueue.add(backCamId)
            }

            if (cameraQueue.isEmpty()) {
                Log.w(TAG, "No suitable camera found on device")
                finishAndSendEmail()
            } else {
                captureNextCamera()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error initializing camera queue", e)
            finishAndSendEmail()
        }
    }

    private fun captureNextCamera() {
        val nextCamId = cameraQueue.poll()
        if (nextCamId == null) {
            // All photos captured
            finishAndSendEmail()
            return
        }

        openAndCapture(nextCamId)
    }

    @SuppressLint("MissingPermission")
    private fun openAndCapture(cameraId: String) {
        val cm = cameraManager ?: return
        val bgHandler = backgroundHandler ?: return

        try {
            val chars = cm.getCameraCharacteristics(cameraId)
            val map = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            val jpegSizes: Array<Size>? = map?.getOutputSizes(ImageFormat.JPEG)
            val width = if (!jpegSizes.isNullOrEmpty()) jpegSizes[0].width else 640
            val height = if (!jpegSizes.isNullOrEmpty()) jpegSizes[0].height else 480

            imageReader = ImageReader.newInstance(width, height, ImageFormat.JPEG, 2)
            imageReader?.setOnImageAvailableListener({ reader ->
                val image = reader.acquireLatestImage()
                if (image != null) {
                    try {
                        val planes = image.planes
                        val buffer: ByteBuffer = planes[0].buffer
                        val bytes = ByteArray(buffer.capacity())
                        buffer.get(bytes)
                        savePhotoBytes(bytes, cameraId)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error saving photo bytes", e)
                    } finally {
                        image.close()
                    }
                }
            }, bgHandler)

            cm.openCamera(cameraId, object : CameraDevice.StateCallback() {
                override fun onOpened(camera: CameraDevice) {
                    cameraDevice = camera
                    bgHandler.postDelayed({
                        takeStillPicture(camera, cameraId)
                    }, 400L)
                }

                override fun onDisconnected(camera: CameraDevice) {
                    closeCurrentCamera()
                    captureNextCamera()
                }

                override fun onError(camera: CameraDevice, error: Int) {
                    Log.e(TAG, "Camera error $error on camera $cameraId")
                    closeCurrentCamera()
                    captureNextCamera()
                }
            }, bgHandler)

        } catch (e: Exception) {
            Log.e(TAG, "Failed to open camera $cameraId", e)
            closeCurrentCamera()
            captureNextCamera()
        }
    }

    private fun takeStillPicture(camera: CameraDevice, cameraId: String) {
        val reader = imageReader ?: run {
            closeCurrentCamera()
            captureNextCamera()
            return
        }
        val bgHandler = backgroundHandler ?: return

        try {
            val captureBuilder = camera.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE).apply {
                addTarget(reader.surface)
                set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
                set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON)
            }

            camera.createCaptureSession(listOf(reader.surface), object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(session: CameraCaptureSession) {
                    try {
                        session.capture(captureBuilder.build(), object : CameraCaptureSession.CaptureCallback() {
                            override fun onCaptureCompleted(
                                session: CameraCaptureSession,
                                request: CaptureRequest,
                                result: TotalCaptureResult
                            ) {
                                super.onCaptureCompleted(session, request, result)
                                Log.i(TAG, "Capture completed for camera $cameraId")
                                bgHandler.postDelayed({
                                    closeCurrentCamera()
                                    captureNextCamera()
                                }, 300L)
                            }
                        }, bgHandler)
                    } catch (e: Exception) {
                        Log.e(TAG, "Capture session error", e)
                        closeCurrentCamera()
                        captureNextCamera()
                    }
                }

                override fun onConfigureFailed(session: CameraCaptureSession) {
                    Log.e(TAG, "Camera capture session configuration failed")
                    closeCurrentCamera()
                    captureNextCamera()
                }
            }, bgHandler)

        } catch (e: Exception) {
            Log.e(TAG, "Error taking still picture", e)
            closeCurrentCamera()
            captureNextCamera()
        }
    }

    private fun savePhotoBytes(bytes: ByteArray, cameraId: String) {
        try {
            val timeStamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.getDefault()).format(Date())
            val filename = "INTRUDER_${cameraId}_$timeStamp.jpg"
            val dir = getExternalFilesDir("IntruderCaptures") ?: cacheDir
            if (!dir.exists()) dir.mkdirs()

            val file = File(dir, filename)
            FileOutputStream(file).use { out ->
                out.write(bytes)
                out.flush()
            }
            capturedFiles.add(file)
            Log.i(TAG, "Saved intruder photo to: ${file.absolutePath} (${file.length()} bytes)")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to write photo file", e)
        }
    }

    private fun closeCurrentCamera() {
        try {
            cameraDevice?.close()
            cameraDevice = null
            imageReader?.close()
            imageReader = null
        } catch (e: Exception) {
            Log.e(TAG, "Error closing camera", e)
        }
    }

    private fun finishAndSendEmail() {
        closeCurrentCamera()

        val email = recipientEmail.ifBlank { AntiTheftPrefs.getAlertEmail(this) }
        Log.i(TAG, "Finishing capture session. Dispatching to $email with ${capturedFiles.size} photos.")

        if (email.isNotBlank()) {
            EmailSender.sendIntruderAlertEmail(
                context = applicationContext,
                recipientEmail = email,
                photoFiles = ArrayList(capturedFiles),
                latitude = latitude,
                longitude = longitude
            ) { success, error ->
                Log.d(TAG, "Email dispatch status: $success (error: $error)")
                stopSelf()
            }
        } else {
            Log.w(TAG, "No alert email set in settings. Skipping email dispatch.")
            stopSelf()
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        closeCurrentCamera()
        stopBackgroundThread()
        Log.d(TAG, "IntruderCaptureService destroyed")
    }
}
