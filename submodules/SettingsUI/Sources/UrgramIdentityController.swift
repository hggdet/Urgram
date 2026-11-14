import Foundation
import UIKit
import PhotosUI
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import AccountContext
import Postbox

// URGRAM: profile identity registry — the publish side.
//
// The editor («هويتي في أورغرام») writes the user's card draft (long bio +
// social links) into UrgramSettings; the banner image is held in memory
// until publishing. Publishing is fully background and invisible: resolve
// the registry supergroup (@majqkq), join it, post ONE record (photo
// message with the URG1 caption, kept-banner by reference, or text-only),
// confirm the record is findable via the same search readers use, then
// leave (posts persist after leaving). Deleting joins, deletes every
// valid own record for everyone, and leaves.
//
// Funnels used (all engine-level, all used elsewhere in the app):
// - resolve: TelegramEnginePeers.resolvePeerByName (TelegramEnginePeers.swift)
// - join: TelegramEnginePeers.joinChannel (TelegramEnginePeers.swift)
// - leave: TelegramEnginePeers.removePeerChat — the same call the stock
//   UI uses to leave a channel (PeerInfoScreen.swift); for a channel it
//   issues channels.leaveChannel (ManagedCloudChatRemoveMessagesOperations.swift)
// - search: TelegramEngineMessages.searchMessages (remote, per-peer)
// - send: enqueueMessages with a TelegramMediaImage built on a
//   LocalFileReferenceMediaResource — the LegacyMediaPickers photo-send
//   construction; keeping an existing banner re-sends it by reference
//   (.message media reference, the ShareController construction)
// - delete: TelegramEngineMessages.deleteMessagesInteractively

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

private func urgramJoinRegistry(context: AccountContext, registryPeerId: PeerId) -> Signal<Bool, NoError> {
    return context.engine.peers.joinChannel(peerId: registryPeerId, hash: nil)
    |> map { _ -> Bool in
        return true
    }
    |> `catch` { _ -> Signal<Bool, NoError> in
        // Joining a supergroup the account already belongs to can surface
        // as an error; fall back to the stored participation status.
        return context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: registryPeerId))
        |> map { peer -> Bool in
            if case let .channel(channel) = peer {
                return channel.participationStatus == .member
            }
            return false
        }
    }
}

private func urgramLeaveRegistry(context: AccountContext, registryPeerId: PeerId) -> Signal<Void, NoError> {
    return context.engine.peers.removePeerChat(peerId: registryPeerId, reportChatSpam: false)
}

/// All valid records in the registry authored by `ownerUserId` (author ==
/// owner and the URG1 marker + JSON parse — the anti-forgery filter),
/// newest first.
private func urgramSearchValidRecords(context: AccountContext, registryPeerId: PeerId, ownerUserId: Int64) -> Signal<[Message], NoError> {
    return context.engine.messages.searchMessages(location: .peer(peerId: registryPeerId, fromId: nil, tags: nil, reactions: nil, threadId: nil, minDate: nil, maxDate: nil), query: "\(ownerUserId)", state: nil, limit: 100)
    |> map { searchResult, _ -> [Message] in
        let messages = searchResult.messages.filter { message in
            guard let author = message.author, author.id.namespace == Namespaces.Peer.CloudUser else {
                return false
            }
            return UrgramIdentityRegistry.parseRecord(text: message.text, authorUserId: author.id.id._internalGetInt64Value(), ownerUserId: ownerUserId) != nil
        }
        return messages.sorted(by: { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp > rhs.timestamp
            }
            return lhs.id.id > rhs.id.id
        })
    }
}

// URGRAM (build 29): step-specific publish outcome, so the editor can say
// WHERE publishing failed instead of one generic "check your connection".
private enum UrgramPublishFailure {
    case resolve
    case join
    case post
}

private enum UrgramPublishResult {
    case success(bannerMessageId: Int32?)
    case failure(UrgramPublishFailure)
}

