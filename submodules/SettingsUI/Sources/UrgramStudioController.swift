import Foundation
import UIKit
import UniformTypeIdentifiers
import Display
import AsyncDisplayKit
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import AccountContext
import ItemListPeerActionItem
import ComponentFlow
import SliderComponent

// URGRAM (build 20): Urgram Studio — design the app's appearance with a live
// preview, save named designs, share a design as a .urgramtheme file and
// import designs shared by others.
//
// Every control here maps to a VERIFIED runtime theme parameter (see
// URGRAM.md "Build 20"):
// - accent color / outgoing bubble colors / chat wallpaper go through
//   PresentationThemeSettings.themeSpecificAccentColors +
//   themeSpecificChatWallpapers, applied with
//   updatePresentationThemeSettingsInteractively — the exact mechanism
//   Telegram's own accent-color flow uses, so the whole app re-themes live.
// - bubble corner radius writes PresentationChatBubbleSettings.mainRadius
//   (auxiliaryRadius = mainRadius / 2, same as BubbleSettingsController).
// Incoming bubble color, message text colors, chat-list / navigation-bar
// backgrounds, "glass intensity" and chat-list density have NO such runtime
// parameter and are deliberately NOT offered.
// URGRAM (Studio V2): also exposed, through the same apply path —
// PresentationThemeSettings.fontSize / listsFontSize (+ useSystemFont),
// largeEmoji, PresentationChatBubbleSettings.mergeBubbleCorners and
// serifMessageFont; one-tap preset designs; and a "Main Interface" section
// whose switches write real preferences directly (stories-bar visibility via
// UrgramSettings.hideStoriesBar, archived-row visibility via
// ChatArchiveSettings.isHiddenByDefault, and the chat-list navigation
// buttons gated in ChatListLocationContext.updateChatList). Glass
// intensity and floating-bar corner shape were re-verified for Studio V2:
// the glass effect is UIKit's fixed UIGlassEffect and the floating bars'
// corner radii are hard-coded per call site — no settings-reachable value
// exists, so neither is offered.

func urgramStudioHexString(_ argb: UInt32) -> String {
    return String(format: "#%06X", argb & 0x00ffffff)
}

func urgramStudioSwatchImage(_ argb: UInt32, diameter: CGFloat = 29.0) -> UIImage? {
    let color = UIColor(argb: argb)
    return generateImage(CGSize(width: diameter, height: diameter), contextGenerator: { size, context in
        context.clear(CGRect(origin: CGPoint(), size: size))
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: CGRect(origin: CGPoint(), size: size))
        context.setStrokeColor(UIColor.black.withAlphaComponent(0.12).cgColor)
        context.setLineWidth(1.0 / UIScreenScale + 0.5)
        context.strokeEllipse(in: CGRect(origin: CGPoint(), size: size).insetBy(dx: 0.5, dy: 0.5))
    })
}

func urgramStudioWallpaper(for design: UrgramThemeDesign) -> TelegramWallpaper? {
    switch design.wallpaperMode {
    case 1:
        return .color(design.wallpaperColorA)
    case 2:
        return .gradient(TelegramWallpaper.Gradient(id: nil, colors: [design.wallpaperColorA, design.wallpaperColorB], settings: WallpaperSettings()))
    default:
        return nil
    }
}

// URGRAM: applies a design through the verified theme path, mirroring
// ThemeSettingsController's accent-apply block step for step (general theme
// reference, validity check via makePresentationTheme, accent entry with the
// wallpaper embedded, colored-index wallpaper entry for builtin themes).
// A photo/file chat wallpaper the user set themselves is not clobbered.
func urgramStudioApplyDesign(context: AccountContext, design: UrgramThemeDesign) {
    let wallpaper = urgramStudioWallpaper(for: design)
    let accentEntry = PresentationThemeAccentColor(index: -1, baseColor: .custom, accentColor: design.accentColor, bubbleColors: design.bubbleColors, wallpaper: wallpaper)
    let _ = updatePresentationThemeSettingsInteractively(accountManager: context.sharedContext.accountManager, { current in
        let autoNightModeTriggered = context.sharedContext.currentPresentationData.with { $0 }.autoNightModeTriggered
        var currentTheme = current.currentModeTheme
        if autoNightModeTriggered {
            currentTheme = current.currentModeAutomaticThemeSwitchSetting.theme
        }

        let generalThemeReference: PresentationThemeReference
        if case let .cloud(theme) = currentTheme, let settings = theme.theme.settings?.first {
            generalThemeReference = .builtin(PresentationBuiltinThemeReference(baseTheme: settings.baseTheme))
        } else {
            generalThemeReference = currentTheme
        }

        guard let _ = makePresentationTheme(mediaBox: context.sharedContext.accountManager.mediaBox, themeReference: generalThemeReference, accentColor: accentEntry.color, wallpaper: wallpaper, baseColor: accentEntry.baseColor) else {
            return current
        }

        var updatedTheme = current.currentModeTheme
        var updatedAutomaticThemeSwitchSetting = current.currentModeAutomaticThemeSwitchSetting
        if autoNightModeTriggered {
            updatedAutomaticThemeSwitchSetting.theme = generalThemeReference
        } else {
            updatedTheme = generalThemeReference
        }

        var updated = current
        updated.currentModeTheme = updatedTheme
        updated.currentModeAutomaticThemeSwitchSetting = updatedAutomaticThemeSwitchSetting
        updated.themeSpecificAccentColors[generalThemeReference.index] = accentEntry.withUpdatedWallpaper(wallpaper)
        if case .builtin = generalThemeReference {
            let coloredIndex = coloredThemeIndex(reference: generalThemeReference, accentColor: accentEntry)
            if let existingWallpaper = current.themeSpecificChatWallpapers[coloredIndex] {
                if existingWallpaper.isColorOrGradient || existingWallpaper.isPattern || existingWallpaper.isBuiltin {
                    updated.themeSpecificChatWallpapers[coloredIndex] = wallpaper
                }
            } else {
                updated.themeSpecificChatWallpapers[coloredIndex] = wallpaper
            }
        }
        updated.chatBubbleSettings.mainRadius = design.bubbleRadius
        updated.chatBubbleSettings.auxiliaryRadius = design.bubbleRadius / 2
        // URGRAM (Studio V2): the remaining verified PresentationThemeSettings
        // parameters. Font sizes share the single useSystemFont switch in the
        // runtime (PresentationData.resolveFontSize), so a design stores both
        // sizes; -1 means "follow the system size". Fields left nil by older
        // (build 20–23) designs do not touch the current values.
        if let chatFontSize = design.chatFontSize {
            if chatFontSize < 0 {
                updated.useSystemFont = true
            } else if let fontSize = PresentationFontSize(rawValue: chatFontSize) {
                updated.fontSize = fontSize
                updated.useSystemFont = false
            }
        }
        if let listFontSize = design.listFontSize {
            if listFontSize < 0 {
                updated.useSystemFont = true
            } else if let fontSize = PresentationFontSize(rawValue: listFontSize) {
                updated.listsFontSize = fontSize
                updated.useSystemFont = false
            }
        }
        if let largeEmoji = design.largeEmoji {
            updated.largeEmoji = largeEmoji
        }
        if let mergeBubbleCorners = design.mergeBubbleCorners {
            updated.chatBubbleSettings.mergeBubbleCorners = mergeBubbleCorners
        }
        if let serifMessageFont = design.serifMessageFont {
            updated.chatBubbleSettings.serifMessageFont = serifMessageFont
        }
        return updated
    }).startStandalone()

    UrgramSettingsStore.shared.update { settings in
        settings.studioActiveDesignId = design.id.isEmpty ? nil : design.id
    }
}

// URGRAM: removes the Studio's accent/wallpaper entries for the current
// theme and restores the default bubble radius (16/8, the codebase default).
func urgramStudioResetAppearance(context: AccountContext) {
    let _ = updatePresentationThemeSettingsInteractively(accountManager: context.sharedContext.accountManager, { current in
        var currentTheme = current.currentModeTheme
        if context.sharedContext.currentPresentationData.with({ $0 }).autoNightModeTriggered {
            currentTheme = current.currentModeAutomaticThemeSwitchSetting.theme
        }

        let generalThemeReference: PresentationThemeReference
        if case let .cloud(theme) = currentTheme, let settings = theme.theme.settings?.first {
            generalThemeReference = .builtin(PresentationBuiltinThemeReference(baseTheme: settings.baseTheme))
        } else {
            generalThemeReference = currentTheme
        }

        var updated = current
        updated.themeSpecificAccentColors[generalThemeReference.index] = nil
        if case .builtin = generalThemeReference {
            updated.themeSpecificChatWallpapers[coloredThemeIndex(reference: generalThemeReference, accentColor: nil)] = nil
            updated.themeSpecificChatWallpapers[generalThemeReference.index] = nil
        }
        updated.chatBubbleSettings.mainRadius = 16
        updated.chatBubbleSettings.auxiliaryRadius = 8
        // URGRAM (Studio V2): restore the remaining parameters to the
        // PresentationThemeSettings.defaultSettings values.
        updated.useSystemFont = true
        updated.fontSize = .regular
        updated.listsFontSize = .regular
        updated.largeEmoji = true
        updated.chatBubbleSettings.mergeBubbleCorners = true
        updated.chatBubbleSettings.serifMessageFont = false
        return updated
    }).startStandalone()

    UrgramSettingsStore.shared.update { settings in
        settings.studioActiveDesignId = nil
    }
}

// URGRAM (Studio V2): ready-made designs, applied in one tap through the
// same apply path as saved designs. Values are ordinary UrgramThemeDesign
// values (ARGB colors; wallpaper mode 1 = solid, 2 = gradient).
private struct UrgramStudioPreset {
    let design: UrgramThemeDesign
    let en: String
    let ar: String
}

private let urgramStudioPresets: [UrgramStudioPreset] = [
    UrgramStudioPreset(design: UrgramThemeDesign(id: "preset-ocean", name: "Ocean", accentColor: 0xff0077b6, bubbleColors: [0xff00b4d8, 0xff0077b6], wallpaperMode: 2, wallpaperColorA: 0xff03045e, wallpaperColorB: 0xff0077b6, bubbleRadius: 18), en: "Ocean", ar: "المحيط"),
    UrgramStudioPreset(design: UrgramThemeDesign(id: "preset-sunset", name: "Sunset", accentColor: 0xffff7b54, bubbleColors: [0xffffb26b, 0xffff7b54], wallpaperMode: 2, wallpaperColorA: 0xff2d4059, wallpaperColorB: 0xffff7b54, bubbleRadius: 16), en: "Sunset", ar: "الغروب"),
    UrgramStudioPreset(design: UrgramThemeDesign(id: "preset-forest", name: "Forest", accentColor: 0xff2e933c, bubbleColors: [0xff6bcb77, 0xff2e933c], wallpaperMode: 2, wallpaperColorA: 0xff0b3d2e, wallpaperColorB: 0xff2e933c, bubbleRadius: 14), en: "Forest", ar: "الغابة"),
    UrgramStudioPreset(design: UrgramThemeDesign(id: "preset-rose", name: "Rose", accentColor: 0xffe75480, bubbleColors: [0xffff9fb2, 0xffe75480], wallpaperMode: 2, wallpaperColorA: 0xff3a1c40, wallpaperColorB: 0xffe75480, bubbleRadius: 20), en: "Rose", ar: "الورد"),
    UrgramStudioPreset(design: UrgramThemeDesign(id: "preset-midnight", name: "Midnight", accentColor: 0xff5e5ce6, bubbleColors: [0xff4a4a8a, 0xff2c2c54], wallpaperMode: 2, wallpaperColorA: 0xff0f0f1e, wallpaperColorB: 0xff23233a, bubbleRadius: 12, mergeBubbleCorners: true), en: "Midnight", ar: "منتصف الليل"),
    UrgramStudioPreset(design: UrgramThemeDesign(id: "preset-sand", name: "Sand", accentColor: 0xffb08968, bubbleColors: [0xffddbea9, 0xffb08968], wallpaperMode: 1, wallpaperColorA: 0xffede0d4, wallpaperColorB: 0xffede0d4, bubbleRadius: 16), en: "Sand", ar: "الرمال")
]

