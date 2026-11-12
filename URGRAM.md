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
