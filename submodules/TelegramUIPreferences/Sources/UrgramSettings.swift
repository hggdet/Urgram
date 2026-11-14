import Foundation
import TelegramCore
import SwiftSignalKit

// URGRAM: settings model + store for all Urgram fork features.
// Storage follows the codebase's shared-data convention (same as
// TranslationSettings / ExperimentalUISettings): one Codable struct persisted
// through `AccountManager` shared data under
// `ApplicationSpecificSharedDataKeys.urgramSettings`, shared across accounts.
// `UrgramSettingsStore` is the single writer: it persists through shared data,
// keeps an in-memory value for synchronous readers, and mirrors the flags that
// gate TelegramCore operations into `UrgramFeatureHooks` (TelegramCore cannot
// import this module).
// URGRAM (build 20, Urgram Studio): one saved appearance design. Only
// parameters that map to real runtime theme fields are stored — see
// URGRAM.md "Build 20" for the verified mapping and what was excluded.
// Colors are ARGB values (same convention as PresentationThemeAccentColor
// presets), stored as Int32 bit patterns (build 29: Postbox's adapted
// Codable containers natively support only Bool / String / Double / Int32 /
// Int64 in keyed containers — a UInt32 field encodes as a generic object
// box whose decode throws, and one throwing field aborted the WHOLE
// settings decode, resetting every Urgram setting on relaunch). Convert
// with UInt32(bitPattern:) / Int32(bitPattern:) at color-construction
// sites. `bubbleColors` empty means "derive outgoing bubble colors from
// the accent color"; one entry is a solid fill; two entries are a gradient.
// URGRAM (Studio V2): the design also carries the other verified
// PresentationThemeSettings parameters — chat/list font sizes
// (PresentationFontSize raw values; -1 means "follow the system size",
// nil means the design does not touch font sizes), large emoji, bubble
// corner merging and the serif message font. All new fields are optional
// so build 20–23 design files keep decoding unchanged.
// URGRAM (build 29): fault-isolated field decoding. If one field of a
// stored blob fails to decode (e.g. a build ≤28 blob whose UInt32 / Int
// fields the Postbox adapted containers cannot read back), that field
// alone falls back to its default instead of aborting the whole decode —
// previously a single bad field made `PreferencesEntry.get` return nil
// and silently reset ALL Urgram settings on every relaunch.
private func urgramDecodeField<T>(_ body: () throws -> T?, fallback: T) -> T {
    do {
        if let value = try body() {
            return value
        }
    } catch {
    }
    return fallback
}

private func urgramDecodeOptionalField<T>(_ body: () throws -> T?) -> T? {
    do {
        return try body()
    } catch {
        return nil
    }
}

// URGRAM (build 29): one ARGB color field, stored as an Int32 bit pattern.
// Falls back to reading a legacy UInt32 value (build ≤28 .urgramtheme JSON
// files store plain unsigned numbers) and converting it, so old exported
// designs keep their colors.
private func urgramDecodeArgbField(_ container: KeyedDecodingContainer<StringCodingKey>, _ key: StringCodingKey) -> Int32? {
    // Each attempt is individually non-fatal: an Int32 read of a legacy
    // unsigned JSON number throws (out of range), and that must not skip
    // the UInt32 attempt.
    if let value = try? container.decodeIfPresent(Int32.self, forKey: key), let value = value {
        return value
    }
    if let legacyValue = try? container.decodeIfPresent(UInt32.self, forKey: key), let legacyValue = legacyValue {
        return Int32(bitPattern: legacyValue)
    }
    return nil
}

private func urgramDecodeArgbArrayField(_ container: KeyedDecodingContainer<StringCodingKey>, _ key: StringCodingKey) -> [Int32]? {
    if let values = try? container.decodeIfPresent([Int32].self, forKey: key), let values = values {
        return values
    }
    if let legacyValues = try? container.decodeIfPresent([UInt32].self, forKey: key), let legacyValues = legacyValues {
        return legacyValues.map { Int32(bitPattern: $0) }
    }
    return nil
}