// URGRAM (Studio V2): display name for a stored font-size raw value
// (-1 = follow the system size, otherwise a PresentationFontSize raw value).
func urgramStudioFontSizeName(_ rawValue: Int32, isArabic: Bool) -> String {
    switch rawValue {
    case -1:
        return isArabic ? "حجم النظام" : "System Size"
    case 0:
        return isArabic ? "صغير جدًا" : "Extra Small"
    case 1:
        return isArabic ? "صغير" : "Small"
    case 2:
        return isArabic ? "عادي" : "Regular"
    case 6:
        return isArabic ? "متوسط" : "Medium"
    case 3:
        return isArabic ? "كبير" : "Large"
    case 4:
        return isArabic ? "كبير جدًا" : "Extra Large"
    case 5:
        return isArabic ? "الأكبر" : "Largest"
    default:
        return isArabic ? "عادي" : "Regular"
    }
}

// URGRAM (Studio V2): tap-to-cycle order for the font-size rows.
func urgramStudioNextFontSizeRaw(_ rawValue: Int32) -> Int32 {
    let order: [Int32] = [-1, 0, 1, 2, 6, 3, 4, 5]
    if let index = order.firstIndex(of: rawValue), index + 1 < order.count {
        return order[index + 1]
    }
    return order[0]
}

// URGRAM (ambience — snow): display name for a snow intensity value
// (0 = light, 1 = medium, 2 = heavy).
func urgramStudioSnowIntensityName(_ value: Int, isArabic: Bool) -> String {
    switch value {
    case 2:
        return isArabic ? "كثيف" : "Heavy"
    case 1:
        return isArabic ? "متوسط" : "Medium"
    default:
        return isArabic ? "خفيف" : "Light"
    }
}

// URGRAM: a titled continuous slider row, adapted from
// ThemeSettingsBrightnessItem (same node/block-background handling) with a
// text label instead of the min/max icons.
final class UrgramStudioSliderItem: ListViewItem, ItemListItem {
    let systemStyle: ItemListSystemStyle
    let theme: PresentationTheme
    let title: String
    let value: CGFloat
    let sectionId: ItemListSectionId
    let updated: (CGFloat) -> Void

    init(systemStyle: ItemListSystemStyle = .legacy, theme: PresentationTheme, title: String, value: CGFloat, sectionId: ItemListSectionId, updated: @escaping (CGFloat) -> Void) {
        self.systemStyle = systemStyle
        self.theme = theme
        self.title = title
        self.value = value
        self.sectionId = sectionId
        self.updated = updated
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, neighbors: ListViewItemNeighbors, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = UrgramStudioSliderItemNode()
            let (layout, apply) = node.asyncLayout()(self, params, itemListNeighbors(item: self, topFacet: neighbors.previous?.base(ItemListNeighborFacet.self), bottomFacet: neighbors.next?.base(ItemListNeighborFacet.self)))

            node.contentSize = layout.contentSize
            node.insets = layout.insets

            Queue.mainQueue().async {
                completion(node, {
                    return (nil, { _ in apply() })
                })
            }
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, neighbors: ListViewItemNeighbors, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? UrgramStudioSliderItemNode {
                let makeLayout = nodeValue.asyncLayout()

                async {
                    let (layout, apply) = makeLayout(self, params, itemListNeighbors(item: self, topFacet: neighbors.previous?.base(ItemListNeighborFacet.self), bottomFacet: neighbors.next?.base(ItemListNeighborFacet.self)))
                    Queue.mainQueue().async {
                        completion(layout, { _ in
                            apply()
                        })
                    }
                }
            }
        }
    }
}

final class UrgramStudioSliderItemNode: ListViewItemNode {
    private let backgroundNode: ASDisplayNode
    private let topStripeNode: ASDisplayNode
    private let bottomStripeNode: ASDisplayNode
    private let maskNode: ASImageNode

    private let titleNode: ASTextNode
    private let slider = ComponentView<Empty>()

    private var item: UrgramStudioSliderItem?
    private var layoutParams: ListViewItemLayoutParams?

    init() {
        self.backgroundNode = ASDisplayNode()
        self.backgroundNode.isLayerBacked = true

        self.topStripeNode = ASDisplayNode()
        self.topStripeNode.isLayerBacked = true

        self.bottomStripeNode = ASDisplayNode()
        self.bottomStripeNode.isLayerBacked = true

        self.maskNode = ASImageNode()

        self.titleNode = ASTextNode()
        self.titleNode.displaysAsynchronously = false
        self.titleNode.maximumNumberOfLines = 1
        self.titleNode.truncationMode = .byTruncatingTail

        super.init(layerBacked: false)

        self.addSubnode(self.titleNode)
    }

    func asyncLayout() -> (_ item: UrgramStudioSliderItem, _ params: ListViewItemLayoutParams, _ neighbors: ItemListNeighbors) -> (ListViewItemNodeLayout, () -> Void) {
        return { [weak self] item, params, neighbors in
            let contentSize: CGSize
            let insets: UIEdgeInsets
            let separatorHeight = UIScreenPixel
            let separatorRightInset: CGFloat = item.systemStyle == .glass ? 16.0 : 0.0

            contentSize = CGSize(width: params.width, height: 52.0)
            insets = itemListNeighborsGroupedInsets(neighbors, params)

            let layout = ListViewItemNodeLayout(contentSize: contentSize, insets: insets)
            let layoutSize = layout.size

            return (layout, { [weak self] in
                if let strongSelf = self {
                    strongSelf.item = item
                    strongSelf.layoutParams = params

                    strongSelf.backgroundNode.backgroundColor = item.theme.list.itemBlocksBackgroundColor
                    strongSelf.topStripeNode.backgroundColor = item.theme.list.itemBlocksSeparatorColor
                    strongSelf.bottomStripeNode.backgroundColor = item.theme.list.itemBlocksSeparatorColor

                    if strongSelf.backgroundNode.supernode == nil {
                        strongSelf.insertSubnode(strongSelf.backgroundNode, at: 0)
                    }
                    if strongSelf.topStripeNode.supernode == nil {
                        strongSelf.insertSubnode(strongSelf.topStripeNode, at: 1)
                    }
                    if strongSelf.bottomStripeNode.supernode == nil {
                        strongSelf.insertSubnode(strongSelf.bottomStripeNode, at: 2)
                    }
                    if strongSelf.maskNode.supernode == nil {
                        strongSelf.insertSubnode(strongSelf.maskNode, at: 3)
                    }

                    let hasCorners = itemListHasRoundedBlockLayout(params)
                    var hasTopCorners = false
                    var hasBottomCorners = false
                    switch neighbors.top {
                    case .sameSection(false):
                        strongSelf.topStripeNode.isHidden = true
                    default:
                        hasTopCorners = true
                        strongSelf.topStripeNode.isHidden = hasCorners
                    }
                    let bottomStripeInset: CGFloat
                    let bottomStripeOffset: CGFloat
                    switch neighbors.bottom {
                        case .sameSection(false):
                            bottomStripeInset = params.leftInset + 16.0
                            bottomStripeOffset = -separatorHeight
                            strongSelf.bottomStripeNode.isHidden = false
                        default:
                            bottomStripeInset = 0.0
                            bottomStripeOffset = 0.0
                            hasBottomCorners = true
                            strongSelf.bottomStripeNode.isHidden = hasCorners
                    }

                    strongSelf.maskNode.image = hasCorners ? PresentationResourcesItemList.cornersImage(item.theme, top: hasTopCorners, bottom: hasBottomCorners, glass: item.systemStyle == .glass) : nil

                    strongSelf.backgroundNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: params.width, height: contentSize.height + min(insets.top, separatorHeight) + min(insets.bottom, separatorHeight)))
                    strongSelf.maskNode.frame = strongSelf.backgroundNode.frame.inset(by: UIEdgeInsets(top: 0.0, left: params.leftInset, bottom: 0.0, right: params.rightInset))
                    strongSelf.topStripeNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: layoutSize.width, height: separatorHeight))
                    strongSelf.bottomStripeNode.frame = CGRect(origin: CGPoint(x: bottomStripeInset, y: contentSize.height + bottomStripeOffset), size: CGSize(width: layoutSize.width - bottomStripeInset - params.rightInset - separatorRightInset, height: separatorHeight))

                    strongSelf.titleNode.attributedText = NSAttributedString(string: item.title, font: Font.regular(15.0), textColor: item.theme.list.itemPrimaryTextColor)
                    strongSelf.titleNode.frame = CGRect(origin: CGPoint(x: params.leftInset + 16.0, y: 16.0), size: CGSize(width: 92.0, height: 20.0))

                    let sliderX = params.leftInset + 16.0 + 92.0 + 8.0
                    let sliderSize = strongSelf.slider.update(
                        transition: .immediate,
                        component: AnyComponent(
                            SliderComponent(
                                content: .continuous(.init(
                                    value: item.value,
                                    minValue: nil,
                                    range: 0.0 ... 1.0,
                                    valueUpdated: { [weak self] value in
                                        self?.item?.updated(value)
                                    }
                                )),
                                useNative: true,
                                trackBackgroundColor: item.theme.list.itemSwitchColors.frameColor,
                                trackForegroundColor: item.theme.list.itemAccentColor
                            )
                        ),
                        environment: {},
                        containerSize: CGSize(width: params.width - sliderX - params.rightInset - 16.0, height: 44.0)
                    )
                    if let sliderView = strongSelf.slider.view {
                        if sliderView.superview == nil {
                            strongSelf.view.addSubview(sliderView)
                        }
                        sliderView.frame = CGRect(origin: CGPoint(x: sliderX, y: 4.0), size: sliderSize)
                    }
                }
            })
        }
    }

    override func animateInsertion(_ currentTimestamp: Double, duration: Double, options: ListViewItemAnimationOptions) {
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.4)
    }

    override func animateRemoved(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.15, removeOnCompletion: false)
    }
}

// URGRAM: a fake chat-list row rendered from the PREVIEW theme's real
// chat-list colors (title / message / date / unread badge / avatar accent),
// so the accent color's effect on the chat list is visible in the preview.
final class UrgramStudioChatListPreviewItem: ListViewItem, ItemListItem {
    let systemStyle: ItemListSystemStyle
    let theme: PresentationTheme
    let titleText: String
    let messageText: String
    let sectionId: ItemListSectionId

