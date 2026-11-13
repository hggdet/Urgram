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

// URGRAM (item 15, viewer): the bookmarks list. Bookmarks are text
// snapshots saved from the message context menu ("Bookmark"); the store
// lives in TelegramCore (UrgramBookmarks.swift). Rows reuse the archive
// viewer's formatting helpers from UrgramArchiveController.swift.

private final class UrgramBookmarksControllerArguments {
    let clearBookmarks: () -> Void

    init(clearBookmarks: @escaping () -> Void) {
        self.clearBookmarks = clearBookmarks
    }
}

private enum UrgramBookmarksSection: Int32 {
    case list
    case actions
}

private enum UrgramBookmarksControllerEntry: ItemListNodeEntry {
    case header
    case empty
    case bookmark(index: Int, text: String)
    case footer
    case clear

    var section: ItemListSectionId {
        switch self {
        case .header, .empty, .bookmark, .footer:
            return UrgramBookmarksSection.list.rawValue
        case .clear:
            return UrgramBookmarksSection.actions.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .header: return 0
        case .empty: return 1
        case let .bookmark(index, _): return 10 + Int32(index)
        case .footer: return 100000
        case .clear: return 0
        }
    }

    static func <(lhs: UrgramBookmarksControllerEntry, rhs: UrgramBookmarksControllerEntry) -> Bool {
        if lhs.section != rhs.section {
            return lhs.section < rhs.section
        }
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! UrgramBookmarksControllerArguments
        switch self {
        case .header:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: urgramText(presentationData, "Bookmarks", "الإشارات المرجعية"), sectionId: self.section)
        case .empty:
            return ItemListTextItem(presentationData: presentationData, text: .plain(urgramText(presentationData, "No bookmarks yet. Long-press any message and choose \"Bookmark\" to keep a copy of its text here.", "لا إشارات مرجعية بعد. اضغط مطوّلًا على أي رسالة واختر «إشارة مرجعية» لحفظ نسخة من نصها هنا.")), sectionId: self.section)
        case let .bookmark(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case .footer:
            return ItemListTextItem(presentationData: presentationData, text: .plain(urgramText(presentationData, "Bookmarks are kept on this device only (at most 500). Only text is stored — photos and files are not preserved.", "تُحفظ الإشارات المرجعية على هذا الجهاز فقط (٥٠٠ كحد أقصى). يُحفظ النص فقط — الصور والملفات لا تُحفظ.")), sectionId: self.section)
        case .clear:
            return ItemListActionItem(presentationData: presentationData, title: urgramText(presentationData, "Clear Bookmarks", "مسح الإشارات المرجعية"), kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.clearBookmarks()
            })
        }
    }
}

private func urgramBookmarksControllerEntries(rows: [UrgramArchiveRow], isArabic: Bool) -> [UrgramBookmarksControllerEntry] {
    var entries: [UrgramBookmarksControllerEntry] = []
    entries.append(.header)
    if rows.isEmpty {
        entries.append(.empty)
        return entries
    }
    let dateFormatter = DateFormatter()
    dateFormatter.dateStyle = .medium
    dateFormatter.timeStyle = .short
    for (index, row) in rows.prefix(300).enumerated() {
        entries.append(.bookmark(index: index, text: urgramArchiveRowText(row, dateFormatter: dateFormatter, isArabic: isArabic)))
    }
    entries.append(.footer)
    entries.append(.clear)
    return entries
}

public func urgramBookmarksController(context: AccountContext) -> ViewController {
    let reloadPromise = ValuePromise<Int>(0)
    var reloadCounter = 0

    let arguments = UrgramBookmarksControllerArguments(
        clearBookmarks: {
            let _ = context.account.postbox.transaction { transaction -> Void in
                urgramClearBookmarks(transaction: transaction)
            }.startStandalone()
            reloadCounter += 1
            reloadPromise.set(reloadCounter)
        }
    )

    let bookmarksSignal = reloadPromise.get()
    |> mapToSignal { _ -> Signal<[UrgramArchiveRow], NoError> in
        return context.account.postbox.transaction { transaction -> [UrgramArchiveRow] in
            return urgramBookmarks(transaction: transaction).reversed().map { message in
                return UrgramArchiveRow(message: message, peerName: urgramArchivePeerName(transaction.getPeer(PeerId(message.peerId))))
            }
        }
    }

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        bookmarksSignal
    )
    |> deliverOnMainQueue
    |> map { presentationData, rows -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var presentationData = presentationData
        let updatedTheme = presentationData.theme.withModalBlocksBackground()
        presentationData = presentationData.withUpdated(theme: updatedTheme)

        let isArabic = presentationData.strings.primaryComponent.languageCode.hasPrefix("ar")
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(isArabic ? "الإشارات المرجعية" : "Bookmarks"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: urgramBookmarksControllerEntries(rows: rows, isArabic: isArabic), style: .blocks, animateChanges: true)

        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    return controller
}