public struct UrgramThemeDesign: Codable, Equatable {
    public var id: String
    public var name: String
    public var accentColor: Int32
    public var bubbleColors: [Int32]
    // 0 = keep the theme's default chat wallpaper, 1 = solid color, 2 = gradient
    public var wallpaperMode: Int32
    public var wallpaperColorA: Int32
    public var wallpaperColorB: Int32
    public var bubbleRadius: Int32
    public var chatFontSize: Int32?
    public var listFontSize: Int32?
    public var largeEmoji: Bool?
    public var mergeBubbleCorners: Bool?
    public var serifMessageFont: Bool?

    public init(
        id: String,
        name: String,
        accentColor: Int32,
        bubbleColors: [Int32],
        wallpaperMode: Int32,
        wallpaperColorA: Int32,
        wallpaperColorB: Int32,
        bubbleRadius: Int32,
        chatFontSize: Int32? = nil,
        listFontSize: Int32? = nil,
        largeEmoji: Bool? = nil,
        mergeBubbleCorners: Bool? = nil,
        serifMessageFont: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.accentColor = accentColor
        self.bubbleColors = bubbleColors
        self.wallpaperMode = wallpaperMode
        self.wallpaperColorA = wallpaperColorA
        self.wallpaperColorB = wallpaperColorB
        self.bubbleRadius = bubbleRadius
        self.chatFontSize = chatFontSize
        self.listFontSize = listFontSize
        self.largeEmoji = largeEmoji
        self.mergeBubbleCorners = mergeBubbleCorners
        self.serifMessageFont = serifMessageFont
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)

        // URGRAM (build 29): every field is fault-isolated — see
        // urgramDecodeField above.
        self.id = urgramDecodeField({ try container.decodeIfPresent(String.self, forKey: "id") }, fallback: "")
        self.name = urgramDecodeField({ try container.decodeIfPresent(String.self, forKey: "name") }, fallback: "")
        self.accentColor = urgramDecodeField({ urgramDecodeArgbField(container, "accentColor") }, fallback: Int32(bitPattern: 0xff2aabee))
        self.bubbleColors = urgramDecodeField({ urgramDecodeArgbArrayField(container, "bubbleColors") }, fallback: [])
        self.wallpaperMode = urgramDecodeField({ try container.decodeIfPresent(Int32.self, forKey: "wallpaperMode") }, fallback: 0)
        self.wallpaperColorA = urgramDecodeField({ urgramDecodeArgbField(container, "wallpaperColorA") }, fallback: Int32(bitPattern: 0xff2aabee))
        self.wallpaperColorB = urgramDecodeField({ urgramDecodeArgbField(container, "wallpaperColorB") }, fallback: Int32(bitPattern: 0xff2aabee))
        self.bubbleRadius = urgramDecodeField({ try container.decodeIfPresent(Int32.self, forKey: "bubbleRadius") }, fallback: 16)
        self.chatFontSize = urgramDecodeOptionalField({ try container.decodeIfPresent(Int32.self, forKey: "chatFontSize") })
        self.listFontSize = urgramDecodeOptionalField({ try container.decodeIfPresent(Int32.self, forKey: "listFontSize") })
        self.largeEmoji = urgramDecodeOptionalField({ try container.decodeIfPresent(Bool.self, forKey: "largeEmoji") })
        self.mergeBubbleCorners = urgramDecodeOptionalField({ try container.decodeIfPresent(Bool.self, forKey: "mergeBubbleCorners") })
        self.serifMessageFont = urgramDecodeOptionalField({ try container.decodeIfPresent(Bool.self, forKey: "serifMessageFont") })
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)

        try container.encode(self.id, forKey: "id")
        try container.encode(self.name, forKey: "name")
        try container.encode(self.accentColor, forKey: "accentColor")
        try container.encode(self.bubbleColors, forKey: "bubbleColors")
        try container.encode(self.wallpaperMode, forKey: "wallpaperMode")
        try container.encode(self.wallpaperColorA, forKey: "wallpaperColorA")
        try container.encode(self.wallpaperColorB, forKey: "wallpaperColorB")
        try container.encode(self.bubbleRadius, forKey: "bubbleRadius")
        try container.encodeIfPresent(self.chatFontSize, forKey: "chatFontSize")
        try container.encodeIfPresent(self.listFontSize, forKey: "listFontSize")
        try container.encodeIfPresent(self.largeEmoji, forKey: "largeEmoji")
        try container.encodeIfPresent(self.mergeBubbleCorners, forKey: "mergeBubbleCorners")
        try container.encodeIfPresent(self.serifMessageFont, forKey: "serifMessageFont")
    }
}

