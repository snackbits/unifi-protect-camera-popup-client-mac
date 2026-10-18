import AppCore
import AppKit
import SwiftUI

/// Template pop-up field ("Oben rechts ⌃⌄"): 12 pt, padding 3/10, radius 6, `chipBorder`, `field`.
/// The field is drawn 1:1; the list that opens is the native menu.
struct PopUpField<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    @StateObject private var anchor = ViewAnchor()

    private var title: String {
        options.first { $0.value == selection }?.title ?? ""
    }

    var body: some View {
        Button(action: present) {
            HStack(spacing: 6) {
                Text(title).lineLimit(1)
                TemplateIcon.chevronUpDown.image(size: 9)
            }
            .font(.system(size: 12))
            .foregroundStyle(Tokens.fg.color)
            .padding(.vertical, 3)
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 6).fill(Tokens.field.color))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Tokens.chipBorder.color, lineWidth: 1))
            .contentShape(Rectangle())
            .background(AnchorView(anchor: anchor))
        }
        .buttonStyle(.plain)
        .accessibilityValue(title)
    }

    private func present() {
        guard let view = anchor.view else { return }
        MenuPresenter.popUp(
            titles: options.map { $0.title },
            selectedIndex: options.firstIndex { $0.value == selection },
            in: view
        ) { index in
            selection = options[index].value
        }
    }
}

/// Holds the AppKit view a menu is positioned at.
final class ViewAnchor: ObservableObject {
    weak var view: NSView?
}

struct AnchorView: NSViewRepresentable {
    let anchor: ViewAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchor.view = nsView
    }
}

@MainActor
enum MenuPresenter {
    /// Shows a native menu with the selected item over `view` (like a pop-up button).
    static func popUp(titles: [String], selectedIndex: Int?, in view: NSView, onSelect: @escaping (Int) -> Void) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let handler = MenuHandler(onSelect)
        for (index, title) in titles.enumerated() {
            let item = NSMenuItem(title: title, action: #selector(MenuHandler.pick(_:)), keyEquivalent: "")
            item.target = handler
            item.tag = index
            item.state = index == selectedIndex ? .on : .off
            menu.addItem(item)
        }
        let positioning = selectedIndex.flatMap { menu.item(at: $0) }
        let origin = NSPoint(x: 0, y: view.isFlipped ? 0 : view.bounds.height)
        menu.popUp(positioning: positioning, at: origin, in: view)
        withExtendedLifetime(handler) {}
    }
}

private final class MenuHandler: NSObject {
    private let onSelect: (Int) -> Void

    init(_ onSelect: @escaping (Int) -> Void) {
        self.onSelect = onSelect
    }

    @objc func pick(_ sender: NSMenuItem) {
        onSelect(sender.tag)
    }
}
