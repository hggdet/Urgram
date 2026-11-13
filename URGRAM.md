# Urgram

Urgram is an unofficial Telegram client for iOS, built from the official
open-source Telegram-iOS code (GPL) with its own identity and an extended
feature set. It is **not** affiliated with or endorsed by Telegram.

- Display name: **Urgram** (أورغرام)
- Bundle ID: `com.hggdet.urgram`
- API credentials: the project owner's own api_id/api_hash from
  my.telegram.org, injected at build time via CI secrets (never committed).

## Features

See [FEATURES.md](FEATURES.md) for the full approved feature list
(34 features: ghost mode, anti-delete/anti-edit, restricted-content saving,
hidden chats, streamer mode, bulk downloads, on-device voice-to-text, and more).

## Building

Built on GitHub Actions (public repo) following Telegram's own compilation
guide: `build-system/Make/Make.py build` with a Urgram configuration and
codesigning data generated from Telegram's `fake-codesigning` templates by
`build-system/urgram/generate_codesigning.py`. The resulting IPA is
unsigned/fake-signed and is meant to be re-signed with your own certificate.

## Credits & licence

- Upstream: [Telegram-iOS](https://github.com/TelegramMessenger/Telegram-iOS)
  by Telegram Messenger LLP — GPL. This fork publishes its code in compliance
  with the licence, as required.
- Urgram identity, icons and feature work: Abdulbasit Khudair (ابو العبد).

## Fork patches (Urgram vs upstream Telegram-iOS 13.2)
- **Display/reservedRegions (2026-11-12):** `UIView.reservedRegions` needs the iOS 27.1 SDK (Xcode 27); CI runners top out at Xcode 26.6 (SDK 26.5), so the two call sites in `submodules/Display/Source/ReservedArea.swift` (`activeOcclusionFrames`) and `WindowContent.swift` (`activeDivision`) could not compile even inside `#available`. Patched to return the documented pre-27.1 fallbacks (`[]` / `nil`) — iPhone Duo foldable-only paths, inert on all current devices. Revert when CI moves to Xcode 27.

- **ShareScreen SIL crash (2026-11-12):** Xcode 26.6 swiftc crashes (Exit 6, OSSACompleteLifetime) on `ShareScreen.init`; added `-disable-sil-ownership-verifier` to that module\u2019s `copts` only (the compiler\u2019s own suggested workaround). Revisit on a newer Xcode.

## Fork patch: app-group fallback + English name + user icon (2026-11-12)
- On-device verdict for build 7: app hung on a black screen after re-signing with the user's certificate. Root cause (source-verified): AppDelegate builds the shared container name as "group." + the RUNTIME bundle id; after re-signing the bundle id becomes the profile's fixed app ID, whose entitled groups are the profile's generic ones, so containerURL returns nil and startup stops ("Error 2" path). Patch: `effectiveAppGroupName` probes the preferred group and falls back to the first application-group parsed from the embedded provisioning profile. Applied at both AppDelegate sites (startup + background URL sessions).
- Display name: ar.lproj CFBundleDisplayName changed from «أورغرام» to "Urgram" (user wants the English name on his Arabic device).
- Primary icon: the Bazel build uses the Icon Composer file Telegram.icon (Telegram's layered blue icon); the PNG DefaultAppIcon set is commented out in BUILD resources, so build 7 showed Telegram's icon. Telegram.icon is now a single full-bleed image layer using the user's own icon (Assets/UrgramIcon.png).

## Fork patch: app-group fallback v2 + sandbox container + base name/scheme (2026-11-12, build 9)
- On-device verdict for build 8: STILL a black screen (no alert, app stays open). The v1 fallback returned the first embedded-profile group WITHOUT checking that its container resolves — if the re-signing did not entitle that group (or no profile is embedded), the startup guard still failed. v2 changes:
  - `embeddedProfileAppGroups()` parses the profile's application-groups once; `effectiveAppGroupName` now returns the first profile group whose `containerURL` is non-nil (i.e. the build is actually entitled to it).
  - At the startup guard: if NO app-group container is available at all, fall back to a private `UrgramSharedContainer` directory inside the app's Application Support folder and continue startup instead of stalling on the "Error 2" black screen. Data then lives in the app sandbox (extensions are removed in the user's signing flow anyway).
- Base name/scheme: the real sources are the INLINE `plist_fragment` templates in `Telegram/BUILD` (`TelegramInfoPlist`, `AppNameInfoPlist`, `UrlTypesInfoPlist`) — the earlier fix edited Info.plist/InfoBazel.plist, which the Bazel app target does not use. Templates now set CFBundleDisplayName/CFBundleName to "Urgram" and the primary URL scheme to "urgram" ("telegram" kept in the compatibility list).
- Verification: the screenshots workflow now reproduces the user's re-signing geometry in the simulator (foreign fixed bundle id + only generic profile groups entitled + embedded profile, plus a no-profile worst case) and screenshots each launch.

## Build 10 — features wave 1 (2026-11-12)

Implements the approved list in `FEATURES-FINAL.md` (34 items; the two AI
items 13/34 were deleted by the owner and are skipped entirely; item 5 uses
regular translation engines only — no AI key). Placement rule honoured: every
feature control lives in ONE dedicated **Urgram** section inside Settings
(Settings list → "Urgram" row → one ItemList screen with grouped toggles).
All fork changes carry a `// URGRAM` marker. Nothing here was compiled on the
development machine (no Xcode/Bazel on Linux); the first CI build is the real
check. Per-item status below is exact: **implemented** / **partial** /
**documented, not wired** (with the reason).

### Foundation

- **Settings model + store** — `submodules/TelegramUIPreferences/Sources/UrgramSettings.swift`:
  one Codable struct with a field per toggle, persisted through AccountManager
  shared data under `ApplicationSpecificSharedDataKeys.urgramSettings`
  (new key value 24 in `PostboxKeys.swift`) — the same mechanism as
  TranslationSettings/ExperimentalUISettings. `UrgramSettingsStore.shared`
  keeps a synchronous in-memory value for UI readers and mirrors the flags
  TelegramCore needs into `UrgramFeatureHooks` (TelegramCore cannot import
  TelegramUIPreferences). Seeded/synced at launch from
  `TelegramUI/Sources/SharedAccountContext.swift` (dedicated shared-data
  subscription), which also pushes the resolved font family into Display and
  the HD-photo default into the legacy picker's defaults key.
- **Core hooks bridge** — `submodules/TelegramCore/Sources/State/UrgramFeatureHooks.swift`:
  plain static Bools (default false): ghost ×4, hideSponsored,
  saveRestrictedBypass, keepDeletedMessages, secretChatScreenshotSilent.
- **Settings screen** — `submodules/SettingsUI/Sources/UrgramSettingsController.swift`
  (ItemList, modelled on ArchiveSettingsController): sections Ghost Mode /
  Privacy / Content / Chats / Media and Downloads / Calls / Translation /
  Font (disclosure) / Network (disclosure) / Actions. Injected via a new
  `.urgram` case in all three PeerInfo settings enums + a disclosure row in
  the main Settings list (`PeerInfoScreen.swift`, `PeerInfoSettingsItems.swift`,
  `PeerInfoScreenSettingsActions.swift`). Icon is a placeholder
  (`PresentationResourcesSettings.appearance`) — no Urgram asset exists yet.
  Strings are English; localization comes later.

### Per-item status (FEATURES-FINAL numbering)

- **1 Ghost mode — implemented.** Gates in TelegramCore, all keyed on
  `UrgramFeatureHooks`: read receipts (`State/SynchronizePeerReadState.swift`
  `pushPeerReadState` returns the local state without the network request —
  covers messages/channels readHistory and secret-chat readEncryptedHistory);
  voice/video "listened/viewed" receipts
  (`State/ManagedSynchronizeConsumeMessageContentsOperations.swift` returns
  `.complete()`; the operation-log entry is still cleared by the caller);
  typing/recording indicators (`State/ManagedLocalInputActivities.swift`
  returns `.complete()` before `messages.setTyping`); online status
  (`State/ManagedAccountPresence.swift` forces offline in `updatePresence` —
  takes effect at the next presence change, it does not retroactively hide a
  live session); story views (`State/ManagedSynchronizeViewStoriesOperations.swift`
  `pushStoriesAreSeen` returns `.complete()`). The stop-typing draft call in
  TypingDraftStop.swift was deliberately left alone.
- **2 Save restricted content — implemented (message level).**
  `ApiUtils/StoreMessage_Telegram.swift`: both `(flags & (1 << 26))` sites
  insert `.CopyProtected` only when the toggle is off, so with it on, media
  arrives without the protection flag and save/forward/copy work across the
  message UI. Caveats: messages already stored keep their old flag until
  re-stored; the chat-level `associatedData.isCopyProtectionEnabled` still
  gates a few surfaces (e.g. capture protection); view-once media has no
  dedicated save affordance (with ghost-read on it is never reported and the
  file stays in the local media cache).
- **3 Anti-delete / anti-edit — partial (deletes only).**
  `TelegramEngine/Messages/UrgramMessageArchive.swift`: deleted messages are
  captured (text + metadata, cap 1000, FIFO) in ONE per-account preferences
  entry (core-local key 100) at the top of `_internal_deleteMessages`
  (`TelegramEngine/Messages/DeleteMessages.swift`) — the funnel used by state
  replay, so remote deletes, autoremove/TTL and own delete-for-everyone are
  all archived. **Edits are NOT captured**: general edits flow as
  StoreMessages through the merged-state replay, which is pinned by
  Tests/StateSync and the state invariants in `State/CLAUDE.md` — no safe
  single choke point exists. **No archive viewer screen yet** (read API:
  `urgramArchivedMessages(transaction:)`); the `keepEditedMessages` toggle
  exists in settings but currently has no consumer.
- **4 Proxies — implemented (import + entry point).**
  `SettingsUI/Sources/UrgramProxySettingsController.swift`: saved-server
  count, bulk import of `t.me/proxy` / `tg://proxy` links (hex or base64url
  secrets, dedupe, appended via `updateProxySettingsInteractively`), and a
  row into Telegram's own proxy screen, which already shows per-server live
  status/ping. Not done: auto-switch on failure (no upstream support) and a
  bundled curated server list (deliberately — unverified public proxies rot
  and can be malicious; users import from channels they trust).
- **5 Translation — toggle wiring implemented.** The Urgram "Translate Whole
  Chats" switch drives Telegram's own TranslationSettings
  (`showTranslate` + `translateChats`); message and whole-chat translation
  already exist upstream (`TelegramEngine/Messages/Translate.swift`, Google/
  Telegram engines — no AI key, per the owner's decision). **Outgoing
  long-press-send translation is NOT wired** (needs send-button long-press
  surgery in the chat controller); its toggle exists but has no consumer yet.
- **6 Voice-to-text — documented, not wired.** In-tree transcription is
  server-side only (`TelegramEngine/Messages/Transcription.swift`,
  Premium/trial-gated). There is no on-device (SFSpeechRecognizer) pipeline
  in the tree; building one blind is a new subsystem, not a patch.
- **7 Accounts — cap removed; session backup not done.** The add-account
  limit (3, or 4 with Premium) is raised to 100 in
  `PeerInfoScreenSettingsActions.swift`, making the Premium upsell branch
  unreachable. **SMS-free session backup/restore is NOT implemented**:
  exporting auth sessions is credential export (keys live in each account's
  Postbox + keychain) and needs its own security design and review.
- **8 Hide sponsored — implemented (in-chat).**
  `TelegramEngine/Messages/AdMessages.swift`: `AdMessagesHistoryContextImpl.activate()`
  returns early when on, so sponsored messages are never fetched. Caveats: a
  previously cached sponsored state (≤5 min) can surface once; the separate
  chat-list/search promo surface (ChatListUI promoInfo) is not covered.
- **9 Hidden chats + decoy passcode — documented, not wired.** Chat-list
  contents are Postbox-view-driven; filtering peers out safely (counts,
  search, notifications, badges) cannot be done blind without corrupting
  list state. Identified pieces for a future build: PasscodeUI for the
  decoy code, a hidden-peer set in UrgramSettings, filtering at
  ChatListController's view application point.
- **10 Keyword filters — documented, not wired.** Toggle + keyword list are
  stored in UrgramSettings. Candidate consumption point: item transformation
  in ChatHistoryListNode; chat-list keyword hiding was judged too invasive
  for this pass.
- **11 Download manager / bulk channel download — documented, not wired.**
  Upstream already has download surfaces and shared-media multi-select save.
  `downloadBoost` toggle exists with no consumer (parallel-connection tuning
  lives deep in the media box/network layer).
- **12 Chat-list utilities — partial.** "Mark All Chats as Read" action is
  implemented on the Urgram screen (`engine.messages.markAllChatsAsRead()`).
  Folders-at-bottom: upstream's `foldersTabAtBottom` experimental flag has
  NO consumers in 13.2 (folders render in the chat-list header) — toggle
  exists, nothing to flip. Settings search integration not done
  (SettingsSearchableItems.swift is a ~4600-line id↔title map).
- **14 Contact notes — covered by upstream, no code.** Telegram 13.2 already
  syncs a per-user note (`CachedUserData.note`, shown/edited in PeerInfo).
  Difference: upstream's note is server-synced, not local-only.
- **15 Bookmarks with categories — documented, not wired.** Design: a
  preferences entry like the item-3 archive; entry point = message context
  menu (`ChatInterfaceStateContextMenus.swift`); viewer = an ItemList
  screen. Not built in this pass.
- **16 Streamer mode — documented, not wired.** Toggle exists. Design:
  observe `UIScreen.capturedDidChangeNotification` in SharedAccountContext
  and gate chat-list titles / profile headers while capturing. Not built —
  the gating points are spread across ChatListUI and PeerInfo rendering.
- **17 Calls — half.** Force TCP is wired: the Urgram switch mirrors into
  `ExperimentalUISettings.enableVoipTcp`, the flag the call stack reads.
  Call confirmation is NOT wired: outgoing calls funnel through
  PresentationCallManager with several creation sites and no single small
  gate was found; toggle exists with no consumer.
- **18 Forward without attribution / repeat message — documented, not
  wired.** Hook points identified: engine `ForwardMessages` and the forward
  action in `ChatInterfaceStateContextMenus.swift`. Not built.
- **19 Peek chat without reading — covered.** Upstream chat-list peek
  (long-press preview) does not mark read, and ghost mode (item 1) covers
  opening chats without receipts.
- **20 Stories — implemented (bar hiding).** `ChatListUI/Sources/ChatListController.swift`:
  when `hideStoriesBar` or `disableStories` is on, the story-subscriptions
  update feeds the header an empty list (no items, no own-story avatar), so
  the stories bar never appears. The change applies when subscription data
  next updates (or the list is recreated). `disableStories` currently does
  the same as hiding the bar — stories can still be opened from avatars
  inside chats; full story blocking is not wired.
- **21 HD photos by default — implemented.** The media picker's HD default
  is the legacy defaults key `TG_photoHighQuality_v0`
  (TGMediaAssetsController). The Urgram switch writes it (on toggle, and
  re-asserted from the SharedAccountContext settings sync). Last writer
  wins if the user flips the picker's own HD button afterwards.
- **22 Font — implemented.** Built-ins ship in
  `Telegram/Telegram-iOS/Resources/UrgramFonts/` (Tajawal Regular/Medium/Bold,
  Cairo variable, IBM Plex Sans Arabic Regular/Bold + OFL licence files),
  picked up by the existing AppResources glob — no BUILD edit.
  `TelegramUIPreferences/Sources/UrgramFontManager.swift` registers fonts
  with CoreText (process scope), imports user .ttf/.otf files into
  Application Support/UrgramFonts (security-scoped copy), and resolves the
  active family. `Display/Source/Font.swift`: `Font.urgramCustomFamilyName`
  + face-matching helper; the plain `regular/medium/semibold/bold`
  factories route through it with system-font fallback. Picker screen:
  `SettingsUI/Sources/UrgramFontSettingsController.swift` (built-ins +
  import via UIDocumentPickerViewController). Limitations: the
  `Font.with(...)` design/traits path is not hooked, and the choice applies
  to screens opened after the change (full apply needs a restart — stated
  in the picker footer).
- **23 Account ID / registration date / DC — documented, not wired.** Own
  and peer IDs exist locally (`peer.id`), and the current DC is in the
  network layer, but neither is surfaced on profiles upstream; registration
  date is not stored by Telegram at all (only third-party approximations
  from ID age). No UI added in this pass.
- **24 Secret-chat & media extras — partial.** Screenshot-without-notification
  in secret chats is implemented:
  `SecretChats/SetSecretChatMessageAutoremoveTimeoutInteractively.swift`
  `_internal_addSecretChatMessageScreenshot` returns `.complete()` when on
  (the cloud-chat `messages.sendScreenshotNotification` paths in
  PendingMessageManager/StandaloneSendMessage are a separate surface, not
  gated). Voice-message noise suppression NOT wired (recorder-side DSP).
  Bulk delete of own messages NOT wired as UI; the engine primitive
  (`_internal_deleteAllMessagesWithAuthor`) exists.
- **25 Force/partial copy — covered by item 2.** Dropping `.CopyProtected`
  at store time re-enables text selection and copy for protected messages
  (selection nodes gate on the same flag). Chat-level copy-protection
  (associatedData) still blocks a few nodes — see item 2 caveats.
- **26 Combine messages / undo-redo — documented, not wired.** The 13.2
  chat input is a new native rich editor (lists/code/quotes make Enter and
  edit semantics structural); merging outgoing messages would need a
  send-pipeline transform in ChatSendMessageActionUI. Not attempted blind.
- **27 Double-tap to edit own messages — implemented.**
  `ChatMessageBubbleItemNode.swift` gesture fallback: with the toggle on,
  double-tapping your own message calls
  `controllerInteraction.setupEditMessage(...)` instead of the default quick
  reaction. Coverage: the fallback double-tap path (messages without a more
  specific bubble action); media-specific double-tap actions are unchanged.
  Editability (time limit) is enforced by the edit flow itself.
  **Build 11 fix (2026-11-13):** `setupEditMessage` does not exist on
  `ChatControllerInteraction` — it lives on `ChatPanelInterfaceInteraction`.
  Added a `setupEditMessage` closure to `ChatControllerInteraction`
  (default no-op, so preview/other controllers keep compiling) and wired
  it in `ChatController` to `interfaceInteraction?.setupEditMessage(...)`.
  The bubble-node call site is unchanged.
  **Build 13 fix:** Swift requires call-site argument order to match the
  init declaration — the closure had to sit after
  `toggleMessageRichTextCheckbox` in `ChatController` too.
  **Build 15 (2026-11-13) — Arabic UI + font-import picker fix.** On-device
  verdict for build 14: features work, but (a) the whole Urgram section
  was English-only and (b) font import showed files greyed out. Fixes:
  all Urgram screens (settings, font, proxies incl. the import alert) are
  now bilingual via `urgramText(...)` in UrgramSettingsController.swift —
  Arabic when the app language is Arabic, English otherwise (Telegram's
  generated string tables carry no fork keys; font family names stay
  Latin). The font picker no longer filters by ttf/otf UTTypes (a
  sideloaded app declares none, so iOS 27 greys the files out); it opens
  all files and `UrgramFontManager.importFont` validates the pick.
  **Build 16 (2026-11-13) — placement + intro rebrand.** At the user's
  order: the Urgram row in the main Settings list moved from after
  Advanced to directly under My Profile (`SettingsSection.urgram` now
  follows `.myProfile` in PeerInfoSettingsItems.swift) so people notice
  it. Intro page 1 rebranded per BRAND.md: en `Tour.Title1` "Telegram" →
  "Urgram", `Tour.Text1` → the approved tagline "Five thousand years of
  **messages**. One **Urgram**." (RMIntro reads the en bundle; the intro
  artwork animation itself is compiled OpenGL data and is unchanged.)
- **28 Auto-delete — covered by upstream.** Per-chat autoremove timers and
  a global auto-delete (Privacy → Auto-Delete Messages) already exist in
  13.2. Delete-all-my-messages: see item 24.
- **29 @all mention / auto-reply — documented, not wired.** Toggles and the
  auto-reply text are stored in UrgramSettings. @all needs member-list
  expansion at send time in the chat controller; auto-reply needs an
  incoming-message reactor in TelegramCore with loop safeguards. Both are
  subsystems, not patches; not attempted blind.
- **30 Hide phone in profile — implemented (edit screen).**
  `PeerInfoSettingsItems.swift` `settingsEditingItems`: your phone row is
  omitted when the toggle is on. The profile header's phone line is not
  gated. Block-secret-chat option: not present (no such upstream concept).
- **31 Send with Enter — documented, not wired.** Toggle exists. The 13.2
  input panel uses a native rich editor that bypasses the classic
  `shouldChangeTextIn` delegate (`ChatTextInputPanelNode.swift`); Enter is
  structural there (lists, code blocks, quotes), so intercepting it blind
  risks corrupting input behaviour.
- **32 Music lyrics — documented, not wired.** No lyrics source/API exists
  in the tree for arbitrary audio files.
- **33 Plugins — not implemented.** A plugin platform (runtime, API surface,
  sandboxing, distribution) is a project of its own, out of scope for a
  settings-and-hooks pass.
- **35 Apple Watch — infeasible in this tree.** There is no watch target in
  Telegram-iOS 13.2's build graph at all; nothing to extend.
- **36 Analytics / keyword monitoring / call recording — not implemented.**
  Chat statistics beyond upstream's built-in channel stats, keyword
  monitoring (see item 10), and call recording (also legally sensitive in
  many jurisdictions) were left out deliberately.

### Build 17 (2026-11-13) — second feature wave

Researched first (hook points verified in-tree), then wired:

- **Item 3 (edits) — WIRED.** `UrgramFeatureHooks.keepEditedMessages`
  (mirrored from settings) gates a capture in
  `StateReplay.applyEditMessage`: before the edit applies, the stored
  message's current text is snapshotted via
  `urgramArchiveEditBeforeUpdate` into a separate preferences store
  (key 101, cap 1,000). Equal-text arrivals (media-only edits, own edits
  already applied by RequestEditMessage) no-op. The archive viewer now
  has two sections: Deleted Messages / Originals Before Editing.
- **Item 15 Bookmarks — WIRED.** New "Bookmark" item in the message
  context menu (`ChatInterfaceStateContextMenus.swift`, after Translate)
  snapshots the message text via `urgramAddBookmark` (TelegramCore,
  `UrgramBookmarks.swift`, key 102, cap 500, re-bookmark replaces). New
  viewer `UrgramBookmarksController.swift`, linked from the Urgram
  settings Content section.
- **Item 17 (call confirmation) — WIRED for 1-to-1 calls.** Gate at the
  top of `AccountContext.requestCall` (the single funnel for chat-header
  and peer-info calls): when the toggle is on, a bilingual alert asks
  before `urgramPerformRequestCall` (the original body) runs. Group
  voice chats (`joinGroupCall`) are not gated.
- **Item 20 (Disable Stories, hard) — WIRED.** When on,
  `StoryContainerScreen.openPeerStoriesCustom` returns immediately, so
  stories cannot be opened from the chat list, chat avatars or peer
  info. Own archived stories (a separate entry point) still open.
- **Item 23 — completed.** The Urgram settings account row now also
  shows the datacenter (`context.account.masterDatacenterId`, e.g.
  "DC4"). Registration date remains unavailable from the client.
- **Item 31 Send with Enter — toggle REMOVED as redundant.** Verified
  in-tree: upstream already sends with Enter by default
  (`ChatSettings.sendWithCmdEnter` defaults to false; the user-facing
  inverse toggle lives in Appearance). A fork toggle that defaults off
  while the behaviour is on would have been a fake switch.

### Build 18 — fix for the build-17 compile failure (run 43387280835)

Build 17 compiled SettingsUI last and died on two real Swift errors:

- `Peer` / `PeerId` not in scope in `UrgramArchiveController.swift` and
  `UrgramBookmarksController.swift`: both live in Postbox, and SettingsUI
  had no Postbox dependency. Fix: `import Postbox` in both files,
  `"//submodules/Postbox:Postbox"` added to the SettingsUI `BUILD` deps,
  and both files added to `submodules/Postbox/AllowedImporters.txt`
  (the import allowlist — the `.postbox` allowlist already covered them
  since the build-16 fix). Verified locally: PostboxImportCheck exits 0.
- `Account` has no member `masterDatacenterId` (it exists only on
  `UnauthorizedAccount`): the account row now reads
  `Int32(context.account.network.datacenterId)`, the same pattern
  upstream uses in `Account.swift:91`.

The four cascade errors (`ItemGenerationArguments` inference) follow from
the unresolved types above and are expected to vanish with them.

**Build 18 failed before compilation** (run 43401099418, ~163 s): Bazel
visibility — the `Postbox` target is only visible to its `:clients`
package_group, which did not list `//submodules/SettingsUI`, so the new
dep failed analysis. Fixed in build 19 (commit 6c817fb7, run 43402858441)
by adding SettingsUI to the `clients` group in `submodules/Postbox/BUILD`.
The two build-17 Swift errors remain unverified until a build gets past
analysis.

Still documented-not-wired after this wave: 6 voice-to-text, 9 hidden
chats + decoy PIN, 10 keyword filters (storage exists; no honest
message-hiding hook verified yet), 11 download boost, 12b folders at
bottom, 16 streamer mode, 18 forward without attribution, 24b noise
suppression, 26 combine/undo-redo, 29 @all + auto-reply, 32 lyrics,
33 plugins.

### Verification honesty

No compile was run for any of this (Linux VM, no Xcode). What was done:
line-by-line self-review of every new/modified file; every non-obvious API
(ItemList item inits, ProxySettings/ProxyServerSettings, update*Interactively
helpers, PreferencesEntry, operation-log completion semantics, BUILD glob
coverage for the modules touched) was checked against an existing upstream
usage in the same tree. Remaining risk concentrates in: Swift type-checking
details the review could not execute, the ItemList entry plumbing, and the
font face-matching at runtime. The first CI build + simulator pass is the
real verification.

## Build 20 — Urgram Studio

A design studio inside the Urgram settings section ("Urgram Studio" /
«استوديو أورغرام», row under the Font section, label shows the active
design's name). The user designs the app's appearance with a LIVE preview,
saves named designs, shares a design as a `.urgramtheme` file and imports
designs shared by others (import applies in one tap).

### What was wired (all verified against the in-tree theme system)

Storage: `UrgramThemeDesign` (Codable, manual StringCodingKey pattern like
the rest of UrgramSettings) + `studioDesigns: [UrgramThemeDesign]` and
`studioActiveDesignId: String?` on `UrgramSettings`
(`TelegramUIPreferences/Sources/UrgramSettings.swift`). A design stores
ONLY parameters that map to real runtime theme fields: `accentColor`
(ARGB), `bubbleColors` (ARGB; empty = derive from accent, 1 = solid,
2 = gradient), `wallpaperMode` (0 theme default / 1 solid / 2 gradient) +
`wallpaperColorA/B`, `bubbleRadius`.

Apply path (`SettingsUI/Sources/UrgramStudioController.swift`,
`urgramStudioApplyDesign`): writes through
`updatePresentationThemeSettingsInteractively`, mirroring
ThemeSettingsController's accent-apply block — general theme reference
(cloud theme with settings → its builtin base), validity-checked with
`makePresentationTheme`, accent entry
`themeSpecificAccentColors[general.index]` (baseColor `.custom`,
index −1, wallpaper embedded via `withUpdatedWallpaper`), the
colored-index `themeSpecificChatWallpapers` entry for builtin themes
(without clobbering a photo/file wallpaper the user set), and
`chatBubbleSettings.mainRadius` (+ `auxiliaryRadius = mainRadius / 2`,
the BubbleSettingsController rule; other bubble settings preserved).
The presentation-data signal re-emits, so the whole app re-themes live,
no restart. Reset removes the accent/wallpaper entries for the current
theme and restores radius 16/8.

Preview: the real `ThemeSettingsChatPreviewItem` (actual Telegram bubble
rendering over the draft wallpaper) with the theme produced by
`customizePresentationTheme` from the draft (same function the upstream
accent editor previews with), plus a chat-list row item rendered from the
preview theme's real `chatList` colors (title / message / date / unread
badge / accent avatar), so the accent's effect on the chat list is visible.

Color editing: preset palette (swatches) + HSB sliders
(`UrgramStudioSliderItem`, adapted from ThemeSettingsBrightnessItem on
SliderComponent); `BubbleSettingsRadiusItem` is reused as-is for the
radius (upstream range 8–16 step 2; the stored radius still accepts
4–24 from imported designs and applies as-is).

Share/import: export encodes the design as JSON in a `<name>.urgramtheme`
file and offers it via UIActivityViewController (send it in any chat).
Import uses the Studio's document picker (unfiltered `.data`, same
build-15 rule as fonts — a sideloaded app declares no UTI for the type),
parses + sanitizes (fresh UUID, radius clamped 4–24, ≤2 bubble colors),
saves and applies immediately.

