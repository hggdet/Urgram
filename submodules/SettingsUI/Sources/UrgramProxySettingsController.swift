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

// URGRAM (item 4): bulk MTProxy import. Telegram's own proxy screen (Data and
// Storage > Proxy) already stores servers and shows live reachability/ping
// for each; what it lacks is importing many `t.me/proxy` links at once and a
// ready entry point, which is what this screen adds.

private final class UrgramProxySettingsControllerArguments {
    let importProxies: () -> Void
    let openSystemProxySettings: () -> Void

    init(importProxies: @escaping () -> Void, openSystemProxySettings: @escaping () -> Void) {
        self.importProxies = importProxies
        self.openSystemProxySettings = openSystemProxySettings
    }
}

private enum UrgramProxySettingsSection: Int32 {
    case main
}

private enum UrgramProxySettingsControllerEntry: ItemListNodeEntry {
    case header
    case count(Int)
    case importAction
    case systemAction
    case footer

    var section: ItemListSectionId {
        return UrgramProxySettingsSection.main.rawValue
    }

    var stableId: Int32 {
        switch self {
        case .header: return 0
        case .count: return 1
        case .importAction: return 2
        case .systemAction: return 3
        case .footer: return 4
        }
    }

    static func <(lhs: UrgramProxySettingsControllerEntry, rhs: UrgramProxySettingsControllerEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! UrgramProxySettingsControllerArguments
        switch self {
        case .header:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "Proxies", sectionId: self.section)
        case let .count(count):
            return ItemListTextItem(presentationData: presentationData, text: .plain(count == 0 ? "No proxy servers saved yet." : "\(count) proxy server(s) saved."), sectionId: self.section)
        case .importAction:
            return ItemListActionItem(presentationData: presentationData, title: "Import Proxies from Links", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.importProxies()
            })
        case .systemAction:
            return ItemListDisclosureItem(presentationData: presentationData, title: "All Proxy Settings", label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openSystemProxySettings()
            })
        case .footer:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Paste one or more t.me/proxy links (or tg://proxy links), one per line. Servers are added to Telegram's proxy list, where each server's live status and ping are shown. Find fresh public proxies in channels that publish them, then import them here in bulk."), sectionId: self.section)
        }
    }
}

// URGRAM
func urgramDataFromHexString(_ string: String) -> Data? {
    let string = string.trimmingCharacters(in: .whitespaces)
    guard string.count % 2 == 0, !string.isEmpty else {
        return nil
    }
    var data = Data()
    data.reserveCapacity(string.count / 2)
    var index = string.startIndex
    while index < string.endIndex {
        let nextIndex = string.index(index, offsetBy: 2)
        guard let byte = UInt8(string[index..<nextIndex], radix: 16) else {
            return nil
        }
        data.append(byte)
        index = nextIndex
    }
    return data
}

// URGRAM: parses `server`/`port`/`secret` out of a proxy link. The secret is
// hex (classic / dd / ee prefixed) or base64url (FakeTLS) encoded.
func urgramParseProxyLink(_ link: String) -> ProxyServerSettings? {
    guard let components = URLComponents(string: link.trimmingCharacters(in: .whitespacesAndNewlines)), let queryItems = components.queryItems else {
        return nil
    }
    var server: String?
    var port: Int32?
    var secret: String?
    for item in queryItems {
        switch item.name {
        case "server": server = item.value
        case "port": port = item.value.flatMap { Int32($0) }
        case "secret": secret = item.value
        default: break
        }
    }
    guard let server = server, !server.isEmpty, let port = port, let secretString = secret, !secretString.isEmpty else {
        return nil
    }
    let secretData: Data?
    if let hexData = urgramDataFromHexString(secretString) {
        secretData = hexData
    } else {
        var base64 = secretString.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        secretData = Data(base64Encoded: base64)
    }
    guard let secret = secretData, !secret.isEmpty else {
        return nil
    }
    return ProxyServerSettings(host: server, port: port, connection: .mtp(secret: secret))
}

public func urgramProxySettingsController(context: AccountContext) -> ViewController {
    var presentImportImpl: (() -> Void)?
    var pushImpl: ((ViewController) -> Void)?

    let arguments = UrgramProxySettingsControllerArguments(
        importProxies: {
            presentImportImpl?()
        },
        openSystemProxySettings: {
            pushImpl?(proxySettingsController(context: context))
        }
    )

    let proxySettings = context.sharedContext.accountManager.sharedData(keys: [SharedDataKeys.proxySettings])
    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        proxySettings
    )
    |> deliverOnMainQueue
    |> map { presentationData, sharedData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var presentationData = presentationData
        let updatedTheme = presentationData.theme.withModalBlocksBackground()
        presentationData = presentationData.withUpdated(theme: updatedTheme)

        let settings = sharedData.entries[SharedDataKeys.proxySettings]?.get(ProxySettings.self) ?? ProxySettings.defaultSettings
        var entries: [UrgramProxySettingsControllerEntry] = []
        entries.append(.header)
        entries.append(.count(settings.servers.count))
        entries.append(.importAction)
        entries.append(.systemAction)
        entries.append(.footer)

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Proxies"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true)

        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushImpl = { [weak controller] c in
        controller?.push(c)
    }
    presentImportImpl = { [weak controller] in
        guard let controller = controller else {
            return
        }
        let alert = UIAlertController(title: "Import Proxies", message: "Paste proxy links, one per line.", preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = "https://t.me/proxy?server=...&port=...&secret=..."
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Import", style: .default, handler: { _ in
            guard let text = alert.textFields?.first?.text, !text.isEmpty else {
                return
            }
            let servers = text.components(separatedBy: .newlines).compactMap { urgramParseProxyLink($0) }
            if servers.isEmpty {
                return
            }
            let _ = updateProxySettingsInteractively(accountManager: context.sharedContext.accountManager, { current in
                var updated = current
                for server in servers where !updated.servers.contains(server) {
                    updated.servers.append(server)
                }
                return updated
            }).startStandalone()
        }))
        controller.present(alert, animated: true)
    }
    return controller
}
