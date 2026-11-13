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

// URGRAM: fork UI strings are bilingual — Telegram's generated string
// tables carry no fork keys, so Urgram screens pick Arabic when the app
// language is Arabic and English otherwise.
func urgramIsArabicLanguage(_ presentationData: ItemListPresentationData) -> Bool {
    return presentationData.strings.primaryComponent.languageCode.hasPrefix("ar")
}

func urgramText(_ presentationData: ItemListPresentationData, _ en: String, _ ar: String) -> String {
    return urgramIsArabicLanguage(presentationData) ? ar : en
}

private final class UrgramSettingsControllerArguments {
    let update: (WritableKeyPath<UrgramSettings, Bool>, Bool) -> Void
    let openFonts: () -> Void
    let openProxies: () -> Void
    let openArchive: () -> Void
    let markAllChatsAsRead: () -> Void

    init(
        update: @escaping (WritableKeyPath<UrgramSettings, Bool>, Bool) -> Void,
        openFonts: @escaping () -> Void,
        openProxies: @escaping () -> Void,
        openArchive: @escaping () -> Void,
        markAllChatsAsRead: @escaping () -> Void
    ) {
        self.update = update
        self.openFonts = openFonts
        self.openProxies = openProxies
        self.openArchive = openArchive
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
    case openArchive
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
    case accountId(Int64)

    var section: ItemListSectionId {
        switch self {
        case .ghostHeader, .ghostHideRead, .ghostHideTyping, .ghostHideOnline, .ghostHideStoryViews, .ghostFooter:
            return UrgramSettingsSection.ghost.rawValue
        case .privacyHeader, .streamerMode, .secretChatScreenshotSilent, .hidePhoneInProfile:
            return UrgramSettingsSection.privacy.rawValue
        case .contentHeader, .saveRestrictedBypass, .keepDeletedMessages, .keepEditedMessages, .openArchive, .hideSponsored, .keywordFiltersEnabled, .contentFooter:
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
        case .actionsHeader, .markAllRead, .accountId:
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
        case .openArchive: return 24
        case .hideSponsored: return 25
        case .keywordFiltersEnabled: return 26
        case .contentFooter: return 27
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
        case .accountId: return 82
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
            return ItemListSectionHeaderItem(presentationData: presentationData, text: urgramText(presentationData, "Ghost Mode", "وضع الشبح"), sectionId: self.section)
        case let .ghostHideRead(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: urgramText(presentationData, "Hide Read Receipts", "إخفاء علامات القراءة"), value: value, keyPath: \.ghostHideRead)
        case let .ghostHideTyping(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: urgramText(presentationData, "Hide Typing", "إخفاء مؤشر الكتابة"), value: value, keyPath: \.ghostHideTyping)
        case let .ghostHideOnline(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: urgramText(presentationData, "Hide Online Status", "إخفاء حالة الاتصال"), value: value, keyPath: \.ghostHideOnline)
        case let .ghostHideStoryViews(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: urgramText(presentationData, "Hide Story Views", "إخفاء مشاهدات القصص"), value: value, keyPath: \.ghostHideStoryViews)
        case .ghostFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(urgramText(presentationData, "With Ghost Mode on, other people won't see when you read, type, come online or watch stories. Your chats still update normally on this device.", "عند تفعيل وضع الشبح، لن يرى الآخرون متى تقرأ أو تكتب أو تتصل أو تشاهد القصص. محادثاتك تُحدَّث بشكل طبيعي على هذا الجهاز.")), sectionId: self.section)
        case .privacyHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: urgramText(presentationData, "Privacy", "الخصوصية"), sectionId: self.section)
        case let .streamerMode(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: urgramText(presentationData, "Streamer Mode", "وضع البث"), value: value, keyPath: \.streamerMode)
        case let .secretChatScreenshotSilent(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: urgramText(presentationData, "Secret Chat Screenshots Without Notification", "لقطات المحادثة السرية بدون إشعار"), value: value, keyPath: \.secretChatScreenshotSilent)
        case let .hidePhoneInProfile(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: urgramText(presentationData, "Hide Phone Number in My Profile", "إخفاء رقم هاتفي في ملفي الشخصي"), value: value, keyPath: \.hidePhoneInProfile)
        case .contentHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: urgramText(presentationData, "Content", "المحتوى"), sectionId: self.section)
        case let .saveRestrictedBypass(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: urgramText(presentationData, "Save Restricted Content", "حفظ المحتوى المقيد"), value: value, keyPath: \.saveRestrictedBypass)
        case let .keepDeletedMessages(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: urgramText(presentationData, "Keep Deleted Messages", "الاحتفاظ بالرسائل المحذوفة"), value: value, keyPath: \.keepDeletedMessages)
        case let .keepEditedMessages(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: urgramText(presentationData, "Keep Original Text of Edited Messages", "الاحتفاظ بالنص الأصلي للرسائل المعدّلة"), value: value, keyPath: \.keepEditedMessages)
        case .openArchive:
            return ItemListDisclosureItem(presentationData: presentationData, title: urgramText(presentationData, "Deleted Messages Archive", "أرشيف الرسائل المحذوفة"), label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openArchive()
            })
        case let .hideSponsored(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: urgramText(presentationData, "Hide Sponsored Messages", "إخفاء الرسائل المموّلة"), value: value, keyPath: \.hideSponsored)
        case let .keywordFiltersEnabled(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: urgramText(presentationData, "Keyword Filters", "فلاتر الكلمات"), value: value, keyPath: \.keywordFiltersEnabled)
        case .contentFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(urgramText(presentationData, "Deleted messages are kept only on this device — open the archive above to read them.", "تُحفظ الرسائل المحذوفة على هذا الجهاز فقط — افتح الأرشيف أعلاه لقراءتها.")), sectionId: self.section)
        case .chatsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: urgramText(presentationData, "Chats", "المحادثات"), sectionId: self.section)
        case let .sendWithEnter(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: urgramText(presentationData, "Send With Enter", "الإرسال بزر الإدخال"), value: value, keyPath: \.sendWithEnter)
        case let .hideStoriesBar(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: urgramText(presentationData, "Hide Stories Bar", "إخفاء شريط القصص"), value: value, keyPath: \.hideStoriesBar)
        case let .disableStories(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: urgramText(presentationData, "Disable Stories", "تعطيل القصص"), value: value, keyPath: \.disableStories)
        case let .foldersAtBottom(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: urgramText(presentationData, "Folders at Bottom", "المجلدات في الأسفل"), value: value, keyPath: \.foldersAtBottom)
        case let .doubleTapEditOwnMessages(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: urgramText(presentationData, "Double-Tap to Edit My Messages", "الضغط مرتين لتعديل رسائلي"), value: value, keyPath: \.doubleTapEditOwnMessages)
        case let .mentionAll(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: urgramText(presentationData, "Mention All (@all)", "منشن الجميع (@all)"), value: value, keyPath: \.mentionAll)
        case let .autoReplyEnabled(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: urgramText(presentationData, "Auto-Reply", "الرد التلقائي"), value: value, keyPath: \.autoReplyEnabled)
        case .chatsFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(urgramText(presentationData, "Some chat options take effect the next time the chat is opened.", "بعض خيارات المحادثة تسري عند فتح المحادثة في المرة القادمة.")), sectionId: self.section)
        case .mediaHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: urgramText(presentationData, "Media and Downloads", "الوسائط والتنزيلات"), sectionId: self.section)
        case let .defaultHDPhotos(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: urgramText(presentationData, "Send Photos in HD by Default", "إرسال الصور بجودة HD افتراضيًا"), value: value, keyPath: \.defaultHDPhotos)
        case let .downloadBoost(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: urgramText(presentationData, "Download Boost", "تسريع التنزيل"), value: value, keyPath: \.downloadBoost)
        case let .voiceNoiseSuppression(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: urgramText(presentationData, "Voice Message Noise Suppression", "كتم ضوضاء الرسائل الصوتية"), value: value, keyPath: \.voiceNoiseSuppression)
        case .callsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: urgramText(presentationData, "Calls", "المكالمات"), sectionId: self.section)
        case let .callConfirmation(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: urgramText(presentationData, "Confirm Before Calling", "التأكيد قبل الاتصال"), value: value, keyPath: \.callConfirmation)
        case let .forceTcpCalls(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: urgramText(presentationData, "Force TCP for Calls", "فرض TCP للمكالمات"), value: value, keyPath: \.forceTcpCalls)
        case .translationHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: urgramText(presentationData, "Translation", "الترجمة"), sectionId: self.section)
        case let .translateChats(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: urgramText(presentationData, "Translate Whole Chats", "ترجمة المحادثات كاملة"), value: value, keyPath: \.translateChats)
        case let .translateOutgoingLongPress(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: urgramText(presentationData, "Long-Press Send to Translate", "الضغط المطوّل على الإرسال للترجمة"), value: value, keyPath: \.translateOutgoingLongPress)
        case .fontHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: urgramText(presentationData, "Font", "الخط"), sectionId: self.section)
        case let .fontChoice(label):
            return ItemListDisclosureItem(presentationData: presentationData, title: urgramText(presentationData, "App Font", "خط التطبيق"), label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openFonts()
            })
        case .proxyHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: urgramText(presentationData, "Network", "الشبكة"), sectionId: self.section)
        case .proxies:
            return ItemListDisclosureItem(presentationData: presentationData, title: urgramText(presentationData, "Proxies", "البروكسيات"), label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openProxies()
            })
        case .actionsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: urgramText(presentationData, "Actions", "إجراءات"), sectionId: self.section)
        case .markAllRead:
            return ItemListActionItem(presentationData: presentationData, title: urgramText(presentationData, "Mark All Chats as Read", "تعليم كل المحادثات كمقروءة"), kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.markAllChatsAsRead()
            })
        case let .accountId(id):
            return ItemListTextItem(presentationData: presentationData, text: .plain(urgramText(presentationData, "Your Telegram ID: \(id)", "معرّف حسابك (ID): \(id)")), sectionId: self.section)
        }
    }
}