    init(systemStyle: ItemListSystemStyle = .legacy, theme: PresentationTheme, titleText: String, messageText: String, sectionId: ItemListSectionId) {
        self.systemStyle = systemStyle
        self.theme = theme
        self.titleText = titleText
        self.messageText = messageText
        self.sectionId = sectionId
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, neighbors: ListViewItemNeighbors, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = UrgramStudioChatListPreviewItemNode()
            let (layout, apply) = node.asyncLayout()(self, params, itemListNeighbors(item: self, topFacet: neighbors.previous?.base(ItemListNeighborFacet.self), bottomFacet: neighbors.next?.base(ItemListNeighborFacet.self)))

            node.contentSize = layout.contentSize
            node.insets = layout.insets

            Queue.mainQueue().async {
                completion(node, {
                    return (nil, { _ in apply() })
                })
            }
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, neighbors: ListViewItemNeighbors, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? UrgramStudioChatListPreviewItemNode {
                let makeLayout = nodeValue.asyncLayout()

                async {
                    let (layout, apply) = makeLayout(self, params, itemListNeighbors(item: self, topFacet: neighbors.previous?.base(ItemListNeighborFacet.self), bottomFacet: neighbors.next?.base(ItemListNeighborFacet.self)))
                    Queue.mainQueue().async {
                        completion(layout, { _ in
                            apply()
                        })
                    }
                }
            }
        }
    }
}

final class UrgramStudioChatListPreviewItemNode: ListViewItemNode {
    private let backgroundNode: ASDisplayNode
    private let topStripeNode: ASDisplayNode
    private let bottomStripeNode: ASDisplayNode
    private let maskNode: ASImageNode

    private let avatarNode: ASImageNode
    private let initialNode: ASTextNode
    private let titleNode: ASTextNode
    private let messageNode: ASTextNode
    private let timeNode: ASTextNode
    private let badgeNode: ASImageNode
    private let badgeTextNode: ASTextNode

    private var item: UrgramStudioChatListPreviewItem?
    private var layoutParams: ListViewItemLayoutParams?

    init() {
        self.backgroundNode = ASDisplayNode()
        self.backgroundNode.isLayerBacked = true

        self.topStripeNode = ASDisplayNode()
        self.topStripeNode.isLayerBacked = true

        self.bottomStripeNode = ASDisplayNode()
        self.bottomStripeNode.isLayerBacked = true

        self.maskNode = ASImageNode()

        self.avatarNode = ASImageNode()
        self.avatarNode.displaysAsynchronously = false
        self.avatarNode.displayWithoutProcessing = true

        self.initialNode = ASTextNode()
        self.initialNode.displaysAsynchronously = false
        self.initialNode.maximumNumberOfLines = 1

        self.titleNode = ASTextNode()
        self.titleNode.displaysAsynchronously = false
        self.titleNode.maximumNumberOfLines = 1
        self.titleNode.truncationMode = .byTruncatingTail

        self.messageNode = ASTextNode()
        self.messageNode.displaysAsynchronously = false
        self.messageNode.maximumNumberOfLines = 1
        self.messageNode.truncationMode = .byTruncatingTail

        self.timeNode = ASTextNode()
        self.timeNode.displaysAsynchronously = false
        self.timeNode.maximumNumberOfLines = 1

        self.badgeNode = ASImageNode()
        self.badgeNode.displaysAsynchronously = false
        self.badgeNode.displayWithoutProcessing = true

        self.badgeTextNode = ASTextNode()
        self.badgeTextNode.displaysAsynchronously = false
        self.badgeTextNode.maximumNumberOfLines = 1

        super.init(layerBacked: false)

        self.addSubnode(self.avatarNode)
        self.addSubnode(self.initialNode)
        self.addSubnode(self.titleNode)
        self.addSubnode(self.messageNode)
        self.addSubnode(self.timeNode)
        self.addSubnode(self.badgeNode)
        self.addSubnode(self.badgeTextNode)
    }

    func asyncLayout() -> (_ item: UrgramStudioChatListPreviewItem, _ params: ListViewItemLayoutParams, _ neighbors: ItemListNeighbors) -> (ListViewItemNodeLayout, () -> Void) {
        return { [weak self] item, params, neighbors in
            let contentSize: CGSize
            let insets: UIEdgeInsets
            let separatorHeight = UIScreenPixel
            let separatorRightInset: CGFloat = item.systemStyle == .glass ? 16.0 : 0.0

            contentSize = CGSize(width: params.width, height: 66.0)
            insets = itemListNeighborsGroupedInsets(neighbors, params)

            let layout = ListViewItemNodeLayout(contentSize: contentSize, insets: insets)
            let layoutSize = layout.size

            return (layout, { [weak self] in
                if let strongSelf = self {
                    strongSelf.item = item
                    strongSelf.layoutParams = params

                    strongSelf.backgroundNode.backgroundColor = item.theme.chatList.itemBackgroundColor
                    strongSelf.topStripeNode.backgroundColor = item.theme.list.itemBlocksSeparatorColor
                    strongSelf.bottomStripeNode.backgroundColor = item.theme.list.itemBlocksSeparatorColor

                    if strongSelf.backgroundNode.supernode == nil {
                        strongSelf.insertSubnode(strongSelf.backgroundNode, at: 0)
                    }
                    if strongSelf.topStripeNode.supernode == nil {
                        strongSelf.insertSubnode(strongSelf.topStripeNode, at: 1)
                    }
                    if strongSelf.bottomStripeNode.supernode == nil {
                        strongSelf.insertSubnode(strongSelf.bottomStripeNode, at: 2)
                    }
                    if strongSelf.maskNode.supernode == nil {
                        strongSelf.insertSubnode(strongSelf.maskNode, at: 3)
                    }

                    let hasCorners = itemListHasRoundedBlockLayout(params)
                    var hasTopCorners = false
                    var hasBottomCorners = false
                    switch neighbors.top {
                    case .sameSection(false):
                        strongSelf.topStripeNode.isHidden = true
                    default:
                        hasTopCorners = true
                        strongSelf.topStripeNode.isHidden = hasCorners
                    }
                    let bottomStripeInset: CGFloat
                    let bottomStripeOffset: CGFloat
                    switch neighbors.bottom {
                        case .sameSection(false):
                            bottomStripeInset = params.leftInset + 16.0
                            bottomStripeOffset = -separatorHeight
                            strongSelf.bottomStripeNode.isHidden = false
                        default:
                            bottomStripeInset = 0.0
                            bottomStripeOffset = 0.0
                            hasBottomCorners = true
                            strongSelf.bottomStripeNode.isHidden = hasCorners
                    }

                    strongSelf.maskNode.image = hasCorners ? PresentationResourcesItemList.cornersImage(item.theme, top: hasTopCorners, bottom: hasBottomCorners, glass: item.systemStyle == .glass) : nil

                    strongSelf.backgroundNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: params.width, height: contentSize.height + min(insets.top, separatorHeight) + min(insets.bottom, separatorHeight)))
                    strongSelf.maskNode.frame = strongSelf.backgroundNode.frame.inset(by: UIEdgeInsets(top: 0.0, left: params.leftInset, bottom: 0.0, right: params.rightInset))
                    strongSelf.topStripeNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: layoutSize.width, height: separatorHeight))
                    strongSelf.bottomStripeNode.frame = CGRect(origin: CGPoint(x: bottomStripeInset, y: contentSize.height + bottomStripeOffset), size: CGSize(width: layoutSize.width - bottomStripeInset - params.rightInset - separatorRightInset, height: separatorHeight))

                    let contentLeft = params.leftInset + 14.0
                    let contentRight = params.width - params.rightInset - 14.0
                    let avatarSize: CGFloat = 46.0
                    let avatarFrame = CGRect(origin: CGPoint(x: contentLeft, y: (contentSize.height - avatarSize) / 2.0), size: CGSize(width: avatarSize, height: avatarSize))
                    strongSelf.avatarNode.image = generateImage(avatarFrame.size, contextGenerator: { size, context in
                        context.clear(CGRect(origin: CGPoint(), size: size))
                        context.setFillColor(item.theme.list.itemAccentColor.cgColor)
                        context.fillEllipse(in: CGRect(origin: CGPoint(), size: size))
                    })
                    strongSelf.avatarNode.frame = avatarFrame
                    strongSelf.initialNode.attributedText = NSAttributedString(string: "U", font: Font.semibold(19.0), textColor: .white, paragraphAlignment: .center)
                    strongSelf.initialNode.frame = CGRect(origin: CGPoint(x: avatarFrame.minX, y: avatarFrame.minY + 12.0), size: CGSize(width: avatarFrame.width, height: 24.0))

                    let textLeft = avatarFrame.maxX + 11.0
                    let timeWidth: CGFloat = 44.0
                    strongSelf.titleNode.attributedText = NSAttributedString(string: item.titleText, font: Font.semibold(16.0), textColor: item.theme.chatList.titleColor)
                    strongSelf.titleNode.frame = CGRect(origin: CGPoint(x: textLeft, y: 11.0), size: CGSize(width: contentRight - timeWidth - 6.0 - textLeft, height: 20.0))
                    strongSelf.messageNode.attributedText = NSAttributedString(string: item.messageText, font: Font.regular(14.0), textColor: item.theme.chatList.messageTextColor)
                    strongSelf.messageNode.frame = CGRect(origin: CGPoint(x: textLeft, y: 35.0), size: CGSize(width: contentRight - 30.0 - textLeft, height: 18.0))
                    strongSelf.timeNode.attributedText = NSAttributedString(string: "12:30", font: Font.regular(13.0), textColor: item.theme.chatList.dateTextColor, paragraphAlignment: .right)
                    strongSelf.timeNode.frame = CGRect(origin: CGPoint(x: contentRight - timeWidth, y: 12.0), size: CGSize(width: timeWidth, height: 17.0))

                    let badgeSize = CGSize(width: 20.0, height: 18.0)
                    let badgeFrame = CGRect(origin: CGPoint(x: contentRight - badgeSize.width, y: 36.0), size: badgeSize)
                    strongSelf.badgeNode.image = generateImage(badgeSize, contextGenerator: { size, context in
                        context.clear(CGRect(origin: CGPoint(), size: size))
                        context.setFillColor(item.theme.chatList.unreadBadgeActiveBackgroundColor.cgColor)
                        let path = CGPath(roundedRect: CGRect(origin: CGPoint(), size: size), cornerWidth: size.height / 2.0, cornerHeight: size.height / 2.0, transform: nil)
                        context.addPath(path)
                        context.fillPath()
                    })
                    strongSelf.badgeNode.frame = badgeFrame
                    strongSelf.badgeTextNode.attributedText = NSAttributedString(string: "3", font: Font.semibold(12.0), textColor: item.theme.chatList.unreadBadgeActiveTextColor, paragraphAlignment: .center)
                    strongSelf.badgeTextNode.frame = CGRect(origin: CGPoint(x: badgeFrame.minX, y: badgeFrame.minY + 2.0), size: CGSize(width: badgeFrame.width, height: 15.0))
                }
            })
        }
    }

    override func animateInsertion(_ currentTimestamp: Double, duration: Double, options: ListViewItemAnimationOptions) {
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.4)
    }

    override func animateRemoved(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.15, removeOnCompletion: false)
    }
}

// MARK: - Studio screen

private struct UrgramStudioDraft: Equatable {
    var parameters: UrgramThemeDesign
    // The saved design the draft was loaded from; cleared by any edit.
    var sourceDesignId: String?
}

private enum UrgramStudioColorTarget {
    case accent
    case bubble1
    case bubble2
    case wallpaperA
    case wallpaperB
}

