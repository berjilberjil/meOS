import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// UIKit-hosted Photos picker for the event editor.
///
/// SwiftUI `PhotosPicker` inside `EventEditorSheet` remounted every time
/// `AppState` published (live-sync ticks every 1.5s). PHPickerViewController
/// reloaded the library for a second or two and dropped the selection.
/// This controller is created once; `updateUIViewController` only refreshes
/// the callbacks, so a tick cannot rebuild the picker.
struct EventMediaPicker: UIViewControllerRepresentable {
    var selectionLimit: Int
    var onPick: ([PHPickerResult]) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .any(of: [.images, .videos])
        config.selectionLimit = max(1, selectionLimit)
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
        context.coordinator.onPick = onPick
        context.coordinator.onCancel = onCancel
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        var onPick: ([PHPickerResult]) -> Void
        var onCancel: () -> Void
        init(onPick: @escaping ([PHPickerResult]) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            if results.isEmpty { onCancel() } else { onPick(results) }
        }
    }
}