/// Fetches the just-posted registry message by its id — the publish
/// confirmation (build 29: this replaces the old confirm-by-search, whose
/// server-side search indexing lag and byte-for-byte caption comparison
/// reported "Publishing failed" even when the post had landed). Retries
/// briefly while the message and its media propagate locally.
private func urgramFetchPostedMessage(context: AccountContext, messageId: MessageId, attemptsLeft: Int) -> Signal<EngineMessage?, NoError> {
    return context.engine.data.get(TelegramEngine.EngineData.Item.Messages.Message(id: messageId))
    |> take(1)
    |> mapToSignal { message -> Signal<EngineMessage?, NoError> in
        if let message = message {
            return .single(message)
        }
        if attemptsLeft <= 0 {
            return .single(nil)
        }
        return Signal<EngineMessage?, NoError>.complete()
        |> delay(2.0, queue: Queue.concurrentDefaultQueue())
        |> then(urgramFetchPostedMessage(context: context, messageId: messageId, attemptsLeft: attemptsLeft - 1))
    }
}

/// Publishes the identity record. Success is defined by the post itself:
/// `enqueueMessages` returning a real message id (build 29 — previously
/// success required a server search to find a byte-identical caption,
/// which lagged and mismatched). On success the resolved-record cache is
/// updated immediately so the user's own profile reflects it without
/// waiting for the 24h cache window.
private func urgramPublishIdentity(context: AccountContext, card: UrgramIdentityCard, newBanner: (data: Data, dimensions: PixelDimensions)?, removeBanner: Bool) -> Signal<UrgramPublishResult, NoError> {
    // URGRAM (build 29): lazily attach + seed the identity cache store so
    // the success path's setEntry actually persists (no launch-time
    // attach exists anymore — see UrgramIdentityCacheStore).
    return UrgramIdentityCacheStore.shared.attachAndSeedOnce(accountManager: context.sharedContext.accountManager)
    |> mapToSignal { _ -> Signal<UrgramPublishResult, NoError> in
        return urgramPublishIdentitySeeded(context: context, card: card, newBanner: newBanner, removeBanner: removeBanner)
    }
}

