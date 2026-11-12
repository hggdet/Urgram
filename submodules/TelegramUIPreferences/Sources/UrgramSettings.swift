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
        customFontFileName: String?
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
            customFontFileName: nil
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)

        self.ghostHideRead = try container.decodeIfPresent(Bool.self, forKey: "ghostHideRead") ?? false
        self.ghostHideTyping = try container.decodeIfPresent(Bool.self, forKey: "ghostHideTyping") ?? false
        self.ghostHideOnline = try container.decodeIfPresent(Bool.self, forKey: "ghostHideOnline") ?? false
        self.ghostHideStoryViews = try container.decodeIfPresent(Bool.self, forKey: "ghostHideStoryViews") ?? false
        self.streamerMode = try container.decodeIfPresent(Bool.self, forKey: "streamerMode") ?? false
        self.secretChatScreenshotSilent = try container.decodeIfPresent(Bool.self, forKey: "secretChatScreenshotSilent") ?? false
        self.hidePhoneInProfile = try container.decodeIfPresent(Bool.self, forKey: "hidePhoneInProfile") ?? false
        self.saveRestrictedBypass = try container.decodeIfPresent(Bool.self, forKey: "saveRestrictedBypass") ?? false
        self.keepDeletedMessages = try container.decodeIfPresent(Bool.self, forKey: "keepDeletedMessages") ?? false
        self.keepEditedMessages = try container.decodeIfPresent(Bool.self, forKey: "keepEditedMessages") ?? false
        self.hideSponsored = try container.decodeIfPresent(Bool.self, forKey: "hideSponsored") ?? false
        self.keywordFiltersEnabled = try container.decodeIfPresent(Bool.self, forKey: "keywordFiltersEnabled") ?? false
        self.keywordFilters = try container.decodeIfPresent([String].self, forKey: "keywordFilters") ?? []
        self.sendWithEnter = try container.decodeIfPresent(Bool.self, forKey: "sendWithEnter") ?? false
        self.hideStoriesBar = try container.decodeIfPresent(Bool.self, forKey: "hideStoriesBar") ?? false
        self.disableStories = try container.decodeIfPresent(Bool.self, forKey: "disableStories") ?? false
        self.foldersAtBottom = try container.decodeIfPresent(Bool.self, forKey: "foldersAtBottom") ?? false
        self.doubleTapEditOwnMessages = try container.decodeIfPresent(Bool.self, forKey: "doubleTapEditOwnMessages") ?? false
        self.mentionAll = try container.decodeIfPresent(Bool.self, forKey: "mentionAll") ?? false
        self.autoReplyEnabled = try container.decodeIfPresent(Bool.self, forKey: "autoReplyEnabled") ?? false
        self.autoReplyText = try container.decodeIfPresent(String.self, forKey: "autoReplyText") ?? ""
        self.defaultHDPhotos = try container.decodeIfPresent(Bool.self, forKey: "defaultHDPhotos") ?? false
        self.downloadBoost = try container.decodeIfPresent(Bool.self, forKey: "downloadBoost") ?? false
        self.voiceNoiseSuppression = try container.decodeIfPresent(Bool.self, forKey: "voiceNoiseSuppression") ?? false
        self.callConfirmation = try container.decodeIfPresent(Bool.self, forKey: "callConfirmation") ?? false
        self.forceTcpCalls = try container.decodeIfPresent(Bool.self, forKey: "forceTcpCalls") ?? false
        self.translateChats = try container.decodeIfPresent(Bool.self, forKey: "translateChats") ?? false
        self.translateOutgoingLongPress = try container.decodeIfPresent(Bool.self, forKey: "translateOutgoingLongPress") ?? false
        self.fontChoice = try container.decodeIfPresent(String.self, forKey: "fontChoice") ?? "system"
        self.customFontName = try container.decodeIfPresent(String.self, forKey: "customFontName")
        self.customFontFileName = try container.decodeIfPresent(String.self, forKey: "customFontFileName")
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
        UrgramFeatureHooks.ghostHideRead = settings.ghostHideRead
        UrgramFeatureHooks.ghostHideTyping = settings.ghostHideTyping
        UrgramFeatureHooks.ghostHideOnline = settings.ghostHideOnline
        UrgramFeatureHooks.ghostHideStoryViews = settings.ghostHideStoryViews
        UrgramFeatureHooks.hideSponsored = settings.hideSponsored
        UrgramFeatureHooks.saveRestrictedBypass = settings.saveRestrictedBypass
        UrgramFeatureHooks.keepDeletedMessages = settings.keepDeletedMessages
        UrgramFeatureHooks.secretChatScreenshotSilent = settings.secretChatScreenshotSilent
    }
}
