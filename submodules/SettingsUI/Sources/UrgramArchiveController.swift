import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import Postbox
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import AccountContext

// URGRAM (item 3, viewer): screen for the local message archive — messages
// that were deleted (captured by `_internal_deleteMessages`) and the
// pre-edit originals of edited messages (captured by
// StateReplay.applyEditMessage). Both stores live in TelegramCore
// (UrgramMessageArchive.swift) as per-account preferences entries. This
// screen reads them back (newest first) and can clear both. Text only —
// media files are not preserved.

struct UrgramArchiveRow {
    let message: UrgramArchivedMessage
    let peerName: String?
}

// URGRAM: display name for an archived message's peer, resolved inside the
// read transaction (user name / @username, channel or group title).
func urgramArchivePeerName(_ peer: Peer?) -> String? {
    guard let peer = peer else {
        return nil
    }
    if let user = peer as? TelegramUser {
        let name = [user.firstName, user.lastName].compactMap { $0 }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        if !name.isEmpty {
            return name
        }
        if let username = user.username, !username.isEmpty {
            return "@\(username)"
        }
        return nil
    } else if let channel = peer as? TelegramChannel {
        return channel.title
    } else if let group = peer as? TelegramGroup {
        return group.title
    }
    return nil
}

func urgramArchiveMediaLabel(_ mediaKind: String, isArabic: Bool) -> String {
    if mediaKind.contains("Image") {
        return isArabic ? "[صورة]" : "[Photo]"
    } else if mediaKind.contains("Video") || mediaKind.contains("InstantVideo") {
        return isArabic ? "[فيديو]" : "[Video]"
    } else if mediaKind.contains("Audio") || mediaKind.contains("Voice") {
        return isArabic ? "[رسالة صوتية]" : "[Voice message]"
    } else if mediaKind.contains("File") {
        return isArabic ? "[ملف]" : "[File]"
    } else if mediaKind.contains("Sticker") {
        return isArabic ? "[ملصق]" : "[Sticker]"
    } else if mediaKind.contains("Location") {
        return isArabic ? "[موقع]" : "[Location]"
    } else if mediaKind.isEmpty {
        return isArabic ? "[رسالة بدون نص]" : "[Message without text]"
    }
    return isArabic ? "[وسائط]" : "[Media]"
}

func urgramArchiveRowText(_ row: UrgramArchiveRow, dateFormatter: DateFormatter, isArabic: Bool) -> String {
    let message = row.message
    let name: String
    if let peerName = row.peerName, !peerName.isEmpty {
        name = peerName
    } else if message.isOutgoing {
        name = isArabic ? "أنت" : "You"
    } else {
        name = isArabic ? "غير معروف" : "Unknown"
    }
    let date = dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(message.timestamp)))
    let body = message.text.isEmpty ? urgramArchiveMediaLabel(message.mediaKind, isArabic: isArabic) : message.text
    return "\(name) • \(date)\n\(body)"
}

private final class UrgramArchiveControllerArguments {
    let clearArchive: () -> Void

    init(clearArchive: @escaping () -> Void) {
        self.clearArchive = clearArchive
    }
}

private enum UrgramArchiveSection: Int32 {
    case deleted
    case edited
    case actions
}

private enum UrgramArchiveControllerEntry: ItemListNodeEntry {
    case deletedHeader
    case deletedEmpty
    case deletedMessage(index: Int, text: String)
    case editedHeader
    case editedEmpty
    case editedMessage(index: Int, text: String)
    case footer
    case clear

    var section: ItemListSectionId {
        switch self {
        case .deletedHeader, .deletedEmpty, .deletedMessage:
            return UrgramArchiveSection.deleted.rawValue
        case .editedHeader, .editedEmpty, .editedMessage, .footer:
            return UrgramArchiveSection.edited.rawValue
        case .clear:
            return UrgramArchiveSection.actions.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .deletedHeader: return 0
        case .deletedEmpty: return 1
        case let .deletedMessage(index, _): return 10 + Int32(index)
        case .editedHeader: return 0
        case .editedEmpty: return 1
        case let .editedMessage(index, _): return 10 + Int32(index)
        case .footer: return 100000
        case .clear: return 0
        }
    }