public struct UrgramSettings: Codable, Equatable {
    // Ghost mode (item 1)
    public var ghostHideRead: Bool
    public var ghostHideTyping: Bool
    public var ghostHideOnline: Bool
    public var ghostHideStoryViews: Bool
    // Privacy extras (items 16, 24, 30)
    public var streamerMode: Bool
    public var secretChatScreenshotSilent: Bool
    public var hidePhoneInProfile: Bool
    // Content (items 2, 3, 8, 10)
    public var saveRestrictedBypass: Bool
    public var keepDeletedMessages: Bool
    public var keepEditedMessages: Bool
    public var hideSponsored: Bool
    public var keywordFiltersEnabled: Bool
    public var keywordFilters: [String]
    // Chats (items 12, 20, 27, 29, 31)
    public var sendWithEnter: Bool
    public var hideStoriesBar: Bool
    public var disableStories: Bool
    public var foldersAtBottom: Bool
    public var doubleTapEditOwnMessages: Bool
    public var mentionAll: Bool
    public var autoReplyEnabled: Bool
    public var autoReplyText: String
    // Media & downloads (items 11, 21, 24)
    public var defaultHDPhotos: Bool
    public var downloadBoost: Bool
    public var voiceNoiseSuppression: Bool
    // Calls (item 17)
    public var callConfirmation: Bool
    public var forceTcpCalls: Bool
    // Translation (item 5, regular engines only — no AI key by user's decision)
    public var translateChats: Bool
    public var translateOutgoingLongPress: Bool
    // Font (item 22): "system", "tajawal", "cairo", "plexArabic" or "custom"
    public var fontChoice: String
    public var customFontName: String?
    public var customFontFileName: String?
    // Urgram Studio (build 20): saved appearance designs + the applied one
    public var studioDesigns: [UrgramThemeDesign]
    public var studioActiveDesignId: String?
    // Clean Edition additions (build 20): quick-reply templates (inserted
    // into the chat input from the attachment menu) and the auto-archive
    // rule for inactive chats (0 = off, otherwise days of inactivity).
    public var replyTemplates: [String]
    // URGRAM (build 29): Int32, not Int — Postbox's adapted keyed Codable
    // containers have no Int overload (encode hits assertionFailure and
    // writes Int32; decode throws), which poisoned the whole settings
    // decode. Same for snowIntensity below.
    public var autoArchiveInactiveDays: Int32
    // Studio V2 (main interface): hide the main chat-list navigation bar's
    // Edit / Compose / Add-Story buttons. Gated at the button rebuild in
    // ChatListLocationContext.updateChatList (ChatListController.swift).
    public var homeHideEditButton: Bool
    public var homeHideComposeButton: Bool
    public var homeHideStoryButton: Bool
    // Hidden chats: peer ids (packed via PeerId.toInt64()) the user hid from
    // the main chat list. Filtered at ChatListNode's entry filtering and
    // managed from the lock-gated "Hidden Chats" screen in Urgram Settings.
    public var hiddenPeerIds: [Int64]
    // Auto-reply: last auto-reply send time per peer (key = packed peer id
    // as string, value = seconds since 1970). Enforces at most one
    // auto-reply per peer per 24 hours.
    public var autoReplyLastSentAt: [String: Double]
    // Ambience (snow): falling-snow overlay over the whole app window with
    // slowly accumulating snow caps. Intensity: 0 = light, 1 = medium,
    // 2 = heavy. Deliberately NOT part of UrgramThemeDesign: designs are
    // shareable color themes; this is a device-local ambience preference.
    public var snowEnabled: Bool
    public var snowIntensity: Int32
    // Profile identity registry: the user's own card draft (long bio +
    // social links), edited in «هويتي في أورغرام» and published to the
    // registry group from there. The banner image itself is not stored
    // here; publishing re-reads the current published record to keep it.
    public var identityBio: String
    public var identityLinks: [UrgramIdentityLink]

