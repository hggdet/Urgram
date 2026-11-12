import Foundation
import CoreText
import UIKit

// URGRAM (item 22): font registration and resolution.
// - Built-in choices (Tajawal, Cairo, IBM Plex Sans Arabic — all SIL OFL) ship
//   in the app bundle under Resources/UrgramFonts (picked up by the existing
//   AppResources filegroup glob in Telegram/BUILD) and are registered with
//   CoreText for the process scope on first use.
// - User-imported .ttf/.otf files are copied to Application Support/UrgramFonts
//   and registered the same way.
// The resolved family name is pushed into `Font.urgramCustomFamilyName`
// (Display) from SharedAccountContext.
public enum UrgramFontManager {
    public static let builtInChoices: [(id: String, familyName: String, fileNames: [String])] = [
        ("tajawal", "Tajawal", ["Tajawal-Regular.ttf", "Tajawal-Medium.ttf", "Tajawal-Bold.ttf"]),
        ("cairo", "Cairo", ["Cairo.ttf"]),
        ("plexArabic", "IBM Plex Sans Arabic", ["IBMPlexSansArabic-Regular.ttf", "IBMPlexSansArabic-Bold.ttf"])
    ]

    private static var didRegisterBuiltInFonts = false

    public static func importedFontsDirectory() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = base.appendingPathComponent("UrgramFonts", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        }
        return directory
    }

    private static func registerFont(at url: URL) {
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            // Already registered (or invalid) — both are non-fatal here.
            let _ = error?.takeRetainedValue()
        }
    }

    public static func registerBuiltInFontsIfNeeded() {
        if didRegisterBuiltInFonts {
            return
        }
        didRegisterBuiltInFonts = true
        guard let resourcePath = Bundle.main.resourcePath else {
            return
        }
        let wanted = Set(builtInChoices.flatMap { $0.fileNames })
        guard let enumerator = FileManager.default.enumerator(atPath: resourcePath) else {
            return
        }
        for case let file as String in enumerator {
            if wanted.contains((file as NSString).lastPathComponent) {
                registerFont(at: URL(fileURLWithPath: (resourcePath as NSString).appendingPathComponent(file)))
            }
        }
    }

    // URGRAM: returns (postScriptName, familyName) for a font file URL, or nil.
    public static func fontNames(at url: URL) -> (postScriptName: String, familyName: String)? {
        guard let provider = CGDataProvider(url as CFURL), let cgFont = CGFont(provider) else {
            return nil
        }
        let ctFont = CTFontCreateWithGraphicsFont(cgFont, 0.0, nil, nil)
        let postScriptName = CTFontCopyPostScriptName(ctFont) as String
        let familyName = CTFontCopyFamilyName(ctFont) as String
        return (postScriptName, familyName)
    }

    // URGRAM: copies a picked font file into Application Support and registers
    // it. Returns the stored file name plus the font's names, or nil on failure.
    public static func importFont(from sourceUrl: URL) -> (fileName: String, postScriptName: String, familyName: String)? {
        guard let directory = importedFontsDirectory() else {
            return nil
        }
        let accessing = sourceUrl.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                sourceUrl.stopAccessingSecurityScopedResource()
            }
        }
        let fileName = sourceUrl.lastPathComponent
        let destination = directory.appendingPathComponent(fileName)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: sourceUrl, to: destination)
        } catch {
            return nil
        }
        registerFont(at: destination)
        guard let names = fontNames(at: destination) else {
            return nil
        }
        return (fileName, names.postScriptName, names.familyName)
    }

    public static func registerImportedFontIfNeeded(settings: UrgramSettings) {
        guard let fileName = settings.customFontFileName, let directory = importedFontsDirectory() else {
            return
        }
        let url = directory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: url.path) {
            registerFont(at: url)
        }
    }

    // URGRAM: the family name to hand to Display's Font factory, or nil for the
    // system font.
    public static func resolvedFamilyName(settings: UrgramSettings) -> String? {
        registerBuiltInFontsIfNeeded()
        switch settings.fontChoice {
        case "custom":
            registerImportedFontIfNeeded(settings: settings)
            return settings.customFontName
        default:
            if let choice = builtInChoices.first(where: { $0.id == settings.fontChoice }) {
                return choice.familyName
            }
            return nil
        }
    }
}
