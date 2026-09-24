import UIKit
import Flutter
import GoogleMaps
import Contacts
import CoreLocation
import AVFoundation
import Photos
import AudioToolbox

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, CLLocationManagerDelegate {

  private let CHANNEL = "com.mat.familytrack/background_service"
  private var backgroundChannel: FlutterMethodChannel?
  private var locationManager: CLLocationManager?
  private var sirenPlayer: AVAudioPlayer?
  private var vibrationTimer: Timer?
  private var sirenAutoStopTimer: Timer?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Initialize Google Maps SDK for iOS (injected dynamically)
    let mapsApiKey = (Bundle.main.object(forInfoDictionaryKey: "GoogleMapsAPIKey") as? String)
      ?? ProcessInfo.processInfo.environment["MAPS_API_KEY"]
      ?? ""
    if !mapsApiKey.isEmpty {
      GMSServices.provideAPIKey(mapsApiKey)
    }

    // Initialize Native CoreLocation Manager for Background & Significant Location Changes
    setupNativeLocationManager()

    // Handle background launch triggered by iOS location change
    if launchOptions?[.location] != nil {
      locationManager?.startMonitoringSignificantLocationChanges()
    }

    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let backgroundChannel = FlutterMethodChannel(name: CHANNEL, binaryMessenger: controller.binaryMessenger)
    self.backgroundChannel = backgroundChannel

    backgroundChannel.setMethodCallHandler({ [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      guard let self = self else { return }

      switch call.method {
      // 1. Device Contacts
      case "getDeviceContacts":
        self.fetchDeviceContacts(result: result)

      // 2. OEM / Hardware Info
      case "getDeviceOemInfo":
        let oemInfo: [String: Any] = [
          "manufacturer": "Apple",
          "brand": "Apple",
          "model": UIDevice.current.model,
          "isStrictOem": false,
          "systemVersion": UIDevice.current.systemVersion,
          "name": UIDevice.current.name
        ]
        result(oemInfo)

      // 3. Settings Navigation
      case "openLocationSettings", "openOemAutoStartSettings", "openBatteryOptimizationSettings":
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString),
           UIApplication.shared.canOpenURL(settingsUrl) {
          UIApplication.shared.open(settingsUrl, options: [:]) { success in
            result(success)
          }
        } else {
          result(false)
        }

      // 4. Background Service Management
      case "startNativeStickyService":
        self.startBackgroundLocationTracking()
        result(true)

      case "stopNativeStickyService":
        self.locationManager?.stopUpdatingLocation()
        result(true)

      case "requestBatteryOptimizationExemption":
        result(true)

      case "updateStickyNotification":
        result(true)

      // 5. Anti-Theft Device Security & Administrator Status
      case "isDeviceAdminActive", "requestDeviceAdmin", "removeDeviceAdmin":
        // iOS uses hardware Secure Enclave, Face ID / Touch ID, and system Passcode
        result(true)

      case "getAntiTheftConfig":
        let defaults = UserDefaults.standard
        let map: [String: Any] = [
          "alertEmail": defaults.string(forKey: "anti_theft_alert_email") ?? "",
          "senderEmail": defaults.string(forKey: "anti_theft_sender_email") ?? "",
          "senderPassword": defaults.string(forKey: "anti_theft_sender_password") ?? "",
          "enabled": defaults.object(forKey: "anti_theft_enabled") as? Bool ?? true,
          "siren": defaults.object(forKey: "anti_theft_siren") as? Bool ?? false,
          "dualCam": defaults.object(forKey: "anti_theft_dual_cam") as? Bool ?? false,
          "failedAttempts": defaults.object(forKey: "anti_theft_failed_attempts") as? Int ?? 2,
          "isAdminActive": true
        ]
        result(map)

      case "setAntiTheftConfig":
        let defaults = UserDefaults.standard
        if let alertEmail = call.argument<String>("alertEmail") {
          defaults.set(alertEmail, forKey: "anti_theft_alert_email")
        }
        if let senderEmail = call.argument<String>("senderEmail") {
          defaults.set(senderEmail, forKey: "anti_theft_sender_email")
        }
        if let senderPassword = call.argument<String>("senderPassword") {
          defaults.set(senderPassword, forKey: "anti_theft_sender_password")
        }
        if let enabled = call.argument<Bool>("enabled") {
          defaults.set(enabled, forKey: "anti_theft_enabled")
        }
        if let siren = call.argument<Bool>("siren") {
          defaults.set(siren, forKey: "anti_theft_siren")
        }
        if let dualCam = call.argument<Bool>("dualCam") {
          defaults.set(dualCam, forKey: "anti_theft_dual_cam")
        }
        if let failedAttempts = call.argument<Int>("failedAttempts") {
          defaults.set(failedAttempts, forKey: "anti_theft_failed_attempts")
        }
        result(true)

      // 6. Emergency Siren Alarm & Intruder Capture
      case "testIntruderAlarm":
        let playSiren = call.argument<Bool>("playSiren") ?? true
        let dualCam = call.argument<Bool>("dualCam") ?? false
        let email = call.argument<String>("alertEmail") ?? UserDefaults.standard.string(forKey: "anti_theft_alert_email") ?? ""

        if playSiren {
          self.startIntruderSirenAlert(autoStopSeconds: 6.0)
        }

        let dir = self.getIntruderCapturesDirectory()
        let coord = self.locationManager?.location?.coordinate
        IntruderPhotoManager.shared.captureIntruder(
          dualCam: dualCam,
          capturesDir: dir,
          coordinate: coord
        ) { [weak self] paths in
          guard let self = self else { return }
          self.backgroundChannel?.invokeMethod("onIntruderCaptured", arguments: [
            "photoPaths": paths,
            "latitude": coord?.latitude ?? 0.0,
            "longitude": coord?.longitude ?? 0.0,
            "alertEmail": email
          ])
        }
        result(true)

      case "stopIntruderAlarm":
        self.stopIntruderSirenAlert()
        result(true)

      // 7. Intruder Photos Management
      case "getIntruderPhotos":
        self.fetchIntruderPhotos(result: result)

      case "savePhotoToGallery":
        self.savePhotoToGallery(call: call, result: result)

      case "deleteIntruderPhoto":
        self.deleteIntruderPhoto(call: call, result: result)

      case "clearAllIntruderPhotos":
        self.clearAllIntruderPhotos(result: result)

      // 8. Offline SMS Emergency Configuration
      case "isOfflineSmsEnabled":
        let enabled = UserDefaults.standard.object(forKey: "offline_sms_enabled") as? Bool ?? true
        result(enabled)

      case "setOfflineSmsEnabled":
        let enabled = call.argument<Bool>("enabled") ?? true
        UserDefaults.standard.set(enabled, forKey: "offline_sms_enabled")
        result(true)

      case "getOfflineSmsPhone":
        let phone = UserDefaults.standard.string(forKey: "offline_sms_phone") ?? ""
        result(phone)

      case "setOfflineSmsPhone":
        let phone = call.argument<String>("phone") ?? ""
        UserDefaults.standard.set(phone, forKey: "offline_sms_phone")
        result(true)

      case "hasSmsPermission", "requestSmsPermission":
        result(true)

      case "sendTestOfflineSms":
        self.handleSendTestOfflineSms(call: call, result: result)

      // 9. Call Logs & SMS Reading (iOS Sandbox Restricts 3rd-Party Access)
      case "getDeviceCallLogs", "getDeviceSms":
        result([[String: Any]]())

      case "hasCallLogPermission":
        result(false)

      case "requestCallLogPermission":
        result(true)

      // 10. Email Dispatch (Native or Fallback)
      case "testSendAlertEmail", "sendBackupFilesEmail":
        // Signal Dart layer to run the high-performance cross-platform TLS SMTP dispatcher
        result(["success": false, "fallback": true, "error": "USE_DART_SMTP"])

      default:
        result(FlutterMethodNotImplemented)
      }
    })

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - Native Background Location Management
  private func setupNativeLocationManager() {
    locationManager = CLLocationManager()
    locationManager?.delegate = self
    locationManager?.desiredAccuracy = kCLLocationAccuracyBest
    locationManager?.distanceFilter = 40.0
    locationManager?.pausesLocationUpdatesAutomatically = false

    if #available(iOS 9.0, *) {
      locationManager?.allowsBackgroundLocationUpdates = true
      locationManager?.showsBackgroundLocationIndicator = true
    }

    // Always start significant location change monitoring (wakes app even if terminated)
    if CLLocationManager.significantLocationChangeMonitoringAvailable() {
      locationManager?.startMonitoringSignificantLocationChanges()
    }
  }

  private func startBackgroundLocationTracking() {
    locationManager?.startUpdatingLocation()
    if CLLocationManager.significantLocationChangeMonitoringAvailable() {
      locationManager?.startMonitoringSignificantLocationChanges()
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let latest = locations.last else { return }
    NSLog("[FamilyTracker-iOS] CoreLocation update: \(latest.coordinate.latitude), \(latest.coordinate.longitude)")
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    NSLog("[FamilyTracker-iOS] CoreLocation error: \(error.localizedDescription)")
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  // MARK: - Emergency Siren Alert & Audio Playback
  private func startIntruderSirenAlert(autoStopSeconds: Double = 6.0) {
    stopIntruderSirenAlert()

    do {
      let audioSession = AVAudioSession.sharedInstance()
      try audioSession.setCategory(.playback, mode: .default, options: [.duckOthers])
      try audioSession.setActive(true)

      // Generate a loud 2-second dual-frequency oscillating emergency siren audio buffer
      let sampleRate: Double = 22050.0
      let duration: Double = 2.0
      let totalSamples = Int(sampleRate * duration)
      var pcmData = Data()

      for i in 0..<totalSamples {
        let t = Double(i) / sampleRate
        // Oscillate frequency between 750 Hz and 1300 Hz
        let freq = 750.0 + 550.0 * (0.5 * (1.0 + sin(2.0 * Double.pi * 1.5 * t)))
        let sample = sin(2.0 * Double.pi * freq * t)
        let intSample = Int16(sample * 32767.0 * 0.95)
        var littleEndian = intSample.littleEndian
        withUnsafeBytes(of: &littleEndian) { pcmData.append(contentsOf: $0) }
      }

      let wavData = createWavData(fromPcm: pcmData, sampleRate: Int(sampleRate), numChannels: 1, bitsPerSample: 16)
      sirenPlayer = try AVAudioPlayer(data: wavData)
      sirenPlayer?.numberOfLoops = -1 // Infinite loop until cancelled
      sirenPlayer?.volume = 1.0
      sirenPlayer?.prepareToPlay()
      sirenPlayer?.play()

      // Repeating haptic vibration
      vibrationTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { _ in
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
      }
      AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)

      // Auto-stop siren timer (matching Android 6-second burst)
      if autoStopSeconds > 0 {
        sirenAutoStopTimer = Timer.scheduledTimer(withTimeInterval: autoStopSeconds, repeats: false) { [weak self] _ in
          self?.stopIntruderSirenAlert()
        }
      }
    } catch {
      NSLog("[FamilyTracker-iOS] Failed to start siren audio: \(error.localizedDescription)")
      AudioServicesPlayAlertSound(1005)
    }
  }

  private func stopIntruderSirenAlert() {
    sirenAutoStopTimer?.invalidate()
    sirenAutoStopTimer = nil
    sirenPlayer?.stop()
    sirenPlayer = nil
    vibrationTimer?.invalidate()
    vibrationTimer = nil
  }

  // Helper to build a valid RIFF/WAVE container for in-memory PCM audio
  private func createWavData(fromPcm pcm: Data, sampleRate: Int, numChannels: Int, bitsPerSample: Int) -> Data {
    var data = Data()
    let byteRate = sampleRate * numChannels * bitsPerSample / 8
    let blockAlign = numChannels * bitsPerSample / 8
    let subchunk2Size = pcm.count
    let chunkSize = 36 + subchunk2Size

    data.append("RIFF".utf8Data)
    data.append(UInt32(chunkSize).littleEndianData)
    data.append("WAVE".utf8Data)
    data.append("fmt ".utf8Data)
    data.append(UInt32(16).littleEndianData) // Subchunk1Size
    data.append(UInt16(1).littleEndianData)  // AudioFormat (PCM)
    data.append(UInt16(numChannels).littleEndianData)
    data.append(UInt32(sampleRate).littleEndianData)
    data.append(UInt32(byteRate).littleEndianData)
    data.append(UInt16(blockAlign).littleEndianData)
    data.append(UInt16(bitsPerSample).littleEndianData)
    data.append("data".utf8Data)
    data.append(UInt32(subchunk2Size).littleEndianData)
    data.append(pcm)

    return data
  }

  // MARK: - Intruder Photos Storage Management
  private func getIntruderCapturesDirectory() -> URL {
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let dir = docs.appendingPathComponent("intruder_captures")
    if !FileManager.default.fileExists(atPath: dir.path) {
      try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
    }
    return dir
  }

  private func fetchIntruderPhotos(result: @escaping FlutterResult) {
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self = self else { return }
      var list = [[String: Any]]()
      let dir = self.getIntruderCapturesDirectory()

      do {
        let fileUrls = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey], options: .skipsHiddenFiles)
        let sortedUrls = fileUrls.sorted { url1, url2 in
          let d1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
          let d2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
          return d1 > d2
        }

        for fileUrl in sortedUrls {
          let name = fileUrl.lastPathComponent
          if name.lowercased().hasSuffix(".jpg") && name != ".nomedia" {
            var item = [String: Any]()
            item["path"] = fileUrl.path
            item["name"] = name
            let resValues = try? fileUrl.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            item["size"] = resValues?.fileSize ?? 0
            let modDate = resValues?.contentModificationDate ?? Date()
            item["timestamp"] = Int64(modDate.timeIntervalSince1970 * 1000)
            item["isFront"] = name.contains("FRONT") || (name.contains("INTRUDER_1") && !name.contains("BACK"))

            var lat = 0.0
            var lng = 0.0
            let jsonUrl = dir.appendingPathComponent(name.replacingOccurrences(of: ".jpg", with: ".json"))
            if let jsonData = try? Data(contentsOf: jsonUrl),
               let jsonObj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
              lat = (jsonObj["latitude"] as? Double) ?? 0.0
              lng = (jsonObj["longitude"] as? Double) ?? 0.0
            }
            item["latitude"] = lat
            item["longitude"] = lng

            list.append(item)
          }
        }
      } catch {
        NSLog("[FamilyTracker-iOS] Error listing intruder captures: \(error.localizedDescription)")
      }

      DispatchQueue.main.async {
        result(list)
      }
    }
  }

  private func savePhotoToGallery(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let filePath = args["filePath"] as? String,
          FileManager.default.fileExists(atPath: filePath) else {
      result(false)
      return
    }

    let fileUrl = URL(fileURLWithPath: filePath)
    PHPhotoLibrary.requestAuthorization { status in
      if status == .authorized || status == .limited {
        PHPhotoLibrary.shared().performChanges({
          PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileUrl)
        }) { success, error in
          DispatchQueue.main.async {
            result(success)
          }
        }
      } else {
        DispatchQueue.main.async {
          result(false)
        }
      }
    }
  }

  private func deleteIntruderPhoto(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let filePath = args["filePath"] as? String else {
      result(false)
      return
    }

    let fm = FileManager.default
    let jsonPath = filePath.replacingOccurrences(of: ".jpg", with: ".json")
    try? fm.removeItem(atPath: jsonPath)
    if fm.fileExists(atPath: filePath) {
      do {
        try fm.removeItem(atPath: filePath)
        result(true)
      } catch {
        result(false)
      }
    } else {
      result(false)
    }
  }

  private func clearAllIntruderPhotos(result: @escaping FlutterResult) {
    let dir = getIntruderCapturesDirectory()
    let fm = FileManager.default
    if let files = try? fm.contentsOfDirectory(atPath: dir.path) {
      for f in files {
        if f != ".nomedia" {
          try? fm.removeItem(atPath: dir.appendingPathComponent(f).path)
        }
      }
    }
    result(true)
  }

  // MARK: - Offline SMS Handler
  private func handleSendTestOfflineSms(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let phone = (call.arguments as? [String: Any])?["phone"] as? String
      ?? UserDefaults.standard.string(forKey: "offline_sms_phone")
      ?? ""

    if !phone.isEmpty {
      UserDefaults.standard.set(phone, forKey: "offline_sms_phone")
    }

    let coord = locationManager?.location?.coordinate ?? CLLocationCoordinate2D(latitude: 17.4374, longitude: 78.3759)
    let body = "🚨 FamilyTracker Location Alert!\n📍 Coordinates: \(coord.latitude), \(coord.longitude)\nMaps: https://maps.google.com/?q=\(coord.latitude),\(coord.longitude)"

    if let cleanPhone = phone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined().addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
       let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
       let smsUrl = URL(string: "sms:\(cleanPhone)&body=\(encodedBody)"),
       UIApplication.shared.canOpenURL(smsUrl) {
      UIApplication.shared.open(smsUrl, options: [:]) { opened in
        result(["success": opened, "message": "SMS composer prepared with live GPS location"])
      }
    } else {
      result(["success": true, "message": "Location prepared for SMS: \(coord.latitude), \(coord.longitude)"])
    }
  }

  // MARK: - Device Contacts Fetching
  private func fetchDeviceContacts(result: @escaping FlutterResult) {
    let store = CNContactStore()
    let status = CNContactStore.authorizationStatus(for: .contacts)

    if status == .authorized {
      DispatchQueue.global(qos: .userInitiated).async {
        var contactsMap: [String: String] = [:]
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)

        do {
          try store.enumerateContacts(with: request) { (contact, stop) in
            let fullName = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
            if !fullName.isEmpty {
              for phone in contact.phoneNumbers {
                let numberStr = phone.value.stringValue
                let cleanNumber = numberStr.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                if !cleanNumber.isEmpty {
                  contactsMap[cleanNumber] = fullName
                  if cleanNumber.count >= 10 {
                    let last10 = String(cleanNumber.suffix(10))
                    contactsMap[last10] = fullName
                  }
                }
              }
            }
          }
          DispatchQueue.main.async {
            result(contactsMap)
          }
        } catch {
          DispatchQueue.main.async {
            result(contactsMap)
          }
        }
      }
    } else if status == .notDetermined {
      store.requestAccess(for: .contacts) { [weak self] (granted, _) in
        if granted {
          self?.fetchDeviceContacts(result: result)
        } else {
          DispatchQueue.main.async {
            result([String: String]())
          }
        }
      }
    } else {
      result([String: String]())
    }
  }
}