private final class UrgramStudioControllerArguments {
    let context: AccountContext
    let updateDraft: ((inout UrgramThemeDesign) -> Void) -> Void
    let openColorEditor: (UrgramStudioColorTarget) -> Void
    let applyDraft: () -> Void
    let saveDraft: () -> Void
    let resetAppearance: () -> Void
    let designAction: (UrgramThemeDesign) -> Void
    let importDesign: () -> Void
    // URGRAM (Studio V2)
    let applyPreset: (UrgramThemeDesign) -> Void
    let cycleFontSize: (Bool) -> Void
    let updateHomeFlag: (WritableKeyPath<UrgramSettings, Bool>, Bool) -> Void
    let setArchiveHidden: (Bool) -> Void
    let cycleSnowIntensity: () -> Void

    init(context: AccountContext, updateDraft: @escaping ((inout UrgramThemeDesign) -> Void) -> Void, openColorEditor: @escaping (UrgramStudioColorTarget) -> Void, applyDraft: @escaping () -> Void, saveDraft: @escaping () -> Void, resetAppearance: @escaping () -> Void, designAction: @escaping (UrgramThemeDesign) -> Void, importDesign: @escaping () -> Void, applyPreset: @escaping (UrgramThemeDesign) -> Void, cycleFontSize: @escaping (Bool) -> Void, updateHomeFlag: @escaping (WritableKeyPath<UrgramSettings, Bool>, Bool) -> Void, setArchiveHidden: @escaping (Bool) -> Void, cycleSnowIntensity: @escaping () -> Void) {
        self.context = context
        self.updateDraft = updateDraft
        self.openColorEditor = openColorEditor
        self.applyDraft = applyDraft
        self.saveDraft = saveDraft
        self.resetAppearance = resetAppearance
        self.designAction = designAction
        self.importDesign = importDesign
        self.applyPreset = applyPreset
        self.cycleFontSize = cycleFontSize
        self.updateHomeFlag = updateHomeFlag
        self.setArchiveHidden = setArchiveHidden
        self.cycleSnowIntensity = cycleSnowIntensity
    }
}

private enum UrgramStudioSection: Int32 {
    case preview
    case presets
    case interface
    case bubbles
    case texts
    case background
    case actions
    case home
    case ambience
    case designs
}

private enum UrgramStudioControllerEntry: ItemListNodeEntry {
    case previewHeader
    case chatPreview(PresentationTheme, TelegramWallpaper, PresentationChatBubbleCorners, PresentationFontSize, PresentationStrings, PresentationDateTimeFormat, PresentationPersonNameOrder, [ChatPreviewMessageItem])
    case chatListPreview(PresentationTheme, String, String)
    case previewFooter

    case presetsHeader
    case preset(UrgramThemeDesign, String, Int)

    case interfaceHeader
    case accent(UInt32)
    case interfaceFooter

    case bubblesHeader
    case bubbleDerived(Bool)
    case bubbleColor1(UInt32)
    case bubbleGradient(Bool)
    case bubbleColor2(UInt32)
    case radius(Int32)
    case mergeCorners(Bool)

    case textsHeader
    case chatFontSize(Int32)
    case listFontSize(Int32)
    case largeEmoji(Bool)
    case serifFont(Bool)

    case backgroundHeader
    case wallpaperDefault(Bool)
    case wallpaperSolid(Bool)
    case wallpaperGradient(Bool)
    case wallpaperColorA(UInt32, Int32)
    case wallpaperColorB(UInt32)

    case applyAction
    case saveAction
    case resetAction

    case homeHeader
    case homeHideStories(Bool)
    case homeArchiveHidden(Bool)
    case homeHideEdit(Bool)
    case homeHideCompose(Bool)
    case homeHideStory(Bool)
    case homeFooter

    case ambienceHeader
    case snowEnabled(Bool)
    case snowIntensity(Int)
    case ambienceFooter

    case designsHeader
    case importAction
    case designsEmptyFooter
    case design(UrgramThemeDesign, Bool, Int)

    var section: ItemListSectionId {
        switch self {
        case .previewHeader, .chatPreview, .chatListPreview, .previewFooter:
            return UrgramStudioSection.preview.rawValue
        case .presetsHeader, .preset:
            return UrgramStudioSection.presets.rawValue
        case .interfaceHeader, .accent, .interfaceFooter:
            return UrgramStudioSection.interface.rawValue
        case .bubblesHeader, .bubbleDerived, .bubbleColor1, .bubbleGradient, .bubbleColor2, .radius, .mergeCorners:
            return UrgramStudioSection.bubbles.rawValue
        case .textsHeader, .chatFontSize, .listFontSize, .largeEmoji, .serifFont:
            return UrgramStudioSection.texts.rawValue
        case .backgroundHeader, .wallpaperDefault, .wallpaperSolid, .wallpaperGradient, .wallpaperColorA, .wallpaperColorB:
            return UrgramStudioSection.background.rawValue
        case .applyAction, .saveAction, .resetAction:
            return UrgramStudioSection.actions.rawValue
        case .homeHeader, .homeHideStories, .homeArchiveHidden, .homeHideEdit, .homeHideCompose, .homeHideStory, .homeFooter:
            return UrgramStudioSection.home.rawValue
        case .ambienceHeader, .snowEnabled, .snowIntensity, .ambienceFooter:
            return UrgramStudioSection.ambience.rawValue
        case .designsHeader, .importAction, .designsEmptyFooter, .design:
            return UrgramStudioSection.designs.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .previewHeader: return 0
        case .chatPreview: return 1
        case .chatListPreview: return 2
        case .previewFooter: return 3
        case .presetsHeader: return 10
        case let .preset(_, _, index):
            return 100 + Int32(index)
        case .interfaceHeader: return 20
        case .accent: return 21
        case .interfaceFooter: return 22
        case .bubblesHeader: return 30
        case .bubbleDerived: return 31
        case .bubbleColor1: return 32
        case .bubbleGradient: return 33
        case .bubbleColor2: return 34
        case .radius: return 35
        case .mergeCorners: return 36
        case .textsHeader: return 40
        case .chatFontSize: return 41
        case .listFontSize: return 42
        case .largeEmoji: return 43
        case .serifFont: return 44
        case .backgroundHeader: return 50
        case .wallpaperDefault: return 51
        case .wallpaperSolid: return 52
        case .wallpaperGradient: return 53
        case .wallpaperColorA: return 54
        case .wallpaperColorB: return 55
        case .applyAction: return 60
        case .saveAction: return 61
        case .resetAction: return 62
        case .homeHeader: return 70
        case .homeHideStories: return 71
        case .homeArchiveHidden: return 72
        case .homeHideEdit: return 73
        case .homeHideCompose: return 74
        case .homeHideStory: return 75
        case .homeFooter: return 76
        case .ambienceHeader: return 77
        case .snowEnabled: return 78
        case .snowIntensity: return 79
        case .ambienceFooter: return 80
        case .designsHeader: return 90
        case .importAction: return 91
        case .designsEmptyFooter: return 92
        case let .design(_, _, index):
            return 1000 + Int32(index)
        }
    }

    static func <(lhs: UrgramStudioControllerEntry, rhs: UrgramStudioControllerEntry) -> Bool {
        if lhs.section != rhs.section {
            return lhs.section < rhs.section
        }
        return lhs.stableId < rhs.stableId
    }

