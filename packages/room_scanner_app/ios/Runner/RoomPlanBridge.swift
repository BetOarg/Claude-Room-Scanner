import Foundation
import RoomPlan
import Flutter
import UIKit

/// Bridge de comunicación nativo entre Flutter y la API RoomPlan de Apple (iOS 16+)
@available(iOS 16.0, *)
public class RoomPlanBridge: NSObject, RoomCaptureViewDelegate, RoomCaptureSessionDelegate {
    
    private var roomCaptureView: RoomCaptureView?
    private var flutterResult: FlutterResult?
    private weak var presentingViewController: UIViewController?

    /// Verifica si el dispositivo cuenta con soporte de hardware (iOS 16+ y sensor LiDAR)
    public static func isSupported() -> Bool {
        if #available(iOS 16.0, *) {
            return RoomCaptureSession.isSupported
        }
        return false
    }

    /// Inicia la sesión de captura visual nativa de RoomPlan
    public func startScanning(from viewController: UIViewController, result: @escaping FlutterResult) {
        guard RoomPlanBridge.isSupported() else {
            result(FlutterError(
                code: "UNSUPPORTED_HARDWARE",
                message: "RoomPlan requiere iOS 16.0 o superior y un sensor LiDAR.",
                details: nil
            ))
            return
        }

        self.flutterResult = result
        self.presentingViewController = viewController

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let captureView = RoomCaptureView(frame: viewController.view.bounds)
            captureView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            captureView.delegate = self
            captureView.captureSession.delegate = self
            self.roomCaptureView = captureView

            viewController.view.addSubview(captureView)
            
            let configuration = RoomCaptureSession.Configuration()
            captureView.captureSession.run(configuration: configuration)
        }
    }

    /// Cancela manualmente la sesión de escaneo en curso
    public func stopScanning() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.roomCaptureView?.captureSession.stop()
            self.cleanupView()
            if let result = self.flutterResult {
                result(nil)
                self.flutterResult = nil
            }
        }
    }

    // MARK: - RoomCaptureViewDelegate

    /// Permite desplegar la vista 3D interactiva de revisión nativa de Apple
    public func captureView(shouldPresent processedResult: CapturedRoom, error: Error?) -> Bool {
        return error == nil
    }

    /// Callback ejecutado tras confirmar la estructura en la vista 3D nativa
    public func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        if let error = error {
            self.sendFlutterResult(FlutterError(
                code: "SCAN_ERROR",
                message: error.localizedDescription,
                details: nil
            ))
            self.cleanupView()
            return
        }

        var wallsData: [[String: Any]] = []
        for wall in processedResult.walls {
            wallsData.append([
                "length": wall.dimensions.x,
                "height": wall.dimensions.y
            ])
        }

        var openingsData: [[String: Any]] = []
        for door in processedResult.doors {
            openingsData.append([
                "type": "door",
                "width": door.dimensions.x,
                "height": door.dimensions.y
            ])
        }
        for window in processedResult.windows {
            openingsData.append([
                "type": "window",
                "width": window.dimensions.x,
                "height": window.dimensions.y
            ])
        }

        let payload: [String: Any] = [
            "areaSquareMeters": 0.0,
            "walls": wallsData,
            "openings": openingsData
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: []),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            self.sendFlutterResult(jsonString)
        } else {
            self.sendFlutterResult(FlutterError(
                code: "SERIALIZATION_FAILED",
                message: "Error al serializar la habitación a JSON",
                details: nil
            ))
        }

        self.cleanupView()
    }

    // MARK: - Métodos Auxiliares

    private func sendFlutterResult(_ value: Any) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let result = self.flutterResult else { return }
            result(value)
            self.flutterResult = nil
        }
    }

    private func cleanupView() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.roomCaptureView?.captureSession.stop()
            self.roomCaptureView?.removeFromSuperview()
            self.roomCaptureView = nil
        }
    }
}