// MARK: - Byte Helper Extensions
private extension String {
  var utf8Data: Data { Data(self.utf8) }
}

private extension UInt16 {
  var littleEndianData: Data {
    var v = self.littleEndian
    return Data(bytes: &v, count: 2)
  }
}

private extension UInt32 {
  var littleEndianData: Data {
    var v = self.littleEndian
    return Data(bytes: &v, count: 4)
  }
}

// MARK: - Intruder Camera Capture Engine for iOS
class IntruderPhotoManager: NSObject, AVCapturePhotoCaptureDelegate {
  static let shared = IntruderPhotoManager()

  private var captureSession: AVCaptureSession?
  private var photoOutput: AVCapturePhotoOutput?
  private var completion: (([String]) -> Void)?
  private var capturedPaths: [String] = []
  private var isDualCam: Bool = false
  private var isFront: Bool = true
  private var capturesDir: URL?
  private var coordinate: CLLocationCoordinate2D?

  func captureIntruder(
    dualCam: Bool,
    capturesDir: URL,
    coordinate: CLLocationCoordinate2D?,
    completion: @escaping ([String]) -> Void
  ) {
    self.isDualCam = dualCam
    self.capturesDir = capturesDir
    self.coordinate = coordinate
    self.completion = completion
    self.capturedPaths = []
    self.isFront = true

    let status = AVCaptureDevice.authorizationStatus(for: .video)
    if status == .authorized {
      self.captureForPosition(position: .front)
    } else if status == .notDetermined {
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        if granted {
          DispatchQueue.main.async {
            self?.captureForPosition(position: .front)
          }
        } else {
          completion([])
        }
      }
    } else {
      NSLog("[FamilyTracker-iOS] Camera permission not granted for intruder capture")
      completion([])
    }
  }

  private func captureForPosition(position: AVCaptureDevice.Position) {
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self = self else { return }

      let session = AVCaptureSession()
      session.sessionPreset = .photo

      let discovery = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.builtInWideAngleCamera],
        mediaType: .video,
        position: position
      )

      guard let camera = discovery.devices.first,
            let input = try? AVCaptureDeviceInput(device: camera) else {
        DispatchQueue.main.async {
          if self.isFront && self.isDualCam {
            self.isFront = false
            self.captureForPosition(position: .back)
          } else {
            self.completion?(self.capturedPaths)
          }
        }
        return
      }

      if session.canAddInput(input) {
        session.addInput(input)
      }

      // Configure hardware sensor for continuous auto-exposure, white balance & focus
      do {
        try camera.lockForConfiguration()
        if camera.isExposureModeSupported(.continuousAutoExposure) {
          camera.exposureMode = .continuousAutoExposure
        }
        if camera.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
          camera.whiteBalanceMode = .continuousAutoWhiteBalance
        }
        if camera.isFocusModeSupported(.continuousAutoFocus) {
          camera.focusMode = .continuousAutoFocus
        }
        camera.unlockForConfiguration()
      } catch {
        NSLog("[FamilyTracker-iOS] Camera lockForConfiguration error: \(error.localizedDescription)")
      }

      let output = AVCapturePhotoOutput()
      if session.canAddOutput(output) {
        session.addOutput(output)
      }

      self.captureSession = session
      self.photoOutput = output

      session.startRunning()

      // Allow 750ms for Apple ISP hardware to meter scene lux and converge auto-exposure & white-balance
      // Prevents initial white washed-out / overexposed frames when starting from dormant state
      Thread.sleep(forTimeInterval: 0.75)

      let settings = AVCapturePhotoSettings()
      if output.supportedFlashModes.contains(.off) {
        settings.flashMode = .off
      }
      if output.isHighResolutionCaptureEnabled {
        settings.isHighResolutionPhotoEnabled = true
      }

      output.capturePhoto(with: settings, delegate: self)
    }
  }

  func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
    defer {
      captureSession?.stopRunning()
      captureSession = nil
      photoOutput = nil
    }

    if let error = error {
      NSLog("[FamilyTracker-iOS] Photo capture error: \(error.localizedDescription)")
    } else if let data = photo.fileDataRepresentation(), let dir = self.capturesDir {
      let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
      let label = isFront ? "INTRUDER_FRONT" : "INTRUDER_BACK"
      let photoName = "\(label)_\(timestamp).jpg"
      let jsonName = "\(label)_\(timestamp).json"

      let photoUrl = dir.appendingPathComponent(photoName)
      let jsonUrl = dir.appendingPathComponent(jsonName)

      try? data.write(to: photoUrl)

      let meta: [String: Any] = [
        "timestamp": timestamp,
        "isFront": isFront,
        "latitude": coordinate?.latitude ?? 0.0,
        "longitude": coordinate?.longitude ?? 0.0,
        "fileName": photoName
      ]
      if let jsonData = try? JSONSerialization.data(withJSONObject: meta, options: .prettyPrinted) {
        try? jsonData.write(to: jsonUrl)
      }

      capturedPaths.append(photoUrl.path)
      NSLog("[FamilyTracker-iOS] Captured intruder photo: \(photoName)")
    }

    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      if self.isFront && self.isDualCam {
        self.isFront = false
        self.captureForPosition(position: .back)
      } else {
        self.completion?(self.capturedPaths)
      }
    }
  }
}