    static func ==(lhs: UrgramStudioControllerEntry, rhs: UrgramStudioControllerEntry) -> Bool {
        switch lhs {
        case .previewHeader:
            if case .previewHeader = rhs { return true } else { return false }
        case let .chatPreview(lhsTheme, lhsWallpaper, lhsCorners, lhsFontSize, lhsStrings, lhsFormat, lhsOrder, lhsItems):
            if case let .chatPreview(rhsTheme, rhsWallpaper, rhsCorners, rhsFontSize, rhsStrings, rhsFormat, rhsOrder, rhsItems) = rhs, lhsTheme === rhsTheme, lhsWallpaper == rhsWallpaper, lhsCorners == rhsCorners, lhsFontSize == rhsFontSize, lhsStrings === rhsStrings, lhsFormat == rhsFormat, lhsOrder == rhsOrder, lhsItems == rhsItems { return true } else { return false }
        case let .chatListPreview(lhsTheme, lhsTitle, lhsMessage):
            if case let .chatListPreview(rhsTheme, rhsTitle, rhsMessage) = rhs, lhsTheme === rhsTheme, lhsTitle == rhsTitle, lhsMessage == rhsMessage { return true } else { return false }
        case .previewFooter:
            if case .previewFooter = rhs { return true } else { return false }
        case .presetsHeader:
            if case .presetsHeader = rhs { return true } else { return false }
        case let .preset(lhsDesign, lhsName, lhsIndex):
            if case let .preset(rhsDesign, rhsName, rhsIndex) = rhs, lhsDesign == rhsDesign, lhsName == rhsName, lhsIndex == rhsIndex { return true } else { return false }
        case .interfaceHeader:
            if case .interfaceHeader = rhs { return true } else { return false }
        case let .accent(lhsValue):
            if case let .accent(rhsValue) = rhs, lhsValue == rhsValue { return true } else { return false }
        case .interfaceFooter:
            if case .interfaceFooter = rhs { return true } else { return false }
        case .bubblesHeader:
            if case .bubblesHeader = rhs { return true } else { return false }
        case let .bubbleDerived(lhsValue):
            if case let .bubbleDerived(rhsValue) = rhs, lhsValue == rhsValue { return true } else { return false }
        case let .bubbleColor1(lhsValue):
            if case let .bubbleColor1(rhsValue) = rhs, lhsValue == rhsValue { return true } else { return false }
        case let .bubbleGradient(lhsValue):
            if case let .bubbleGradient(rhsValue) = rhs, lhsValue == rhsValue { return true } else { return false }
        case let .bubbleColor2(lhsValue):
            if case let .bubbleColor2(rhsValue) = rhs, lhsValue == rhsValue { return true } else { return false }
        case let .radius(lhsValue):
            if case let .radius(rhsValue) = rhs, lhsValue == rhsValue { return true } else { return false }
        case let .mergeCorners(lhsValue):
            if case let .mergeCorners(rhsValue) = rhs, lhsValue == rhsValue { return true } else { return false }
        case .textsHeader:
            if case .textsHeader = rhs { return true } else { return false }
        case let .chatFontSize(lhsValue):
            if case let .chatFontSize(rhsValue) = rhs, lhsValue == rhsValue { return true } else { return false }
        case let .listFontSize(lhsValue):
            if case let .listFontSize(rhsValue) = rhs, lhsValue == rhsValue { return true } else { return false }
        case let .largeEmoji(lhsValue):
            if case let .largeEmoji(rhsValue) = rhs, lhsValue == rhsValue { return true } else { return false }
        case let .serifFont(lhsValue):
            if case let .serifFont(rhsValue) = rhs, lhsValue == rhsValue { return true } else { return false }
        case .backgroundHeader:
            if case .backgroundHeader = rhs { return true } else { return false }
        case let .wallpaperDefault(lhsValue):
            if case let .wallpaperDefault(rhsValue) = rhs, lhsValue == rhsValue { return true } else { return false }
        case let .wallpaperSolid(lhsValue):
            if case let .wallpaperSolid(rhsValue) = rhs, lhsValue == rhsValue { return true } else { return false }
        case let .wallpaperGradient(lhsValue):
            if case let .wallpaperGradient(rhsValue) = rhs, lhsValue == rhsValue { return true } else { return false }
        case let .wallpaperColorA(lhsValue, lhsMode):
            if case let .wallpaperColorA(rhsValue, rhsMode) = rhs, lhsValue == rhsValue, lhsMode == rhsMode { return true } else { return false }
        case let .wallpaperColorB(lhsValue):
            if case let .wallpaperColorB(rhsValue) = rhs, lhsValue == rhsValue { return true } else { return false }
        case .applyAction:
            if case .applyAction = rhs { return true } else { return false }
        case .saveAction:
            if case .saveAction = rhs { return true } else { return false }
        case .resetAction:
            if case .resetAction = rhs { return true } else { return false }
        case .homeHeader:
            if case .homeHeader = rhs { return true } else { return false }
        case let .homeHideStories(lhsValue):
            if case let .homeHideStories(rhsValue) = rhs, lhsValue == rhsValue { return true } else { return false }
        case let .homeArchiveHidden(lhsValue):
            if case let .homeArchiveHidden(rhsValue) = rhs, lhsValue == rhsValue { return true } else { return false }
        case let .homeHideEdit(lhsValue):
            if case let .homeHideEdit(rhsValue) = rhs, lhsValue == rhsValue { return true } else { return false }
        case let .homeHideCompose(lhsValue):
            if case let .homeHideCompose(rhsValue) = rhs, lhsValue == rhsValue { return true } else { return false }
        case let .homeHideStory(lhsValue):
            if case let .homeHideStory(rhsValue) = rhs, lhsValue == rhsValue { return true } else { return false }
        case .homeFooter:
            if case .homeFooter = rhs { return true } else { return false }
        case .ambienceHeader:
            if case .ambienceHeader = rhs { return true } else { return false }
        case let .snowEnabled(lhsValue):
            if case let .snowEnabled(rhsValue) = rhs, lhsValue == rhsValue { return true } else { return false }
        case let .snowIntensity(lhsValue):
            if case let .snowIntensity(rhsValue) = rhs, lhsValue == rhsValue { return true } else { return false }
        case .ambienceFooter:
            if case .ambienceFooter = rhs { return true } else { return false }
        case .designsHeader:
            if case .designsHeader = rhs { return true } else { return false }
        case .importAction:
            if case .importAction = rhs { return true } else { return false }
        case .designsEmptyFooter:
            if case .designsEmptyFooter = rhs { return true } else { return false }
        case let .design(lhsDesign, lhsActive, lhsIndex):
            if case let .design(rhsDesign, rhsActive, rhsIndex) = rhs, lhsDesign == rhsDesign, lhsActive == rhsActive, lhsIndex == rhsIndex { return true } else { return false }
        }
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! UrgramStudioControllerArguments
        let isArabic = urgramIsArabicLanguage(presentationData)
        switch self {
        case .previewHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: urgramText(presentationData, "Preview", "المعاينة"), sectionId: self.section)
        case let .chatPreview(theme, wallpaper, corners, fontSize, strings, dateTimeFormat, nameDisplayOrder, items):
            return ThemeSettingsChatPreviewItem(context: arguments.context, systemStyle: .glass, theme: theme, componentTheme: theme, strings: strings, sectionId: self.section, fontSize: fontSize, chatBubbleCorners: corners, wallpaper: wallpaper, dateTimeFormat: dateTimeFormat, nameDisplayOrder: nameDisplayOrder, messageItems: items)
        case let .chatListPreview(theme, title, message):
            return UrgramStudioChatListPreviewItem(systemStyle: .glass, theme: theme, titleText: title, messageText: message, sectionId: self.section)
        case .previewFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(urgramText(presentationData, "The preview is built on your current theme. Applying a design tints that theme — you can switch the base theme in Telegram's Appearance settings at any time.", "تُبنى المعاينة على سِمتك الحالية. تطبيق التصميم يلوّن تلك السمة — يمكنك تغيير السمة الأساسية من إعدادات المظهر في تيليغرام في أي وقت.")), sectionId: self.section)
        case .presetsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: urgramText(presentationData, "Ready Designs", "تصاميم جاهزة"), sectionId: self.section)
        case let .preset(design, name, _):
            return ItemListPeerActionItem(presentationData: presentationData, systemStyle: .glass, icon: urgramStudioSwatchImage(design.accentColor), title: name, sectionId: self.section, height: .generic, color: .accent, editing: false, action: {
                arguments.applyPreset(design)
            })
        case .interfaceHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: urgramText(presentationData, "Interface Colors", "ألوان الواجهة"), sectionId: self.section)
        case let .accent(value):
            return ItemListDisclosureItem(presentationData: presentationData, title: urgramText(presentationData, "Accent Color", "لون التمييز"), label: urgramStudioHexString(value), sectionId: self.section, style: .blocks, action: {
                arguments.openColorEditor(.accent)
            })
        case .interfaceFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(urgramText(presentationData, "The accent color drives the tab bar selection, navigation buttons, search, unread badges and checkmarks across the app.", "لون التمييز يقود لون تحديد شريط التبويبات وأزرار التنقّل والبحث وشارات غير المقروء وعلامات القراءة في كل التطبيق.")), sectionId: self.section)
        case .bubblesHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: urgramText(presentationData, "Bubbles", "الفقاعات"), sectionId: self.section)
        case let .bubbleDerived(checked):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: urgramText(presentationData, "Bubbles from Accent Color", "الفقاعات من لون التمييز"), style: .left, checked: checked, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.updateDraft { parameters in
                    if parameters.bubbleColors.isEmpty {
                        parameters.bubbleColors = [parameters.accentColor]
                    } else {
                        parameters.bubbleColors = []
                    }
                }
            })
        case let .bubbleColor1(value):
            return ItemListDisclosureItem(presentationData: presentationData, title: urgramText(presentationData, "Outgoing Bubble Color", "لون فقاعة الرسائل الصادرة"), label: urgramStudioHexString(value), sectionId: self.section, style: .blocks, action: {
                arguments.openColorEditor(.bubble1)
            })
        case let .bubbleGradient(checked):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: urgramText(presentationData, "Bubble Gradient", "تدرّج الفقاعة"), style: .left, checked: checked, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.updateDraft { parameters in
                    if parameters.bubbleColors.count > 1 {
                        parameters.bubbleColors = [parameters.bubbleColors[0]]
                    } else if parameters.bubbleColors.count == 1 {
                        parameters.bubbleColors = [parameters.bubbleColors[0], parameters.bubbleColors[0]]
                    }
                }
            })
        case let .bubbleColor2(value):
            return ItemListDisclosureItem(presentationData: presentationData, title: urgramText(presentationData, "Outgoing Bubble Color 2", "لون فقاعة الرسائل الصادرة الثاني"), label: urgramStudioHexString(value), sectionId: self.section, style: .blocks, action: {
                arguments.openColorEditor(.bubble2)
            })
        case .backgroundHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: urgramText(presentationData, "Background", "الخلفية"), sectionId: self.section)
        case let .wallpaperDefault(checked):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: urgramText(presentationData, "Chat Background: Theme Default", "خلفية المحادثة: افتراضي السمة"), style: .left, checked: checked, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.updateDraft { $0.wallpaperMode = 0 }
            })
        case let .wallpaperSolid(checked):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: urgramText(presentationData, "Chat Background: Solid Color", "خلفية المحادثة: لون واحد"), style: .left, checked: checked, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.updateDraft { $0.wallpaperMode = 1 }
            })
        case let .wallpaperGradient(checked):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: urgramText(presentationData, "Chat Background: Gradient", "خلفية المحادثة: تدرّج"), style: .left, checked: checked, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.updateDraft { $0.wallpaperMode = 2 }
            })
        case let .wallpaperColorA(value, mode):
            return ItemListDisclosureItem(presentationData: presentationData, title: mode == 2 ? urgramText(presentationData, "Background Color 1", "لون الخلفية الأول") : urgramText(presentationData, "Background Color", "لون الخلفية"), label: urgramStudioHexString(value), sectionId: self.section, style: .blocks, action: {
                arguments.openColorEditor(.wallpaperA)
            })
        case let .wallpaperColorB(value):
            return ItemListDisclosureItem(presentationData: presentationData, title: urgramText(presentationData, "Background Color 2", "لون الخلفية الثاني"), label: urgramStudioHexString(value), sectionId: self.section, style: .blocks, action: {
                arguments.openColorEditor(.wallpaperB)
            })
        case let .radius(value):
            let displayValue = min(16, max(8, Int(value)))
            let snappedValue = displayValue - (displayValue % 2)
            return BubbleSettingsRadiusItem(theme: presentationData.theme, value: snappedValue, enabled: true, disableLeadingInset: false, displayIcons: true, disableDecorations: false, force: false, sectionId: self.section, updated: { newValue in
                arguments.updateDraft { $0.bubbleRadius = Int32(newValue) }
            })
        case let .mergeCorners(checked):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: urgramText(presentationData, "Merge Bubble Corners", "دمج زوايا الفقاعات المتتالية"), style: .left, checked: checked, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.updateDraft { $0.mergeBubbleCorners = !(checked) }
            })
        case .textsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: urgramText(presentationData, "Text & Links", "النصوص والروابط"), sectionId: self.section)
        case let .chatFontSize(rawValue):
            return ItemListDisclosureItem(presentationData: presentationData, title: urgramText(presentationData, "Chat Text Size", "حجم نص المحادثات"), label: urgramStudioFontSizeName(rawValue, isArabic: isArabic), sectionId: self.section, style: .blocks, action: {
                arguments.cycleFontSize(true)
            })
        case let .listFontSize(rawValue):
            return ItemListDisclosureItem(presentationData: presentationData, title: urgramText(presentationData, "List Text Size", "حجم نص القوائم"), label: urgramStudioFontSizeName(rawValue, isArabic: isArabic), sectionId: self.section, style: .blocks, action: {
                arguments.cycleFontSize(false)
            })
        case let .largeEmoji(checked):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: urgramText(presentationData, "Large Emoji", "إيموجي كبيرة"), style: .left, checked: checked, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.updateDraft { $0.largeEmoji = !(checked) }
            })
        case let .serifFont(checked):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: urgramText(presentationData, "Serif Message Font", "خط رسائل مزخرف (Serif)"), style: .left, checked: checked, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.updateDraft { $0.serifMessageFont = !(checked) }
            })
        case .applyAction:
            return ItemListActionItem(presentationData: presentationData, title: urgramText(presentationData, "Apply Design", "تطبيق التصميم"), kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.applyDraft()
            })
        case .saveAction:
            return ItemListActionItem(presentationData: presentationData, title: urgramText(presentationData, "Save Design…", "حفظ التصميم…"), kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.saveDraft()
            })
        case .resetAction:
            return ItemListActionItem(presentationData: presentationData, title: urgramText(presentationData, "Reset Appearance", "إعادة تعيين المظهر"), kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.resetAppearance()
            })
        case .homeHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: urgramText(presentationData, "Main Interface", "الواجهة الرئيسية"), sectionId: self.section)
        case let .homeHideStories(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: urgramText(presentationData, "Hide Stories Bar", "إخفاء شريط القصص"), value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateHomeFlag(\.hideStoriesBar, value)
            })
        case let .homeArchiveHidden(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: urgramText(presentationData, "Hide Archived Chats Row", "إخفاء صف المحادثات المؤرشفة"), value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.setArchiveHidden(value)
            })
        case let .homeHideEdit(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: urgramText(presentationData, "Hide Edit Button", "إخفاء زر التحرير"), value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateHomeFlag(\.homeHideEditButton, value)
            })
        case let .homeHideCompose(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: urgramText(presentationData, "Hide New Message Button", "إخفاء زر رسالة جديدة"), value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateHomeFlag(\.homeHideComposeButton, value)
            })
        case let .homeHideStory(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: urgramText(presentationData, "Hide Add Story Button", "إخفاء زر إضافة قصة"), value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateHomeFlag(\.homeHideStoryButton, value)
            })
        case .homeFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(urgramText(presentationData, "These switches apply immediately — they are interface preferences, not part of saved designs.", "هذه المفاتيح تُطبَّق فورًا — هي تفضيلات واجهة وليست جزءًا من التصاميم المحفوظة.")), sectionId: self.section)
        case .ambienceHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: urgramText(presentationData, "Ambience", "أجواء"), sectionId: self.section)
        case let .snowEnabled(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: urgramText(presentationData, "Snowfall ❄️", "تساقط الثلج ❄️"), value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateHomeFlag(\.snowEnabled, value)
            })
        case let .snowIntensity(value):
            return ItemListDisclosureItem(presentationData: presentationData, title: urgramText(presentationData, "Snow Intensity", "كثافة الثلج"), label: urgramStudioSnowIntensityName(value, isArabic: isArabic), sectionId: self.section, style: .blocks, action: {
                arguments.cycleSnowIntensity()
            })
        case .ambienceFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(urgramText(presentationData, "Snow falls over the whole app and slowly piles up at the top and bottom of the screen. It melts away when you turn it off.", "يتساقط الثلج على التطبيق كله ويتراكم ببطء أعلى الشاشة وأسفلها. يذوب عند إيقافه.")), sectionId: self.section)
        case .designsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: urgramText(presentationData, "My Designs", "تصاميمي"), sectionId: self.section)
        case .importAction:
            return ItemListActionItem(presentationData: presentationData, title: urgramText(presentationData, "Import Design…", "استيراد تصميم…"), kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.importDesign()
            })
        case .designsEmptyFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(urgramText(presentationData, "No saved designs yet. Shape your look above, then tap Save Design. Tap a design to apply, rename, share or delete it.", "لا تصاميم محفوظة بعد. شكّل مظهرك أعلاه ثم اضغط حفظ التصميم. اضغط أي تصميم لتطبيقه أو إعادة تسميته أو مشاركته أو حذفه.")), sectionId: self.section)
        case let .design(design, isActive, _):
            let title = design.name + (isActive ? (isArabic ? " • مفعّل" : " • Active") : "")
            return ItemListPeerActionItem(presentationData: presentationData, systemStyle: .glass, icon: urgramStudioSwatchImage(design.accentColor), title: title, sectionId: self.section, height: .generic, color: .accent, editing: false, action: {
                arguments.designAction(design)
            })
        }
    }
}

