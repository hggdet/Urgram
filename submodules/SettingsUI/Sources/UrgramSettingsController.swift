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

// URGRAM: the single dedicated settings screen for all Urgram fork features
// (placement rule: every feature control lives here, never scattered through
// Telegram's own settings). Modelled on ArchiveSettingsController.

private final class UrgramSettingsControllerArguments {
    let update: (WritableKeyPath<UrgramSettings, Bool>, Bool) -> Void
    let openFonts: () -> Void
    let openProxies: () -> Void
    let markAllChatsAsRead: () -> Void

    init(
        update: @escaping (WritableKeyPath<UrgramSettings, Bool>, Bool) -> Void,
        openFonts: @escaping () -> Void,
        openProxies: @escaping () -> Void,
        markAllChatsAsRead: @escaping () -> Void
    ) {
        self.update = update
        self.openFonts = openFonts
        self.openProxies = openProxies
        self.markAllChatsAsRead = markAllChatsAsRead
    }
}

private enum UrgramSettingsSection: Int32 {
    case ghost
    case privacy
    case content
    case chats
    case media
    case calls
    case translation
    case font
    case proxy
    case actions
}

private enum UrgramSettingsControllerEntry: ItemListNodeEntry {
    case ghostHeader
    case ghostHideRead(Bool)
    case ghostHideTyping(Bool)
    case ghostHideOnline(Bool)
    case ghostHideStoryViews(Bool)
    case ghostFooter

    case privacyHeader
    case streamerMode(Bool)
    case secretChatScreenshotSilent(Bool)
    case hidePhoneInProfile(Bool)

    case contentHeader
    case saveRestrictedBypass(Bool)
    case keepDeletedMessages(Bool)
    case keepEditedMessages(Bool)
    case hideSponsored(Bool)
    case keywordFiltersEnabled(Bool)
    case contentFooter

    case chatsHeader
    case sendWithEnter(Bool)
    case hideStoriesBar(Bool)
    case disableStories(Bool)
    case foldersAtBottom(Bool)
    case doubleTapEditOwnMessages(Bool)
    case mentionAll(Bool)
    case autoReplyEnabled(Bool)
    case chatsFooter

    case mediaHeader
    case defaultHDPhotos(Bool)
    case downloadBoost(Bool)
    case voiceNoiseSuppression(Bool)

    case callsHeader
    case callConfirmation(Bool)
    case forceTcpCalls(Bool)

    case translationHeader
    case translateChats(Bool)
    case translateOutgoingLongPress(Bool)

    case fontHeader
    case fontChoice(String)

    case proxyHeader
    case proxies

    case actionsHeader
    case markAllRead

