import Foundation
import UIKit
import UniformTypeIdentifiers
import Display
import AsyncDisplayKit
import SwiftSignalKit
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
        return updated
    }).startStandalone()

    UrgramSettingsStore.shared.update { settings in
        settings.studioActiveDesignId = nil
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

    init(context: AccountContext, updateDraft: @escaping ((inout UrgramThemeDesign) -> Void) -> Void, openColorEditor: @escaping (UrgramStudioColorTarget) -> Void, applyDraft: @escaping () -> Void, saveDraft: @escaping () -> Void, resetAppearance: @escaping () -> Void, designAction: @escaping (UrgramThemeDesign) -> Void, importDesign: @escaping () -> Void) {
        self.context = context
        self.updateDraft = updateDraft
        self.openColorEditor = openColorEditor
        self.applyDraft = applyDraft
        self.saveDraft = saveDraft
        self.resetAppearance = resetAppearance
        self.designAction = designAction
        self.importDesign = importDesign
    }
}

private enum UrgramStudioSection: Int32 {
    case preview
    case colors
    case actions
    case designs
}

private enum UrgramStudioControllerEntry: ItemListNodeEntry {
    case previewHeader
    case chatPreview(PresentationTheme, TelegramWallpaper, PresentationChatBubbleCorners, PresentationFontSize, PresentationStrings, PresentationDateTimeFormat, PresentationPersonNameOrder, [ChatPreviewMessageItem])
    case chatListPreview(PresentationTheme, String, String)
    case previewFooter

    case colorsHeader
    case accent(UInt32)
    case bubbleDerived(Bool)
    case bubbleColor1(UInt32)
    case bubbleGradient(Bool)
    case bubbleColor2(UInt32)
    case wallpaperDefault(Bool)
    case wallpaperSolid(Bool)
    case wallpaperGradient(Bool)
    case wallpaperColorA(UInt32, Int32)
    case wallpaperColorB(UInt32)
    case radius(Int32)

    case applyAction
    case saveAction
    case resetAction

    case designsHeader
    case importAction
    case designsEmptyFooter
    case design(UrgramThemeDesign, Bool, Int)