    public init(
        ghostHideRead: Bool,
        ghostHideTyping: Bool,
        ghostHideOnline: Bool,
        ghostHideStoryViews: Bool,
        streamerMode: Bool,
        secretChatScreenshotSilent: Bool,
        hidePhoneInProfile: Bool,
        saveRestrictedBypass: Bool,
        keepDeletedMessages: Bool,
        keepEditedMessages: Bool,
        hideSponsored: Bool,
        keywordFiltersEnabled: Bool,
        keywordFilters: [String],
        sendWithEnter: Bool,
        hideStoriesBar: Bool,
        disableStories: Bool,
        foldersAtBottom: Bool,
        doubleTapEditOwnMessages: Bool,
        mentionAll: Bool,
        autoReplyEnabled: Bool,
        autoReplyText: String,
        defaultHDPhotos: Bool,
        downloadBoost: Bool,
        voiceNoiseSuppression: Bool,
        callConfirmation: Bool,
        forceTcpCalls: Bool,
        translateChats: Bool,
        translateOutgoingLongPress: Bool,
        fontChoice: String,
        customFontName: String?,
        customFontFileName: String?,
        studioDesigns: [UrgramThemeDesign],
        studioActiveDesignId: String?,
        replyTemplates: [String],
        autoArchiveInactiveDays: Int32,
        homeHideEditButton: Bool,
        homeHideComposeButton: Bool,
        homeHideStoryButton: Bool,
        hiddenPeerIds: [Int64],
        autoReplyLastSentAt: [String: Double],
        snowEnabled: Bool,
        snowIntensity: Int32,
        identityBio: String,
        identityLinks: [UrgramIdentityLink]
    ) {
        self.ghostHideRead = ghostHideRead
        self.ghostHideTyping = ghostHideTyping
        self.ghostHideOnline = ghostHideOnline
        self.ghostHideStoryViews = ghostHideStoryViews
        self.streamerMode = streamerMode
        self.secretChatScreenshotSilent = secretChatScreenshotSilent
        self.hidePhoneInProfile = hidePhoneInProfile
        self.saveRestrictedBypass = saveRestrictedBypass
        self.keepDeletedMessages = keepDeletedMessages
        self.keepEditedMessages = keepEditedMessages
        self.hideSponsored = hideSponsored
        self.keywordFiltersEnabled = keywordFiltersEnabled
        self.keywordFilters = keywordFilters
        self.sendWithEnter = sendWithEnter
        self.hideStoriesBar = hideStoriesBar
        self.disableStories = disableStories
        self.foldersAtBottom = foldersAtBottom
        self.doubleTapEditOwnMessages = doubleTapEditOwnMessages
        self.mentionAll = mentionAll
        self.autoReplyEnabled = autoReplyEnabled
        self.autoReplyText = autoReplyText
        self.defaultHDPhotos = defaultHDPhotos
        self.downloadBoost = downloadBoost
        self.voiceNoiseSuppression = voiceNoiseSuppression
        self.callConfirmation = callConfirmation
        self.forceTcpCalls = forceTcpCalls
        self.translateChats = translateChats
        self.translateOutgoingLongPress = translateOutgoingLongPress
        self.fontChoice = fontChoice
        self.customFontName = customFontName
        self.customFontFileName = customFontFileName
        self.studioDesigns = studioDesigns
        self.studioActiveDesignId = studioActiveDesignId
        self.replyTemplates = replyTemplates
        self.autoArchiveInactiveDays = autoArchiveInactiveDays
        self.homeHideEditButton = homeHideEditButton
        self.homeHideComposeButton = homeHideComposeButton
        self.homeHideStoryButton = homeHideStoryButton
        self.hiddenPeerIds = hiddenPeerIds
        self.autoReplyLastSentAt = autoReplyLastSentAt
        self.snowEnabled = snowEnabled
        self.snowIntensity = snowIntensity
        self.identityBio = identityBio
        self.identityLinks = identityLinks
    }