private func urgramStudioControllerEntries(presentationData: PresentationData, settings: UrgramSettings, draft: UrgramStudioDraft, themeSettings: PresentationThemeSettings, archiveHidden: Bool) -> [UrgramStudioControllerEntry] {
    let parameters = draft.parameters
    let isArabic = presentationData.strings.primaryComponent.languageCode.hasPrefix("ar")

    let draftWallpaper = urgramStudioWallpaper(for: parameters)
    let previewTheme = customizePresentationTheme(presentationData.theme, editing: false, accentColor: UIColor(argb: parameters.accentColor), outgoingAccentColor: nil, backgroundColors: [], bubbleColors: parameters.bubbleColors.map { $0 & 0x00ffffff }, animateBubbleColors: nil, wallpaper: draftWallpaper, baseColor: .custom)
    // URGRAM (Studio V2): the preview reflects the draft's own values for the
    // new parameters, falling back to the live presentation data.
    let previewCorners = PresentationChatBubbleCorners(mainRadius: CGFloat(parameters.bubbleRadius), auxiliaryRadius: CGFloat(parameters.bubbleRadius / 2), mergeBubbleCorners: parameters.mergeBubbleCorners ?? presentationData.chatBubbleCorners.mergeBubbleCorners, hasTails: presentationData.chatBubbleCorners.hasTails, bubbleMode: presentationData.chatBubbleCorners.bubbleMode, serifMessageText: parameters.serifMessageFont ?? presentationData.chatBubbleCorners.serifMessageText)
    let previewWallpaper = draftWallpaper ?? presentationData.chatWallpaper
    let previewFontSize: PresentationFontSize
    if let rawChatFontSize = parameters.chatFontSize, rawChatFontSize >= 0, let fontSize = PresentationFontSize(rawValue: rawChatFontSize) {
        previewFontSize = fontSize
    } else {
        previewFontSize = presentationData.chatFontSize
    }
    let effectiveChatFontRaw: Int32 = parameters.chatFontSize ?? (themeSettings.useSystemFont ? -1 : themeSettings.fontSize.rawValue)
    let effectiveListFontRaw: Int32 = parameters.listFontSize ?? (themeSettings.useSystemFont ? -1 : themeSettings.listsFontSize.rawValue)

    var entries: [UrgramStudioControllerEntry] = []

    entries.append(.previewHeader)
    entries.append(.chatPreview(previewTheme, previewWallpaper, previewCorners, previewFontSize, presentationData.strings, presentationData.dateTimeFormat, presentationData.nameDisplayOrder, [
        ChatPreviewMessageItem(outgoing: false, reply: (presentationData.strings.Appearance_PreviewReplyAuthor, presentationData.strings.Appearance_PreviewReplyText), text: presentationData.strings.Appearance_PreviewIncomingText, nameColor: .preset(.blue), backgroundEmojiId: nil),
        ChatPreviewMessageItem(outgoing: true, reply: nil, text: presentationData.strings.Appearance_PreviewOutgoingText, nameColor: .preset(.blue), backgroundEmojiId: nil)
    ]))
    entries.append(.chatListPreview(previewTheme, isArabic ? "أورغرام" : "Urgram", isArabic ? "جرّب تصميمك الجديد 🎨" : "Try your new design 🎨"))
    entries.append(.previewFooter)

    entries.append(.presetsHeader)
    for (index, preset) in urgramStudioPresets.enumerated() {
        entries.append(.preset(preset.design, isArabic ? preset.ar : preset.en, index))
    }

    entries.append(.interfaceHeader)
    entries.append(.accent(parameters.accentColor))
    entries.append(.interfaceFooter)

    entries.append(.bubblesHeader)
    entries.append(.bubbleDerived(parameters.bubbleColors.isEmpty))
    if !parameters.bubbleColors.isEmpty {
        entries.append(.bubbleColor1(parameters.bubbleColors[0]))
        entries.append(.bubbleGradient(parameters.bubbleColors.count > 1))
        if parameters.bubbleColors.count > 1 {
            entries.append(.bubbleColor2(parameters.bubbleColors[1]))
        }
    }
    entries.append(.radius(parameters.bubbleRadius))
    entries.append(.mergeCorners(parameters.mergeBubbleCorners ?? themeSettings.chatBubbleSettings.mergeBubbleCorners))

    entries.append(.textsHeader)
    entries.append(.chatFontSize(effectiveChatFontRaw))
    entries.append(.listFontSize(effectiveListFontRaw))
    entries.append(.largeEmoji(parameters.largeEmoji ?? themeSettings.largeEmoji))
    entries.append(.serifFont(parameters.serifMessageFont ?? themeSettings.chatBubbleSettings.serifMessageFont))

    entries.append(.backgroundHeader)
    entries.append(.wallpaperDefault(parameters.wallpaperMode == 0))
    entries.append(.wallpaperSolid(parameters.wallpaperMode == 1))
    entries.append(.wallpaperGradient(parameters.wallpaperMode == 2))
    if parameters.wallpaperMode == 1 {
        entries.append(.wallpaperColorA(parameters.wallpaperColorA, parameters.wallpaperMode))
    } else if parameters.wallpaperMode == 2 {
        entries.append(.wallpaperColorA(parameters.wallpaperColorA, parameters.wallpaperMode))
        entries.append(.wallpaperColorB(parameters.wallpaperColorB))
    }

    entries.append(.applyAction)
    entries.append(.saveAction)
    entries.append(.resetAction)

    entries.append(.homeHeader)
    entries.append(.homeHideStories(settings.hideStoriesBar))
    entries.append(.homeArchiveHidden(archiveHidden))
    entries.append(.homeHideEdit(settings.homeHideEditButton))
    entries.append(.homeHideCompose(settings.homeHideComposeButton))
    entries.append(.homeHideStory(settings.homeHideStoryButton))
    entries.append(.homeFooter)

    entries.append(.ambienceHeader)
    entries.append(.snowEnabled(settings.snowEnabled))
    entries.append(.snowIntensity(settings.snowIntensity))
    entries.append(.ambienceFooter)

    entries.append(.designsHeader)
    entries.append(.importAction)
    if settings.studioDesigns.isEmpty {
        entries.append(.designsEmptyFooter)
    } else {
        for (index, design) in settings.studioDesigns.enumerated() {
            entries.append(.design(design, settings.studioActiveDesignId == design.id, index))
        }
    }

    return entries
}

// URGRAM: writes the design as a JSON .urgramtheme file and offers it
// through the system share sheet, so it can be sent in any chat or app.
private func urgramStudioExportDesign(_ design: UrgramThemeDesign, present: @escaping (UIViewController) -> Void) {
    guard let data = try? JSONEncoder().encode(design) else {
        return
    }
    let invalidCharacters = CharacterSet(charactersIn: "/\\:?%*|\"<>")
    let safeName = design.name.components(separatedBy: invalidCharacters).joined(separator: "-").trimmingCharacters(in: .whitespaces)
    let fileName = (safeName.isEmpty ? "UrgramDesign" : safeName) + ".urgramtheme"
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(fileName)
    guard (try? data.write(to: url, options: .atomic)) != nil else {
        return
    }
    let activityController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    present(activityController)
}

private func urgramStudioSanitizedImportedDesign(_ design: UrgramThemeDesign, fallbackName: String) -> UrgramThemeDesign {
    var design = design
    design.id = UUID().uuidString
    if design.name.trimmingCharacters(in: .whitespaces).isEmpty {
        design.name = fallbackName
    }
    design.bubbleColors = Array(design.bubbleColors.prefix(2))
    design.wallpaperMode = min(2, max(0, design.wallpaperMode))
    design.bubbleRadius = min(24, max(4, design.bubbleRadius))
    // URGRAM (Studio V2): font sizes are -1 (system) or a valid
    // PresentationFontSize raw value (0...6); anything else is dropped so a
    // malformed file cannot write an invalid size.
    if let chatFontSize = design.chatFontSize, chatFontSize < -1 || chatFontSize > 6 {
        design.chatFontSize = nil
    }
    if let listFontSize = design.listFontSize, listFontSize < -1 || listFontSize > 6 {
        design.listFontSize = nil
    }
    return design
}

// URGRAM: retains the import document-picker delegate while it is on screen.
private final class UrgramStudioImportPickerDelegate: NSObject, UIDocumentPickerDelegate {
    let completion: (URL?) -> Void

    init(completion: @escaping (URL?) -> Void) {
        self.completion = completion
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        UrgramStudioImportPickerDelegate.active = nil
        self.completion(urls.first)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        UrgramStudioImportPickerDelegate.active = nil
        self.completion(nil)
    }

    static var active: UrgramStudioImportPickerDelegate?
}

