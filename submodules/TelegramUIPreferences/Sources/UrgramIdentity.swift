import Foundation
import TelegramCore
import SwiftSignalKit

// URGRAM: profile identity registry (banner + extended ID card).
//
// Settled design: a public Telegram supergroup acts as the registry
// "server". A user's identity record is ONE post in that group: a photo
// message (the banner) — or a text-only message when there is no banner —
// whose caption/text first line is exactly `URG1|<ownerUserId>`, followed
// by a JSON object {"bio": ..., "links": [...]}. The newest valid record
// wins. A record counts only when the message author IS the profile owner
// (anti-forgery). End users never see the group; publishing joins, posts
// and leaves in the background.
//
// This file holds everything that is pure data: the card model, the
// record text make/parse pair, link URL building, and the per-user cache
// of resolved records (Codable, persisted through shared data exactly
// like UrgramSettings). The engine funnels (resolve/search/join/post) live
// in the UI modules that use them: SettingsUI (publish) and PeerInfoScreen
// (read), because they need Postbox message types.

public struct UrgramIdentityLink: Codable, Equatable {
    // instagram | tiktok | x | youtube | web | custom
    public var type: String
    public var value: String

    public init(type: String, value: String) {
        self.type = type
        self.value = value
    }
}

public struct UrgramIdentityCard: Codable, Equatable {
    public var bio: String
    public var links: [UrgramIdentityLink]

    public init(bio: String, links: [UrgramIdentityLink]) {
        self.bio = bio
        self.links = links
    }
}

public enum UrgramIdentityRegistry {
    /// The registry supergroup's public username (baked in by design).
    public static let username = "majqkq"

    /// Cache freshness window: a resolved record is refetched when older.
    public static let cacheLifetime: Double = 24.0 * 60.0 * 60.0

    public static func marker(for userId: Int64) -> String {
        return "URG1|\(userId)"
    }

    public static func recordText(ownerUserId: Int64, card: UrgramIdentityCard) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        let json: String
        if let data = try? encoder.encode(card), let string = String(data: data, encoding: .utf8) {
            json = string
        } else {
            json = "{\"bio\":\"\",\"links\":[]}"
        }
        return marker(for: ownerUserId) + "\n" + json
    }

    /// Parses a candidate record. Returns nil unless the author is the
    /// owner (anti-forgery), the first line is exactly the owner's marker,
    /// and the remainder decodes as a card.
    public static func parseRecord(text: String, authorUserId: Int64, ownerUserId: Int64) -> UrgramIdentityCard? {
        guard authorUserId == ownerUserId else {
            return nil
        }
        let marker = self.marker(for: ownerUserId)
        guard text.hasPrefix(marker) else {
            return nil
        }
        let rest = text.dropFirst(marker.count)
        guard rest.hasPrefix("\n") else {
            return nil
        }
        let jsonText = rest.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = jsonText.data(using: .utf8), let card = try? JSONDecoder().decode(UrgramIdentityCard.self, from: data) else {
            return nil
        }
        return card
    }

    /// Builds the tappable URL for a link row. Values are user-entered:
    /// bare handles for the social types, a URL (scheme optional) for
    /// web/custom. Returns nil when nothing openable can be formed.
    public static func linkURL(_ link: UrgramIdentityLink) -> String? {
        let raw = link.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            return nil
        }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return raw
        }
        let handle = raw.hasPrefix("@") ? String(raw.dropFirst()) : raw
        switch link.type {
        case "instagram":
            return handle.isEmpty ? nil : "https://instagram.com/\(handle)"
        case "tiktok":
            return handle.isEmpty ? nil : "https://www.tiktok.com/@\(handle)"
        case "x":
            return handle.isEmpty ? nil : "https://x.com/\(handle)"
        case "youtube":
            return handle.isEmpty ? nil : "https://www.youtube.com/@\(handle)"
        default:
            // web | custom: treat the value as a URL, defaulting to https.
            return "https://\(raw)"
        }
    }

    public static func linkTitle(_ type: String, isArabic: Bool) -> String {
        switch type {
        case "instagram":
            return "Instagram"
        case "tiktok":
            return "TikTok"
        case "x":
            return "X"
        case "youtube":
            return "YouTube"
        case "web":
            return isArabic ? "الموقع" : "Website"
        default:
            return isArabic ? "رابط" : "Link"
        }
    }
}

