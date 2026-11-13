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

// URGRAM (item 3, viewer): screen for the local deleted-messages archive.
// The capture side lives in TelegramCore (UrgramMessageArchive.swift): while
// "Keep Deleted Messages" is on, `_internal_deleteMessages` stores the text
// and metadata of removed messages in a per-account preferences entry before
// deleting them. This screen reads them back (newest first) and can clear
// the archive. Text only — media files are not preserved.

private struct UrgramArchiveRow {
    let message: UrgramArchivedMessage
    let peerName: String?
}

// URGRAM: display name for an archived message's peer, resolved inside the
// read transaction (user name / @username, channel or group title).
private func urgramArchivePeerName(_ peer: Peer?) -> String? {
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

private final class UrgramArchiveControllerArguments {
    let clearArchive: () -> Void

    init(clearArchive: @escaping () -> Void) {
        self.clearArchive = clearArchive
    }
}

private enum UrgramArchiveSection: Int32 {
    case list
    case actions
}

private enum UrgramArchiveControllerEntry: ItemListNodeEntry {
    case header
    case empty
    case message(index: Int, text: String)
    case footer(Int)
    case clear

    var section: ItemListSectionId {
        switch self {
        case .header, .empty, .message, .footer:
            return UrgramArchiveSection.list.rawValue
        case .clear:
            return UrgramArchiveSection.actions.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .header: return 0
        case .empty: return 1
        case let .message(index, _): return 10 + Int32(index)
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
        case .header:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: urgramText(presentationData, "Deleted Messages Archive", "أرشيف الرسائل المحذوفة"), sectionId: self.section)
        case .empty:
            return ItemListTextItem(presentationData: presentationData, text: .plain(urgramText(presentationData, "Nothing here yet. When \"Keep Deleted Messages\" is on, messages that get deleted in your chats are kept here so you can still read them.", "لا شيء هنا بعد. عند تفعيل «الاحتفاظ بالرسائل المحذوفة»، تُحفظ هنا الرسائل التي تُحذف من محادثاتك حتى تبقى قادرًا على قراءتها.")), sectionId: self.section)
        case let .message(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .footer(total):
            return ItemListTextItem(presentationData: presentationData, text: .plain(urgramText(presentationData, "The archive keeps at most 1,000 messages, on this device only. Only text is stored — photos and files are not preserved. Showing the newest \(total).", "يحتفظ الأرشيف بما يصل إلى ١٠٠٠ رسالة، على هذا الجهاز فقط. يُحفظ النص فقط — الصور والملفات لا تُحفظ. تُعرض الأحدث: \(total).")), sectionId: self.section)
        case .clear:
            return ItemListActionItem(presentationData: presentationData, title: urgramText(presentationData, "Clear Archive", "مسح الأرشيف"), kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.clearArchive()
            })
        }
    }
}

private func urgramArchiveMediaLabel(_ mediaKind: String, isArabic: Bool) -> String {
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

private func urgramArchiveControllerEntries(rows: [UrgramArchiveRow], isArabic: Bool) -> [UrgramArchiveControllerEntry] {
    var entries: [UrgramArchiveControllerEntry] = []
    entries.append(.header)
    if rows.isEmpty {
        entries.append(.empty)
        return entries
    }
    let dateFormatter = DateFormatter()
    dateFormatter.dateStyle = .medium
    dateFormatter.timeStyle = .short
    let displayed = Array(rows.prefix(300))
    for (index, row) in displayed.enumerated() {
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
        entries.append(.message(index: index, text: "\(name) • \(date)\n\(body)"))
    }
    entries.append(.footer(displayed.count))
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
            }.startStandalone()
            reloadCounter += 1
            reloadPromise.set(reloadCounter)
        }
    )

    let archiveSignal = reloadPromise.get()
    |> mapToSignal { _ -> Signal<[UrgramArchiveRow], NoError> in
        return context.account.postbox.transaction { transaction -> [UrgramArchiveRow] in
            return urgramArchivedMessages(transaction: transaction).reversed().map { message in
                let peerName = urgramArchivePeerName(transaction.getPeer(PeerId(message.peerId)))
                return UrgramArchiveRow(message: message, peerName: peerName)
            }
        }
    }

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        archiveSignal
    )
    |> deliverOnMainQueue
    |> map { presentationData, rows -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var presentationData = presentationData
        let updatedTheme = presentationData.theme.withModalBlocksBackground()
        presentationData = presentationData.withUpdated(theme: updatedTheme)

        let isArabic = presentationData.strings.primaryComponent.languageCode.hasPrefix("ar")
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(isArabic ? "الرسائل المحذوفة" : "Deleted Messages"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: urgramArchiveControllerEntries(rows: rows, isArabic: isArabic), style: .blocks, animateChanges: true)

        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    return controller
}