    public static var defaultSettings: UrgramSettings {
        return UrgramSettings(
            ghostHideRead: false,
            ghostHideTyping: false,
            ghostHideOnline: false,
            ghostHideStoryViews: false,
            streamerMode: false,
            secretChatScreenshotSilent: false,
            hidePhoneInProfile: false,
            saveRestrictedBypass: false,
            keepDeletedMessages: false,
            keepEditedMessages: false,
            hideSponsored: false,
            keywordFiltersEnabled: false,
            keywordFilters: [],
            sendWithEnter: false,
            hideStoriesBar: false,
            disableStories: false,
            foldersAtBottom: false,
            doubleTapEditOwnMessages: false,
            mentionAll: false,
            autoReplyEnabled: false,
            autoReplyText: "",
            defaultHDPhotos: false,
            downloadBoost: false,
            voiceNoiseSuppression: false,
            callConfirmation: false,
            forceTcpCalls: false,
            translateChats: false,
            translateOutgoingLongPress: false,
            fontChoice: "system",
            customFontName: nil,
            customFontFileName: nil,
            studioDesigns: [],
            studioActiveDesignId: nil,
            replyTemplates: [],
            autoArchiveInactiveDays: 0,
            homeHideEditButton: false,
            homeHideComposeButton: false,
            homeHideStoryButton: false,
            hiddenPeerIds: [],
            autoReplyLastSentAt: [:],
            snowEnabled: false,
            snowIntensity: 0,
            identityBio: "",
            identityLinks: []
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)

        // URGRAM (build 29): every field is fault-isolated — a field whose
        // stored form this build cannot read (notably the Int fields of
        // build ≤28 blobs, written as Int32 boxes with no matching keyed
        // decode) falls back to its default alone instead of aborting the
        // whole settings decode and resetting everything.
        self.ghostHideRead = urgramDecodeField({ try container.decodeIfPresent(Bool.self, forKey: "ghostHideRead") }, fallback: false)
        self.ghostHideTyping = urgramDecodeField({ try container.decodeIfPresent(Bool.self, forKey: "ghostHideTyping") }, fallback: false)
        self.ghostHideOnline = urgramDecodeField({ try container.decodeIfPresent(Bool.self, forKey: "ghostHideOnline") }, fallback: false)
        self.ghostHideStoryViews = urgramDecodeField({ try container.decodeIfPresent(Bool.self, forKey: "ghostHideStoryViews") }, fallback: false)
        self.streamerMode = urgramDecodeField({ try container.decodeIfPresent(Bool.self, forKey: "streamerMode") }, fallback: false)
        self.secretChatScreenshotSilent = urgramDecodeField({ try container.decodeIfPresent(Bool.self, forKey: "secretChatScreenshotSilent") }, fallback: false)
        self.hidePhoneInProfile = urgramDecodeField({ try container.decodeIfPresent(Bool.self, forKey: "hidePhoneInProfile") }, fallback: false)
        self.saveRestrictedBypass = urgramDecodeField({ try container.decodeIfPresent(Bool.self, forKey: "saveRestrictedBypass") }, fallback: false)
        self.keepDeletedMessages = urgramDecodeField({ try container.decodeIfPresent(Bool.self, forKey: "keepDeletedMessages") }, fallback: false)
        self.keepEditedMessages = urgramDecodeField({ try container.decodeIfPresent(Bool.self, forKey: "keepEditedMessages") }, fallback: false)
        self.hideSponsored = urgramDecodeField({ try container.decodeIfPresent(Bool.self, forKey: "hideSponsored") }, fallback: false)
        self.keywordFiltersEnabled = urgramDecodeField({ try container.decodeIfPresent(Bool.self, forKey: "keywordFiltersEnabled") }, fallback: false)
        self.keywordFilters = urgramDecodeField({ try container.decodeIfPresent([String].self, forKey: "keywordFilters") }, fallback: [])
        self.sendWithEnter = urgramDecodeField({ try container.decodeIfPresent(Bool.self, forKey: "sendWithEnter") }, fallback: false)
        self.hideStoriesBar = urgramDecodeField({ try container.decodeIfPresent(Bool.self, forKey: "hideStoriesBar") }, fallback: false)
        self.disableStories = urgramDecodeField({ try container.decodeIfPresent(Bool.self, forKey: "disableStories") }, fallback: false)
        self.foldersAtBottom = urgramDecodeField({ try container.decodeIfPresent(Bool.self, forKey: "foldersAtBottom") }, fallback: false)
        self.doubleTapEditOwnMessages = urgramDecodeField({ try container.decodeIfPresent(Bool.self, forKey: "doubleTapEditOwnMessages") }, fallback: false)
        self.mentionAll = urgramDecodeField({ try container.decodeIfPresent(Bool.self, forKey: "mentionAll") }, fallback: false)
        self.autoReplyEnabled = urgramDecodeField({ try container.decodeIfPresent(Bool.self, forKey: "autoReplyEnabled") }, fallback: false)
        self.autoReplyText = urgramDecodeField({ try container.decodeIfPresent(String.self, forKey: "autoReplyText") }, fallback: "")
        self.defaultHDPhotos = urgramDecodeField({ try container.decodeIfPresent(Bool.self, forKey: "defaultHDPhotos") }, fallback: false)
        self.downloadBoost = urgramDecodeField({ try container.decodeIfPresent(Bool.self, forKey: "downloadBoost") }, fallback: false)
        self.voiceNoiseSuppression = urgramDecodeField({ try container.decodeIfPresent(Bool.self, forKey: "voiceNoiseSuppression") }, fallback: false)
        self.callConfirmation = urgramDecodeField({ try container.decodeIfPresent(Bool.self, forKey: "callConfirmation") }, fallback: false)
        self.forceTcpCalls = urgramDecodeField({ try container.decodeIfPresent(Bool.self, forKey: "forceTcpCalls") }, fallback: false)
        self.translateChats = urgramDecodeField({ try container.decodeIfPresent(Bool.self, forKey: "translateChats") }, fallback: false)
        self.translateOutgoingLongPress = urgramDecodeField({ try container.decodeIfPresent(Bool.self, forKey: "translateOutgoingLongPress") }, fallback: false)
        self.fontChoice = urgramDecodeField({ try container.decodeIfPresent(String.self, forKey: "fontChoice") }, fallback: "system")
        self.customFontName = urgramDecodeOptionalField({ try container.decodeIfPresent(String.self, forKey: "customFontName") })
        self.customFontFileName = urgramDecodeOptionalField({ try container.decodeIfPresent(String.self, forKey: "customFontFileName") })
        self.studioDesigns = urgramDecodeField({ try container.decodeIfPresent([UrgramThemeDesign].self, forKey: "studioDesigns") }, fallback: [])
        self.studioActiveDesignId = urgramDecodeOptionalField({ try container.decodeIfPresent(String.self, forKey: "studioActiveDesignId") })
        self.replyTemplates = urgramDecodeField({ try container.decodeIfPresent([String].self, forKey: "replyTemplates") }, fallback: [])
        self.autoArchiveInactiveDays = urgramDecodeField({ try container.decodeIfPresent(Int32.self, forKey: "autoArchiveInactiveDays") }, fallback: 0)
        self.homeHideEditButton = urgramDecodeField({ try container.decodeIfPresent(Bool.self, forKey: "homeHideEditButton") }, fallback: false)
        self.homeHideComposeButton = urgramDecodeField({ try container.decodeIfPresent(Bool.self, forKey: "homeHideComposeButton") }, fallback: false)
        self.homeHideStoryButton = urgramDecodeField({ try container.decodeIfPresent(Bool.self, forKey: "homeHideStoryButton") }, fallback: false)
        self.hiddenPeerIds = urgramDecodeField({ try container.decodeIfPresent([Int64].self, forKey: "hiddenPeerIds") }, fallback: [])
        self.autoReplyLastSentAt = urgramDecodeField({ try container.decodeIfPresent([String: Double].self, forKey: "autoReplyLastSentAt") }, fallback: [:])
        self.snowEnabled = urgramDecodeField({ try container.decodeIfPresent(Bool.self, forKey: "snowEnabled") }, fallback: false)
        self.snowIntensity = urgramDecodeField({ try container.decodeIfPresent(Int32.self, forKey: "snowIntensity") }, fallback: 0)
        self.identityBio = urgramDecodeField({ try container.decodeIfPresent(String.self, forKey: "identityBio") }, fallback: "")
        self.identityLinks = urgramDecodeField({ try container.decodeIfPresent([UrgramIdentityLink].self, forKey: "identityLinks") }, fallback: [])
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)

