#if os(macOS)
import AppKit
import SwiftUI

/// A persistent AppKit editor: selecting a reply must never strand SwiftUI's field focus.
struct TutorChatComposer: NSViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    @Binding var height: CGFloat
    var send: () -> Void
    /// Esc stops the tutor's answer; nil while none is on its way, so Esc behaves as usual.
    var stop: (() -> Void)? = nil

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        let editor = Editor()
        editor.delegate = context.coordinator
        editor.drawsBackground = false
        editor.isRichText = false
        editor.importsGraphics = false
        editor.isEditable = true
        editor.isSelectable = true
        editor.font = .systemFont(ofSize: 15)
        editor.textContainerInset = NSSize(width: 2, height: 8)
        editor.isHorizontallyResizable = false
        editor.isVerticallyResizable = true
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.lineFragmentPadding = 0
        editor.setAccessibilityLabel("Ask your tutor")
        scroll.documentView = editor
        context.coordinator.editor = editor
        updateNSView(scroll, context: context)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? Editor else { return }
        editor.textColor = NSColor(PP.ink)
        editor.insertionPointColor = NSColor(PP.accent)
        editor.placeholderColor = NSColor(PP.inkMuted)
        if editor.string != text {
            editor.string = text
            editor.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }
        editor.needsDisplay = true
        editor.onLayout = { [weak coordinator = context.coordinator] in coordinator?.measure() }
        context.coordinator.measure()
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TutorChatComposer
        weak var editor: Editor?
        init(_ parent: TutorChatComposer) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let editor else { return }
            parent.text = editor.string
            editor.needsDisplay = true
            measure()
        }

        func textDidBeginEditing(_ notification: Notification) { parent.focused = true }
        func textDidEndEditing(_ notification: Notification) { parent.focused = false }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)), !textView.hasMarkedText(),
               let stop = parent.stop {
                stop()
                return true
            }
            // Shift-Return inserts a line break. Return sends, except during input-method composition.
            guard commandSelector == #selector(NSResponder.insertNewline(_:)),
                  !textView.hasMarkedText(),
                  NSApp.currentEvent?.modifierFlags.contains(.shift) != true else { return false }
            parent.send()
            return true
        }

        func measure() {
            guard let editor, let container = editor.textContainer, let layout = editor.layoutManager,
                  container.containerSize.width > 0 else { return }
            layout.ensureLayout(for: container)
            let line = layout.defaultLineHeight(for: editor.font ?? .systemFont(ofSize: 15))
            let measured = min(line * 4, max(line, layout.usedRect(for: container).height)) + 16
            guard abs(parent.height - measured) > 0.5 else { return }
            DispatchQueue.main.async { [weak self] in self?.parent.height = measured }
        }
    }

    final class Editor: NSTextView {
        var placeholderColor = NSColor.secondaryLabelColor
        var onLayout: (() -> Void)?

        override func layout() {
            super.layout()
            onLayout?()
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            if string.isEmpty {
                ("Ask your tutor" as NSString).draw(
                    at: NSPoint(x: textContainerInset.width, y: textContainerInset.height),
                    withAttributes: [.font: font ?? .systemFont(ofSize: 15), .foregroundColor: placeholderColor])
            }
        }
    }
}
#endif