public func urgramStudioController(context: AccountContext) -> ViewController {
    var pushImpl: ((ViewController) -> Void)?
    var presentImpl: ((UIViewController) -> Void)?

    let initialSettings = UrgramSettingsStore.shared.current
    let initialPresentationData = context.sharedContext.currentPresentationData.with { $0 }
    let initialDraft: UrgramStudioDraft
    if let activeId = initialSettings.studioActiveDesignId, let activeDesign = initialSettings.studioDesigns.first(where: { $0.id == activeId }) {
        initialDraft = UrgramStudioDraft(parameters: activeDesign, sourceDesignId: activeDesign.id)
    } else {
        initialDraft = UrgramStudioDraft(parameters: UrgramThemeDesign(
            id: "",
            name: "",
            accentColor: initialPresentationData.theme.list.itemAccentColor.argb,
            bubbleColors: [],
            wallpaperMode: 0,
            wallpaperColorA: 0xff2aabee,
            wallpaperColorB: 0xff7b2ff7,
            bubbleRadius: Int32(initialPresentationData.chatBubbleCorners.mainRadius)
        ), sourceDesignId: nil)
    }
    let draftValue = Atomic<UrgramStudioDraft>(value: initialDraft)
    let draftPromise = ValuePromise<UrgramStudioDraft>(initialDraft, ignoreRepeated: true)
    // URGRAM (Studio V2): latest persisted theme settings, kept in sync by
    // the state signal below; the font-size cycle reads the effective
    // fallback (system vs stored size) from it.
    let themeSettingsValue = Atomic<PresentationThemeSettings>(value: PresentationThemeSettings.defaultSettings)

    let arguments = UrgramStudioControllerArguments(
        context: context,
        updateDraft: { mutate in
            var draft = draftValue.with { $0 }
            mutate(&draft.parameters)
            draft.sourceDesignId = nil
            draft.parameters.id = ""
            let _ = draftValue.swap(draft)
            draftPromise.set(draft)
        },
        openColorEditor: { target in
            let draft = draftValue.with { $0 }
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let isArabic = presentationData.strings.primaryComponent.languageCode.hasPrefix("ar")
            let title: String
            let initialColor: UInt32
            let applyColor: (inout UrgramThemeDesign, UInt32) -> Void
            switch target {
            case .accent:
                title = isArabic ? "لون التمييز" : "Accent Color"
                initialColor = draft.parameters.accentColor
                applyColor = { parameters, color in parameters.accentColor = color }
            case .bubble1:
                title = isArabic ? "لون فقاعة الرسائل الصادرة" : "Outgoing Bubble Color"
                initialColor = draft.parameters.bubbleColors.first ?? draft.parameters.accentColor
                applyColor = { parameters, color in
                    if parameters.bubbleColors.isEmpty {
                        parameters.bubbleColors = [color]
                    } else {
                        parameters.bubbleColors[0] = color
                    }
                }
            case .bubble2:
                title = isArabic ? "لون فقاعة الرسائل الصادرة الثاني" : "Outgoing Bubble Color 2"
                initialColor = draft.parameters.bubbleColors.count > 1 ? draft.parameters.bubbleColors[1] : draft.parameters.accentColor
                applyColor = { parameters, color in
                    if parameters.bubbleColors.count > 1 {
                        parameters.bubbleColors[1] = color
                    } else if parameters.bubbleColors.count == 1 {
                        parameters.bubbleColors.append(color)
                    }
                }
            case .wallpaperA:
                title = isArabic ? "لون الخلفية" : "Background Color"
                initialColor = draft.parameters.wallpaperColorA
                applyColor = { parameters, color in parameters.wallpaperColorA = color }
            case .wallpaperB:
                title = isArabic ? "لون الخلفية الثاني" : "Background Color 2"
                initialColor = draft.parameters.wallpaperColorB
                applyColor = { parameters, color in parameters.wallpaperColorB = color }
            }
            pushImpl?(urgramStudioColorController(context: context, title: title, initialColor: initialColor, updated: { color in
                var updatedDraft = draftValue.with { $0 }
                applyColor(&updatedDraft.parameters, color)
                updatedDraft.sourceDesignId = nil
                updatedDraft.parameters.id = ""
                let _ = draftValue.swap(updatedDraft)
                draftPromise.set(updatedDraft)
            }))
        },
        applyDraft: {
            let draft = draftValue.with { $0 }
            var design = draft.parameters
            design.id = draft.sourceDesignId ?? ""
            urgramStudioApplyDesign(context: context, design: design)
        },
        saveDraft: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let isArabic = presentationData.strings.primaryComponent.languageCode.hasPrefix("ar")
            let draft = draftValue.with { $0 }
            let alert = UIAlertController(title: isArabic ? "حفظ التصميم" : "Save Design", message: isArabic ? "اختر اسمًا لهذا التصميم." : "Choose a name for this design.", preferredStyle: .alert)
            alert.addTextField { textField in
                textField.text = draft.parameters.name.isEmpty ? (isArabic ? "تصميمي" : "My Design") : draft.parameters.name
                textField.autocapitalizationType = .words
            }
            alert.addAction(UIAlertAction(title: isArabic ? "إلغاء" : "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: isArabic ? "حفظ" : "Save", style: .default, handler: { _ in
                let name = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespaces) ?? ""
                var design = draft.parameters
                design.id = UUID().uuidString
                design.name = name.isEmpty ? (isArabic ? "تصميمي" : "My Design") : name
                UrgramSettingsStore.shared.update { settings in
                    settings.studioDesigns.append(design)
                }
                let savedDraft = UrgramStudioDraft(parameters: design, sourceDesignId: design.id)
                let _ = draftValue.swap(savedDraft)
                draftPromise.set(savedDraft)
            }))
            presentImpl?(alert)
        },
        resetAppearance: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let isArabic = presentationData.strings.primaryComponent.languageCode.hasPrefix("ar")
            let alert = UIAlertController(title: isArabic ? "إعادة تعيين المظهر" : "Reset Appearance", message: isArabic ? "سيتم حذف لون التمييز وخلفية المحادثة ونصف قطر الفقاعات التي ضبطها الاستوديو والرجوع إلى مظهر السمة الافتراضي." : "This removes the Studio's accent color, chat background and bubble radius, returning to the theme's default look.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: isArabic ? "إلغاء" : "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: isArabic ? "إعادة تعيين" : "Reset", style: .destructive, handler: { _ in
                urgramStudioResetAppearance(context: context)
                let resetDraft = UrgramStudioDraft(parameters: UrgramThemeDesign(
                    id: "",
                    name: "",
                    accentColor: PresentationThemeBaseColor.blue.color.argb,
                    bubbleColors: [],
                    wallpaperMode: 0,
                    wallpaperColorA: 0xff2aabee,
                    wallpaperColorB: 0xff7b2ff7,
                    bubbleRadius: 16
                ), sourceDesignId: nil)
                let _ = draftValue.swap(resetDraft)
                draftPromise.set(resetDraft)
            }))
            presentImpl?(alert)
        },
        designAction: { design in
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let isArabic = presentationData.strings.primaryComponent.languageCode.hasPrefix("ar")
            let sheet = UIAlertController(title: design.name, message: nil, preferredStyle: .actionSheet)
            sheet.addAction(UIAlertAction(title: isArabic ? "تطبيق" : "Apply", style: .default, handler: { _ in
                urgramStudioApplyDesign(context: context, design: design)
                let loadedDraft = UrgramStudioDraft(parameters: design, sourceDesignId: design.id)
                let _ = draftValue.swap(loadedDraft)
                draftPromise.set(loadedDraft)
            }))
            sheet.addAction(UIAlertAction(title: isArabic ? "إعادة تسمية" : "Rename", style: .default, handler: { _ in
                let alert = UIAlertController(title: isArabic ? "إعادة تسمية" : "Rename", message: nil, preferredStyle: .alert)
                alert.addTextField { textField in
                    textField.text = design.name
                    textField.autocapitalizationType = .words
                }
                alert.addAction(UIAlertAction(title: isArabic ? "إلغاء" : "Cancel", style: .cancel))
                alert.addAction(UIAlertAction(title: isArabic ? "حفظ" : "Save", style: .default, handler: { _ in
                    let name = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespaces) ?? ""
                    guard !name.isEmpty else {
                        return
                    }
                    UrgramSettingsStore.shared.update { settings in
                        if let index = settings.studioDesigns.firstIndex(where: { $0.id == design.id }) {
                            settings.studioDesigns[index].name = name
                        }
                    }
                }))
                presentImpl?(alert)
            }))
            sheet.addAction(UIAlertAction(title: isArabic ? "مشاركة (تصدير ملف)" : "Share (Export File)", style: .default, handler: { _ in
                if let presentImpl = presentImpl {
                    urgramStudioExportDesign(design, present: presentImpl)
                }
            }))
            sheet.addAction(UIAlertAction(title: isArabic ? "حذف" : "Delete", style: .destructive, handler: { _ in
                UrgramSettingsStore.shared.update { settings in
                    settings.studioDesigns.removeAll(where: { $0.id == design.id })
                    if settings.studioActiveDesignId == design.id {
                        settings.studioActiveDesignId = nil
                    }
                }
            }))
            sheet.addAction(UIAlertAction(title: isArabic ? "إلغاء" : "Cancel", style: .cancel))
            presentImpl?(sheet)
        },
        importDesign: {
            guard let presentImpl = presentImpl else {
                return
            }
            // Same rule as the font picker (build 15 fix): no UTType filter —
            // a sideloaded app declares no .urgramtheme type, so filtering
            // would grey the files out. Parse and validate after the pick.
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data])
            let delegate = UrgramStudioImportPickerDelegate(completion: { url in
                guard let url = url else {
                    return
                }
                let scoped = url.startAccessingSecurityScopedResource()
                let data = try? Data(contentsOf: url)
                if scoped {
                    url.stopAccessingSecurityScopedResource()
                }
                guard let data = data, let parsed = try? JSONDecoder().decode(UrgramThemeDesign.self, from: data) else {
                    return
                }
                let design = urgramStudioSanitizedImportedDesign(parsed, fallbackName: url.deletingPathExtension().lastPathComponent)
                UrgramSettingsStore.shared.update { settings in
                    settings.studioDesigns.append(design)
                }
                // Import applies in one tap.
                urgramStudioApplyDesign(context: context, design: design)
                let loadedDraft = UrgramStudioDraft(parameters: design, sourceDesignId: design.id)
                let _ = draftValue.swap(loadedDraft)
                draftPromise.set(loadedDraft)
            })
            UrgramStudioImportPickerDelegate.active = delegate
            picker.delegate = delegate
            presentImpl(picker)
        },
        applyPreset: { presetDesign in
            // Presets are not saved designs: clear the id so the apply path
            // does not record a non-existent design as the active one.
            var design = presetDesign
            design.id = ""
            urgramStudioApplyDesign(context: context, design: design)
            let loadedDraft = UrgramStudioDraft(parameters: design, sourceDesignId: nil)
            let _ = draftValue.swap(loadedDraft)
            draftPromise.set(loadedDraft)
        },
        cycleFontSize: { isChat in
            var draft = draftValue.with { $0 }
            let themeSettings = themeSettingsValue.with { $0 }
            let currentChatRaw: Int32 = draft.parameters.chatFontSize ?? (themeSettings.useSystemFont ? -1 : themeSettings.fontSize.rawValue)
            let currentListRaw: Int32 = draft.parameters.listFontSize ?? (themeSettings.useSystemFont ? -1 : themeSettings.listsFontSize.rawValue)
            // Font sizes share the runtime's single useSystemFont switch, so
            // cycling one size pins the other at its current effective value.
            if isChat {
                draft.parameters.chatFontSize = urgramStudioNextFontSizeRaw(currentChatRaw)
                if draft.parameters.listFontSize == nil {
                    draft.parameters.listFontSize = currentListRaw
                }
            } else {
                draft.parameters.listFontSize = urgramStudioNextFontSizeRaw(currentListRaw)
                if draft.parameters.chatFontSize == nil {
                    draft.parameters.chatFontSize = currentChatRaw
                }
            }
            draft.sourceDesignId = nil
            draft.parameters.id = ""
            let _ = draftValue.swap(draft)
            draftPromise.set(draft)
        },
        updateHomeFlag: { keyPath, value in
            UrgramSettingsStore.shared.update { settings in
                settings[keyPath: keyPath] = value
            }
        },
        setArchiveHidden: { value in
            let _ = updateChatArchiveSettings(engine: context.engine, { current in
                return ChatArchiveSettings(isHiddenByDefault: value, hiddenPsaPeerId: current.hiddenPsaPeerId)
            }).start()
        },
        cycleSnowIntensity: {
            UrgramSettingsStore.shared.update { settings in
                settings.snowIntensity = (settings.snowIntensity + 1) % 3
            }
        }
    )

    let presentationThemeSettingsSignal = context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.presentationThemeSettings])
    |> map { values -> PresentationThemeSettings in
        return values.entries[ApplicationSpecificSharedDataKeys.presentationThemeSettings]?.get(PresentationThemeSettings.self) ?? PresentationThemeSettings.defaultSettings
    }
    let archiveHiddenSignal = context.engine.data.subscribe(TelegramEngine.EngineData.Item.Configuration.ApplicationSpecificPreference(key: ApplicationSpecificPreferencesKeys.chatArchiveSettings))
    |> map { entry -> Bool in
        return entry?.get(ChatArchiveSettings.self)?.isHiddenByDefault ?? false
    }

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        UrgramSettingsStore.shared.settingsSignal,
        draftPromise.get(),
        presentationThemeSettingsSignal,
        archiveHiddenSignal
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings, draft, themeSettings, archiveHidden -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let _ = themeSettingsValue.swap(themeSettings)
        var chromePresentationData = presentationData
        let updatedTheme = presentationData.theme.withModalBlocksBackground()
        chromePresentationData = presentationData.withUpdated(theme: updatedTheme)

        let isArabic = presentationData.strings.primaryComponent.languageCode.hasPrefix("ar")
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(chromePresentationData), title: .text(isArabic ? "استوديو أورغرام" : "Urgram Studio"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(chromePresentationData), entries: urgramStudioControllerEntries(presentationData: presentationData, settings: settings, draft: draft, themeSettings: themeSettings, archiveHidden: archiveHidden), style: .blocks, animateChanges: true)

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

