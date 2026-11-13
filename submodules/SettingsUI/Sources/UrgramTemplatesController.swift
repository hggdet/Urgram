import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import AccountContext

// URGRAM (build 20, Clean Edition): quick-reply templates. The user saves
// reusable texts here; inside a chat they appear as the "Reply Templates"
// attachment-menu button (AttachmentButtonType.urgramTemplates, handled in
// ChatControllerOpenAttachmentMenu) which inserts the chosen text into the
// chat input via interfaceInteraction.updateTextInputStateAndMode.

private final class UrgramTemplatesSettingsControllerArguments {
    let addTemplate: () -> Void
    let templateAction: (Int) -> Void

    init(addTemplate: @escaping () -> Void, templateAction: @escaping (Int) -> Void) {
        self.addTemplate = addTemplate
        self.templateAction = templateAction
    }
}

private enum UrgramTemplatesControllerEntry: ItemListNodeEntry {
    case header
    case empty
    case template(Int, String)
    case addAction
    case footer

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        switch self {
        case .header: return 0
        case .empty: return 1
        case let .template(index, _): return 10 + Int32(index)
        case .addAction: return 10000
        case .footer: return 10001
        }
    }

    static func <(lhs: UrgramTemplatesControllerEntry, rhs: UrgramTemplatesControllerEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! UrgramTemplatesSettingsControllerArguments
        switch self {
        case .header:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: urgramText(presentationData, "Quick Replies", "ردود سريعة"), sectionId: self.section)
        case .empty:
            return ItemListTextItem(presentationData: presentationData, text: .plain(urgramText(presentationData, "No templates yet. Add your first one below.", "لا توجد قوالب بعد. أضف أول قالب من الأسفل.")), sectionId: self.section)
        case let .template(index, text):
            return ItemListDisclosureItem(presentationData: presentationData, title: text, label: "", sectionId: self.section, style: .blocks, action: {
                arguments.templateAction(index)
            })
        case .addAction:
            return ItemListActionItem(presentationData: presentationData, title: urgramText(presentationData, "Add Template", "إضافة قالب"), kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.addTemplate()
            })
        case .footer:
            return ItemListTextItem(presentationData: presentationData, text: .plain(urgramText(presentationData, "Templates appear in the attachment menu (paperclip) inside any chat — tap one to insert it into the message field. Tap a template here to delete it.", "تظهر القوالب في قائمة المرفقات (المشبك) داخل أي محادثة — اضغط قالبًا لإدراجه في حقل الرسالة. اضغط قالبًا هنا لحذفه.")), sectionId: self.section)
        }
    }
}

private func urgramTemplatesSettingsControllerEntries(settings: UrgramSettings) -> [UrgramTemplatesControllerEntry] {
    var entries: [UrgramTemplatesControllerEntry] = []
    entries.append(.header)
    if settings.replyTemplates.isEmpty {
        entries.append(.empty)
    } else {
        for (index, text) in settings.replyTemplates.enumerated() {
            entries.append(.template(index, text))
        }
    }
    entries.append(.addAction)
    entries.append(.footer)
    return entries
}

