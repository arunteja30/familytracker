import UIKit
import Flutter
import GoogleMaps
import Contacts

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  private let CHANNEL = "com.mat.familytrack/background_service"

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

    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let backgroundChannel = FlutterMethodChannel(name: CHANNEL, binaryMessenger: controller.binaryMessenger)

    backgroundChannel.setMethodCallHandler({ [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      switch call.method {
      case "getDeviceContacts":
        self?.fetchDeviceContacts(result: result)
      case "getDeviceOemInfo":
        let oemInfo: [String: Any] = [
          "manufacturer": "Apple",
          "brand": "Apple",
          "model": UIDevice.current.model,
          "isStrictOem": false,
          "systemVersion": UIDevice.current.systemVersion
        ]
        result(oemInfo)
      case "openLocationSettings":
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString),
           UIApplication.shared.canOpenURL(settingsUrl) {
          UIApplication.shared.open(settingsUrl, options: [:]) { success in
            result(success)
          }
        } else {
          result(false)
        }
      case "startNativeStickyService":
        // iOS background location is handled via standard CLLocationManager / Geolocator background modes
        result(true)
      case "requestBatteryOptimizationExemption":
        result(true)
      case "openOemAutoStartSettings":
        result(false)
      default:
        result(FlutterMethodNotImplemented)
      }
    })

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  // Fetch device contacts asynchronously using iOS Contacts framework
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
