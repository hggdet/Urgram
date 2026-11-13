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
import LocalAuthentication

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
    let openStudio: () -> Void
    let openProxies: () -> Void
    let openArchive: () -> Void
    let openBookmarks: () -> Void
    let openTemplates: () -> Void
    let openHiddenChats: () -> Void
    let pickAutoReplyTemplate: () -> Void
    let cycleAutoArchive: () -> Void
    let markAllChatsAsRead: () -> Void

    init(
        update: @escaping (WritableKeyPath<UrgramSettings, Bool>, Bool) -> Void,
        openFonts: @escaping () -> Void,
        openStudio: @escaping () -> Void,
        openProxies: @escaping () -> Void,
        openArchive: @escaping () -> Void,
        openBookmarks: @escaping () -> Void,
        openTemplates: @escaping () -> Void,
        openHiddenChats: @escaping () -> Void,
        pickAutoReplyTemplate: @escaping () -> Void,
        cycleAutoArchive: @escaping () -> Void,
        markAllChatsAsRead: @escaping () -> Void
    ) {
        self.update = update
        self.openFonts = openFonts
        self.openStudio = openStudio
        self.openProxies = openProxies
        self.openArchive = openArchive
        self.openBookmarks = openBookmarks
        self.openTemplates = openTemplates
        self.openHiddenChats = openHiddenChats
        self.pickAutoReplyTemplate = pickAutoReplyTemplate
        self.cycleAutoArchive = cycleAutoArchive
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
    case studio
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
    case openBookmarks
    case hideSponsored(Bool)
    case keywordFiltersEnabled(Bool)
    case contentFooter

    case chatsHeader
    case hideStoriesBar(Bool)
    case disableStories(Bool)
    case foldersAtBottom(Bool)
    case doubleTapEditOwnMessages(Bool)
    case mentionAll(Bool)
    case autoReplyEnabled(Bool)
    case openTemplates(Int)
    case autoArchive(Int)
    case autoReplyTemplate(String)
    case openHiddenChats(Int)
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

    case studioHeader
    case openStudio(String?)

    case proxyHeader
    case proxies

    case actionsHeader
    case markAllRead
    case accountInfo(Int64, Int32)
    case editionInfo

    var section: ItemListSectionId {
        switch self {
        case .ghostHeader, .ghostHideRead, .ghostHideTyping, .ghostHideOnline, .ghostHideStoryViews, .ghostFooter:
            return UrgramSettingsSection.ghost.rawValue
        case .privacyHeader, .streamerMode, .secretChatScreenshotSilent, .hidePhoneInProfile:
            return UrgramSettingsSection.privacy.rawValue
        case .contentHeader, .saveRestrictedBypass, .keepDeletedMessages, .keepEditedMessages, .openArchive, .openBookmarks, .hideSponsored, .keywordFiltersEnabled, .contentFooter:
            return UrgramSettingsSection.content.rawValue
        case .chatsHeader, .hideStoriesBar, .disableStories, .foldersAtBottom, .doubleTapEditOwnMessages, .mentionAll, .autoReplyEnabled, .autoReplyTemplate, .openTemplates, .autoArchive, .openHiddenChats, .chatsFooter:
            return UrgramSettingsSection.chats.rawValue
        case .mediaHeader, .defaultHDPhotos, .downloadBoost, .voiceNoiseSuppression:
            return UrgramSettingsSection.media.rawValue
        case .callsHeader, .callConfirmation, .forceTcpCalls:
            return UrgramSettingsSection.calls.rawValue
        case .translationHeader, .translateChats, .translateOutgoingLongPress:
            return UrgramSettingsSection.translation.rawValue
        case .fontHeader, .fontChoice:
            return UrgramSettingsSection.font.rawValue
        case .studioHeader, .openStudio:
            return UrgramSettingsSection.studio.rawValue
        case .proxyHeader, .proxies:
            return UrgramSettingsSection.proxy.rawValue
        case .actionsHeader, .markAllRead, .accountInfo, .editionInfo:
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
        case .openBookmarks: return 25
        case .hideSponsored: return 26
        case .keywordFiltersEnabled: return 27
        case .contentFooter: return 28
        case .chatsHeader: return 30
        case .hideStoriesBar: return 32
        case .disableStories: return 33
        case .foldersAtBottom: return 34
        case .doubleTapEditOwnMessages: return 35
        case .mentionAll: return 36
        case .autoReplyEnabled: return 37
        case .openTemplates: return 38
        case .autoArchive: return 39
        case .openHiddenChats: return 40
        case .autoReplyTemplate: return 41
        case .chatsFooter: return 42
        case .mediaHeader: return 45
        case .defaultHDPhotos: return 46
        case .downloadBoost: return 47
        case .voiceNoiseSuppression: return 48
        case .callsHeader: return 50
        case .callConfirmation: return 51
        case .forceTcpCalls: return 52
        case .translationHeader: return 60
        case .translateChats: return 61
        case .translateOutgoingLongPress: return 62
        case .fontHeader: return 70
        case .fontChoice: return 71
        case .studioHeader: return 77
        case .openStudio: return 78
        case .proxyHeader: return 75
        case .proxies: return 76
        case .actionsHeader: return 80
        case .markAllRead: return 81
        case .accountInfo: return 82
        case .editionInfo: return 83
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
            return ItemListDisclosureItem(presentationData: presentationData, title: urgramText(presentationData, "Deleted & Edited Messages Archive", "أرشيف الرسائل المحذوفة والمعدّلة"), label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openArchive()
            })
        case .openBookmarks:
            return ItemListDisclosureItem(presentationData: presentationData, title: urgramText(presentationData, "Bookmarks", "الإشارات المرجعية"), label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openBookmarks()
            })
        case let .hideSponsored(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: urgramText(presentationData, "Hide Sponsored Messages", "إخفاء الرسائل المموّلة"), value: value, keyPath: \.hideSponsored)
        case let .keywordFiltersEnabled(value):
            return self.switchItem(presentationData: presentationData, arguments: arguments, title: urgramText(presentationData, "Keyword Filters", "فلاتر الكلمات"), value: value, keyPath: \.keywordFiltersEnabled)
        case .contentFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(urgramText(presentationData, "Deleted messages are kept only on this device — open the archive above to read them.", "تُحفظ الرسائل المحذوفة على هذا الجهاز فقط — افتح الأرشيف أعلاه لقراءتها.")), sectionId: self.section)
        case .chatsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: urgramText(presentationData, "Chats", "المحادثات"), sectionId: self.section)
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
        case let .autoReplyTemplate(text):
            let label = text.isEmpty ? urgramText(presentationData, "Not Set", "غير مضبوط") : String(text.prefix(24))
            return ItemListDisclosureItem(presentationData: presentationData, title: urgramText(presentationData, "Auto-Reply Message", "رسالة الرد التلقائي"), label: label, sectionId: self.section, style: .blocks, action: {
                arguments.pickAutoReplyTemplate()
            })
        case let .openTemplates(count):
            return ItemListDisclosureItem(presentationData: presentationData, title: urgramText(presentationData, "Quick Replies", "ردود سريعة"), label: count > 0 ? "\(count)" : "", sectionId: self.section, style: .blocks, action: {
                arguments.openTemplates()
            })
        case let .autoArchive(days):
            let label: String
            switch days {
            case 30:
                label = urgramText(presentationData, "30 days", "30 يومًا")
            case 90:
                label = urgramText(presentationData, "90 days", "90 يومًا")
            default:
                label = urgramText(presentationData, "Off", "إيقاف")
            }
            return ItemListDisclosureItem(presentationData: presentationData, title: urgramText(presentationData, "Auto-Archive Inactive Chats", "أرشفة المحادثات الخاملة تلقائيًا"), label: label, sectionId: self.section, style: .blocks, action: {
                arguments.cycleAutoArchive()
            })
        case let .openHiddenChats(count):
            return ItemListDisclosureItem(presentationData: presentationData, title: urgramText(presentationData, "Hidden Chats", "المحادثات المخفية"), label: count > 0 ? "\(count)" : "", sectionId: self.section, style: .blocks, action: {
                arguments.openHiddenChats()
            })
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
        case .studioHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: urgramText(presentationData, "Appearance", "المظهر"), sectionId: self.section)
        case let .openStudio(activeDesignName):
            return ItemListDisclosureItem(presentationData: presentationData, title: urgramText(presentationData, "Urgram Studio", "استوديو أورغرام"), label: activeDesignName ?? "", sectionId: self.section, style: .blocks, action: {
                arguments.openStudio()
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
        case let .accountInfo(id, datacenterId):
            return ItemListTextItem(presentationData: presentationData, text: .plain(urgramText(presentationData, "Your Telegram ID: \(id) • Datacenter: DC\(datacenterId)", "معرّف حسابك (ID): \(id) • مركز البيانات: DC\(datacenterId)")), sectionId: self.section)
        case .editionInfo:
            return ItemListTextItem(presentationData: presentationData, text: .plain(urgramText(presentationData, "Edition: Clean", "النسخة النظيفة")), sectionId: self.section)
        }
    }
}