private func urgramSettingsControllerEntries(settings: UrgramSettings, isArabic: Bool, accountId: Int64) -> [UrgramSettingsControllerEntry] {
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
    entries.append(.openArchive)
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
    entries.append(.fontChoice(urgramFontChoiceLabel(settings, isArabic: isArabic)))

    entries.append(.proxyHeader)
    entries.append(.proxies)

    entries.append(.actionsHeader)
    entries.append(.markAllRead)
    entries.append(.accountId(accountId))

    return entries
}

// URGRAM (font family names stay in Latin as proper names; only the
// System/Custom labels follow the app language.)
func urgramFontChoiceLabel(_ settings: UrgramSettings, isArabic: Bool) -> String {
    switch settings.fontChoice {
    case "tajawal":
        return "Tajawal"
    case "cairo":
        return "Cairo"
    case "plexArabic":
        return "IBM Plex Sans Arabic"
    case "custom":
        return settings.customFontName ?? (isArabic ? "مخصص" : "Custom")
    default:
        return isArabic ? "النظام" : "System"
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
        openArchive: {
            pushImpl?(urgramArchiveController(context: context))
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
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: urgramSettingsControllerEntries(settings: settings, isArabic: presentationData.strings.primaryComponent.languageCode.hasPrefix("ar"), accountId: context.account.peerId.toInt64()), style: .blocks, animateChanges: true)

        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushImpl = { [weak controller] c in
        controller?.push(c)
    }
    return controller
}