### Excluded, and why

- Incoming bubble color, message text colors: the accent mechanism never
  touches them; only full .attheme theme editing could, which is a
  different (heavyweight) system — out of scope.
- Chat-list and navigation/tab-bar BACKGROUND colors: they follow the
  base theme; the accent mechanism tints only their accents (tab bar
  selection, badges, checkmarks), which the Studio does control.
- "Glass intensity": no theme parameter exists (only the unrelated
  ExperimentalUISettings.fakeGlass bool).
- Chat-list density: no runtime parameter exists.
- "Open in Urgram" document-type registration for .urgramtheme: not
  cheap — it needs an Info.plist document type plus AppDelegate URL
  routing; the Studio's in-app document-picker import covers sharing.
- Applying a design while a cloud theme with settings is active switches
  the current theme to that theme's builtin base first — this is
  upstream's own accent-apply semantics, inherited deliberately.

## Build 20 — Clean Edition

The user's call (2026-11-13): ship a CLEAN edition — no privacy-bypass
features, everything shown must genuinely work — while the full edition's
code stays in the same tree behind an edition flag.

### Edition mechanics

- `UrgramEdition.isClean` (`TelegramCore/Sources/State/UrgramFeatureHooks.swift`)
  is a compile-time constant, `true` in this build.
- Gating is at the single mirroring point: `UrgramSettingsStore.mirrorToCoreHooks`
  forces every bypass hook to `false` in the clean edition, whatever a
  previously stored settings value says: ghostHideRead, ghostHideTyping,
  ghostHideOnline, ghostHideStoryViews, saveRestrictedBypass,
  keepDeletedMessages, keepEditedMessages, hideSponsored,
  secretChatScreenshotSilent. Non-bypass hooks (disableStories) mirror
  normally. No bypass code path or store was deleted.
