import Foundation
import Postbox

// URGRAM (item 3): local archive of messages removed through
// `_internal_deleteMessages` while "Keep Deleted Messages" is on. Stored as a
// single per-account preferences entry (text + metadata only; media files are
// not preserved). Read back via `urgramArchivedMessages(transaction:)`.

public struct UrgramArchivedMessage: Equatable {
    public var peerId: Int64
    public var namespace: Int32
    public var messageId: Int32
    public var timestamp: Int32
    public var authorId: Int64?
    public var isOutgoing: Bool
    public var text: String
    public var mediaKind: String

    public init(peerId: Int64, namespace: Int32, messageId: Int32, timestamp: Int32, authorId: Int64?, isOutgoing: Bool, text: String, mediaKind: String) {
        self.peerId = peerId
        self.namespace = namespace
        self.messageId = messageId
        self.timestamp = timestamp
        self.authorId = authorId
        self.isOutgoing = isOutgoing
        self.text = text
        self.mediaKind = mediaKind
    }
}

extension UrgramArchivedMessage: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)
        self.peerId = try container.decode(Int64.self, forKey: "peerId")
        self.namespace = try container.decode(Int32.self, forKey: "namespace")
        self.messageId = try container.decode(Int32.self, forKey: "messageId")
        self.timestamp = try container.decode(Int32.self, forKey: "timestamp")
        self.authorId = try container.decodeIfPresent(Int64.self, forKey: "authorId")
        self.isOutgoing = (try container.decode(Int32.self, forKey: "isOutgoing")) != 0
        self.text = try container.decode(String.self, forKey: "text")
        self.mediaKind = try container.decode(String.self, forKey: "mediaKind")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        try container.encode(self.peerId, forKey: "peerId")
        try container.encode(self.namespace, forKey: "namespace")
        try container.encode(self.messageId, forKey: "messageId")
        try container.encode(self.timestamp, forKey: "timestamp")
        if let authorId = self.authorId {
            try container.encode(authorId, forKey: "authorId")
        } else {
            try container.encodeNil(forKey: "authorId")
        }
        try container.encode((self.isOutgoing ? 1 : 0) as Int32, forKey: "isOutgoing")
        try container.encode(self.text, forKey: "text")
        try container.encode(self.mediaKind, forKey: "mediaKind")
    }
}

// URGRAM: preferences key for the archive. Value 100 sits clear of the
// app-specific keys in TelegramUIPreferences/PostboxKeys.swift (0...26).
private let urgramMessageArchivePreferencesKey: ValueBoxKey = applicationSpecificPreferencesKey(100)

private let urgramMessageArchiveLimit = 1000

// URGRAM
public func urgramArchivedMessages(transaction: Transaction) -> [UrgramArchivedMessage] {
    return transaction.getPreferencesEntry(key: urgramMessageArchivePreferencesKey)?.get([UrgramArchivedMessage].self) ?? []
}

// URGRAM: empties the archive (used by the archive viewer's Clear action).
public func urgramClearMessageArchive(transaction: Transaction) {
    if let entry = PreferencesEntry([UrgramArchivedMessage]()) {
        transaction.setPreferencesEntry(key: urgramMessageArchivePreferencesKey, value: entry)
    }
}

// URGRAM (item 3, edits): pre-edit originals live under their own key (101)
// so the viewer can present them separately from deleted messages. The
// record's fields describe the ORIGINAL (pre-edit) message.
private let urgramEditedOriginalsPreferencesKey: ValueBoxKey = applicationSpecificPreferencesKey(101)

private let urgramEditedOriginalsLimit = 1000

// URGRAM
public func urgramEditedOriginals(transaction: Transaction) -> [UrgramArchivedMessage] {
    return transaction.getPreferencesEntry(key: urgramEditedOriginalsPreferencesKey)?.get([UrgramArchivedMessage].self) ?? []
}

// URGRAM
public func urgramClearEditedOriginals(transaction: Transaction) {
    if let entry = PreferencesEntry([UrgramArchivedMessage]()) {
        transaction.setPreferencesEntry(key: urgramEditedOriginalsPreferencesKey, value: entry)
    }
}

// URGRAM: called from StateReplay.applyEditMessage before the edit is
// applied, so the message's current (pre-edit) text survives locally.
// No-ops when the stored text already equals the incoming text (media- or
// caption-only edits, reaction updates, and own edits whose response was
// already applied by RequestEditMessage all land here with equal text).
func urgramArchiveEditBeforeUpdate(transaction: Transaction, id: MessageId, newText: String) {
    guard let old = transaction.getMessage(id) else {
        return
    }
    if old.text.isEmpty || old.text == newText {
        return
    }
    let mediaKind: String
    if let firstMedia = old.media.first {
        mediaKind = String(describing: type(of: firstMedia))
    } else {
        mediaKind = ""
    }
    let record = UrgramArchivedMessage(
        peerId: id.peerId.toInt64(),
        namespace: id.namespace,
        messageId: id.id,
        timestamp: old.timestamp,
        authorId: old.author?.id.toInt64(),
        isOutgoing: !old.flags.contains(.Incoming),
        text: old.text,
        mediaKind: mediaKind
    )
    var originals = urgramEditedOriginals(transaction: transaction)
    originals.append(record)
    if originals.count > urgramEditedOriginalsLimit {
        originals.removeFirst(originals.count - urgramEditedOriginalsLimit)
    }
    if let entry = PreferencesEntry(originals) {
        transaction.setPreferencesEntry(key: urgramEditedOriginalsPreferencesKey, value: entry)
    }
}

// URGRAM: called from `_internal_deleteMessages` before the messages are
// removed, so their text survives locally.
func urgramArchiveMessagesBeforeDeletion(transaction: Transaction, ids: [MessageId]) {
    var messages: [UrgramArchivedMessage] = []
    for id in ids {
        guard let message = transaction.getMessage(id) else {
            continue
        }
        let mediaKind: String
        if let firstMedia = message.media.first {
            mediaKind = String(describing: type(of: firstMedia))
        } else {
            mediaKind = ""
        }
        messages.append(UrgramArchivedMessage(
            peerId: id.peerId.toInt64(),
            namespace: id.namespace,
            messageId: id.id,
            timestamp: message.timestamp,
            authorId: message.author?.id.toInt64(),
            isOutgoing: !message.flags.contains(.Incoming),
            text: message.text,
            mediaKind: mediaKind
        ))
    }
    if messages.isEmpty {
        return
    }
    var archived = urgramArchivedMessages(transaction: transaction)
    archived.append(contentsOf: messages)
    if archived.count > urgramMessageArchiveLimit {
        archived.removeFirst(archived.count - urgramMessageArchiveLimit)
    }
    if let entry = PreferencesEntry(archived) {
        transaction.setPreferencesEntry(key: urgramMessageArchivePreferencesKey, value: entry)
    }
}
