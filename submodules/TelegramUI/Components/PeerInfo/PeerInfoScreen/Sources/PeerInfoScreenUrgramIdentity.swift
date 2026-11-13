import Foundation
import Display
import SwiftSignalKit
import TelegramCore
import TelegramUIPreferences
import AccountContext
import Postbox
import PhotoResources

// URGRAM: profile identity registry — the read side.
//
// When a user profile opens, the registry supergroup (@majqkq) is
// searched in the background for that user's identity record. A record
// counts only when the message author IS the profile owner and the first
// line is exactly `URG1|<ownerUserId>` (anti-forgery — see
// UrgramIdentityRegistry in TelegramUIPreferences); the newest valid
// record wins. Results are cached per user id for 24 hours
// (UrgramIdentityCacheStore). No record → the presentation is nil and
// the profile renders exactly as stock.
//
// Funnels: resolve via TelegramEnginePeers.resolvePeerByName; records
// via TelegramEngineMessages.searchMessages (remote per-peer search —
// the same call the Urgram chat export pages through); a cached banner
// is re-materialized via TelegramEngineMessages.downloadMessage
// (channels.getMessages by id under the hood).

struct UrgramIdentityPresentation {
    var card: UrgramIdentityCard
    var bannerImageSignal: Signal<(TransformImageArguments) -> DrawingContext?, NoError>?
    var bannerKey: String?
}

private func urgramResolveRegistryPeerId(context: AccountContext) -> Signal<PeerId?, NoError> {
    return context.engine.peers.resolvePeerByName(name: UrgramIdentityRegistry.username, referrer: nil)
    |> mapToSignal { result -> Signal<PeerId?, NoError> in
        switch result {
        case .progress:
            return .never()
        case let .result(peer):
            return .single(peer?.id)
        }
    }
    |> take(1)
}

private func urgramPresentation(card: UrgramIdentityCard, message: Message?, context: AccountContext) -> UrgramIdentityPresentation {
    var bannerImageSignal: Signal<(TransformImageArguments) -> DrawingContext?, NoError>?
    var bannerKey: String?
    if let message = message {
        for media in message.media {
            if let image = media as? TelegramMediaImage {
                bannerImageSignal = mediaGridMessagePhoto(account: context.account, userLocation: .peer(message.id.peerId), photoReference: .message(message: MessageReference(message), media: image), fullRepresentationSize: CGSize(width: 1280.0, height: 1280.0))
                bannerKey = "\(message.id.id):\(image.imageId.id)"
                break
            }
        }
    }
    return UrgramIdentityPresentation(card: card, bannerImageSignal: bannerImageSignal, bannerKey: bannerKey)
}

/// Serves a cached entry. A cached banner is re-fetched by message id so
/// its image can render without a full registry search.
private func urgramPresentationFromCache(context: AccountContext, entry: UrgramIdentityCacheEntry, ownerUserId: Int64) -> Signal<UrgramIdentityPresentation?, NoError> {
    guard let card = entry.card else {
        return .single(nil)
    }
    guard let bannerMessageId = entry.bannerMessageId else {
        return .single(urgramPresentation(card: card, message: nil, context: context))
    }
    return urgramResolveRegistryPeerId(context: context)
    |> mapToSignal { registryPeerId -> Signal<UrgramIdentityPresentation?, NoError> in
        guard let registryPeerId = registryPeerId else {
            return .single(urgramPresentation(card: card, message: nil, context: context))
        }
        return context.engine.messages.downloadMessage(messageId: EngineMessage.Id(peerId: registryPeerId, namespace: Namespaces.Message.Cloud, id: bannerMessageId))
        |> map { engineMessage -> UrgramIdentityPresentation? in
            guard let message = engineMessage?._asMessage(), let author = message.author, UrgramIdentityRegistry.parseRecord(text: message.text, authorUserId: author.id.id._internalGetInt64Value(), ownerUserId: ownerUserId) != nil else {
                // The cached banner message no longer validates (edited
                // or replaced): show the card without a banner.
                return urgramPresentation(card: card, message: nil, context: context)
            }
            return urgramPresentation(card: card, message: message, context: context)
        }
    }
}

func urgramIdentityPresentationSignal(context: AccountContext, ownerPeerId: PeerId) -> Signal<UrgramIdentityPresentation?, NoError> {
    let ownerUserId = ownerPeerId.id._internalGetInt64Value()
    let cachedEntry = UrgramIdentityCacheStore.shared.entry(for: ownerUserId)
    let now = Date().timeIntervalSince1970

    if let entry = cachedEntry, entry.isFresh(now: now) {
        return urgramPresentationFromCache(context: context, entry: entry, ownerUserId: ownerUserId)
    }

    let fallback: Signal<UrgramIdentityPresentation?, NoError>
    let hasStaleCard: Bool
    if let entry = cachedEntry, entry.card != nil {
        fallback = urgramPresentationFromCache(context: context, entry: entry, ownerUserId: ownerUserId)
        hasStaleCard = true
    } else {
        fallback = .single(nil)
        hasStaleCard = false
    }

    let network = urgramResolveRegistryPeerId(context: context)
    |> mapToSignal { registryPeerId -> Signal<UrgramIdentityPresentation?, NoError> in
        guard let registryPeerId = registryPeerId else {
            // Resolution failed (e.g. offline): keep whatever the cache
            // had instead of clearing the profile.
            return fallback
        }
        return context.engine.messages.searchMessages(location: .peer(peerId: registryPeerId, fromId: nil, tags: nil, reactions: nil, threadId: nil, minDate: nil, maxDate: nil), query: "\(ownerUserId)", state: nil, limit: 100)
        |> map { searchResult, _ -> UrgramIdentityPresentation? in
            let candidates = searchResult.messages.filter { message in
                guard let author = message.author, author.id.namespace == Namespaces.Peer.CloudUser else {
                    return false
                }
                return author.id.id._internalGetInt64Value() == ownerUserId
            }.sorted(by: { lhs, rhs in
                if lhs.timestamp != rhs.timestamp {
                    return lhs.timestamp > rhs.timestamp
                }
                return lhs.id.id > rhs.id.id
            })
            for message in candidates {
                guard let author = message.author else {
                    continue
                }
                if let card = UrgramIdentityRegistry.parseRecord(text: message.text, authorUserId: author.id.id._internalGetInt64Value(), ownerUserId: ownerUserId) {
                    let hasBanner = message.media.contains(where: { $0 is TelegramMediaImage })
                    UrgramIdentityCacheStore.shared.setEntry(UrgramIdentityCacheEntry(card: card, bannerMessageId: hasBanner ? message.id.id : nil, fetchedAt: Date().timeIntervalSince1970), for: ownerUserId)
                    return urgramPresentation(card: card, message: message, context: context)
                }
            }
            UrgramIdentityCacheStore.shared.setEntry(UrgramIdentityCacheEntry(card: nil, bannerMessageId: nil, fetchedAt: Date().timeIntervalSince1970), for: ownerUserId)
            return nil
        }
    }

    if hasStaleCard {
        return fallback |> then(network)
    }
    return network
}