    static func <(lhs: UrgramArchiveControllerEntry, rhs: UrgramArchiveControllerEntry) -> Bool {
        if lhs.section != rhs.section {
            return lhs.section < rhs.section
        }
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! UrgramArchiveControllerArguments
        switch self {
        case .deletedHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: urgramText(presentationData, "Deleted Messages", "الرسائل المحذوفة"), sectionId: self.section)
        case .deletedEmpty:
            return ItemListTextItem(presentationData: presentationData, text: .plain(urgramText(presentationData, "Nothing here yet. When \"Keep Deleted Messages\" is on, messages that get deleted in your chats are kept here so you can still read them.", "لا شيء هنا بعد. عند تفعيل «الاحتفاظ بالرسائل المحذوفة»، تُحفظ هنا الرسائل التي تُحذف من محادثاتك حتى تبقى قادرًا على قراءتها.")), sectionId: self.section)
        case let .deletedMessage(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case .editedHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: urgramText(presentationData, "Originals Before Editing", "النصوص الأصلية قبل التعديل"), sectionId: self.section)
        case .editedEmpty:
            return ItemListTextItem(presentationData: presentationData, text: .plain(urgramText(presentationData, "Nothing here yet. When \"Keep Original Text of Edited Messages\" is on, the text a message had before it was edited is kept here.", "لا شيء هنا بعد. عند تفعيل «الاحتفاظ بالنص الأصلي للرسائل المعدّلة»، يُحفظ هنا النص الذي كانت عليه الرسالة قبل تعديلها.")), sectionId: self.section)
        case let .editedMessage(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case .footer:
            return ItemListTextItem(presentationData: presentationData, text: .plain(urgramText(presentationData, "Each list keeps at most 1,000 messages, on this device only. Only text is stored — photos and files are not preserved.", "تحتفظ كل قائمة بما يصل إلى ١٠٠٠ رسالة، على هذا الجهاز فقط. يُحفظ النص فقط — الصور والملفات لا تُحفظ.")), sectionId: self.section)
        case .clear:
            return ItemListActionItem(presentationData: presentationData, title: urgramText(presentationData, "Clear Archive", "مسح الأرشيف"), kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.clearArchive()
            })
        }
    }
}

private func urgramArchiveControllerEntries(deleted: [UrgramArchiveRow], edited: [UrgramArchiveRow], isArabic: Bool) -> [UrgramArchiveControllerEntry] {
    let dateFormatter = DateFormatter()
    dateFormatter.dateStyle = .medium
    dateFormatter.timeStyle = .short

    var entries: [UrgramArchiveControllerEntry] = []
    entries.append(.deletedHeader)
    if deleted.isEmpty {
        entries.append(.deletedEmpty)
    } else {
        for (index, row) in deleted.prefix(300).enumerated() {
            entries.append(.deletedMessage(index: index, text: urgramArchiveRowText(row, dateFormatter: dateFormatter, isArabic: isArabic)))
        }
    }
    entries.append(.editedHeader)
    if edited.isEmpty {
        entries.append(.editedEmpty)
    } else {
        for (index, row) in edited.prefix(300).enumerated() {
            entries.append(.editedMessage(index: index, text: urgramArchiveRowText(row, dateFormatter: dateFormatter, isArabic: isArabic)))
        }
    }
    entries.append(.footer)
    entries.append(.clear)
    return entries
}

public func urgramArchiveController(context: AccountContext) -> ViewController {
    let reloadPromise = ValuePromise<Int>(0)
    var reloadCounter = 0

    let arguments = UrgramArchiveControllerArguments(
        clearArchive: {
            let _ = context.account.postbox.transaction { transaction -> Void in
                urgramClearMessageArchive(transaction: transaction)
                urgramClearEditedOriginals(transaction: transaction)
            }.startStandalone()
            reloadCounter += 1
            reloadPromise.set(reloadCounter)
        }
    )

    let archiveSignal = reloadPromise.get()
    |> mapToSignal { _ -> Signal<(deleted: [UrgramArchiveRow], edited: [UrgramArchiveRow]), NoError> in
        return context.account.postbox.transaction { transaction -> (deleted: [UrgramArchiveRow], edited: [UrgramArchiveRow]) in
            let deleted = urgramArchivedMessages(transaction: transaction).reversed().map { message in
                return UrgramArchiveRow(message: message, peerName: urgramArchivePeerName(transaction.getPeer(PeerId(message.peerId))))
            }
            let edited = urgramEditedOriginals(transaction: transaction).reversed().map { message in
                return UrgramArchiveRow(message: message, peerName: urgramArchivePeerName(transaction.getPeer(PeerId(message.peerId))))
            }
            return (deleted: deleted, edited: edited)
        }
    }

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        archiveSignal
    )
    |> deliverOnMainQueue
    |> map { presentationData, archive -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var presentationData = presentationData
        let updatedTheme = presentationData.theme.withModalBlocksBackground()
        presentationData = presentationData.withUpdated(theme: updatedTheme)

        let isArabic = presentationData.strings.primaryComponent.languageCode.hasPrefix("ar")
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(isArabic ? "أرشيف الرسائل" : "Message Archive"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: urgramArchiveControllerEntries(deleted: archive.deleted, edited: archive.edited, isArabic: isArabic), style: .blocks, animateChanges: true)

        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    return controller
}