private func urgramPublishIdentitySeeded(context: AccountContext, card: UrgramIdentityCard, newBanner: (data: Data, dimensions: PixelDimensions)?, removeBanner: Bool) -> Signal<UrgramPublishResult, NoError> {
    let ownerPeerId = context.account.peerId
    let ownerUserId = ownerPeerId.id._internalGetInt64Value()
    let recordText = UrgramIdentityRegistry.recordText(ownerUserId: ownerUserId, card: card)

    return urgramResolveRegistryPeerId(context: context)
    |> mapToSignal { registryPeerId -> Signal<UrgramPublishResult, NoError> in
        guard let registryPeerId = registryPeerId else {
            return .single(.failure(.resolve))
        }
        return urgramJoinRegistry(context: context, registryPeerId: registryPeerId)
        |> mapToSignal { joined -> Signal<UrgramPublishResult, NoError> in
            guard joined else {
                return .single(.failure(.join))
            }
            let existingBannerSignal: Signal<(Message, TelegramMediaImage)?, NoError>
            if newBanner == nil && !removeBanner {
                existingBannerSignal = urgramSearchValidRecords(context: context, registryPeerId: registryPeerId, ownerUserId: ownerUserId)
                |> map { records -> (Message, TelegramMediaImage)? in
                    guard let message = records.first else {
                        return nil
                    }
                    for media in message.media {
                        if let image = media as? TelegramMediaImage {
                            return (message, image)
                        }
                    }
                    return nil
                }
            } else {
                existingBannerSignal = .single(nil)
            }
            let publishSignal: Signal<UrgramPublishResult, NoError> = existingBannerSignal
            |> mapToSignal { existingBanner -> Signal<UrgramPublishResult, NoError> in
                let message: EnqueueMessage
                if let newBanner = newBanner {
                    let randomId = Int64.random(in: Int64.min ... Int64.max)
                    let tempFile = EngineTempBox.shared.tempFile(fileName: "urgram-banner-\(randomId).jpg")
                    guard (try? newBanner.data.write(to: URL(fileURLWithPath: tempFile.path))) != nil else {
                        return .single(.failure(.post))
                    }
                    let resource = LocalFileReferenceMediaResource(localFilePath: tempFile.path, randomId: randomId)
                    let representation = TelegramMediaImageRepresentation(dimensions: newBanner.dimensions, resource: resource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false)
                    let image = TelegramMediaImage(imageId: MediaId(namespace: Namespaces.Media.LocalImage, id: randomId), representations: [representation], immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
                    message = .message(text: recordText, attributes: [], inlineStickers: [:], mediaReference: .standalone(media: image), threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
                } else if let existingBanner = existingBanner {
                    message = .message(text: recordText, attributes: [], inlineStickers: [:], mediaReference: .message(message: MessageReference(existingBanner.0), media: existingBanner.1), threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
                } else {
                    message = .message(text: recordText, attributes: [], inlineStickers: [:], mediaReference: nil, threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
                }
                let expectsBanner = newBanner != nil || existingBanner != nil
                return enqueueMessages(account: context.account, peerId: registryPeerId, messages: [message])
                |> take(1)
                |> mapToSignal { ids -> Signal<UrgramPublishResult, NoError> in
                    guard let postedId = ids.compactMap({ $0 }).first else {
                        return .single(.failure(.post))
                    }
                    // The post landed (a real id came back). Fetch the
                    // message by id only to learn whether it carries the
                    // banner image for the cache entry; if the fetch lags
                    // behind the upload, the sent id is trusted instead.
                    return urgramFetchPostedMessage(context: context, messageId: postedId, attemptsLeft: 6)
                    |> map { fetched -> UrgramPublishResult in
                        let bannerMessageId: Int32?
                        if let fetched = fetched {
                            bannerMessageId = fetched.media.contains(where: { $0 is TelegramMediaImage }) ? postedId.id : nil
                        } else {
                            bannerMessageId = expectsBanner ? postedId.id : nil
                        }
                        UrgramIdentityCacheStore.shared.setEntry(UrgramIdentityCacheEntry(card: card, bannerMessageId: bannerMessageId, fetchedAt: Date().timeIntervalSince1970), for: ownerUserId)
                        return .success(bannerMessageId: bannerMessageId)
                    }
                }
            }
            // Whatever happened above, the account leaves the registry
            // group again — its posts persist after leaving.
            return publishSignal
            |> mapToSignal { result -> Signal<UrgramPublishResult, NoError> in
                return urgramLeaveRegistry(context: context, registryPeerId: registryPeerId)
                |> map { _ -> UrgramPublishResult in
                    return result
                }
            }
        }
    }
}

/// Deletes every valid own record from the registry. Returns false when
/// there was nothing to delete or a step failed.
private func urgramDeleteIdentity(context: AccountContext) -> Signal<Bool, NoError> {
    // URGRAM (build 29): lazily attach + seed the identity cache store so
    // the negative-cache setEntry below actually persists.
    return UrgramIdentityCacheStore.shared.attachAndSeedOnce(accountManager: context.sharedContext.accountManager)
    |> mapToSignal { _ -> Signal<Bool, NoError> in
        return urgramDeleteIdentitySeeded(context: context)
    }
}

private func urgramDeleteIdentitySeeded(context: AccountContext) -> Signal<Bool, NoError> {
    let ownerUserId = context.account.peerId.id._internalGetInt64Value()

    return urgramResolveRegistryPeerId(context: context)
    |> mapToSignal { registryPeerId -> Signal<Bool, NoError> in
        guard let registryPeerId = registryPeerId else {
            return .single(false)
        }
        return urgramJoinRegistry(context: context, registryPeerId: registryPeerId)
        |> mapToSignal { joined -> Signal<Bool, NoError> in
            guard joined else {
                return .single(false)
            }
            let deleteSignal = urgramSearchValidRecords(context: context, registryPeerId: registryPeerId, ownerUserId: ownerUserId)
            |> mapToSignal { records -> Signal<Bool, NoError> in
                if records.isEmpty {
                    return .single(false)
                }
                return context.engine.messages.deleteMessagesInteractively(messageIds: records.map { $0.id }, type: .forEveryone)
                |> map { _ -> Bool in
                    UrgramIdentityCacheStore.shared.setEntry(UrgramIdentityCacheEntry(card: nil, bannerMessageId: nil, fetchedAt: Date().timeIntervalSince1970), for: ownerUserId)
                    return true
                }
            }
            return deleteSignal
            |> mapToSignal { success -> Signal<Bool, NoError> in
                return urgramLeaveRegistry(context: context, registryPeerId: registryPeerId)
                |> map { _ -> Bool in
                    return success
                }
            }
        }
    }
}

// MARK: - Editor

private final class UrgramIdentityEditorState {
    var bio: String
    var bannerImage: (data: Data, dimensions: PixelDimensions)?
    var bannerRemoved = false
    var hasExistingBanner = false
    var existingLookupDone = false
    var isBusy = false
    var statusText: String?
    var bioPersistGeneration = 0

    let versionPromise = ValuePromise<Int>(0, ignoreRepeated: false)
    private var version = 0
    let disposable = MetaDisposable()

    init(bio: String) {
        self.bio = bio
    }

    func bump() {
        self.version += 1
        self.versionPromise.set(self.version)
    }
}

private var urgramIdentityPhotoPickerDelegate: UrgramIdentityPhotoPickerDelegate?

private final class UrgramIdentityPhotoPickerDelegate: NSObject, PHPickerViewControllerDelegate {
    var onPick: ((UIImage?) -> Void)?

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else {
            self.onPick?(nil)
            return
        }
        let _ = provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            Queue.mainQueue().async {
                self?.onPick?(object as? UIImage)
            }
        }
    }
}

private func urgramPrepareBannerImage(_ image: UIImage) -> (data: Data, dimensions: PixelDimensions)? {
    let maxDimension: CGFloat = 1280.0
    let size = image.size
    guard size.width > 0.0, size.height > 0.0 else {
        return nil
    }
    let scale = max(size.width, size.height) > maxDimension ? maxDimension / max(size.width, size.height) : 1.0
    let targetSize = CGSize(width: max(1.0, floor(size.width * scale)), height: max(1.0, floor(size.height * scale)))
    let renderer = UIGraphicsImageRenderer(size: targetSize)
    let scaled = renderer.image { _ in
        image.draw(in: CGRect(origin: CGPoint(), size: targetSize))
    }
    guard let data = scaled.jpegData(compressionQuality: 0.85) else {
        return nil
    }
    return (data, PixelDimensions(targetSize))
}

private final class UrgramIdentityControllerArguments {
    let bannerAction: () -> Void
    let bioUpdated: (String) -> Void
    let linkAction: (Int) -> Void
    let addLink: () -> Void
    let publish: () -> Void
    let deleteIdentity: () -> Void

    init(bannerAction: @escaping () -> Void, bioUpdated: @escaping (String) -> Void, linkAction: @escaping (Int) -> Void, addLink: @escaping () -> Void, publish: @escaping () -> Void, deleteIdentity: @escaping () -> Void) {
        self.bannerAction = bannerAction
        self.bioUpdated = bioUpdated
        self.linkAction = linkAction
        self.addLink = addLink
        self.publish = publish
        self.deleteIdentity = deleteIdentity
    }
}

private enum UrgramIdentityControllerEntry: ItemListNodeEntry {
    case header
    case banner(String)
    case bioHeader
    case bio(String)
    case linksHeader
    case link(Int, UrgramIdentityLink)
    case addLink
    case publish
    case deleteIdentity
    case status(String)
    case footer

    var section: ItemListSectionId {
        switch self {
        case .header, .banner, .bioHeader, .bio:
            return 0
        case .linksHeader, .link, .addLink:
            return 1
        case .publish, .deleteIdentity, .status, .footer:
            return 2
        }
    }

    var stableId: Int32 {
        switch self {
        case .header: return 0
        case .banner: return 1
        case .bioHeader: return 2
        case .bio: return 3
        case .linksHeader: return 10
        case let .link(index, _): return 20 + Int32(index)
        case .addLink: return 100
        case .publish: return 110
        case .deleteIdentity: return 111
        case .status: return 112
        case .footer: return 113
        }
    }

    static func <(lhs: UrgramIdentityControllerEntry, rhs: UrgramIdentityControllerEntry) -> Bool {
        if lhs.section != rhs.section {
            return lhs.section < rhs.section
        }
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! UrgramIdentityControllerArguments
        switch self {
        case .header:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: urgramText(presentationData, "My Urgram Identity", "هويتي في أورغرام"), sectionId: self.section)
        case let .banner(label):
            return ItemListDisclosureItem(presentationData: presentationData, title: urgramText(presentationData, "Profile Banner", "صورة البنر"), label: label, sectionId: self.section, style: .blocks, action: {
                arguments.bannerAction()
            })
        case .bioHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: urgramText(presentationData, "Long Bio", "نبذة طويلة"), sectionId: self.section)
        case let .bio(text):
            return ItemListMultilineInputItem(presentationData: presentationData, text: text, placeholder: urgramText(presentationData, "Write more about yourself — only Urgram users see this", "اكتب عن نفسك أكثر — يراها مستخدمو أورغرام فقط"), maxLength: ItemListMultilineInputItemTextLimit(value: 2000, display: true), sectionId: self.section, style: .blocks, capitalization: true, autocorrection: true, minimalHeight: 90.0, textUpdated: { text in
                arguments.bioUpdated(text)
            })
        case .linksHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: urgramText(presentationData, "My Accounts", "روابط حساباتي"), sectionId: self.section)
        case let .link(index, link):
            return ItemListDisclosureItem(presentationData: presentationData, title: UrgramIdentityRegistry.linkTitle(link.type, isArabic: urgramIsArabicLanguage(presentationData)), label: link.value, sectionId: self.section, style: .blocks, action: {
                arguments.linkAction(index)
            })
        case .addLink:
            return ItemListActionItem(presentationData: presentationData, title: urgramText(presentationData, "Add Link", "إضافة رابط"), kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.addLink()
            })
        case .publish:
            return ItemListActionItem(presentationData: presentationData, title: urgramText(presentationData, "Publish My Identity", "نشر هويتي"), kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.publish()
            })
        case .deleteIdentity:
            return ItemListActionItem(presentationData: presentationData, title: urgramText(presentationData, "Delete My Identity", "حذف هويتي"), kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.deleteIdentity()
            })
        case let .status(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case .footer:
            return ItemListTextItem(presentationData: presentationData, text: .plain(urgramText(presentationData, "Your banner and card are visible only to Urgram users, on your profile. Publishing happens in the background — you won't see any group or extra chat.", "بنرك وبطاقتك يظهران لمستخدمي أورغرام فقط، في ملفك الشخصي. النشر يتم بالخلفية — لن ترى أي مجموعة أو محادثة إضافية.")), sectionId: self.section)
        }
    }
}