    var section: ItemListSectionId {
        switch self {
        case .previewHeader, .chatPreview, .chatListPreview, .previewFooter:
            return UrgramStudioSection.preview.rawValue
        case .colorsHeader, .accent, .bubbleDerived, .bubbleColor1, .bubbleGradient, .bubbleColor2, .wallpaperDefault, .wallpaperSolid, .wallpaperGradient, .wallpaperColorA, .wallpaperColorB, .radius:
            return UrgramStudioSection.colors.rawValue
        case .applyAction, .saveAction, .resetAction:
            return UrgramStudioSection.actions.rawValue
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
        case .colorsHeader: return 10
        case .accent: return 11
        case .bubbleDerived: return 12
        case .bubbleColor1: return 13
        case .bubbleGradient: return 14
        case .bubbleColor2: return 15
        case .wallpaperDefault: return 16
        case .wallpaperSolid: return 17
        case .wallpaperGradient: return 18
        case .wallpaperColorA: return 19
        case .wallpaperColorB: return 20
        case .radius: return 21
        case .applyAction: return 30
        case .saveAction: return 31
        case .resetAction: return 32
        case .designsHeader: return 40
        case .importAction: return 41
        case .designsEmptyFooter: return 42
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
        case .colorsHeader:
            if case .colorsHeader = rhs { return true } else { return false }
        case let .accent(lhsValue):
            if case let .accent(rhsValue) = rhs, lhsValue == rhsValue { return true } else { return false }
        case let .bubbleDerived(lhsValue):
            if case let .bubbleDerived(rhsValue) = rhs, lhsValue == rhsValue { return true } else { return false }
        case let .bubbleColor1(lhsValue):
            if case let .bubbleColor1(rhsValue) = rhs, lhsValue == rhsValue { return true } else { return false }
        case let .bubbleGradient(lhsValue):
            if case let .bubbleGradient(rhsValue) = rhs, lhsValue == rhsValue { return true } else { return false }
        case let .bubbleColor2(lhsValue):
            if case let .bubbleColor2(rhsValue) = rhs, lhsValue == rhsValue { return true } else { return false }
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
        case let .radius(lhsValue):
            if case let .radius(rhsValue) = rhs, lhsValue == rhsValue { return true } else { return false }
        case .applyAction:
            if case .applyAction = rhs { return true } else { return false }
        case .saveAction:
            if case .saveAction = rhs { return true } else { return false }
        case .resetAction:
            if case .resetAction = rhs { return true } else { return false }
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
        case .colorsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: urgramText(presentationData, "Colors and Bubbles", "الألوان والفقاعات"), sectionId: self.section)
        case let .accent(value):
            return ItemListDisclosureItem(presentationData: presentationData, title: urgramText(presentationData, "Accent Color", "لون التمييز"), label: urgramStudioHexString(value), sectionId: self.section, style: .blocks, action: {
                arguments.openColorEditor(.accent)
            })
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

private func urgramStudioControllerEntries(presentationData: PresentationData, settings: UrgramSettings, draft: UrgramStudioDraft) -> [UrgramStudioControllerEntry] {
    let parameters = draft.parameters
    let isArabic = presentationData.strings.primaryComponent.languageCode.hasPrefix("ar")

    let draftWallpaper = urgramStudioWallpaper(for: parameters)
    let previewTheme = customizePresentationTheme(presentationData.theme, editing: false, accentColor: UIColor(argb: parameters.accentColor), outgoingAccentColor: nil, backgroundColors: [], bubbleColors: parameters.bubbleColors.map { $0 & 0x00ffffff }, animateBubbleColors: nil, wallpaper: draftWallpaper, baseColor: .custom)
    let previewCorners = PresentationChatBubbleCorners(mainRadius: CGFloat(parameters.bubbleRadius), auxiliaryRadius: CGFloat(parameters.bubbleRadius / 2), mergeBubbleCorners: presentationData.chatBubbleCorners.mergeBubbleCorners, hasTails: presentationData.chatBubbleCorners.hasTails, bubbleMode: presentationData.chatBubbleCorners.bubbleMode, serifMessageText: presentationData.chatBubbleCorners.serifMessageText)
    let previewWallpaper = draftWallpaper ?? presentationData.chatWallpaper

    var entries: [UrgramStudioControllerEntry] = []

    entries.append(.previewHeader)
    entries.append(.chatPreview(previewTheme, previewWallpaper, previewCorners, presentationData.chatFontSize, presentationData.strings, presentationData.dateTimeFormat, presentationData.nameDisplayOrder, [
        ChatPreviewMessageItem(outgoing: false, reply: (presentationData.strings.Appearance_PreviewReplyAuthor, presentationData.strings.Appearance_PreviewReplyText), text: presentationData.strings.Appearance_PreviewIncomingText, nameColor: .preset(.blue), backgroundEmojiId: nil),
        ChatPreviewMessageItem(outgoing: true, reply: nil, text: presentationData.strings.Appearance_PreviewOutgoingText, nameColor: .preset(.blue), backgroundEmojiId: nil)
    ]))
    entries.append(.chatListPreview(previewTheme, isArabic ? "أورغرام" : "Urgram", isArabic ? "جرّب تصميمك الجديد 🎨" : "Try your new design 🎨"))
    entries.append(.previewFooter)

    entries.append(.colorsHeader)
    entries.append(.accent(parameters.accentColor))
    entries.append(.bubbleDerived(parameters.bubbleColors.isEmpty))
    if !parameters.bubbleColors.isEmpty {
        entries.append(.bubbleColor1(parameters.bubbleColors[0]))
        entries.append(.bubbleGradient(parameters.bubbleColors.count > 1))
        if parameters.bubbleColors.count > 1 {
            entries.append(.bubbleColor2(parameters.bubbleColors[1]))
        }
    }
    entries.append(.wallpaperDefault(parameters.wallpaperMode == 0))
    entries.append(.wallpaperSolid(parameters.wallpaperMode == 1))
    entries.append(.wallpaperGradient(parameters.wallpaperMode == 2))
    if parameters.wallpaperMode == 1 {
        entries.append(.wallpaperColorA(parameters.wallpaperColorA, parameters.wallpaperMode))
    } else if parameters.wallpaperMode == 2 {
        entries.append(.wallpaperColorA(parameters.wallpaperColorA, parameters.wallpaperMode))
        entries.append(.wallpaperColorB(parameters.wallpaperColorB))
    }
    entries.append(.radius(parameters.bubbleRadius))

    entries.append(.applyAction)
    entries.append(.saveAction)
    entries.append(.resetAction)

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
        }
    )

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        UrgramSettingsStore.shared.settingsSignal,
        draftPromise.get()
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings, draft -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var chromePresentationData = presentationData
        let updatedTheme = presentationData.theme.withModalBlocksBackground()
        chromePresentationData = presentationData.withUpdated(theme: updatedTheme)

        let isArabic = presentationData.strings.primaryComponent.languageCode.hasPrefix("ar")
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(chromePresentationData), title: .text(isArabic ? "استوديو أورغرام" : "Urgram Studio"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(chromePresentationData), entries: urgramStudioControllerEntries(presentationData: presentationData, settings: settings, draft: draft), style: .blocks, animateChanges: true)

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