// MARK: - Resolved-record cache

public struct UrgramIdentityCacheEntry: Codable, Equatable {
    /// nil card (with a fetchedAt) is a negative entry: known no-record.
    public var card: UrgramIdentityCard?
    /// Message id (in the registry peer) of the newest record's banner
    /// photo, when the record carries one.
    public var bannerMessageId: Int32?
    public var fetchedAt: Double

    public init(card: UrgramIdentityCard?, bannerMessageId: Int32?, fetchedAt: Double) {
        self.card = card
        self.bannerMessageId = bannerMessageId
        self.fetchedAt = fetchedAt
    }

    public func isFresh(now: Double) -> Bool {
        return now - self.fetchedAt < UrgramIdentityRegistry.cacheLifetime
    }
}

public struct UrgramIdentityCache: Codable, Equatable {
    /// Keyed by the owner's plain user id as a string.
    public var entries: [String: UrgramIdentityCacheEntry]

    public init(entries: [String: UrgramIdentityCacheEntry]) {
        self.entries = entries
    }

    public static var empty: UrgramIdentityCache {
        return UrgramIdentityCache(entries: [:])
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)
        self.entries = try container.decodeIfPresent([String: UrgramIdentityCacheEntry].self, forKey: "entries") ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        try container.encode(self.entries, forKey: "entries")
    }
}

public func updateUrgramIdentityCacheInteractively(accountManager: AccountManager<TelegramAccountManagerTypes>, _ f: @escaping (UrgramIdentityCache) -> UrgramIdentityCache) -> Signal<Void, NoError> {
    return accountManager.transaction { transaction -> Void in
        transaction.updateSharedData(ApplicationSpecificSharedDataKeys.urgramIdentityCache, { entry in
            let current: UrgramIdentityCache
            if let entry = entry?.get(UrgramIdentityCache.self) {
                current = entry
            } else {
                current = UrgramIdentityCache.empty
            }
            return SharedPreferencesEntry(f(current))
        })
    }
}

/// In-memory mirror of the identity cache, seeded and kept in sync from
/// SharedAccountContext exactly like UrgramSettingsStore.
public final class UrgramIdentityCacheStore {
    public static let shared = UrgramIdentityCacheStore()

    private let value = Atomic<UrgramIdentityCache>(value: UrgramIdentityCache.empty)
    private var accountManager: AccountManager<TelegramAccountManagerTypes>?
    private var updateDisposable: Disposable?

    public var current: UrgramIdentityCache {
        return self.value.with { $0 }
    }

    public func entry(for userId: Int64) -> UrgramIdentityCacheEntry? {
        return self.current.entries["\(userId)"]
    }

    private init() {
    }

    public func attach(accountManager: AccountManager<TelegramAccountManagerTypes>) {
        self.accountManager = accountManager
    }

    public func applyExternal(_ cache: UrgramIdentityCache) {
        let _ = self.value.swap(cache)
    }

    public func setEntry(_ entry: UrgramIdentityCacheEntry?, for userId: Int64) {
        var updated = self.current
        if let entry = entry {
            updated.entries["\(userId)"] = entry
        } else {
            updated.entries.removeValue(forKey: "\(userId)")
        }
        self.applyExternal(updated)
        if let accountManager = self.accountManager {
            self.updateDisposable?.dispose()
            self.updateDisposable = updateUrgramIdentityCacheInteractively(accountManager: accountManager, { _ in
                return updated
            }).start()
        }
    }
}