// MARK: - Color editor

private struct UrgramStudioPaletteColor {
    let argb: UInt32
    let en: String
    let ar: String
}

private let urgramStudioPalette: [UrgramStudioPaletteColor] = [
    UrgramStudioPaletteColor(argb: 0xff2aabee, en: "Blue", ar: "أزرق"),
    UrgramStudioPaletteColor(argb: 0xff00c2e8, en: "Cyan", ar: "سماوي"),
    UrgramStudioPaletteColor(argb: 0xff00b894, en: "Teal", ar: "فيروزي"),
    UrgramStudioPaletteColor(argb: 0xff4dcc5e, en: "Green", ar: "أخضر"),
    UrgramStudioPaletteColor(argb: 0xffffd60a, en: "Yellow", ar: "أصفر"),
    UrgramStudioPaletteColor(argb: 0xffff9500, en: "Orange", ar: "برتقالي"),
    UrgramStudioPaletteColor(argb: 0xfff55783, en: "Pink", ar: "وردي"),
    UrgramStudioPaletteColor(argb: 0xffff3b30, en: "Red", ar: "أحمر"),
    UrgramStudioPaletteColor(argb: 0xff7b2ff7, en: "Purple", ar: "بنفسجي"),
    UrgramStudioPaletteColor(argb: 0xff5e5ce6, en: "Violet", ar: "أرجواني"),
    UrgramStudioPaletteColor(argb: 0xffa2845e, en: "Brown", ar: "بني"),
    UrgramStudioPaletteColor(argb: 0xff8e8e93, en: "Gray", ar: "رمادي"),
    UrgramStudioPaletteColor(argb: 0xff000000, en: "Black", ar: "أسود"),
    UrgramStudioPaletteColor(argb: 0xffffffff, en: "White", ar: "أبيض")
]

private enum UrgramStudioColorComponent {
    case hue
    case saturation
    case brightness
}

private final class UrgramStudioColorControllerArguments {
    let selectPreset: (Int) -> Void
    let updateComponent: (UrgramStudioColorComponent, CGFloat) -> Void

    init(selectPreset: @escaping (Int) -> Void, updateComponent: @escaping (UrgramStudioColorComponent, CGFloat) -> Void) {
        self.selectPreset = selectPreset
        self.updateComponent = updateComponent
    }
}

private enum UrgramStudioColorSection: Int32 {
    case current
    case presets
    case custom
}

private enum UrgramStudioColorControllerEntry: ItemListNodeEntry {
    case currentHeader
    case currentSwatch(UInt32)
    case presetsHeader
    case preset(Int)
    case customHeader
    case hue(CGFloat)
    case saturation(CGFloat)
    case brightness(CGFloat)
    case customFooter

    var section: ItemListSectionId {
        switch self {
        case .currentHeader, .currentSwatch:
            return UrgramStudioColorSection.current.rawValue
        case .presetsHeader, .preset:
            return UrgramStudioColorSection.presets.rawValue
        case .customHeader, .hue, .saturation, .brightness, .customFooter:
            return UrgramStudioColorSection.custom.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .currentHeader: return 0
        case .currentSwatch: return 1
        case .presetsHeader: return 10
        case let .preset(index): return 20 + Int32(index)
        case .customHeader: return 40
        case .hue: return 41
        case .saturation: return 42
        case .brightness: return 43
        case .customFooter: return 44
        }
    }

    static func <(lhs: UrgramStudioColorControllerEntry, rhs: UrgramStudioColorControllerEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! UrgramStudioColorControllerArguments
        let isArabic = urgramIsArabicLanguage(presentationData)
        switch self {
        case .currentHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: urgramText(presentationData, "Current Color", "اللون الحالي"), sectionId: self.section)
        case let .currentSwatch(value):
            return ItemListPeerActionItem(presentationData: presentationData, systemStyle: .glass, icon: urgramStudioSwatchImage(value), title: urgramStudioHexString(value), sectionId: self.section, height: .generic, color: .disabled, editing: false, action: nil)
        case .presetsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: urgramText(presentationData, "Presets", "ألوان جاهزة"), sectionId: self.section)
        case let .preset(index):
            let paletteColor = urgramStudioPalette[index]
            return ItemListPeerActionItem(presentationData: presentationData, systemStyle: .glass, icon: urgramStudioSwatchImage(paletteColor.argb), title: isArabic ? paletteColor.ar : paletteColor.en, sectionId: self.section, height: .generic, color: .accent, editing: false, action: {
                arguments.selectPreset(index)
            })
        case .customHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: urgramText(presentationData, "Custom Color", "لون مخصص"), sectionId: self.section)
        case let .hue(value):
            return UrgramStudioSliderItem(systemStyle: .glass, theme: presentationData.theme, title: urgramText(presentationData, "Hue", "الدرجة"), value: value, sectionId: self.section, updated: { newValue in
                arguments.updateComponent(.hue, newValue)
            })
        case let .saturation(value):
            return UrgramStudioSliderItem(systemStyle: .glass, theme: presentationData.theme, title: urgramText(presentationData, "Saturation", "التشبع"), value: value, sectionId: self.section, updated: { newValue in
                arguments.updateComponent(.saturation, newValue)
            })
        case let .brightness(value):
            return UrgramStudioSliderItem(systemStyle: .glass, theme: presentationData.theme, title: urgramText(presentationData, "Brightness", "السطوع"), value: value, sectionId: self.section, updated: { newValue in
                arguments.updateComponent(.brightness, newValue)
            })
        case .customFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(urgramText(presentationData, "Changes update the Studio preview behind this screen live.", "التغييرات تُحدّث معاينة الاستوديو خلف هذه الشاشة مباشرة.")), sectionId: self.section)
        }
    }
}

private struct UrgramStudioHSB {
    var hue: CGFloat
    var saturation: CGFloat
    var brightness: CGFloat
}

public func urgramStudioColorController(context: AccountContext, title: String, initialColor: UInt32, updated: @escaping (UInt32) -> Void) -> ViewController {
    var dismissImpl: (() -> Void)?

    let colorPromise = ValuePromise<UInt32>(initialColor, ignoreRepeated: true)
    let initialUIColor = UIColor(argb: initialColor)
    var initialHue: CGFloat = 0.58
    var initialSaturation: CGFloat = 0.75
    var initialBrightness: CGFloat = 0.93
    initialUIColor.getHue(&initialHue, saturation: &initialSaturation, brightness: &initialBrightness, alpha: nil)
    let hsbValue = Atomic<UrgramStudioHSB>(value: UrgramStudioHSB(hue: initialHue, saturation: initialSaturation, brightness: initialBrightness))

    let arguments = UrgramStudioColorControllerArguments(
        selectPreset: { index in
            let color = urgramStudioPalette[index].argb
            var hue: CGFloat = 0.0
            var saturation: CGFloat = 0.0
            var brightness: CGFloat = 0.0
            UIColor(argb: color).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
            let _ = hsbValue.swap(UrgramStudioHSB(hue: hue, saturation: saturation, brightness: brightness))
            colorPromise.set(color)
            updated(color)
            dismissImpl?()
        },
        updateComponent: { component, value in
            var hsb = hsbValue.with { $0 }
            switch component {
            case .hue:
                hsb.hue = value
            case .saturation:
                hsb.saturation = value
            case .brightness:
                hsb.brightness = value
            }
            let _ = hsbValue.swap(hsb)
            let color = UIColor(hue: hsb.hue, saturation: hsb.saturation, brightness: hsb.brightness, alpha: 1.0).argb
            colorPromise.set(color)
            updated(color)
        }
    )

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        colorPromise.get()
    )
    |> deliverOnMainQueue
    |> map { presentationData, color -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var presentationData = presentationData
        let updatedTheme = presentationData.theme.withModalBlocksBackground()
        presentationData = presentationData.withUpdated(theme: updatedTheme)

        let hsb = hsbValue.with { $0 }
        var entries: [UrgramStudioColorControllerEntry] = []
        entries.append(.currentHeader)
        entries.append(.currentSwatch(color))
        entries.append(.presetsHeader)
        for index in urgramStudioPalette.indices {
            entries.append(.preset(index))
        }
        entries.append(.customHeader)
        entries.append(.hue(hsb.hue))
        entries.append(.saturation(hsb.saturation))
        entries.append(.brightness(hsb.brightness))
        entries.append(.customFooter)

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true)

        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    dismissImpl = { [weak controller] in
        controller?.dismiss()
    }
    return controller
}