    var section: ItemListSectionId {
        switch self {
        case .ghostHeader, .ghostHideRead, .ghostHideTyping, .ghostHideOnline, .ghostHideStoryViews, .ghostFooter:
            return UrgramSettingsSection.ghost.rawValue
        case .privacyHeader, .streamerMode, .secretChatScreenshotSilent, .hidePhoneInProfile:
            return UrgramSettingsSection.privacy.rawValue
        case .contentHeader, .saveRestrictedBypass, .keepDeletedMessages, .keepEditedMessages, .hideSponsored, .keywordFiltersEnabled, .contentFooter:
            return UrgramSettingsSection.content.rawValue
        case .chatsHeader, .sendWithEnter, .hideStoriesBar, .disableStories, .foldersAtBottom, .doubleTapEditOwnMessages, .mentionAll, .autoReplyEnabled, .chatsFooter:
            return UrgramSettingsSection.chats.rawValue
        case .mediaHeader, .defaultHDPhotos, .downloadBoost, .voiceNoiseSuppression:
            return UrgramSettingsSection.media.rawValue
        case .callsHeader, .callConfirmation, .forceTcpCalls:
            return UrgramSettingsSection.calls.rawValue
        case .translationHeader, .translateChats, .translateOutgoingLongPress:
            return UrgramSettingsSection.translation.rawValue
        case .fontHeader, .fontChoice:
            return UrgramSettingsSection.font.rawValue
        case .proxyHeader, .proxies:
            return UrgramSettingsSection.proxy.rawValue
        case .actionsHeader, .markAllRead:
            return UrgramSettingsSection.actions.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .ghostHeader: return 0
        case .ghostHideRead: return 1
        case .ghostHideTyping: return 2
        case .ghostHideOnline: return 3
        case .ghostHideStoryViews: return 4
        case .ghostFooter: return 5
        case .privacyHeader: return 10
        case .streamerMode: return 11
        case .secretChatScreenshotSilent: return 12
        case .hidePhoneInProfile: return 13
        case .contentHeader: return 20
        case .saveRestrictedBypass: return 21
        case .keepDeletedMessages: return 22
        case .keepEditedMessages: return 23
        case .hideSponsored: return 24
        case .keywordFiltersEnabled: return 25
        case .contentFooter: return 26
        case .chatsHeader: return 30
        case .sendWithEnter: return 31
        case .hideStoriesBar: return 32
        case .disableStories: return 33
        case .foldersAtBottom: return 34
        case .doubleTapEditOwnMessages: return 35
        case .mentionAll: return 36
        case .autoReplyEnabled: return 37
        case .chatsFooter: return 38
        case .mediaHeader: return 40
        case .defaultHDPhotos: return 41
        case .downloadBoost: return 42
        case .voiceNoiseSuppression: return 43
        case .callsHeader: return 50
        case .callConfirmation: return 51
        case .forceTcpCalls: return 52
        case .translationHeader: return 60
        case .translateChats: return 61
        case .translateOutgoingLongPress: return 62
        case .fontHeader: return 70
        case .fontChoice: return 71
        case .proxyHeader: return 75
        case .proxies: return 76
        case .actionsHeader: return 80
        case .markAllRead: return 81
        }
    }

