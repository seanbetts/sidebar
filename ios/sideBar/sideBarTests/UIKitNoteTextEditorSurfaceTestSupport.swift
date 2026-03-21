import XCTest
@testable import sideBar

func canonicalUIKitPlainTextPass(_ plainText: String) -> String {
    NotesSemanticDocumentCodec.encode(
        NotesSemanticDocumentProjection.document(fromPlainText: plainText)
    ) ?? plainText
}

#if os(iOS)
import Combine
import SwiftUI
import UIKit

@MainActor
@available(iOS 26.0, *)
func mountTextView(
    viewModel: NativeNoteEditorViewModel,
    isEditable: Bool = true,
    autofocusEnabled: Bool = false,
    attachToWindow: Bool = true,
    makeKeyAndVisible: Bool = false,
    formattingBarConfiguration: NoteFormattingBarConfiguration? = nil,
    formattingBarPresentation: NoteFormattingBarPresentation = .keyboardAccessory,
    makeTextView: (() -> UIKitNoteTextEditorSurface.AccessoryTextView)? = nil,
    maxContentWidth: CGFloat? = nil,
    width: CGFloat = 360,
    height: CGFloat = 320
) throws -> UITextView {
    let controller = UIHostingController<AnyView>(
        rootView: AnyView(
            UIKitNoteTextEditorSurface(
                viewModel: viewModel,
                maxContentWidth: maxContentWidth ?? width,
                isEditable: isEditable,
                shouldAutofocus: autofocusEnabled,
                formattingBarConfiguration: formattingBarConfiguration,
                formattingBarPresentation: formattingBarPresentation,
                makeTextView: makeTextView
            )
        )
    )
    let frame = CGRect(x: 0, y: 0, width: width, height: height)
    NotesDetailViewTestRetainer.hostingControllers.append(controller)
    if attachToWindow {
        let window = makeUIKitNoteTextEditorSurfaceHostingWindow(frame: frame)
        window.rootViewController = controller
        if makeKeyAndVisible {
            window.makeKeyAndVisible()
        } else {
            window.isHidden = false
        }
        NotesDetailViewTestRetainer.hostingWindows.append(window)
        controller.view.frame = frame
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
    } else {
        controller.loadViewIfNeeded()
        let hostView = UIView(frame: frame)
        hostView.addSubview(controller.view)
        controller.view.frame = hostView.bounds
        hostView.setNeedsLayout()
        hostView.layoutIfNeeded()
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
    }
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    return try XCTUnwrap(findTextView(in: controller.view))
}

@MainActor
func findTextView(in view: UIView) -> UITextView? {
    if let textView = view as? UITextView {
        return textView
    }
    for subview in view.subviews {
        if let match = findTextView(in: subview) {
            return match
        }
    }
    return nil
}

@MainActor
func makeUIKitNoteTextEditorSurfaceHostingWindow(frame: CGRect) -> UIWindow {
    guard let windowScene = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .first else {
        fatalError("Expected UIWindowScene for UIKit notes editor surface tests")
    }
    let window = UIWindow(windowScene: windowScene)
    window.frame = frame
    return window
}

@MainActor
func simulateUIKitSelectionChange(
    on textView: UITextView,
    to range: NSRange,
    settleDelay: TimeInterval = 0.01
) {
    textView.selectedRange = range
    RunLoop.main.run(until: Date().addingTimeInterval(settleDelay))
    textView.delegate?.textViewDidChangeSelection?(textView)
}

@MainActor
@available(iOS 26.0, *)
func simulateUIKitTouchSelectionChange(
    on textView: UITextView,
    to range: NSRange,
    settleDelay: TimeInterval = 0.01
) {
    simulateUIKitSelectionChange(on: textView, to: range, settleDelay: settleDelay)
}

