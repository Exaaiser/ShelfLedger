import SwiftUI
import AVFoundation
import Vision

struct CameraView: UIViewRepresentable {
    let onBarcode: (String) -> Void
    let onFailure: (String) -> Void
    func makeCoordinator() -> CameraCapture { CameraCapture(onBarcode: onBarcode, onFailure: onFailure) }
    func makeUIView(context: Context) -> CameraPreview {
        let view = CameraPreview()
        view.preview.session = context.coordinator.session
        view.preview.videoGravity = .resizeAspectFill
        context.coordinator.start()
        return view
    }
    func updateUIView(_ uiView: CameraPreview, context: Context) {}
    static func dismantleUIView(_ uiView: CameraPreview, coordinator: CameraCapture) { coordinator.stop() }
}

final class CameraPreview: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

// All capture state and Vision work are confined to this serial queue.
final class CameraCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "io.github.exaaiser.shelfledger.barcode-camera", qos: .userInitiated)
    private let onBarcode: (String) -> Void
    private let onFailure: (String) -> Void
    private var stopped = false
    private var delivered = false
    private var lastFrame = CMTime.zero
    init(onBarcode: @escaping (String) -> Void, onFailure: @escaping (String) -> Void) {
        self.onBarcode = onBarcode; self.onFailure = onFailure
    }
    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: queue.async { self.configure() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { allowed in
                self.queue.async { allowed ? self.configure() : self.fail("Camera access is off. Allow it in Settings, or enter the barcode below.") }
            }
        default: queue.async { self.fail("Camera access is off. Allow it in Settings, or enter the barcode below.") }
        }
    }
    func stop() {
        queue.async {
            self.stopped = true
            if self.session.isRunning { self.session.stopRunning() }
        }
    }
    private func configure() {
        guard !stopped else { return }
        do {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                fail("No camera is available. Enter the barcode below."); return
            }
            let input = try AVCaptureDeviceInput(device: device)
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: queue)
            session.beginConfiguration()
            session.sessionPreset = .high
            guard session.canAddInput(input) else {
                session.commitConfiguration(); fail("The camera could not start. Enter the barcode below."); return
            }
            session.addInput(input)
            guard session.canAddOutput(output) else {
                session.commitConfiguration(); fail("The camera could not start. Enter the barcode below."); return
            }
            session.addOutput(output)
            session.commitConfiguration()
            session.startRunning()
        } catch { fail("The camera could not start. Enter the barcode below.") }
    }
    private func fail(_ message: String) {
        guard !stopped else { return }
        DispatchQueue.main.async { self.onFailure(message) }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !stopped, !delivered else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard CMTimeGetSeconds(time - lastFrame) >= 0.2,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame = time
        let request = VNDetectBarcodesRequest()
        // EAN-13 also represents UPC-A with a leading zero. UPC-E requires expansion,
        // so it is deliberately excluded rather than misinterpreted as EAN-8.
        request.symbologies = [.ean8, .ean13, .itf14]
        do {
            try VNImageRequestHandler(cvPixelBuffer: buffer, options: [:]).perform([request])
            guard let value = request.results?.compactMap(\.payloadStringValue).first(where: { (try? Barcode($0)) != nil }) else { return }
            delivered = true
            session.stopRunning()
            DispatchQueue.main.async { self.onBarcode(value) }
        } catch { /* A blurry frame is retried on the next throttled frame. */ }
    }
}