private func urgramSettingsControllerEntries(settings: UrgramSettings, isArabic: Bool, accountId: Int64, datacenterId: Int32) -> [UrgramSettingsControllerEntry] {
    var entries: [UrgramSettingsControllerEntry] = []

    // URGRAM (build 20, Clean Edition): in the clean edition the bypass
    // sections/rows and every stored-but-unwired (dead) toggle are omitted
    // entirely; the full edition shows everything as before.
    let isClean = UrgramEdition.isClean

    if !isClean {
        entries.append(.ghostHeader)
        entries.append(.ghostHideRead(settings.ghostHideRead))
        entries.append(.ghostHideTyping(settings.ghostHideTyping))
        entries.append(.ghostHideOnline(settings.ghostHideOnline))
        entries.append(.ghostHideStoryViews(settings.ghostHideStoryViews))
        entries.append(.ghostFooter)
    }

    entries.append(.privacyHeader)
    if !isClean {
        entries.append(.streamerMode(settings.streamerMode))
        entries.append(.secretChatScreenshotSilent(settings.secretChatScreenshotSilent))
    }
    entries.append(.hidePhoneInProfile(settings.hidePhoneInProfile))

    entries.append(.contentHeader)
    if !isClean {
        entries.append(.saveRestrictedBypass(settings.saveRestrictedBypass))
        entries.append(.keepDeletedMessages(settings.keepDeletedMessages))
        entries.append(.keepEditedMessages(settings.keepEditedMessages))
        entries.append(.openArchive)
    }
    entries.append(.openBookmarks)
    if !isClean {
        entries.append(.hideSponsored(settings.hideSponsored))
        entries.append(.keywordFiltersEnabled(settings.keywordFiltersEnabled))
        entries.append(.contentFooter)
    }

    entries.append(.chatsHeader)
    entries.append(.hideStoriesBar(settings.hideStoriesBar))
    entries.append(.disableStories(settings.disableStories))
    if !isClean {
        entries.append(.foldersAtBottom(settings.foldersAtBottom))
    }
    entries.append(.mentionAll(settings.mentionAll))
    entries.append(.autoReplyEnabled(settings.autoReplyEnabled))
    entries.append(.autoReplyTemplate(settings.autoReplyText))
    entries.append(.doubleTapEditOwnMessages(settings.doubleTapEditOwnMessages))
    entries.append(.openTemplates(settings.replyTemplates.count))
    entries.append(.autoArchive(settings.autoArchiveInactiveDays))
    entries.append(.openHiddenChats(settings.hiddenPeerIds.count))
    entries.append(.chatsFooter)

    entries.append(.mediaHeader)
    entries.append(.defaultHDPhotos(settings.defaultHDPhotos))
    if !isClean {
        entries.append(.downloadBoost(settings.downloadBoost))
        entries.append(.voiceNoiseSuppression(settings.voiceNoiseSuppression))
    }

    entries.append(.callsHeader)
    entries.append(.callConfirmation(settings.callConfirmation))
    entries.append(.forceTcpCalls(settings.forceTcpCalls))

    entries.append(.translationHeader)
    entries.append(.translateChats(settings.translateChats))
    if !isClean {
        entries.append(.translateOutgoingLongPress(settings.translateOutgoingLongPress))
    }

    entries.append(.fontHeader)
    entries.append(.fontChoice(urgramFontChoiceLabel(settings, isArabic: isArabic)))

    entries.append(.studioHeader)
    entries.append(.openStudio(settings.studioActiveDesignId.flatMap { activeId in settings.studioDesigns.first(where: { $0.id == activeId })?.name }))

    entries.append(.proxyHeader)
    entries.append(.proxies)

    entries.append(.actionsHeader)
    entries.append(.markAllRead)
    entries.append(.accountInfo(accountId, datacenterId))
    if isClean {
        entries.append(.editionInfo)
    }

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
    var presentImpl: ((UIViewController) -> Void)?

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
        openStudio: {
            pushImpl?(urgramStudioController(context: context))
        },
        openProxies: {
            pushImpl?(urgramProxySettingsController(context: context))
        },
        openArchive: {
            pushImpl?(urgramArchiveController(context: context))
        },
        openBookmarks: {
            pushImpl?(urgramBookmarksController(context: context))
        },
        openTemplates: {
            pushImpl?(urgramTemplatesSettingsController(context: context))
        },
        openHiddenChats: {
            // URGRAM (hidden chats): Face ID / device-passcode gate before
            // the hidden-chats list is shown. If the device has no passcode
            // or biometrics configured there is nothing to gate with, so the
            // list opens directly.
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let isArabic = presentationData.strings.primaryComponent.languageCode.hasPrefix("ar")
            let laContext = LAContext()
            var laError: NSError?
            if laContext.canEvaluatePolicy(.deviceOwnerAuthentication, error: &laError) {
                laContext.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: isArabic ? "عرض المحادثات المخفية" : "View hidden chats") { success, _ in
                    Queue.mainQueue().async {
                        if success {
                            pushImpl?(urgramHiddenChatsController(context: context))
                        }
                    }
                }
            } else {
                pushImpl?(urgramHiddenChatsController(context: context))
            }
        },
        pickAutoReplyTemplate: {
            // URGRAM (auto-reply): the reply text is picked from the
            // quick-reply templates, so there is one place to edit phrases.
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let isArabic = presentationData.strings.primaryComponent.languageCode.hasPrefix("ar")
            let templates = UrgramSettingsStore.shared.current.replyTemplates
            if templates.isEmpty {
                let alert = UIAlertController(title: isArabic ? "الرد التلقائي" : "Auto-Reply", message: isArabic ? "أضف عبارات أولًا من «ردود سريعة» في الأعلى، ثم اختر واحدة هنا." : "Add phrases under Quick Replies above first, then pick one here.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: presentationData.strings.Common_OK, style: .default))
                presentImpl?(alert)
                return
            }
            let sheet = UIAlertController(title: isArabic ? "رسالة الرد التلقائي" : "Auto-Reply Message", message: nil, preferredStyle: .actionSheet)
            for template in templates {
                sheet.addAction(UIAlertAction(title: String(template.prefix(60)), style: .default, handler: { _ in
                    UrgramSettingsStore.shared.update { settings in
                        settings.autoReplyText = template
                    }
                }))
            }
            sheet.addAction(UIAlertAction(title: presentationData.strings.Common_Cancel, style: .cancel))
            presentImpl?(sheet)
        },
        cycleAutoArchive: {
            UrgramSettingsStore.shared.update { settings in
                switch settings.autoArchiveInactiveDays {
                case 30:
                    settings.autoArchiveInactiveDays = 90
                case 90:
                    settings.autoArchiveInactiveDays = 0
                default:
                    settings.autoArchiveInactiveDays = 30
                }
            }
        },
        markAllChatsAsRead: {
            // URGRAM (build 20 fix): upstream's engine markAllChatsAsRead()
            // only cleared chats the user had manually marked unread; the
            // interactive variant (the one Telegram's own UI uses) walks
            // every unread chat in the root list.
            let _ = (context.engine.messages.markAllChatsAsReadInteractively(items: [(groupId: .root, filterPredicate: nil)])
            |> deliverOnMainQueue).startStandalone()
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
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: urgramSettingsControllerEntries(settings: settings, isArabic: presentationData.strings.primaryComponent.languageCode.hasPrefix("ar"), accountId: context.account.peerId.toInt64(), datacenterId: Int32(context.account.network.datacenterId)), style: .blocks, animateChanges: true)

        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushImpl = { [weak controller] c in
        controller?.push(c)
    }
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
    return controller
}