- The Urgram settings screen omits, in clean mode: the whole Ghost Mode
  section; streamerMode + secret-chat-screenshot rows (hidePhoneInProfile
  stays); saveRestrictedBypass, keepDeletedMessages, keepEditedMessages,
  the archive row, hideSponsored, keywordFilters and the archive footer;
  and the stored-but-unwired dead toggles: streamerMode, keywordFilters,
  downloadBoost, voiceNoiseSuppression, mentionAll, autoReplyEnabled,
  foldersAtBottom, translateOutgoingLongPress (verified: zero consumers
  of translateOutgoingLongPress exist outside the settings files).
- Account cap: `PeerInfoScreenSettingsActions` .addAccount restores
  upstream's 3 / 4-with-Premium limits when clean (100 in the full edition).
- An "Edition: Clean" / «النسخة النظيفة» row shows at the bottom of the
  Urgram section when clean.
- Also fixed here (both editions): "Mark All Chats as Read" now calls
  `markAllChatsAsReadInteractively(items: [(groupId: .root, filterPredicate: nil)])`
  — the call Telegram's own UI uses; the old `markAllChatsAsRead()` only
  cleared chats the user had manually marked unread.

### New clean features

- **Message reminders — WIRED.** "Remind Me" / «ذكّرني» in the message
  context menu (next to Bookmark; secret chats excluded) → alert with
  1 hour / tomorrow / next week → `UNUserNotificationCenter` local
  notification. The userInfo deliberately carries the exact keys
  AppDelegate's stock tap handler parses (`accountId`/`peerId` as Int64
  with the peer id packed via `PeerId.toInt64()`,
  `messageId.namespace`/`messageId.id` as Int32, categoryIdentifier "c"),
  so a tap opens the chat AT the message via the unmodified
  `openChatWhenReady` path — message-level deep link, zero routing changes.
