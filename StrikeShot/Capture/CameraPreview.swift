import AVFoundation
import SwiftUI
import UIKit

/// Live viewfinder. The preview layer is the view's backing layer (`layerClass`),
/// so it tracks the view's bounds automatically — no manual layout pass needed.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer? {
            layer as? AVCaptureVideoPreviewLayer
        }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer?.session = session
        view.previewLayer?.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if uiView.previewLayer?.session !== session {
            uiView.previewLayer?.session = session
        }
    }
}
