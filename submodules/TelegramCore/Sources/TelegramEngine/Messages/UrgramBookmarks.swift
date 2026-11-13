import Foundation
import Postbox

// URGRAM (item 15): local bookmarks. A bookmark is a text snapshot of a
// message (same record shape as the deleted/edited archive), stored under
// its own per-account preferences key (102). Media files are not preserved.

private let urgramBookmarksPreferencesKey: ValueBoxKey = applicationSpecificPreferencesKey(102)

private let urgramBookmarksLimit = 500

// URGRAM
public func urgramBookmarks(transaction: Transaction) -> [UrgramArchivedMessage] {
    return transaction.getPreferencesEntry(key: urgramBookmarksPreferencesKey)?.get([UrgramArchivedMessage].self) ?? []
}

// URGRAM
public func urgramClearBookmarks(transaction: Transaction) {
    if let entry = PreferencesEntry([UrgramArchivedMessage]()) {
        transaction.setPreferencesEntry(key: urgramBookmarksPreferencesKey, value: entry)
    }
}

// URGRAM: snapshots the stored message with the given id as a bookmark.
// Re-bookmarking the same message replaces the older snapshot.
public func urgramAddBookmark(transaction: Transaction, id: MessageId) {
    guard let message = transaction.getMessage(id) else {
        return
    }
    let mediaKind: String
    if let firstMedia = message.media.first {
        mediaKind = String(describing: type(of: firstMedia))
    } else {
        mediaKind = ""
    }
    let record = UrgramArchivedMessage(
        peerId: id.peerId.toInt64(),
        namespace: id.namespace,
        messageId: id.id,
        timestamp: message.timestamp,
        authorId: message.author?.id.toInt64(),
        isOutgoing: !message.flags.contains(.Incoming),
        text: message.text,
        mediaKind: mediaKind
    )
    var bookmarks = urgramBookmarks(transaction: transaction)
    bookmarks.removeAll { $0.peerId == record.peerId && $0.namespace == record.namespace && $0.messageId == record.messageId }
    bookmarks.append(record)
    if bookmarks.count > urgramBookmarksLimit {
        bookmarks.removeFirst(bookmarks.count - urgramBookmarksLimit)
    }
    if let entry = PreferencesEntry(bookmarks) {
        transaction.setPreferencesEntry(key: urgramBookmarksPreferencesKey, value: entry)
    }
}
