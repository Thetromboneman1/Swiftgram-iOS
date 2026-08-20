#if canImport(UIKit)
import UIKit

/// Rich edit-menu items appended to the system `suggestedActions`. A custom UITextInput view that avoids
/// UITextInteraction does NOT get Look Up / Share / a Format submenu for free (those are text-services
/// features of UITextView/UITextInteraction/WebKit/PDFKit), so we add them ourselves and present modals
/// from the owning view controller found via the responder chain. Writing Tools, when the OS surfaces it,
/// rides in `suggestedActions`.
@available(iOS 13.0, *)
extension DocumentCanvasView {
    /// Append our items to the system-suggested actions (which carry Cut/Copy/Paste/Select and, on a
    /// capable device, Writing Tools). iOS 16+ only — the `UIEditMenuInteraction` delegate hook; the iOS
    /// 13–15 `UIMenuController` fallback builds its flat items in DocumentCanvasView+EditMenu.
    @available(iOS 16.0, *)
    func editMenuInteraction(_ interaction: UIEditMenuInteraction,
                             menuFor configuration: UIEditMenuConfiguration,
                             suggestedActions: [UIMenuElement]) -> UIMenu? {
        if pendingSpellingMenu != nil { return UIMenu(children: spellingGuessMenuElements()) }
        if imageSelection != nil { return nil }   // media atom: no edit menu — Spoiler/Delete live in the host's "•••" media menu; delete is also Backspace on the selected atom
        let defaults = suggestedActions + customEditMenuElements()
        if selFrom < selTo, let provider = hostContextMenuItemsProvider {
            return UIMenu(children: provider(defaults))
        }
        return UIMenu(children: defaults)
    }

    /// Our custom elements for the current selection — empty when the selection is collapsed.
    func customEditMenuElements() -> [UIMenuElement] {
        guard selFrom < selTo else { return [] }
        var elements: [UIMenuElement] = [
            formatMenu(),
            UIAction(title: "Look Up") { [weak self] _ in self?.presentLookUp() },
        ]
        elements.append(UIAction(title: "Share") { [weak self] _ in self?.presentShare() })
        return elements
    }

    private func formatMenu() -> UIMenu {
        UIMenu(title: "Format", children: [
            UIAction(title: "Bold") { [weak self] _ in self?.toggleBold() },
            UIAction(title: "Italic") { [weak self] _ in self?.toggleItalic() },
            UIAction(title: "Underline") { [weak self] _ in self?.toggleUnderline() },
        ])
    }

    /// The nearest view controller up the responder chain (to present Look Up / Share modals).
    func owningViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let r = responder {
            if let vc = r as? UIViewController { return vc }
            responder = r.next
        }
        return nil
    }

    /// The selection's plain text (nil when collapsed/empty).
    private func selectedPlainText() -> String? {
        guard selFrom < selTo, let range = selectedTextRange, let t = text(in: range), !t.isEmpty else { return nil }
        return t
    }

    func presentLookUp() {
        guard let term = selectedPlainText(), let vc = owningViewController() else { return }
        vc.present(UIReferenceLibraryViewController(term: term), animated: true)
    }

    func presentShare() {
        guard let term = selectedPlainText(), let vc = owningViewController() else { return }
        let activity = UIActivityViewController(activityItems: [term], applicationActivities: nil)
        if let pop = activity.popoverPresentationController {   // iPad: anchor to the selection
            pop.sourceView = self
            pop.sourceRect = selectionRects(globalFrom: selFrom, globalTo: selTo).first ?? bounds
        }
        vc.present(activity, animated: true)
    }
}

#endif