private func urgramIdentityControllerEntries(settings: UrgramSettings, state: UrgramIdentityEditorState, presentationData: ItemListPresentationData) -> [UrgramIdentityControllerEntry] {
    let isArabic = urgramIsArabicLanguage(presentationData)
    var entries: [UrgramIdentityControllerEntry] = []

    entries.append(.header)
    let bannerLabel: String
    if state.bannerImage != nil {
        bannerLabel = isArabic ? "جديدة — جاهزة للنشر" : "New — ready to publish"
    } else if state.bannerRemoved {
        bannerLabel = isArabic ? "بدون بنر" : "No banner"
    } else if !state.existingLookupDone {
        bannerLabel = isArabic ? "جارٍ التحقق…" : "Checking…"
    } else if state.hasExistingBanner {
        bannerLabel = isArabic ? "البنر الحالي منشور" : "Current banner is live"
    } else {
        bannerLabel = isArabic ? "بدون بنر" : "No banner"
    }
    entries.append(.banner(bannerLabel))
    entries.append(.bioHeader)
    entries.append(.bio(state.bio))

    entries.append(.linksHeader)
    for (index, link) in settings.identityLinks.enumerated() {
        entries.append(.link(index, link))
    }
    entries.append(.addLink)

    entries.append(.publish)
    entries.append(.deleteIdentity)
    if state.isBusy {
        entries.append(.status(isArabic ? "جارٍ العمل…" : "Working…"))
    } else if let statusText = state.statusText {
        entries.append(.status(statusText))
    }
    entries.append(.footer)

    return entries
}