        try container.encode(self.ghostHideRead, forKey: "ghostHideRead")
        try container.encode(self.ghostHideTyping, forKey: "ghostHideTyping")
        try container.encode(self.ghostHideOnline, forKey: "ghostHideOnline")
        try container.encode(self.ghostHideStoryViews, forKey: "ghostHideStoryViews")
        try container.encode(self.streamerMode, forKey: "streamerMode")
        try container.encode(self.secretChatScreenshotSilent, forKey: "secretChatScreenshotSilent")
        try container.encode(self.hidePhoneInProfile, forKey: "hidePhoneInProfile")
        try container.encode(self.saveRestrictedBypass, forKey: "saveRestrictedBypass")
        try container.encode(self.keepDeletedMessages, forKey: "keepDeletedMessages")
        try container.encode(self.keepEditedMessages, forKey: "keepEditedMessages")
        try container.encode(self.hideSponsored, forKey: "hideSponsored")
        try container.encode(self.keywordFiltersEnabled, forKey: "keywordFiltersEnabled")
        try container.encode(self.keywordFilters, forKey: "keywordFilters")
        try container.encode(self.sendWithEnter, forKey: "sendWithEnter")
        try container.encode(self.hideStoriesBar, forKey: "hideStoriesBar")
        try container.encode(self.disableStories, forKey: "disableStories")
        try container.encode(self.foldersAtBottom, forKey: "foldersAtBottom")
        try container.encode(self.doubleTapEditOwnMessages, forKey: "doubleTapEditOwnMessages")
        try container.encode(self.mentionAll, forKey: "mentionAll")
        try container.encode(self.autoReplyEnabled, forKey: "autoReplyEnabled")
        try container.encode(self.autoReplyText, forKey: "autoReplyText")
        try container.encode(self.defaultHDPhotos, forKey: "defaultHDPhotos")
        try container.encode(self.downloadBoost, forKey: "downloadBoost")
        try container.encode(self.voiceNoiseSuppression, forKey: "voiceNoiseSuppression")
        try container.encode(self.callConfirmation, forKey: "callConfirmation")
        try container.encode(self.forceTcpCalls, forKey: "forceTcpCalls")
        try container.encode(self.translateChats, forKey: "translateChats")
        try container.encode(self.translateOutgoingLongPress, forKey: "translateOutgoingLongPress")
        try container.encode(self.fontChoice, forKey: "fontChoice")
        try container.encodeIfPresent(self.customFontName, forKey: "customFontName")
        try container.encodeIfPresent(self.customFontFileName, forKey: "customFontFileName")
        try container.encode(self.studioDesigns, forKey: "studioDesigns")
        try container.encodeIfPresent(self.studioActiveDesignId, forKey: "studioActiveDesignId")
        try container.encode(self.replyTemplates, forKey: "replyTemplates")
        try container.encode(self.autoArchiveInactiveDays, forKey: "autoArchiveInactiveDays")
        try container.encode(self.homeHideEditButton, forKey: "homeHideEditButton")
        try container.encode(self.homeHideComposeButton, forKey: "homeHideComposeButton")
        try container.encode(self.homeHideStoryButton, forKey: "homeHideStoryButton")
        try container.encode(self.hiddenPeerIds, forKey: "hiddenPeerIds")
        try container.encode(self.autoReplyLastSentAt, forKey: "autoReplyLastSentAt")
        try container.encode(self.snowEnabled, forKey: "snowEnabled")
        try container.encode(self.snowIntensity, forKey: "snowIntensity")
        try container.encode(self.identityBio, forKey: "identityBio")
        try container.encode(self.identityLinks, forKey: "identityLinks")
    }
}