    static func <(lhs: UrgramSettingsControllerEntry, rhs: UrgramSettingsControllerEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    private func switchItem(presentationData: ItemListPresentationData, arguments: UrgramSettingsControllerArguments, title: String, value: Bool, keyPath: WritableKeyPath<UrgramSettings, Bool>) -> ListViewItem {
        return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
            arguments.update(keyPath, value)
        })
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! UrgramSettingsControllerArguments
        switch self {
        case .ghostHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "Ghost Mode", sectionId: self.section)
        case let .ghostHideRead(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: "Hide Read Receipts", value: value, keyPath: \.ghostHideRead)
        case let .ghostHideTyping(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: "Hide Typing", value: value, keyPath: \.ghostHideTyping)
        case let .ghostHideOnline(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: "Hide Online Status", value: value, keyPath: \.ghostHideOnline)
        case let .ghostHideStoryViews(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: "Hide Story Views", value: value, keyPath: \.ghostHideStoryViews)
        case .ghostFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("With Ghost Mode on, other people won't see when you read, type, come online or watch stories. Your chats still update normally on this device."), sectionId: self.section)
        case .privacyHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "Privacy", sectionId: self.section)
        case let .streamerMode(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: "Streamer Mode", value: value, keyPath: \.streamerMode)
        case let .secretChatScreenshotSilent(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: "Secret Chat Screenshots Without Notification", value: value, keyPath: \.secretChatScreenshotSilent)
        case let .hidePhoneInProfile(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: "Hide Phone Number in My Profile", value: value, keyPath: \.hidePhoneInProfile)
        case .contentHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "Content", sectionId: self.section)
        case let .saveRestrictedBypass(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: "Save Restricted Content", value: value, keyPath: \.saveRestrictedBypass)
        case let .keepDeletedMessages(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: "Keep Deleted Messages", value: value, keyPath: \.keepDeletedMessages)
        case let .keepEditedMessages(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: "Keep Original Text of Edited Messages", value: value, keyPath: \.keepEditedMessages)
        case let .hideSponsored(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: "Hide Sponsored Messages", value: value, keyPath: \.hideSponsored)
        case let .keywordFiltersEnabled(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: "Keyword Filters", value: value, keyPath: \.keywordFiltersEnabled)
        case .contentFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Deleted messages are archived only on this device. A viewer for the archive is not included yet."), sectionId: self.section)
        case .chatsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "Chats", sectionId: self.section)
        case let .sendWithEnter(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: "Send With Enter", value: value, keyPath: \.sendWithEnter)
        case let .hideStoriesBar(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: "Hide Stories Bar", value: value, keyPath: \.hideStoriesBar)
        case let .disableStories(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: "Disable Stories", value: value, keyPath: \.disableStories)
        case let .foldersAtBottom(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: "Folders at Bottom", value: value, keyPath: \.foldersAtBottom)
        case let .doubleTapEditOwnMessages(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: "Double-Tap to Edit My Messages", value: value, keyPath: \.doubleTapEditOwnMessages)
        case let .mentionAll(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: "Mention All (@all)", value: value, keyPath: \.mentionAll)
        case let .autoReplyEnabled(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: "Auto-Reply", value: value, keyPath: \.autoReplyEnabled)
        case .chatsFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Some chat options take effect the next time the chat is opened."), sectionId: self.section)
        case .mediaHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "Media and Downloads", sectionId: self.section)
        case let .defaultHDPhotos(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: "Send Photos in HD by Default", value: value, keyPath: \.defaultHDPhotos)
        case let .downloadBoost(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: "Download Boost", value: value, keyPath: \.downloadBoost)
        case let .voiceNoiseSuppression(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: "Voice Message Noise Suppression", value: value, keyPath: \.voiceNoiseSuppression)
        case .callsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "Calls", sectionId: self.section)
        case let .callConfirmation(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: "Confirm Before Calling", value: value, keyPath: \.callConfirmation)
        case let .forceTcpCalls(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: "Force TCP for Calls", value: value, keyPath: \.forceTcpCalls)
        case .translationHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "Translation", sectionId: self.section)
        case let .translateChats(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: "Translate Whole Chats", value: value, keyPath: \.translateChats)
        case let .translateOutgoingLongPress(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: "Long-Press Send to Translate", value: value, keyPath: \.translateOutgoingLongPress)
        case .fontHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "Font", sectionId: self.section)
        case let .fontChoice(label):
            return ItemListDisclosureItem(presentationData: presentationData, title: "App Font", label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openFonts()
            })
        case .proxyHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "Network", sectionId: self.section)
        case .proxies:
            return ItemListDisclosureItem(presentationData: presentationData, title: "Proxies", label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openProxies()
            })
        case .actionsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "Actions", sectionId: self.section)
        case .markAllRead:
            return ItemListActionItem(presentationData: presentationData, title: "Mark All Chats as Read", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.markAllChatsAsRead()
            })
        }
    }
}

