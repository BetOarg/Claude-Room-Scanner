import ARKit
import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {
  // Tipado como `Any?` porque `RoomPlanBridge` solo existe bajo
  // `@available(iOS 16.0, *)`; se castea dentro del bloque `#available`.
  private var roomPlanBridge: Any?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Registra el canal 'com.example.roomplan' contra RoomPlanBridge.
    //
    // Antes `RoomPlanBridge.swift` existía pero nunca se conectaba a un
    // FlutterMethodChannel real: cualquier llamada desde Dart
    // (RoomPlanService.isSupported/startScanning/stopScanning) fallaba
    // silenciosamente con MissingPluginException, incluso en un iPhone con
    // LiDAR compatible.
    if let controller = window?.rootViewController as? FlutterViewController { let deviceCapabilitiesChannel = FlutterMethodChannel(
  name: "com.betOarg.room_scanner_ar/device_capabilities",
  binaryMessenger: controller.binaryMessenger
)

deviceCapabilitiesChannel.setMethodCallHandler { call, result in

  switch call.method {

  case "isARKitSupported":

    if #available(iOS 11.0, *) {
      result(ARWorldTrackingConfiguration.isSupported)
    } else {
      result(false)
    }

  case "isARCoreSupported":

    result(false)

  default:

    result(FlutterMethodNotImplemented)
  }
}
      let roomPlanChannel = FlutterMethodChannel(
        name: "com.example.roomplan",
        binaryMessenger: controller.binaryMessenger
      )

      roomPlanChannel.setMethodCallHandler { [weak self, weak controller] call, result in
        guard let controller = controller else {
          result(FlutterError(
            code: "NO_CONTROLLER",
            message: "No se encontró el FlutterViewController activo.",
            details: nil
          ))
          return
        }

        if #available(iOS 16.0, *) {
          let bridge: RoomPlanBridge
          if let existing = self?.roomPlanBridge as? RoomPlanBridge {
            bridge = existing
          } else {
            bridge = RoomPlanBridge()
            self?.roomPlanBridge = bridge
          }

          switch call.method {
          case "isSupported":
            result(RoomPlanBridge.isSupported())
          case "startScanning":
            bridge.startScanning(from: controller, result: result)
          case "stopScanning":
            bridge.stopScanning()
            result(nil)
          default:
            result(FlutterMethodNotImplemented)
          }
        } else {
          switch call.method {
          case "isSupported":
            result(false)
          default:
            result(FlutterError(
              code: "UNSUPPORTED_IOS_VERSION",
              message: "RoomPlan requiere iOS 16.0 o superior.",
              details: nil
            ))
          }
        }
      }
    }

    return super.application(application, launchOptions: launchOptions)
  }
}