// URGRAM
public func updateUrgramSettingsInteractively(accountManager: AccountManager<TelegramAccountManagerTypes>, _ f: @escaping (UrgramSettings) -> UrgramSettings) -> Signal<Void, NoError> {
    return accountManager.transaction { transaction -> Void in
        transaction.updateSharedData(ApplicationSpecificSharedDataKeys.urgramSettings, { entry in
            let currentSettings: UrgramSettings
            if let entry = entry?.get(UrgramSettings.self) {
                currentSettings = entry
            } else {
                currentSettings = UrgramSettings.defaultSettings
            }
            return SharedPreferencesEntry(f(currentSettings))
        })
    }
}

// URGRAM: single in-memory store. The settings screen reads/writes through it;
// SharedAccountContext seeds it from shared data at launch and keeps it in sync.
public final class UrgramSettingsStore {
    public static let shared = UrgramSettingsStore()

    private let value = Atomic<UrgramSettings>(value: UrgramSettings.defaultSettings)
    private let promise = ValuePromise<UrgramSettings>(UrgramSettings.defaultSettings, ignoreRepeated: true)
    private var accountManager: AccountManager<TelegramAccountManagerTypes>?
    private var updateDisposable: Disposable?

    public var current: UrgramSettings {
        return self.value.with { $0 }
    }