private func urgramSettingsControllerEntries(settings: UrgramSettings) -> [UrgramSettingsControllerEntry] {
    var entries: [UrgramSettingsControllerEntry] = []

    entries.append(.ghostHeader)
    entries.append(.ghostHideRead(settings.ghostHideRead))
    entries.append(.ghostHideTyping(settings.ghostHideTyping))
    entries.append(.ghostHideOnline(settings.ghostHideOnline))
    entries.append(.ghostHideStoryViews(settings.ghostHideStoryViews))
    entries.append(.ghostFooter)

    entries.append(.privacyHeader)
    entries.append(.streamerMode(settings.streamerMode))
    entries.append(.secretChatScreenshotSilent(settings.secretChatScreenshotSilent))
    entries.append(.hidePhoneInProfile(settings.hidePhoneInProfile))

    entries.append(.contentHeader)
    entries.append(.saveRestrictedBypass(settings.saveRestrictedBypass))
    entries.append(.keepDeletedMessages(settings.keepDeletedMessages))
    entries.append(.keepEditedMessages(settings.keepEditedMessages))
    entries.append(.hideSponsored(settings.hideSponsored))
    entries.append(.keywordFiltersEnabled(settings.keywordFiltersEnabled))
    entries.append(.contentFooter)

    entries.append(.chatsHeader)
    entries.append(.sendWithEnter(settings.sendWithEnter))
    entries.append(.hideStoriesBar(settings.hideStoriesBar))
    entries.append(.disableStories(settings.disableStories))
    entries.append(.foldersAtBottom(settings.foldersAtBottom))
    entries.append(.doubleTapEditOwnMessages(settings.doubleTapEditOwnMessages))
    entries.append(.mentionAll(settings.mentionAll))
    entries.append(.autoReplyEnabled(settings.autoReplyEnabled))
    entries.append(.chatsFooter)

    entries.append(.mediaHeader)
    entries.append(.defaultHDPhotos(settings.defaultHDPhotos))
    entries.append(.downloadBoost(settings.downloadBoost))
    entries.append(.voiceNoiseSuppression(settings.voiceNoiseSuppression))

    entries.append(.callsHeader)
    entries.append(.callConfirmation(settings.callConfirmation))
    entries.append(.forceTcpCalls(settings.forceTcpCalls))

    entries.append(.translationHeader)
    entries.append(.translateChats(settings.translateChats))
    entries.append(.translateOutgoingLongPress(settings.translateOutgoingLongPress))

    entries.append(.fontHeader)
    entries.append(.fontChoice(urgramFontChoiceLabel(settings)))

    entries.append(.proxyHeader)
    entries.append(.proxies)

    entries.append(.actionsHeader)
    entries.append(.markAllRead)

    return entries
}

// URGRAM
func urgramFontChoiceLabel(_ settings: UrgramSettings) -> String {
    switch settings.fontChoice {
    case "tajawal":
        return "Tajawal"
    case "cairo":
        return "Cairo"
    case "plexArabic":
        return "IBM Plex Sans Arabic"
    case "custom":
        return settings.customFontName ?? "Custom"
    default:
        return "System"
    }
}

public func urgramSettingsController(context: AccountContext) -> ViewController {
    var pushImpl: ((ViewController) -> Void)?

    let arguments = UrgramSettingsControllerArguments(
        update: { keyPath, value in
            UrgramSettingsStore.shared.update { settings in
                settings[keyPath: keyPath] = value
            }
            // URGRAM (item 5): the Translate Chats toggle drives Telegram's
            // own translation settings so the feature actually engages.
            if keyPath == \UrgramSettings.translateChats {
                let _ = updateTranslationSettingsInteractively(accountManager: context.sharedContext.accountManager, { current in
                    var updated = current
                    updated.showTranslate = value
                    updated.translateChats = value
                    return updated
                }).startStandalone()
            }
            // URGRAM (item 17): Force TCP mirrors into the experimental
            // settings flag the call stack actually reads.
            if keyPath == \UrgramSettings.forceTcpCalls {
                let _ = updateExperimentalUISettingsInteractively(accountManager: context.sharedContext.accountManager, { current in
                    var updated = current
                    updated.enableVoipTcp = value
                    return updated
                }).startStandalone()
            }
            // URGRAM (item 21): the media picker's HD-photo default is kept
            // in this legacy defaults key (TGMediaAssetsController); writing
            // it makes new photo sends start in HD.
            if keyPath == \UrgramSettings.defaultHDPhotos {
                UserDefaults.standard.set(value, forKey: "TG_photoHighQuality_v0")
            }
        },
        openFonts: {
            pushImpl?(urgramFontSettingsController(context: context))
        },
        openProxies: {
            pushImpl?(urgramProxySettingsController(context: context))
        },
        markAllChatsAsRead: {
            let _ = context.engine.messages.markAllChatsAsRead().startStandalone()
        }
    )

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        UrgramSettingsStore.shared.settingsSignal
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var presentationData = presentationData
        let updatedTheme = presentationData.theme.withModalBlocksBackground()
        presentationData = presentationData.withUpdated(theme: updatedTheme)

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Urgram"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: urgramSettingsControllerEntries(settings: settings), style: .blocks, animateChanges: true)

        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushImpl = { [weak controller] c in
        controller?.push(c)
    }
    return controller
}
