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
import ItemListPeerItem

// URGRAM (hidden chats): the lock-gated list of chats the user hid from the
// main chat list (UrgramSettings.hiddenPeerIds, filtered in ChatListNode).
// The LocalAuthentication gate runs before this controller is pushed (see
// urgramOpenHiddenChats in UrgramSettingsController.swift). Tapping a row
// offers opening the chat or unhiding it.

private final class UrgramHiddenChatsControllerArguments {
    let context: AccountContext
    let peerAction: (EnginePeer) -> Void

    init(context: AccountContext, peerAction: @escaping (EnginePeer) -> Void) {
        self.context = context
        self.peerAction = peerAction
    }
}

private enum UrgramHiddenChatsSection: Int32 {
    case list
}

private enum UrgramHiddenChatsControllerEntry: ItemListNodeEntry {
    case header
    case empty
    case peer(EnginePeer, Int)
    case footer

    var section: ItemListSectionId {
        return UrgramHiddenChatsSection.list.rawValue
    }

    var stableId: Int32 {
        switch self {
        case .header: return 0
        case .empty: return 1
        case let .peer(_, index): return 10 + Int32(index)
        case .footer: return 100000
        }
    }

    static func <(lhs: UrgramHiddenChatsControllerEntry, rhs: UrgramHiddenChatsControllerEntry) -> Bool {
        if lhs.section != rhs.section {
            return lhs.section < rhs.section
        }
        return lhs.stableId < rhs.stableId
    }

    static func ==(lhs: UrgramHiddenChatsControllerEntry, rhs: UrgramHiddenChatsControllerEntry) -> Bool {
        switch lhs {
        case .header:
            if case .header = rhs { return true } else { return false }
        case .empty:
            if case .empty = rhs { return true } else { return false }
        case let .peer(lhsPeer, lhsIndex):
            if case let .peer(rhsPeer, rhsIndex) = rhs, lhsPeer.id == rhsPeer.id, lhsIndex == rhsIndex { return true } else { return false }
        case .footer:
            if case .footer = rhs { return true } else { return false }
        }
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! UrgramHiddenChatsControllerArguments
        switch self {
        case .header:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: urgramText(presentationData, "Hidden Chats", "المحادثات المخفية"), sectionId: self.section)
        case .empty:
            return ItemListTextItem(presentationData: presentationData, text: .plain(urgramText(presentationData, "No hidden chats. Long-press a chat in the chat list and choose \"Hide Chat\", or use Hide Chat in a chat's profile.", "لا محادثات مخفية. اضغط مطوّلًا على محادثة في قائمة المحادثات واختر «إخفاء المحادثة»، أو استخدم «إخفاء المحادثة» من ملف المحادثة.")), sectionId: self.section)
        case let .peer(peer, _):
            return ItemListPeerItem(presentationData: presentationData, systemStyle: .glass, dateTimeFormat: presentationData.dateTimeFormat, nameDisplayOrder: presentationData.nameDisplayOrder, context: arguments.context, peer: peer, presence: nil, text: .none, label: .none, editing: ItemListPeerItemEditing(editable: false, editing: false, revealed: nil), switchValue: nil, enabled: true, selectable: true, sectionId: self.section, action: {
                arguments.peerAction(peer)
            }, setPeerIdWithRevealedOptions: { _, _ in
                // Rows are non-editable (revealed: nil), so swipe-reveal never opens.
            }, removePeer: { id in
                // "Remove from this list" means unhide the chat.
                UrgramSettingsStore.shared.update { settings in
                    settings.hiddenPeerIds.removeAll(where: { $0 == id.toInt64() })
                }
            })
        case .footer:
            return ItemListTextItem(presentationData: presentationData, text: .plain(urgramText(presentationData, "Hidden chats are removed from the main chat list only. They still receive messages and appear in search.", "المحادثات المخفية تُزال من قائمة المحادثات الرئيسية فقط. ما زالت تستقبل الرسائل وتظهر في البحث.")), sectionId: self.section)
        }
    }
}

private func urgramHiddenChatsControllerEntries(peers: [EnginePeer]) -> [UrgramHiddenChatsControllerEntry] {
    var entries: [UrgramHiddenChatsControllerEntry] = []
    entries.append(.header)
    if peers.isEmpty {
        entries.append(.empty)
        return entries
    }
    for (index, peer) in peers.enumerated() {
        entries.append(.peer(peer, index))
    }
    entries.append(.footer)
    return entries
}

public func urgramHiddenChatsController(context: AccountContext) -> ViewController {
    var presentImpl: ((UIViewController) -> Void)?
    var navigateImpl: ((EnginePeer) -> Void)?

    let arguments = UrgramHiddenChatsControllerArguments(
        context: context,
        peerAction: { peer in
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let isArabic = presentationData.strings.primaryComponent.languageCode.hasPrefix("ar")
            let sheet = UIAlertController(title: peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder), message: nil, preferredStyle: .actionSheet)
            sheet.addAction(UIAlertAction(title: isArabic ? "فتح المحادثة" : "Open Chat", style: .default, handler: { _ in
                navigateImpl?(peer)
            }))
            sheet.addAction(UIAlertAction(title: isArabic ? "إظهار" : "Unhide", style: .default, handler: { _ in
                let packedId = peer.id.toInt64()
                UrgramSettingsStore.shared.update { settings in
                    settings.hiddenPeerIds.removeAll(where: { $0 == packedId })
                }
            }))
            sheet.addAction(UIAlertAction(title: presentationData.strings.Common_Cancel, style: .cancel))
            presentImpl?(sheet)
        }
    )

    let peersSignal = UrgramSettingsStore.shared.settingsSignal
    |> mapToSignal { settings -> Signal<[EnginePeer], NoError> in
        if settings.hiddenPeerIds.isEmpty {
            return .single([])
        }
        let signals = settings.hiddenPeerIds.map { packedId -> Signal<EnginePeer?, NoError> in
            return context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.RenderedPeer(id: PeerId(packedId)))
            |> map { renderedPeer -> EnginePeer? in
                return renderedPeer?.peer
            }
        }
        return combineLatest(queue: .mainQueue(), signals)
        |> map { peers -> [EnginePeer] in
            return peers.compactMap { $0 }
        }
    }

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        peersSignal
    )
    |> deliverOnMainQueue
    |> map { presentationData, peers -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var presentationData = presentationData
        let updatedTheme = presentationData.theme.withModalBlocksBackground()
        presentationData = presentationData.withUpdated(theme: updatedTheme)

        let isArabic = presentationData.strings.primaryComponent.languageCode.hasPrefix("ar")
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(isArabic ? "المحادثات المخفية" : "Hidden Chats"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: urgramHiddenChatsControllerEntries(peers: peers), style: .blocks, animateChanges: true)

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
    navigateImpl = { [weak controller] peer in
        guard let controller = controller, let navigationController = controller.navigationController as? NavigationController else {
            return
        }
        context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(peer), keepStack: .always, purposefulAction: {}, peekData: nil, forceOpenChat: true))
    }
    return controller
}