    public var settingsSignal: Signal<UrgramSettings, NoError> {
        return self.promise.get()
    }

    private init() {
    }

    // URGRAM: called once from SharedAccountContext.
    public func attach(accountManager: AccountManager<TelegramAccountManagerTypes>) {
        self.accountManager = accountManager
    }

    // URGRAM: called from the SharedAccountContext shared-data subscription.
    public func applyExternal(_ settings: UrgramSettings) {
        let _ = self.value.swap(settings)
        self.promise.set(settings)
        UrgramSettingsStore.mirrorToCoreHooks(settings)
    }

    public func update(_ f: @escaping (inout UrgramSettings) -> Void) {
        var updated = self.current
        f(&updated)
        self.applyExternal(updated)
        if let accountManager = self.accountManager {
            self.updateDisposable?.dispose()
            self.updateDisposable = updateUrgramSettingsInteractively(accountManager: accountManager, { _ in
                return updated
            }).start()
        }
    }

    // URGRAM
    public static func mirrorToCoreHooks(_ settings: UrgramSettings) {
        // URGRAM (build 20, Clean Edition): every privacy-bypass hook is
        // forced off at this single mirroring point when the clean edition
        // ships, whatever a previously stored settings value says. The
        // non-bypass hooks (disableStories) mirror normally in both editions.
        let bypassAllowed = !UrgramEdition.isClean
        UrgramFeatureHooks.ghostHideRead = bypassAllowed && settings.ghostHideRead
        UrgramFeatureHooks.ghostHideTyping = bypassAllowed && settings.ghostHideTyping
        UrgramFeatureHooks.ghostHideOnline = bypassAllowed && settings.ghostHideOnline
        UrgramFeatureHooks.ghostHideStoryViews = bypassAllowed && settings.ghostHideStoryViews
        UrgramFeatureHooks.hideSponsored = bypassAllowed && settings.hideSponsored
        UrgramFeatureHooks.saveRestrictedBypass = bypassAllowed && settings.saveRestrictedBypass
        UrgramFeatureHooks.keepDeletedMessages = bypassAllowed && settings.keepDeletedMessages
        UrgramFeatureHooks.keepEditedMessages = bypassAllowed && settings.keepEditedMessages
        UrgramFeatureHooks.disableStories = settings.disableStories
        UrgramFeatureHooks.secretChatScreenshotSilent = bypassAllowed && settings.secretChatScreenshotSilent
    }
}
