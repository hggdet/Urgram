import Foundation
import UIKit
import UniformTypeIdentifiers
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import AccountContext

// URGRAM (item 22): font picker — built-in OFL fonts (Tajawal, Cairo,
// IBM Plex Sans Arabic) plus importing a user .ttf/.otf file.

private final class UrgramFontSettingsControllerArguments {
    let selectChoice: (String) -> Void
    let importFont: () -> Void

    init(selectChoice: @escaping (String) -> Void, importFont: @escaping () -> Void) {
        self.selectChoice = selectChoice
        self.importFont = importFont
    }
}

private enum UrgramFontSettingsSection: Int32 {
    case fonts
    case custom
}

private enum UrgramFontSettingsControllerEntry: ItemListNodeEntry {
    case header
    case system(Bool)
    case builtIn(id: String, title: String, Bool)
    case customHeader
    case custom(String?, Bool)
    case importAction
    case footer

    var section: ItemListSectionId {
        switch self {
        case .header, .system, .builtIn:
            return UrgramFontSettingsSection.fonts.rawValue
        case .customHeader, .custom, .importAction, .footer:
            return UrgramFontSettingsSection.custom.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .header: return 0
        case .system: return 1
        case let .builtIn(id, _, _):
            switch id {
            case "tajawal": return 2
            case "cairo": return 3
            default: return 4
            }
        case .customHeader: return 10
        case .custom: return 11
        case .importAction: return 12
        case .footer: return 13
        }
    }

    static func <(lhs: UrgramFontSettingsControllerEntry, rhs: UrgramFontSettingsControllerEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! UrgramFontSettingsControllerArguments
        switch self {
        case .header:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: urgramText(presentationData, "App Font", "خط التطبيق"), sectionId: self.section)
        case let .system(checked):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: urgramText(presentationData, "System", "النظام"), style: .left, checked: checked, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.selectChoice("system")
            })
        case let .builtIn(id, title, checked):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: title, style: .left, checked: checked, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.selectChoice(id)
            })
        case .customHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: urgramText(presentationData, "Your Font", "خطك"), sectionId: self.section)
        case let .custom(name, checked):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: name ?? urgramText(presentationData, "Custom Font", "خط مخصص"), style: .left, checked: checked, enabled: name != nil, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.selectChoice("custom")
            })
        case .importAction:
            return ItemListActionItem(presentationData: presentationData, title: urgramText(presentationData, "Import Font File (.ttf / .otf)", "استيراد ملف خط (.ttf / .otf)"), kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.importFont()
            })
        case .footer:
            return ItemListTextItem(presentationData: presentationData, text: .plain(urgramText(presentationData, "The font applies to screens opened after the change; restart the app to apply it everywhere. Built-in fonts are open-source (SIL Open Font License).", "يسري الخط على الشاشات التي تُفتح بعد التغيير؛ أعد تشغيل التطبيق لتطبيقه في كل مكان. الخطوط المدمجة مفتوحة المصدر (رخصة SIL للخطوط المفتوحة).")), sectionId: self.section)
        }
    }
}

private func urgramFontSettingsControllerEntries(settings: UrgramSettings) -> [UrgramFontSettingsControllerEntry] {
    var entries: [UrgramFontSettingsControllerEntry] = []
    entries.append(.header)
    entries.append(.system(settings.fontChoice == "system"))
    for choice in UrgramFontManager.builtInChoices {
        entries.append(.builtIn(id: choice.id, title: choice.familyName, settings.fontChoice == choice.id))
    }
    entries.append(.customHeader)
    entries.append(.custom(settings.customFontName, settings.fontChoice == "custom"))
    entries.append(.importAction)
    entries.append(.footer)
    return entries
}

// URGRAM: retains the document-picker delegate while the picker is on screen.
private final class UrgramFontPickerDelegate: NSObject, UIDocumentPickerDelegate {
    let completion: (URL?) -> Void

    init(completion: @escaping (URL?) -> Void) {
        self.completion = completion
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        UrgramFontPickerDelegate.active = nil
        self.completion(urls.first)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        UrgramFontPickerDelegate.active = nil
        self.completion(nil)
    }

    static var active: UrgramFontPickerDelegate?
}

public func urgramFontSettingsController(context: AccountContext) -> ViewController {
    var presentPickerImpl: (() -> Void)?

    let arguments = UrgramFontSettingsControllerArguments(
        selectChoice: { choice in
            UrgramSettingsStore.shared.update { settings in
                settings.fontChoice = choice
            }
            // Reflect immediately for screens opened afterwards.
            Font.urgramCustomFamilyName = UrgramFontManager.resolvedFamilyName(settings: UrgramSettingsStore.shared.current)
        },
        importFont: {
            presentPickerImpl?()
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

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(presentationData.strings.primaryComponent.languageCode.hasPrefix("ar") ? "خط التطبيق" : "App Font"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: urgramFontSettingsControllerEntries(settings: settings), style: .blocks, animateChanges: true)

        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentPickerImpl = { [weak controller] in
        guard let controller = controller else {
            return
        }
        // URGRAM (fix, build 15): do NOT filter by UTType(filenameExtension:)
        // or .font — a sideloaded app declares no document/UTI types for
        // ttf/otf, so on iOS 27 the Files UI shows font files greyed out and
        // unselectable (reported on device). Open all files instead and let
        // UrgramFontManager.importFont validate the pick (it parses the
        // font's names and returns nil for anything that is not a font).
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data])
        let delegate = UrgramFontPickerDelegate(completion: { url in
            guard let url = url, let imported = UrgramFontManager.importFont(from: url) else {
                return
            }
            UrgramSettingsStore.shared.update { settings in
                settings.customFontFileName = imported.fileName
                settings.customFontName = imported.familyName
                settings.fontChoice = "custom"
            }
            Font.urgramCustomFamilyName = UrgramFontManager.resolvedFamilyName(settings: UrgramSettingsStore.shared.current)
        })
        UrgramFontPickerDelegate.active = delegate
        picker.delegate = delegate
        controller.present(picker, animated: true)
    }
    return controller
}
