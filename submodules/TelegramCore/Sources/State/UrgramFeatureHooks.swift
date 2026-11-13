import Foundation

// URGRAM (build 20, Clean Edition): which edition of the fork this build is.
// `true` ships now: the Clean Edition compiles the privacy-bypass features
// OUT of reach — `UrgramSettingsStore.mirrorToCoreHooks` forces every bypass
// hook to `false` and the Urgram settings screen omits their controls — while
// the full edition's code paths stay in the tree untouched behind this flag.
public enum UrgramEdition {
    public static let isClean: Bool = true
}

// URGRAM: TelegramCore cannot import TelegramUIPreferences (the dependency runs
// the other way), so Urgram feature flags that gate core operations are bridged
// through these plain statics. They are written exclusively by
// `UrgramSettingsStore` / the SharedAccountContext shared-data subscription
// (the same pattern upstream uses for `GlassBackgroundView.useCustomGlassImpl`)
// and read by the gated core operations. All values default to `false`
// (feature off), matching upstream behaviour until the user opts in.
public enum UrgramFeatureHooks {
    /// Item 1 (ghost mode): never push `messages.readHistory` /
    /// `channels.readHistory` / `messages.readMessageContents` to the server.
    public static var ghostHideRead: Bool = false
    /// Item 1 (ghost mode): never send `messages.setTyping`.
    public static var ghostHideTyping: Bool = false
    /// Item 1 (ghost mode): always report `account.updateStatus(offline: true)`.
    public static var ghostHideOnline: Bool = false
    /// Item 1 (ghost mode): never send `stories.readStories`.
    public static var ghostHideStoryViews: Bool = false
    /// Item 8: never fetch or insert sponsored messages in channels.
    public static var hideSponsored: Bool = false
    /// Item 2: drop the CopyProtected flag when messages are stored.
    public static var saveRestrictedBypass: Bool = false
    /// Item 3: keep a local archive copy of messages that get deleted/edited.
    public static var keepDeletedMessages: Bool = false
    /// Item 3 (edits): keep the pre-edit text of messages that get edited
    /// (read in StateReplay.applyEditMessage).
    public static var keepEditedMessages: Bool = false
    /// Item 20 (hard): never open the story viewer at all.
    public static var disableStories: Bool = false
    /// Item 24: do not send the screenshot service notification in secret chats.
    public static var secretChatScreenshotSilent: Bool = false
}
