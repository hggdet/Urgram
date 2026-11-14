import Foundation
import SwiftSignalKit
import TelegramCore
import TelegramUIPreferences
import AccountContext

// URGRAM (build 20, Clean Edition): auto-archive inactive chats. When the
// user enables the rule in the Urgram settings section (autoArchiveInactiveDays
// = 30 or 90), once per cold start — throttled to once per 24 hours via a
// UserDefaults timestamp — every non-pinned chat in the root list whose
// latest message is older than the threshold is moved to the archive with
// the exact operation the swipe/context-menu archive actions use
// (engine.peers.updatePeersGroupIdInteractively with groupId .archive, see
// ChatContextMenus.swift / ChatListController.swift). The account's own
// Saved Messages chat is never archived. Driven from SharedAccountContext
// when the first account contexts become active.
public func urgramRunAutoArchiveIfNeeded(context: AccountContext) {
    let days = UrgramSettingsStore.shared.current.autoArchiveInactiveDays
    guard days > 0 else {
        return
    }
    let lastRunKey = "urgram_autoArchiveLastRun_v1"
    let now = Date().timeIntervalSince1970
    if now - UserDefaults.standard.double(forKey: lastRunKey) < 24.0 * 3600.0 {
        return
    }
    UserDefaults.standard.set(now, forKey: lastRunKey)

    let threshold = Int32(now) - days * 86400
    let _ = (context.engine.messages.chatList(group: .root, count: 1000)
    |> filter { !$0.isLoading }
    |> take(1)
    |> deliverOnMainQueue).start(next: { chatList in
        var peerIds: [EnginePeer.Id] = []
        for item in chatList.items {
            guard case let .chatList(index) = item.index, index.pinningIndex == nil else {
                continue
            }
            guard case let .chatList(peerId) = item.id, peerId != context.account.peerId else {
                continue
            }
            guard let topMessage = item.messages.first, topMessage.timestamp < threshold else {
                continue
            }
            peerIds.append(peerId)
        }
        if !peerIds.isEmpty {
            let _ = context.engine.peers.updatePeersGroupIdInteractively(peerIds: peerIds, groupId: .archive).startStandalone()
        }
    })
}