- **Quick-reply templates — WIRED.** Storage: `UrgramSettings.replyTemplates`.
  Management screen (Urgram section → "Quick Replies"): list, add via
  prompt, delete via action sheet (`UrgramTemplatesController.swift`).
  Use seam: new `AttachmentButtonType.urgramTemplates` (enum + key + ==
  in AttachmentUI, name/icon + accessibility in AttachmentPanel — label
  is the fork's bilingual string, icon reuses the TabNews animation),
  inserted into the attach menu next to .location whenever at least one
  template exists. Its handler presents `urgramTemplatePickerController`
  as a modal over the chat (a plain ItemListController, not an
  AttachmentContainable) and inserts the chosen text at the cursor via
  `interfaceInteraction.updateTextInputStateAndMode` — the same input-state
  transform the formatting shortcuts use.
- **Export chat to file — WIRED.** "Export to File (Urgram)" /
  «تصدير إلى ملف (أورغرام)» disclosure row in the peer-info screen
  (users, groups, channels; secret chats excluded by design). History is
  fetched through the engine's in-chat search
  (`engine.messages.searchMessages`, .peer location, empty query,
  newest-first pages continued via the returned SearchMessagesState,
  capped at the 1000 most recent messages), written as a .txt
  (date, author, text; media as [photo]/[video]/[audio]/[file]/[poll]/
  [service] placeholders) and shared via UIActivityViewController.
- **Auto-archive inactive chats — WIRED.** `UrgramSettings.autoArchiveInactiveDays`
  (0 = off) with an Off / 30 days / 90 days cycle row in the Urgram
  section. Engine: `urgramRunAutoArchiveIfNeeded` (TelegramUI) runs once
  per cold start from SharedAccountContext when the first account
  contexts become active, throttled to once per 24h (UserDefaults), and
  archives every non-pinned root-list peer whose latest message is older
  than the threshold — using the same
  `engine.peers.updatePeersGroupIdInteractively(peerIds:groupId: .archive)`
  the swipe/context-menu archive actions use. The account's own Saved
  Messages chat is never archived; the pass reads the root chat list via
  `engine.messages.chatList(group: .root, count: 1000)`, skipping the
  view's loading emission. Pinned detection: `ChatListIndex.pinningIndex`.
- **Folders at bottom — DROPPED.** The filter tab strip is laid out
  structurally inside ChatListContainerNode (stories header offsets,
  pinned-header fractions and list insets all derive from its top
  placement); moving it is a layout restructure, not a contained change,
  and this environment cannot do the simulator frame verification
  AGENTS.md requires for layout work. The toggle stays out of the clean
  UI (and remains, untouched, in the full edition).

### Verification

- `python3 build-system/Make/PostboxImportCheck.py` exits 0.
- No new `.postbox` use and no new `import Postbox` anywhere in this
  change (Postbox types named in the PeerInfo/TelegramUI targets follow
  those targets' existing visibility pattern — cf. `Namespaces.*` in
  PeerInfoScreen.swift / ChatInterfaceStateContextMenus.swift).
- Not verified here (needs CI + device, as with builds 14/19): compile
  of the new Swift (highest-risk surfaces: the attach-menu handler and
  the SharedAccountContext cold-start subscription), and the visual
  result of the new attach-menu button and settings rows.