public func urgramTemplatesSettingsController(context: AccountContext) -> ViewController {
    var presentImpl: ((UIViewController) -> Void)?

    let arguments = UrgramTemplatesSettingsControllerArguments(
        addTemplate: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let isArabic = presentationData.strings.primaryComponent.languageCode.hasPrefix("ar")
            let alert = UIAlertController(title: isArabic ? "قالب جديد" : "New Template", message: nil, preferredStyle: .alert)
            alert.addTextField(configurationHandler: { textField in
                textField.placeholder = isArabic ? "نص القالب" : "Template text"
            })
            alert.addAction(UIAlertAction(title: isArabic ? "إلغاء" : "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: isArabic ? "حفظ" : "Save", style: .default, handler: { _ in
                let text = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !text.isEmpty {
                    UrgramSettingsStore.shared.update { settings in
                        settings.replyTemplates.append(text)
                    }
                }
            }))
            presentImpl?(alert)
        },
        templateAction: { index in
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let isArabic = presentationData.strings.primaryComponent.languageCode.hasPrefix("ar")
            let templates = UrgramSettingsStore.shared.current.replyTemplates
            guard index < templates.count else {
                return
            }
            let sheet = UIAlertController(title: templates[index], message: nil, preferredStyle: .actionSheet)
            sheet.addAction(UIAlertAction(title: isArabic ? "حذف" : "Delete", style: .destructive, handler: { _ in
                UrgramSettingsStore.shared.update { settings in
                    if index < settings.replyTemplates.count {
                        settings.replyTemplates.remove(at: index)
                    }
                }
            }))
            sheet.addAction(UIAlertAction(title: isArabic ? "إلغاء" : "Cancel", style: .cancel))
            presentImpl?(sheet)
        }
    )

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        UrgramSettingsStore.shared.settingsSignal
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var presentationData = presentationData
        let updatedTheme = presentationData.theme.withModalBlocksBackground()
        presentationData = presentationData.withUpdated(theme: updatedTheme)

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(presentationData.strings.primaryComponent.languageCode.hasPrefix("ar") ? "ردود سريعة" : "Quick Replies"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: urgramTemplatesSettingsControllerEntries(settings: settings), style: .blocks, animateChanges: true)

        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentImpl = { [weak controller] vc in
        guard let controller = controller else {
            return
        }
        if let popover = vc.popoverPresentationController {
            popover.sourceView = controller.view
            popover.sourceRect = CGRect(x: controller.view.bounds.midX, y: controller.view.bounds.maxY - 40.0, width: 0.0, height: 0.0)
            popover.permittedArrowDirections = []
        }
        controller.present(vc, animated: true)
    }
    return controller
}

// URGRAM: the in-chat template picker, presented from the attachment menu.
private final class UrgramTemplatePickerControllerArguments {
    let selectTemplate: (String) -> Void

    init(selectTemplate: @escaping (String) -> Void) {
        self.selectTemplate = selectTemplate
    }
}

private enum UrgramTemplatePickerControllerEntry: ItemListNodeEntry {
    case header
    case template(Int, String)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        switch self {
        case .header: return 0
        case let .template(index, _): return 10 + Int32(index)
        }
    }

    static func <(lhs: UrgramTemplatePickerControllerEntry, rhs: UrgramTemplatePickerControllerEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! UrgramTemplatePickerControllerArguments
        switch self {
        case .header:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: urgramText(presentationData, "Quick Replies", "ردود سريعة"), sectionId: self.section)
        case let .template(_, text):
            return ItemListDisclosureItem(presentationData: presentationData, title: text, label: "", sectionId: self.section, style: .blocks, action: {
                arguments.selectTemplate(text)
            })
        }
    }
}

public func urgramTemplatePickerController(context: AccountContext, completion: @escaping (String) -> Void) -> ViewController {
    var dismissImpl: (() -> Void)?

    let arguments = UrgramTemplatePickerControllerArguments(
        selectTemplate: { text in
            completion(text)
            dismissImpl?()
        }
    )

    let templates = UrgramSettingsStore.shared.current.replyTemplates

    let signal = context.sharedContext.presentationData
    |> deliverOnMainQueue
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var presentationData = presentationData
        let updatedTheme = presentationData.theme.withModalBlocksBackground()
        presentationData = presentationData.withUpdated(theme: updatedTheme)

        var entries: [UrgramTemplatePickerControllerEntry] = [.header]
        for (index, text) in templates.enumerated() {
            entries.append(.template(index, text))
        }

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(presentationData.strings.primaryComponent.languageCode.hasPrefix("ar") ? "ردود سريعة" : "Quick Replies"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false)

        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    dismissImpl = { [weak controller] in
        controller?.dismiss()
    }
    return controller
}