@MainActor
@available(iOS 26.0, *)
func mountSurfaceHost(
    viewModel: NativeNoteEditorViewModel,
    presentationState: FormattingPresentationState,
    textView: ReloadTrackingAccessoryTextView,
    width: CGFloat = 360,
    height: CGFloat = 320
) -> UIHostingController<AnyView> {
    let controller = UIHostingController<AnyView>(
        rootView: AnyView(
            FormattingSurfaceHost(
                presentationState: presentationState,
                viewModel: viewModel,
                textView: textView
            )
        )
    )
    let frame = CGRect(x: 0, y: 0, width: width, height: height)
    let window = makeUIKitNoteTextEditorSurfaceHostingWindow(frame: frame)
    window.rootViewController = controller
    window.makeKeyAndVisible()
    controller.view.frame = frame
    controller.view.setNeedsLayout()
    controller.view.layoutIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    NotesDetailViewTestRetainer.hostingControllers.append(controller)
    NotesDetailViewTestRetainer.hostingWindows.append(window)
    return controller
}

@MainActor
@available(iOS 26.0, *)
final class FormattingPresentationState: ObservableObject {
    @Published var presentation: NoteFormattingBarPresentation

    init(_ presentation: NoteFormattingBarPresentation) {
        self.presentation = presentation
    }
}

@MainActor
@available(iOS 26.0, *)
final class ReloadTrackingAccessoryTextView: UIKitNoteTextEditorSurface.AccessoryTextView {
    private(set) var reloadInputViewsCallCount = 0

    override func reloadInputViews() {
        reloadInputViewsCallCount += 1
        super.reloadInputViews()
    }
}

@MainActor
@available(iOS 26.0, *)
final class AttributeMutationTrackingTextView: UIKitNoteTextEditorSurface.AccessoryTextView {
    private(set) var attributedTextAssignmentCount = 0

    override var attributedText: NSAttributedString! {
        didSet {
            attributedTextAssignmentCount += 1
        }
    }
}

@MainActor
@available(iOS 26.0, *)
final class ScrollTrackingAccessoryTextView: UIKitNoteTextEditorSurface.AccessoryTextView {
    private(set) var scrollRangeToVisibleCallCount = 0

    override func scrollRangeToVisible(_ range: NSRange) {
        scrollRangeToVisibleCallCount += 1
        super.scrollRangeToVisible(range)
    }
}

@MainActor
@available(iOS 26.0, *)
final class ViewportTrackingAccessoryTextView: UIKitNoteTextEditorSurface.AccessoryTextView {
    private(set) var recordedContentOffsets: [CGPoint] = []

    override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
        recordedContentOffsets.append(contentOffset)
        super.setContentOffset(contentOffset, animated: animated)
    }
}

@MainActor
@available(iOS 26.0, *)
struct FormattingSurfaceHost: View {
    @ObservedObject var presentationState: FormattingPresentationState
    let viewModel: NativeNoteEditorViewModel
    let textView: ReloadTrackingAccessoryTextView

    var body: some View {
        UIKitNoteTextEditorSurface(
            viewModel: viewModel,
            maxContentWidth: 360,
            isEditable: true,
            shouldAutofocus: true,
            formattingBarConfiguration: .disabled,
            formattingBarPresentation: presentationState.presentation,
            makeTextView: { textView }
        )
    }
}

@available(iOS 26.0, *)
func assertUIKitInsertionPointUTF16Offset(
    _ selection: AttributedTextSelection,
    in text: AttributedString,
    equals expectedOffset: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let string = String(text.characters)

    switch selection.indices(in: text) {
    case .insertionPoint(let index):
        let characterOffset = text.characters.distance(from: text.startIndex, to: index)
        let stringIndex = string.index(string.startIndex, offsetBy: characterOffset)
        XCTAssertEqual(stringIndex.utf16Offset(in: string), expectedOffset, file: file, line: line)
    case .ranges:
        XCTFail("Expected insertion point selection", file: file, line: line)
    }
}

@available(iOS 26.0, *)
func findEmbeddedFormattingBar(in view: UIView) -> UIKitNoteFormattingBar? {
    for subview in view.subviews {
        if let bar = subview as? UIKitNoteFormattingBar {
            return bar
        }
        if let nested = findEmbeddedFormattingBar(in: subview) {
            return nested
        }
    }

    return nil
}

#endif