public func urgramIdentityController(context: AccountContext) -> ViewController {
    var presentImpl: ((UIViewController) -> Void)?

    let initialSettings = UrgramSettingsStore.shared.current
    let state = UrgramIdentityEditorState(bio: initialSettings.identityBio)
    let ownerUserId = context.account.peerId.id._internalGetInt64Value()

    // Look up the currently published record once, so the banner row can
    // say whether a banner is already live (publishing without picking a
    // new image keeps it).
    state.disposable.set((urgramResolveRegistryPeerId(context: context)
    |> mapToSignal { registryPeerId -> Signal<Bool, NoError> in
        guard let registryPeerId = registryPeerId else {
            return .single(false)
        }
        return urgramSearchValidRecords(context: context, registryPeerId: registryPeerId, ownerUserId: ownerUserId)
        |> map { records -> Bool in
            guard let message = records.first else {
                return false
            }
            return message.media.contains(where: { $0 is TelegramMediaImage })
        }
    }
    |> deliverOnMainQueue).start(next: { hasBanner in
        state.hasExistingBanner = hasBanner
        state.existingLookupDone = true
        state.bump()
    }))

    let arguments = UrgramIdentityControllerArguments(
        bannerAction: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let isArabic = presentationData.strings.primaryComponent.languageCode.hasPrefix("ar")
            let sheet = UIAlertController(title: isArabic ? "صورة البنر" : "Profile Banner", message: nil, preferredStyle: .actionSheet)
            sheet.addAction(UIAlertAction(title: isArabic ? "اختر صورة من المكتبة" : "Choose Photo", style: .default, handler: { _ in
                var configuration = PHPickerConfiguration()
                configuration.filter = .images
                configuration.selectionLimit = 1
                let delegate = UrgramIdentityPhotoPickerDelegate()
                delegate.onPick = { image in
                    urgramIdentityPhotoPickerDelegate = nil
                    guard let image = image, let prepared = urgramPrepareBannerImage(image) else {
                        return
                    }
                    state.bannerImage = prepared
                    state.bannerRemoved = false
                    state.bump()
                }
                urgramIdentityPhotoPickerDelegate = delegate
                let picker = PHPickerViewController(configuration: configuration)
                picker.delegate = delegate
                presentImpl?(picker)
            }))
            if state.bannerImage != nil || state.hasExistingBanner {
                sheet.addAction(UIAlertAction(title: isArabic ? "إزالة البنر" : "Remove Banner", style: .destructive, handler: { _ in
                    state.bannerImage = nil
                    state.bannerRemoved = true
                    state.bump()
                }))
            }
            sheet.addAction(UIAlertAction(title: presentationData.strings.Common_Cancel, style: .cancel))
            presentImpl?(sheet)
        },
        bioUpdated: { text in
            state.bio = text
            // Debounced persist so the draft survives leaving the screen.
            state.bioPersistGeneration += 1
            let generation = state.bioPersistGeneration
            Queue.mainQueue().after(1.0) {
                if state.bioPersistGeneration == generation {
                    let bio = state.bio
                    UrgramSettingsStore.shared.update { settings in
                        settings.identityBio = bio
                    }
                }
            }
        },
        linkAction: { index in
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let isArabic = presentationData.strings.primaryComponent.languageCode.hasPrefix("ar")
            let links = UrgramSettingsStore.shared.current.identityLinks
            guard index < links.count else {
                return
            }
            let link = links[index]
            let sheet = UIAlertController(title: link.value, message: nil, preferredStyle: .actionSheet)
            sheet.addAction(UIAlertAction(title: isArabic ? "تعديل" : "Edit", style: .default, handler: { _ in
                let alert = UIAlertController(title: UrgramIdentityRegistry.linkTitle(link.type, isArabic: isArabic), message: nil, preferredStyle: .alert)
                alert.addTextField(configurationHandler: { textField in
                    textField.text = link.value
                    textField.autocorrectionType = .no
                    textField.autocapitalizationType = .none
                })
                alert.addAction(UIAlertAction(title: presentationData.strings.Common_Cancel, style: .cancel))
                alert.addAction(UIAlertAction(title: isArabic ? "حفظ" : "Save", style: .default, handler: { _ in
                    let value = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !value.isEmpty {
                        UrgramSettingsStore.shared.update { settings in
                            if index < settings.identityLinks.count {
                                settings.identityLinks[index].value = value
                            }
                        }
                    }
                }))
                presentImpl?(alert)
            }))
            sheet.addAction(UIAlertAction(title: isArabic ? "حذف" : "Delete", style: .destructive, handler: { _ in
                UrgramSettingsStore.shared.update { settings in
                    if index < settings.identityLinks.count {
                        settings.identityLinks.remove(at: index)
                    }
                }
            }))
            sheet.addAction(UIAlertAction(title: presentationData.strings.Common_Cancel, style: .cancel))
            presentImpl?(sheet)
        },
        addLink: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let isArabic = presentationData.strings.primaryComponent.languageCode.hasPrefix("ar")
            let types: [(String, String)] = [
                ("instagram", "Instagram"),
                ("tiktok", "TikTok"),
                ("x", "X"),
                ("youtube", "YouTube"),
                ("web", isArabic ? "موقع ويب" : "Website"),
                ("custom", isArabic ? "رابط آخر" : "Other Link")
            ]
            let sheet = UIAlertController(title: isArabic ? "إضافة رابط" : "Add Link", message: nil, preferredStyle: .actionSheet)
            for (type, title) in types {
                sheet.addAction(UIAlertAction(title: title, style: .default, handler: { _ in
                    let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
                    alert.addTextField(configurationHandler: { textField in
                        textField.placeholder = (type == "web" || type == "custom") ? "https://" : (isArabic ? "اسم المستخدم" : "Username")
                        textField.autocorrectionType = .no
                        textField.autocapitalizationType = .none
                    })
                    alert.addAction(UIAlertAction(title: presentationData.strings.Common_Cancel, style: .cancel))
                    alert.addAction(UIAlertAction(title: isArabic ? "حفظ" : "Save", style: .default, handler: { _ in
                        let value = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        if !value.isEmpty {
                            UrgramSettingsStore.shared.update { settings in
                                settings.identityLinks.append(UrgramIdentityLink(type: type, value: value))
                            }
                        }
                    }))
                    presentImpl?(alert)
                }))
            }
            sheet.addAction(UIAlertAction(title: presentationData.strings.Common_Cancel, style: .cancel))
            presentImpl?(sheet)
        },
        publish: {
            guard !state.isBusy else {
                return
            }
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let isArabic = presentationData.strings.primaryComponent.languageCode.hasPrefix("ar")
            // Persist the draft first so what is published matches the
            // editor, and build the card from the current settings.
            let bio = state.bio
            UrgramSettingsStore.shared.update { settings in
                settings.identityBio = bio
            }
            let card = UrgramIdentityCard(bio: bio, links: UrgramSettingsStore.shared.current.identityLinks)
            if card.bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && card.links.isEmpty && state.bannerImage == nil && !state.hasExistingBanner {
                state.statusText = isArabic ? "أضف نبذة أو رابطًا أو صورة بنر أولًا." : "Add a bio, a link or a banner photo first."
                state.bump()
                return
            }
            state.isBusy = true
            state.statusText = nil
            state.bump()
            state.disposable.set((urgramPublishIdentity(context: context, card: card, newBanner: state.bannerImage, removeBanner: state.bannerRemoved)
            |> deliverOnMainQueue).start(next: { result in
                state.isBusy = false
                switch result {
                case .success:
                    state.statusText = isArabic ? "تم النشر — هويتك ظاهرة الآن لمستخدمي أورغرام." : "Published — your identity is now visible to Urgram users."
                    if state.bannerImage != nil {
                        state.hasExistingBanner = true
                        state.bannerImage = nil
                    }
                    if state.bannerRemoved {
                        state.hasExistingBanner = false
                        state.bannerRemoved = false
                    }
                case .failure(.resolve):
                    state.statusText = isArabic ? "تعذّر النشر — لم يتم العثور على مجموعة السجل." : "Publishing failed — the registry group could not be found."
                case .failure(.join):
                    state.statusText = isArabic ? "تعذّر النشر — تعذّر الانضمام إلى مجموعة السجل." : "Publishing failed — could not join the registry group."
                case .failure(.post):
                    state.statusText = isArabic ? "تعذّر النشر عند خطوة الإرسال — حاول مجددًا." : "Publishing failed at the posting step — try again."
                }
                state.bump()
            }))
        },
        deleteIdentity: {
            guard !state.isBusy else {
                return
            }
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let isArabic = presentationData.strings.primaryComponent.languageCode.hasPrefix("ar")
            let alert = UIAlertController(title: isArabic ? "حذف هويتي" : "Delete My Identity", message: isArabic ? "سيُحذف بنرك وبطاقتك المنشورة. المسودة هنا تبقى." : "Your published banner and card will be deleted. The draft here stays.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: presentationData.strings.Common_Cancel, style: .cancel))
            alert.addAction(UIAlertAction(title: isArabic ? "حذف" : "Delete", style: .destructive, handler: { _ in
                state.isBusy = true
                state.statusText = nil
                state.bump()
                state.disposable.set((urgramDeleteIdentity(context: context)
                |> deliverOnMainQueue).start(next: { success in
                    state.isBusy = false
                    if success {
                        state.statusText = isArabic ? "تم حذف هويتك المنشورة." : "Your published identity was deleted."
                        state.hasExistingBanner = false
                        state.bannerRemoved = false
                    } else {
                        state.statusText = isArabic ? "لا توجد هوية منشورة لحذفها، أو تعذّر الحذف." : "No published identity to delete, or deletion failed."
                    }
                    state.bump()
                }))
            }))
            presentImpl?(alert)
        }
    )

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        UrgramSettingsStore.shared.settingsSignal,
        state.versionPromise.get()
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var presentationData = presentationData
        let updatedTheme = presentationData.theme.withModalBlocksBackground()
        presentationData = presentationData.withUpdated(theme: updatedTheme)

        let isArabic = presentationData.strings.primaryComponent.languageCode.hasPrefix("ar")
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(isArabic ? "هويتي في أورغرام" : "My Urgram Identity"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: urgramIdentityControllerEntries(settings: settings, state: state, presentationData: ItemListPresentationData(presentationData)), style: .blocks, animateChanges: true)

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
    return controller
}
