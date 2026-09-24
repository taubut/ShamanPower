# ShamanPower Changelog

## v3.0.0 (unreleased)

### New
- **WoW: Forever support.** ShamanPower runs on the Forever beta from the same download as Anniversary. Where the game hides combat data from addons, the game itself draws the totem timers and countdown numbers, the party buff dots, the reactive and expiring alerts and the cooldown sweeps, so they keep working in combat. Spells that do not exist on Forever (Earth Shield, Bloodlust / Heroism, Drums of Battle, Totem of Wrath, Wrath of Air, the Elementals, Fire Nova Totem) are hidden everywhere: pages, previews, dropdowns, assignments, Auto-Assign. Forever characters start with the setup tour, which has a WoW: Forever step and a Totem Sets step.
- **Blizzard's totem bar as a style** (Forever). Settings > General > Totem Bar Style, or Mode & Twisting > Use Blizzard's Totem Bar: keep the game's own bar and get ShamanPower's timers, duration bars, text, pulse bars, party dots and counters on its slots, with an optional scale override. Picking a totem on Blizzard's bar sets your assignment, and the other way round.
- **Totem sets** (Forever). Call of the Elements always holds your assignments. Ancestors and Spirits can each take a saved loadout (Loadouts tab > Set Page); that loadout's bar button then casts the set in one press. Drop All can cast the set.
- **Grid style** (both clients). Every totem of every element visible in rows: click to drop, the assigned one highlighted, the timer on the dropped one. "Split by Element" makes each row its own movable frame with its own direction.
- **Totem Bar Style in one place.** Settings > General > Main has a dropdown with every style (Normal, TotemTimers, Dynamic, Compact, Grid, and Blizzard's bar on Forever). Hovering a style there, or a style toggle on Mode & Twisting, shows it in the live preview without changing anything. The setup tour shows the styles as cards with a picture each; hovering a card plays it in the preview.
- **Totem Coverage** (Party Buff Tracker, Forever). The reverse of Totem Range: under each of your totems, the names of party members who do NOT have its buff, red or class colour. Per-totem placement and sizes; choose which totems to watch; hides itself once everyone is covered, in combat too.
- **Minimap totem markers** (Forever, open world). A pin where each totem was dropped with a ring for its reach, turning with the minimap. Totem Range Tracker page. Off inside instances.
- **Auto-Assign picks by who is in the group.** Stoneskin for caster-only groups, Strength of Earth with melee; Mana Spring with mana users, else Healing Stream; the Air totem by who benefits. This changes what Anniversary players get from Auto-Assign too.
- **Live preview pane** in the settings window (arrow tab on the right): every module page shows its frames with your current settings, updating as you change them. The Loadouts page previews the bar and, on Forever, the three set pages.
- **Every window from its page.** Totem Range picker, Totem Coverage, Raid Cooldowns assignments, the fear-caster mob list, Totem Assignments: one button on the module's page, and every option those windows hold is on the page too. Test buttons hide the settings window while they run and bring it back after.
- **Ready Reminders** (new module). Placeable icons that light up when a spell comes off cooldown: shocks, Stormstrike, Lava Burst, Riptide, Rage of the Farseer, Nature's Swiftness, Mana Tide, Grounding, Earthbind and more. Show only when ready, always, or always dimmed with a countdown. On by default on Forever; **off by default on Anniversary** (Settings > Ready Reminders, or the setup tour, turns it on). On Forever each character keeps its own list, and the setup tour's spec pick fills it from Forever's talent tree.
- **Fonts** (both clients). Settings > General > Fonts & Textures: pick the font and outline for every number and label ShamanPower draws on screen, or give timers, shield charges, alerts and names their own. Uses WoW's fonts plus every font other addons share through LibSharedMedia (ElvUI, SharedMedia and the like). Hover a font in the list to preview it on your frames. Default keeps the designed look.
- **Bundled fonts and sounds.** Ten fonts (Barlow Condensed, Bebas Neue, Black Ops One, Chakra Petch, Fira Sans, Oxanium, Rajdhani, Russo One, Saira Semi Condensed, Teko; SIL Open Font License) and seven ShamanPower alert sounds (Totem Chime, Shield Pop, Ready Ping, War Horn, Water Drop, Earth Thud, Thunder) in every font and sound list, also for other addons that use LibSharedMedia.
- **Bar textures** (both clients). Settings > General > Fonts & Textures: pick the texture of every bar ShamanPower draws (totem duration bars, cooldown bar, pulse sweeps), or give each its own, from WoW's bar, ShamanPower's four and every texture other addons share. Hover to preview on your bars. **Apply This Look Everywhere** puts your chosen font, outline and texture on everything at once, Compact's lines included; **Reset Look** goes back to the designed look.
- **Mana tint** (option, Appearance > Textures & Colors): totem, flyout and cooldown buttons turn blue while you cannot afford them, like Blizzard's action bars. Colour of your choice.
- **Minimap quick menu:** right-click the minimap icon to switch totem bar style, apply a loadout, open assignments, Unlock UI, Fonts, What's New, the setup tour or settings. Shift-right-click opens settings straight away.
- **Loadout Auto-Switch** (Totem Bar > Auto-Switch, off by default). Pick a loadout for raids, dungeons, battlegrounds and the open world (or go back to the one you had when you leave an instance), and add rules like an equipment manager: loadout + zone + the mob you target (Blackwing Lair + Firemaw -> Fire Resist) or a boss encounter. Never switches in combat; a switch that comes up in a fight happens as soon as it ends. On Forever, target rules only work in the open world (the game hides mob names in instances).
- **Cooldown Announce** (Modules > Cooldown Announce, all off by default): announce Mana Tide (and Bloodlust / Heroism where they exist) when used and a set time before it is back, even in combat on Forever; answer "tide" and your own trigger words in group chat with ready / seconds left (throttled); optionally show the Mana Tide call on your own screen when a group member asks. Chat is never read or sent while the game has chat locked down.
- **Ready Check sweep** (both clients). On a ready check (optionally on entering a dungeon or raid, or with /sp check) ShamanPower lists what you are missing: shield, weapon imbue, totem items in your bags (Forever), assigned totems not down, low mana. Pick what it checks and how it shows it: an on-screen list with icons, a line in your chat window, a sound. On Forever it also warns when one of your totem items leaves your bags.
- **Keybind mode.** /sp bind, or Settings > General > Keybind Mode: every ShamanPower button that can take a key lights up with its current key. Hover one and press a key (Shift, Ctrl and Alt work) to bind it; Escape over a button clears its key. Done saves, Cancel puts every key back. Out of combat only.
- **Trainer Reminder** (Forever, Modules > Trainer Reminder). When you level up, ShamanPower lists the shaman spells and ranks now waiting at your trainer (and anything you skipped earlier), with one summary line at login. Only you see it; a big on-screen note is optional.
- **Fade rules** for the totem bar (Appearance > Visibility, off by default). With Hide Out of Combat or Hide When No Totems on, the bar can fade to an opacity you choose instead of disappearing, and can come back while you target something attackable. Fading is only a change of opacity, so it also works in combat.
- **Share My Setup** (General, /sp share, or the end of the setup tour): a short code listing which ShamanPower features you use - nothing personal - to paste in #setup-stats on the ShamanPower Discord, so the developer can see what people actually use. ShamanPower now also remembers how your setup ended (tour, quick setup, skipped).
- **Unlock UI (move everything).** One button (General > Main, or `/sp unlock`) shows a labelled box on every frame ShamanPower draws; drag them, reset any one, and snap to an optional alignment grid.
- **ShamanPower Discord** on General: help, bug reports, feature voting and early builds. Copy Link button.
- **Loadouts:** the bar has a Move button (Loadouts tab) and a box in Unlock All; a loadout's chosen icon shows on its button; the icon picker is rebuilt on the settings look with a search box.

### Changes
- Compact style has a new look and defaults; a Compact profile already in use keeps its old look.
- Element colour palettes, flyout sizes separate from the bar, and a reset for each settings section.
- Settings window: sizes and opacity show as percentages, long labels wrap instead of being cut off, inputs fit their values, and search highlights the right tab.
- **First login is a small choice, not the whole tour:** take the setup tour, or use Srumar's setup in one click (your spec is read from your talents, or asked when you have none yet). Other classes get the quick tour or Windfury-only mode. "Not now" asks again next login; the tour is always at /sp setup.
- The setup tour has spec cards listing what each pick sets up, a Ready Reminders step and a Position step that moves every frame. Picking a spec only sets starting defaults on a brand-new install.
- Non-shamans get a short tour and a settings list with only what runs for them (Totem Range, Raid Cooldowns, Totem Plates, the Earth Shield tracker, and the Windfury Companion on Anniversary). Tremor Reminder, Shield Charges, Ready Reminders, Expiring Alerts and Reactive Totems no longer load on other classes.
- **Windfury-only mode** for non-shamans: one button on their setup screen (or General > Windfury-Only Mode) turns off every window, bar, icon and nameplate, and keeps only the report that tells the group's shamans whether their weapon has Windfury. That report now runs whenever a shaman is in your party, even with the Totem Range overlay closed, and goes only to your own party (your subgroup in a raid), when it changes plus every 6 s, instead of to the whole raid every 2 s.
- What's New opens by itself once per release on a shaman; any character can open it from the settings header.
- Reactive Totems: the old configuration window is gone; everything is on its settings page. Optional debuff icon (Forever).
- A new setup starts with the totem bar in the middle of the screen and the cooldown bar right under it (beside it for a vertical bar); "Reset position" in Unlock UI puts it back there.
- A saved sound that no longer exists plays Raid Warning instead of nothing.
- The flyout keybindings are for Forever's click-to-open flyouts; on Anniversary they are labelled as such and do nothing.
- Totem cooldown numbers use the game's own countdown on Forever; ShamanPower turns the game option on for you.
- "Totemic Call" reads "Totemic Recall" where the game names it so.
- The Earth Shield column, tracker and options do not appear on a client without Earth Shield.
- Settings text says "ShamanPower's bar" and "Blizzard's bar" throughout.

### Fixes
- Party buff dots drawn by the game were never built on Forever; they are now.
- The loadout bar could not be moved from the settings, and the game's layout cache kept putting it back where an old drag left it.
- Idle CPU and garbage: loops now sleep until a totem, cooldown or aura actually changes, and party and shield buff checks are cached until the buffs change (both clients). On Forever the weapon-imbue and spell lookups, which build a new table per call there, are cached too.
- Newly trained totems appear in the flyouts without a reload; the cooldown bar keeps a custom order when a spell is unavailable.
- Expiring Alerts: "Totem Destroyed" now works in combat on Forever (from ShamanPower's own record of your totems, which the game cannot hide), and can also add a line to your own chat window (on by default, only you see it), show big text on your screen, or tell your group in chat.
- Tremor Reminder "Hide When Tremor Active" never hid in combat on Forever.
- Expiring Alerts: totems that died in combat were announced minutes later with stale timing on Forever.
- Wrath of Air, Totem of Wrath and Fire Nova Totem could be assigned, tracked or listed on a client that lacks them.
- Flametongue Totem's party buff did not match on Forever (spell 8215 is "Rapid Cast" there).

### Known
- Windfury Totem and Flametongue Totem party detection on Forever is unverified above the beta level cap.
- If the game blocks addon messages in an instance fight, Raid Cooldown callers are told so instead of shown "sent".
- Minimap totem markers are Forever only: the Anniversary minimap has no view-radius API, so the option is hidden there.

## v2.1.1 (2026-09-16)

### Fixes
- **Reactive Totems: "Hide when totem active" never worked for Tremor Totem.** The Tremor entry read the wrong totem slot, so the fear alert stayed up even with a Tremor Totem down. Poison and Disease Cleansing were unaffected

## v2.1.0 (2026-09-16)

### New
- **Compact totem bar style** (Settings > Mode & Twisting > Compact Style, and the setup tour's Totem Bar step). A fourth look for the totem bar: no icons, each element is a colored line that drains as the totem runs down and refills with every pulse. Stacked or side by side, any length and thickness, outline or fill for the duration, optional icon squares, pulse countdown text. Your Lightning / Water Shield can be a 3-segment charge line at the start of the bar and Earth Shield a charge line at the end, each with its own toggle. Clicks, flyouts, party dots, the range counter and keybinds work as before. Off until you turn it on
- **Only Show Learned Elements** (Settings > Totem Bar > Items, on by default). A new shaman's bar grows with them: nothing before the Earth quest, then Fire, Water and Air appear as each totem is learned, and the bar stays centered while it grows. Characters with all four totems see no change
- The what's-new card has a **Preview the Compact style** button: a live preview drawn with your own bar settings, with "Turn it on" to switch. /spwhatsnew preview opens it directly

### Fixes
- **Expiring Alerts: Earth and Fire totem alerts were swapped.** A lost Fire totem showed Earth's color and obeyed the Earth toggle, and vice versa; Water and Air were fine. If you had turned off Earth or Fire totem alerts to work around this, re-check those toggles
- **ShamanPower is back under Options > AddOns.** The entry had been silently missing since the 2.5.6 client removed the old registration call

## v2.0.7 (2026-09-16)

### Fixes
- **Earth Shield tracking survives a /reload and untargeted casts.** The Earth Shield button, the Shield Charges number and the ES Tracker only learned who carries your shield from a cast on your current target; a self-cast or a cast on an untargeted party member left them blank, and a /reload lost the tracking until the next cast. The cast target is now resolved through yourself, party and raid, and an Earth Shield already out is picked up at login

## v2.0.6 (2026-09-16)

### New
- **Lock All Pop-Out Trackers** (Settings > Pop-Out Trackers): while on, no pop-out can be dragged, including ALT-drag on the icon. Turn it off to rearrange them

### Fixes
- **Pop-out trackers no longer move on /reload.** Moving a pop-out with ALT-drag on its icon saved its position in a way that depended on the frame's width, and on reload it was restored before the frame had shrunk to icon size, so it landed a bit to the side every time. Scaled pop-outs had a second, smaller version of the same problem. Existing positions convert automatically

## v2.0.5 (2026-09-16)

### Fixes
- **Earth Shield fade alert** (Expiring Alerts) now fires. The Earth Shield check was never started at login and skipped the case where the shield is on yourself, so it could never trigger. It now follows the player your shield is actually on (or your assigned target), including yourself, in party and raid
- **Dropped Totem Indicator Position** moved from Mode & Twisting to Appearance > Layout, next to Totem Flyout Direction
- Settings window: option labels are no longer cut short with "..." when the line has room; a row that needs the space now takes the whole line

## v2.0.4 (2026-09-01)

### New
- **Earth Shield Flyout Filter** - show only the players you would actually shield: pick group roles (Tanks / Healers / Damage - raid Main Tanks count as Tanks), classes, or both. Picks combine, nothing picked shows everyone, and your assigned target always shows. Settings > Totem Bar > Flyouts
- **Screen-aware flyout direction** - with the flyout direction on Auto, the totem bar and Earth Shield flyouts open away from the screen edge (downward when the bar sits near the top, upward near the bottom). Above / Below still force a direction
- **Dropped Totem Indicator Position** - choose where the indicator for a dropped, non-assigned totem (and the Earth Shield one) pops out: Auto, Above, Below, Left or Right
- **Talent totems appear without a reload** - Totem of Wrath and Mana Tide now show up in (and disappear from) the flyouts when you respec, no /reload needed
- **What's-new popup** - a small once-per-update card highlighting big changes; re-open it any time with /spwhatsnew

### Fixes
- Earth Shield flyout no longer sticks open: it closes on mouse-leave again and also closes after clicking a member, like the totem flyouts
- Earth Shield flyout opened on the wrong side on vertical layouts, and did not re-check its direction when the bar moved
- The Earth Shield button no longer flickers between grey and colored while your shield is on someone who is not the assigned target
- Respeccing out of Restoration now resets a Mana Tide assignment the same way Totem of Wrath's is reset
- Totems disabled in the flyout settings could sneak back into the flyout after a right-click assignment; they stay hidden now

## v2.0.3 (2026-08-28)

### Fixes
- **Stutter when an alert sound played at reduced volume.** Any alert with its volume set below 100 (Expiring Alerts, Tremor Reminder, Reactive Totems, twisting, raid cooldown calls) briefly enabled the Dialog sound channel if you had it turned off, which restarts the game's sound engine and caused a visible hitch, twice per alert. If Dialog is disabled the sound now plays on the Master channel instead. Volume 100 was never affected.
- Overlapping alerts could leave your Dialog volume changed after the addon restored it. The original value is now captured once and restored once.

## v2.0.2 (2026-08-28)

### Fixes
- **Totem Assignments**: left-clicking past the last totem now wraps back to "none", the same way right-clicking already wrapped in the other direction. Previously that click did nothing.

### Housekeeping
- Removed dead legacy code: an unused duplicate of the Totemic Call button, an old settings migration that could never run, and a few unused helpers. No behavior change.
- The code base now passes a static check (Lua language server with WoW API annotations, plus luacheck) with no real findings. Nothing user-visible.

## v2.0.1 (2026-08-28)

### Your existing setup is safe
- **Re-running the setup never changes your settings.** The per-spec starting defaults (twisting, Earth Shield tracker and charges, spec cooldown-bar spells, frames off) now apply only on a genuinely fresh install. Existing setups keep every value; the welcome screen says so
- **Automatic backup before anything replaces your setup.** Picking a spec on an existing setup, or applying a built-in layout, first snapshots your whole configuration - profile, every module's settings and all positions - and tells you in a dialog what was saved and where to get it back. The last three backups are kept
- **Restore My Previous Setup** on Settings > Profiles > Built-in Layouts brings a backup back as a new profile (named "<profile> (restored <date>)"), so nothing gets overwritten during the restore either
- Applying a layout with reload now shows the backup notice first and reloads when you press OK

### Also
- Profiles page: **Preview Srumar's Layout** - the same preview-then-apply dialog the setup uses, so the tour is not the only way to get the built-in layout

## v2.0.0 (2026-08-28)

A ground-up rework of how you configure ShamanPower. The addon's features are the same ones you know; the way you find, set up and understand them is new. Requires the TBC Anniversary client (2.5.x).

### Highlights
- **New settings window (`/sp` or `/spui`)**: Replaces the old options dialog entirely. Sidebar navigation grouped into General, Bars and Modules with module power dots, tabbed pages, global and per-page search, scrollbars everywhere, combat lock only on pages that need it, and a background-opacity setting. Everything opens here now: `/sp`, the minimap icon, Interface > AddOns, and right-clicking module frames
- **First-run setup (`/spsetup`)**: A guided walkthrough that opens on first login. Pick your spec, then every feature is explained on the left and shown working live on the right - your real frames fed with sample data, or faithful animated mocks for the secure bars - with the real options next to them. Steps are gated by spec (Earth Shield for Resto, twisting defaults for Enhancement, and so on). Existing users get a small "there's a lot new, take the tour?" card instead of the full screen
- **Non-shaman setup**: Other classes get a short tailored run - Totem Range, Raid Cooldowns, the Windfury Companion (worded for the melee installing it), Totem Plates and Position - and shaman-only settings pages are greyed out for them
- **Built-in layout + sharing**: "Srumar's Layout" is a complete ready-made setup you can preview (live mocks and a what-it-sets summary) before applying, from the setup's Quick Setup or Profiles > Built-in Layouts. Profiles can also be exported as a copyable `SP1:` string and imported live - no reload
- **Windfury Companion**: A small WeakAura for your melee (warriors, rogues, paladins). With it, your Air slot counts who has Windfury and shows whether each is in range. Available from the setup and Settings > Windfury Companion, with the string and the wago.io link

### Setup wizard details
- Totem Bar step: the three display styles (Normal / TotemTimers / Dynamic) animated, an animated flyout demo (hover, left-click drops, right-click assigns), layout, size, opacity, frame
- Assignments step: the real assignments window with a sample three-shaman roster, plus Free Assign and window size
- Duration Bars, Cooldown Bar, Earth Shield Tracker, Shield Charges, Totem Twisting, Raid Cooldowns (click a caller to see the alert the target sees), Reactive Totems, Tremor Reminder, Expiring Alerts, Party Buff Tracker (who is in range of which totem), Totem Range, Totem Plates (real 3D totem models under the plates, faction-correct) - each with its full option set
- Position step steps the wizard aside so you can drag your bars; Finish reloads and can open the full settings window
- Steps tell you when a module is disabled or does not run on your class; preview errors print to chat

### New options
- **Totem Bar**: Enable Mini Totem Bar now truly removes the bar (for shamans who keybind totems and only want the cooldown bar); an attached cooldown bar detaches automatically
- **Duration Bars**: Cooldown Style for totem cooldowns (radial swipe, vertical greys-out, vertical fills-back-in) and Show Cooldown Time
- **Cooldown Bar**: Sweep Style (vertical greys-out / fills-back-in / radial) for cooldowns and shields
- **Party Buff Tracker**: Dot Position (corners, row above/below, column left/right - duration and pulse bars pad away from the dots automatically), Dot Outline (dark ring so dots read on bright icons, on by default) and Dot Size
- **Raid Cooldowns**: Drums of Battle callers - a caller and one drummer per raid group; pressing it shows every assigned drummer a "USE DRUMS NOW" alert. Also Show Caller Button Frame
- **Unlock Bar (move)** toggles on the Totem Bar and Cooldown Bar pages: a grab-anywhere overlay for repositioning, no Alt key, no drag handles
- Test Sound buttons next to every sound picker

### Changes
- Frame positions are stored resolution-independently (relative to the nearest screen anchor), so they survive resolution and UI-scale changes and can be shared; existing positions migrate once
- Scaling a frame keeps it in place instead of sliding it across the screen; saved scales apply before saved positions
- Pop-out trackers, the Raid Cooldowns window, the Totem Range overlay and its click-to-track window, the fear-caster mob list and the totem assignment window were all rebuilt in the new style; frame settings buttons stay reachable in icon-only mode
- Reactive Totems and Tremor Reminder: Icon Size and Scale merged into one Icon Size option (existing scale folded in, nothing moves)
- Text inputs commit when they lose focus, so typing a loadout name and clicking Create keeps the name
- Options whose visibility depends on another option now appear immediately
- The cooldown bar always floats free of the totem bar (the attach option is gone; existing profiles are detached once)
- Totem Plates: pulse timer, countdown text and pulse bar are on by default, matching what the options page showed
- Unused locale strings pruned; dead legacy code and options with no working feature behind them removed (including the Hide Bench raid option and the old Main Tank / Main Assist role options)

### Bug Fixes
- Nature's Swiftness, Shamanistic Rage and Bloodlust buttons never showed their active state on 2.5.x (`AuraUtil.FindAuraByName` errors); replaced with a direct aura scan
- Repeated raid cooldown calls were silently dropped after the first press for non-shaman callers
- Flyout, frame-settings and dropdown popups layering fixes throughout the new UI

### Removed
- Vanilla and Wrath support: only the TBC Anniversary client is supported
- The old AceGUI options dialog and the XML assignment window

## v1.6.2 (2026-07-18)

### Bug Fixes
- **Fixed all flyouts closing instantly on mouse-leave (patch 2.5.6)**: The 2.5.6 client's retail-ported restricted environment broke the recursive `IsUnderMouse(true)` check used by every flyout `_onleave` secure handler (the engine now stops after inspecting only the first child frame, so "is the cursor over me or my children?" almost always answered no). All 10 handlers across the totem bar, cooldown-bar shield, weapon imbue, Earth Shield, and totem loadout bar flyouts now walk their child buttons explicitly using the still-working non-recursive `IsUnderMouse()`. Flyouts open, traverse, and close correctly again, in and out of combat. Fix contributed by 0xdcb (#17); fixes #18 and #15

### Misc
- Bumped Interface to 20506 for the 2.5.6 anniversary client (removes the "out of date" flag in the AddOns list)

## v1.6.1 (2026-02-18)

### New Features
- **Sound Picker Dropdowns**: Added LibSharedMedia sound picker dropdowns to Reactive Totems, Tremor Reminder, and Expiring Alerts (shields, totems, weapon imbues) so users can choose which alert sound plays from a curated list of WoW built-in sounds (plus any sounds added by the SharedMedia addon if installed)
- **Twist Beep Sound**: Play a configurable sound when the totem twist timer reaches a threshold (default 3 seconds remaining). Includes sound picker, volume slider, and threshold slider — all under Settings when Totem Twisting is enabled
- **Reactive Totems: Only Alert in Instances**: New toggle to suppress reactive totem alerts in the open world and only show them inside dungeons, raids, and battlegrounds (off by default)
- **Reactive Totems: Hide When Totem Active**: New toggle (on by default) that hides the reactive alert when the matching cleansing totem is already placed (e.g. Tremor Totem down → fear alert hidden)

### Bug Fixes
- **PallyPower compatibility**: Moved `SetNormalBlessings`, `GetNormalBlessings`, `SyncList`, `AllShamans`, and `AC_DebugEnabled` out of the global namespace and onto the `ShamanPower` table, resolving conflicts where ShamanPower would overwrite PallyPower's identically-named globals (broke PallyPower's per-player blessing mousewheel assignment)
- **Show Tooltips now respected globally**: The "Show Tooltips" setting now gates all tooltips across every ShamanPower element — totem flyouts, cooldown bar items, shield/imbue flyouts, Earth Shield flyout, pop-out frames, loadout bar, and the Tremor Reminder icon. Previously only the main totem bar buttons checked this setting
- **Reactive Totems "Click to cast" tooltip removed**: Removed the misleading "Click to cast" line from Reactive Totems tooltips and updated the options description since click-to-cast was non-functional
- **Shield Charges rendering above UI panels**: Lowered Shield Charges frame strata so the charge numbers no longer display on top of the talent window and other standard UI panels
- **TotemPlates NPC ID fixes**: Fixed several incorrect totem NPC IDs that prevented TotemPlates from recognizing certain totem ranks on nameplates
  - Windfury Totem Ranks 4 and 5 now correctly identified (were using wrong NPC IDs)
  - Frost Resistance Totem Ranks 2 and 3 no longer conflict with Fire Resistance Totem entries
  - Removed non-TBC era NPC IDs from Searing Totem, Tremor Totem, and Grounding Totem

## v1.6.0 (2026-02-05)

### New Features
- **Totem Loadout System**: Save and switch between up to 8 totem loadout presets
  - Full creation form in Buttons > Totem Loadouts: name your loadout, pick a custom icon, choose 4 totems from dropdowns, and click "Create Loadout"
  - On-screen loadout bar with hover flyout for quick switching between loadouts
  - Loadout names displayed next to buttons (toggleable via Look & Feel > Loadout Bar > Hide Loadout Names)
  - "Show Totem Icons on Active Loadout" option to display the 4 assigned totem icons on the active button
  - Loadout bar customization: Scale, Opacity, Lock Position (Look & Feel > Loadout Bar)
  - Per-loadout editing: rename, change icon, swap individual totems, delete
  - Icon picker panel with scrollable icon grid
  - Newly created loadouts auto-activate immediately
  - `/spl save <name>` and `/spl <name>` slash commands for quick save/switch
- **Windfury Tracker WeakAura support**: Non-shaman party members can now broadcast their Windfury weapon enchant status without installing ShamanPower, enabling class-colored Windfury range dots for all party members. Install the [ShamanPower Windfury Tracker Companion](https://wago.io/otSzIN5ai) WeakAura on non-shaman characters. ShamanPower also listens for the popular WFTracker WeakAura addon prefix for broader compatibility

### Bug Fixes
- **Cooldown bar combat lockdown protection**: Fixed taint errors where `Show()`/`Hide()` on the cooldown bar could be blocked during combat if another addon (e.g. Atlas) spread taint through the options panel; visibility updates are now deferred until combat ends
- **Party Buff Tracker and Totem Range Tracker buff detection**: Fixed totem buff detection for Party Range dots and SPRange by using buff spell IDs resolved via `GetSpellInfo()` instead of hardcoded name strings; fixes Wrath of Air Totem and other totems whose buff names don't match the partial totem name
- **Shaman sync fix**: Fixed `SendMessage` dedup suppressing whisper responses to REQ — other shamans' SELF replies were silently dropped if their `lastMsg` already matched, preventing them from appearing in `/sp totems`

## v1.5.9 (2026-02-05)

### New Features
- **Weapon Imbue Left/Right-Click**: Left-click applies imbue to main hand, right-click applies to off hand (both on parent button and flyout)
  - Uses the `/cast [@none]` + `/use slot` macro pattern for reliable weapon targeting
  - Auto-confirms the replacement dialog via `/click StaticPopup1Button1`
  - Tooltips now show click hints (off hand hint only visible if dual wielding)
- **Sound Volume Sliders**: Added volume sliders next to each "Play Sound" toggle across Raid Cooldowns, Reactive Totems, Expiring Alerts, and Tremor Reminder
  - Control alert volume from 0% to 100% per module
  - Routes through the Dialog sound channel — requires Dialog volume set to 100% in WoW audio settings
- **Cooldown Text Color Picker**: Added a color picker for totem cooldown text (under the "Show Totem Cooldowns" toggle)
  - Defaults to white; disabled when cooldowns are toggled off
- **Elemental Mastery on Cooldown Bar**: Added Elemental Mastery as a trackable cooldown bar item (Elemental talent)
- **Split Imbue Icon**: Weapon imbue icon vertically splits to show both imbue icons when main hand and off hand have different imbues
- **Imbue Sweep Overlay**: Weapon imbue icon now shows a color-to-grey vertical sweep as the imbue expires, matching the other cooldown bar icons
- **Duration Text Size Slider**: Added an independent font size slider (6-20) for cooldown bar duration text, separate from progress bar size

### Improvements
- **Totemic Call icon desaturated when no totems active**: The Totemic Call icon on the cooldown bar is now greyed out when no totems are placed, and colorizes when any totem is active
- **Weapon imbue bars unified and dual-tracking**: Weapon imbues now use the same progress-bar system as other cooldowns and show separate bars for main-hand and off-hand when both are active; single imbues expand to full-width.
- **Flyout Requires Right-Click applies to Cooldown Bar**: The "Flyout Requires Right-Click" option now also applies to shield and weapon imbue flyouts on the cooldown bar
- **Spell-colored progress bars preserve urgency colors**: Spell-colored bars now only replace the green (healthy) color; yellow and red time-based colors still show when time is running low

### Changes
- **Play Sound defaults to OFF**: The "Play Sound" toggle for Reactive Totems, Expiring Alerts (shields, totems, weapon imbues), and Tremor Reminder now defaults to off for new users
- **Totem/Cooldown Bar opacity minimum lowered to 0%**: Both bars can now be fully transparent

### Bug Fixes
- **Cooldown text visibility**: Fixed cooldown text rendering behind the cooldown swipe overlay, making it hard to read
- **Cooldown bar progress bar position**: Fixed "Bottom (Horizontal)" progress bars appearing at the top of the frame instead of the bottom
- **Cooldown bar dynamic frame sizing**: The cooldown bar frame now only expands to make room for progress bars when a cooldown is actually active, instead of always reserving the space
- **Missing pulse bars**: Added pulse tracking for Magma Totem (Fire) and Mana Spring Totem (Water) which were missing from the pulse overlay system
- **"On Icon" progress bar position**: Fixed "On Icon (Left & Right)" progress bars adding extra padding/spacing instead of rendering on the icon itself
- **Rockbiter imbue icon**: Fixed Rockbiter weapon imbue showing as Windfury icon due to missing enchant ID fallback

## [v1.5.7](https://github.com/taubut/ShamanPower/releases/tag/v1.5.7) (2026-02-02)

### New Features
- **Right-Click Drops Corner Totem**: New option in Settings > Totem Bar Mode (appears when TotemTimers Style Display is enabled)
  - When enabled, right-clicking a totem button drops the assigned totem (shown in the corner indicator) instead of casting Totemic Call
  - Useful for quickly switching between your active and assigned totems

### Bug Fixes
- **TotemTimers range display fix**: Fixed totem icons flickering between grey and normal when moving in/out of range while using TotemTimers Style Display
  - The range check (greying out icons when out of totem range) now works correctly with TotemTimers mode

## [v1.5.6](https://github.com/taubut/ShamanPower/releases/tag/v1.5.6) (2026-02-02)

### New Features
- **Totem Twisting option in Settings**: Added "Enable Totem Twisting" toggle to Settings > Totem Bar Mode (same as the checkbox in /sp totems, now also accessible in the options panel)
- **Twist Timer: Hide Decimals**: New sub-option (shown when twisting is enabled) to show whole seconds only on the twist countdown (e.g., "8" instead of "8.3")
- **Totem Cooldown Display**: Show cooldown swipe and remaining time on totems that have cooldowns
  - Displays on both the main totem button and in the flyout menu
  - Affects totems with cooldowns: Grounding Totem, Mana Tide Totem, Stoneclaw Totem, Fire Nova Totem, Earth Elemental, Fire Elemental
  - Shows cooldown swipe animation plus countdown text (minutes or seconds)
  - Enabled by default - can be toggled in Look & Feel > Totem Bar > "Show Totem Cooldowns"
- **Totem Flyout Customization**: New "Totem Flyouts" section in Look & Feel
  - Enable/disable individual totems from appearing in flyout menus
  - Organized by element (Earth, Fire, Water, Air) with colored headers
  - Hide totems you never use to keep your flyouts cleaner
  - All totems enabled by default

### Improvements
- **Improved macro reset timers**: Drop All and Twist macros now use `reset=combat/15` instead of just combat reset
  - Macros will reset 15 seconds after last use OR when leaving combat, whichever comes first
  - Prevents macros from getting stuck mid-sequence if combat ends unexpectedly
  - One-time automatic migration for existing users updating from v1.5.5 or earlier

### Bug Fixes
- **TotemTimers style + Twisting fix**: Fixed Air totem icon rapidly flickering when both "TotemTimers Style Display" and "Twist" options are enabled
  - Now correctly shows the currently active totem icon (Windfury or Grace of Air) instead of always showing the assigned totem
- **TotemTimers style flyout fix**: Fixed flyout menu showing wrong totem when using "TotemTimers Style Display"
  - Previously, the flyout would hide the assigned totem while the main button icon showed the active totem (causing visual confusion like Mana Tide appearing on both the main button and in the flyout)
  - Now correctly hides the active totem from the flyout, so the totem shown on the main button icon doesn't also appear in the flyout

## [v1.5.5](https://github.com/taubut/ShamanPower/releases/tag/v1.5.5) (2026-02-02)

### New Features
- **Reincarnation Ankh tracking**: The Reincarnation icon on the cooldown bar now shows reagent status
  - Icon greys out when you have no Ankhs in your inventory
  - Optional Ankh count display in bottom right corner (enable in Look & Feel > Cooldown Display)
  - Count is color coded: Red (0), Yellow (1-3), White (4+)

### Improvements
- **Macro icons now use dynamic spell icons**: All ShamanPower-created macros now use the `?` icon, allowing `#showtooltip` to dynamically display the correct spell icon
  - Affects totem macros (SP_Earth, SP_Fire, SP_Water, SP_Air), Drop All (SP_DropAll), Totemic Call (SP_Recall), and Earth Shield macro
  - One-time automatic migration for existing users updating from v1.5.4 or earlier

## [v1.5.4](https://github.com/taubut/ShamanPower/releases/tag/v1.5.4) (2026-02-01)

### New Features
- **ShamanPower [Reactive Totems] Module**: Shows large totem icons when party members have cleansable debuffs
  - Displays Tremor Totem icon when party members are feared, charmed, or horrified
  - Displays Poison Cleansing Totem icon when party members are poisoned
  - Displays Disease Cleansing Totem icon when party members are diseased
  - Click-to-cast: left-click the icon to instantly drop the totem
  - Each totem type has its own independently movable frame
  - Event-driven with throttling - only scans when party auras change, no polling
  - Party-only scanning (totems are party-wide, not raid-wide)
  - Full customization in Look & Feel: icon size, scale, opacity, glow effects, sounds, hide text options
  - Slash commands: `/spreactive show` (position frames), `/spreactive hide`, `/spreactive test`, `/spreactive reset`

- **ShamanPower [Expiring Alerts] Module**: Scrolling combat text style alerts when buffs expire
  - **Shield Alerts**: Lightning Shield, Water Shield, and Earth Shield (on your assigned target)
  - **Totem Alerts**: Detects when totems are destroyed by enemies vs expired naturally
    - Per-element toggles (Earth, Fire, Water, Air)
    - Rank stripped from totem names for cleaner display
  - **Weapon Imbue Alerts**: Main hand and off hand tracked separately
  - **Display Modes**: Text only, Icon only, or Icon + Text
  - **Animation Styles**: Scroll Up, Scroll Down, Static Fade, Bounce
  - **Customization**: Text size, icon size, duration, opacity (50-100%), font outline
  - **Sound Options**: Per-alert-type sound toggles
  - Center-aligned alerts with draggable positioning frame
  - Slash commands: `/spalerts show` (position), `/spalerts hide`, `/spalerts test`, `/spalerts reset`, `/spalerts toggle`

- **ShamanPower [Tremor Reminder] Module**: Proactive Tremor Totem reminder when targeting fear-casting mobs
  - Shows a Tremor Totem icon when you target known fear-casters (before anyone gets feared)
  - Built-in database of 50+ TBC dungeon and raid fear-casting mobs
  - Click-to-cast: left-click the icon to instantly drop Tremor Totem
  - Hides automatically when Tremor Totem is already active
  - Customization: icon size, scale, opacity, glow effects, glow color, sound
  - Manage custom mob list via slash commands
  - Slash commands: `/sptremor show`, `/sptremor test`, `/sptremor reset`, `/sptremor add <mob>`, `/sptremor remove <mob>`, `/sptremor list`
  - Based on Sweb's Tremor Totem Reminder WeakAura

### Bug Fixes
- **Weapon enchant totem self-range tracking**: Fixed Windfury and Flametongue Totems not greying out when the shaman walks out of range of their own totem
  - Now detects range via weapon enchant (same method as SPRange module)
  - Affects both Windfury Totem (Air) and Flametongue Totem (Fire)
  - Works correctly when "Party Buff Tracker" is disabled - shaman can still see their own totem range
- **TOC Interface version**: Updated all module TOC files to correct Interface version (20505) so they no longer show as "Out of date" in the addon list
- **ES Tracker caster name**: Fixed Earth Shield Tracker showing "Unknown" for caster name due to broken API return value handling in Classic TBC

## [v1.5.3](https://github.com/taubut/ShamanPower/releases/tag/v1.5.3) (2026-01-30)

### New Features
- **Action Bar Addon Keybind Detection**: "Show Keybinds on Buttons" now detects keybinds from action bar addons
  - Supports Bartender4, Dominos, and ElvUI action bars
  - Scans action bars for spells and displays their keybinds on ShamanPower buttons
  - Works for totem buttons, cooldown bar buttons, and weapon imbue button
  - Falls back to ShamanPower-specific bindings if no action bar keybind found
  - Automatically rescans when action bar addons load or when entering world

*Thanks to SexualRhinoceros from the Shaman Discord for contributing this feature!*

## [v1.5.2](https://github.com/taubut/ShamanPower/releases/tag/v1.5.2) (2026-01-30)

### New Features
- **Flyouts Require Right-Click**: Totem Flyouts now have the option to require Right-Click to show
- **TotemTimers Style Display**: New Totem Bar Mode to change the way Active and Non-Active Totems look
- **Totemic Call On Totem Bar**: New option in Cooldown Bar Items to move the Totemic Call icon to the Totem Bar

### Bug Fixes
- Fixed the Totem Bar from showing range of totems when party range indicators were completely turned off

## [v1.5.1](https://github.com/taubut/ShamanPower/releases/tag/v1.5.1) (2026-01-25)

### Memory Optimizations
- **Cooldown bar shield detection**: Switched from polling to event-driven approach using UNIT_AURA
  - Reduced memory allocation from ~12 KB/call to near 0
  - Shield state now cached and only rescanned when auras change
- **Player totem range checking**: Optimized to scan player buffs once per update tick
  - Checks all 4 totem elements in a single buff scan instead of 4 separate scans
  - Reduced memory allocation from ~6 KB/call to near 0
- **Party range UnitHasBuff**: Simplified to match TotemTimers' approach (direct scan, direct comparison)
- **Removed tracking overhead**: Cleaned up all memory profiling code that was adding overhead

### UI Improvements
- **Earth Shield full opacity when active**: ES button now respects the "Full Opacity When Totem Placed" setting
- **Section descriptions**: Added helpful descriptions to all Look & Feel option sections explaining what each section controls

## [v1.5.0](https://github.com/taubut/ShamanPower/releases/tag/v1.5.0) (2026-01-24)

### Major Performance Improvements
- **Massive memory optimization**: Memory usage in 40-man raids reduced from 60MB+ spikes to stable 2-9MB
- **Event-based Earth Shield tracking**: Replaced full raid scanning with event-driven tracking (inspired by TotemTimers)
  - Now tracks who has your ES when you cast it, instead of scanning all 40 players every update
  - Reduced `FindEarthShieldTarget` memory allocation from ~507KB/call to near 0
- **Earth Shield flyout optimization**: Reuses frames instead of creating new ones when group size changes
  - Pre-computed unit strings eliminate string concatenation garbage
  - Checks if disabled BEFORE doing any work
- **Earth Shield flyout disabled by default** for performance (can enable in Settings)

### Modularization
Split optional features into standalone addon modules:
- **ShamanPower_ESTracker**: Raid ES Tracker - tracks Earth Shields cast by OTHER shamans
- **ShamanPower_PartyRange**: Party Totem Range - shows party members in/out of totem range
- **ShamanPower_SPRange**: Totem Range (for non-shamans) - shows when you're in range of totem buffs
- **ShamanPower_RaidCooldowns**: Raid Cooldown Management - BL/Heroism and Mana Tide calling
- **ShamanPower_ShieldCharges**: Shield Charge Display - large on-screen shield charge numbers

All modules are optional and can be enabled/disabled independently via the WoW addon list.

### Party Buff Tracker Fixes
- Fix numbers not updating when display mode set to "Numbers Only" (was only updating when dots enabled)
- Default frame position now centers on screen instead of above totem bar
- Reset Frame Positions button now centers all frames on screen
- Hide numbers for totems without trackable buffs (Tremor, Searing, Disease Cleansing, Earthbind, etc.) instead of showing 0

## [v1.3.9](https://github.com/taubut/ShamanPower/releases/tag/v1.3.9) (2026-01-23)

### New Features
- **Party Buff Tracker**: Shows number of players in range per totem element as numbers
  - Display on icon or as separate movable frames
  - Element colors (Earth=green, Fire=red, Water=blue, Air=white)
  - Scale, opacity, lock, font size options
- **Full Opacity When Active**: Option for totem bar and cooldown bar to show at full opacity when totems are placed or cooldowns are active

### Duration Bar Enhancements
- Add "None" position option to disable duration bar completely
- Add duration text size option (6-20)
- Increase max bar size to 26 (full icon width)
- Fix bottom vertical direction to shrink toward icon (was shrinking away)

### Pulse Bar Enhancements
- Add "None" position option to disable pulse bar
- Add pulse bar size option (was hardcoded to 4)
- Add pulse text size option (6-20)
- Increase max bar size to 26 (full icon width)
- Fix vertical positions (above_vert, below_vert) to respect size setting

### Cooldown Bar Fixes
- Reduce cooldown text size (was too big for icon)
- Flyout menus now go opposite direction when bar is locked to totem bar

### Range Tracker Fixes
- Fix Windfury range tracking to check active totem, not assigned totem
- Windfury dots now only show for players with ShamanPower installed
- Hide dots for totems without trackable buffs (Tremor, Searing, Earthbind, etc.)

### Performance
- Throttle pulse tracking OnUpdate to 20fps (reduces CPU usage)
- Throttle twist timer tracking OnUpdate to 20fps

### Bug Fixes
- Fix "Allow custom scripts?" warning when right-clicking totems (now uses Totemic Call)

## [v1.3.8](https://github.com/taubut/ShamanPower/releases/tag/v1.3.8) (2026-01-22)

### New Features
- **Shield Charge Display**: Large on-screen charge numbers for Lightning Shield, Water Shield, and Earth Shield
  - Separate toggles for player shield and Earth Shield on target
  - Options for scale, opacity, lock position, hide out of combat, hide when no shields
  - When "Hide When No Shields" is unchecked, shows 0 instead of hiding
- **PVP/Dynamic Mode**: Totem bar shows whatever totem is currently placed (no pre-assignment needed)
  - Enable in Settings tab under "Dynamic Totem Mode"
- **Totem Bar Visibility Options**: Hide out of combat, hide when no totems placed
- **Pop-Out Control**: Option to disable middle-click pop-out feature (Settings > Pop-Out Trackers)
- **Earth Shield Tracker Button**: Added button in Settings to open `/spestrack` configuration

### UI Improvements
- **Reorganized Look & Feel Tab**: Now uses sidebar navigation for cleaner organization
- **Reorganized Buttons Tab**: Now uses sidebar navigation matching Look & Feel
- All options use full-width elements for better readability
- Renamed "Totem Range (SPRange)" to "Totem Range Tracker"
- Moved Shield Charge Display options to Look & Feel tab
- Fixed cramped layouts throughout (Totem Bar Items, Totem Bar Order, Earth Shield Tracker, Cooldown Bar Order)
- Dropdown menus now use full names instead of abbreviations

### Tooltip Improvements
- Added "Middle-click to pop out" hint to button tooltips

### Bug Fixes
- Fix totem twisting timer restarting on second totem
- Fix Drop All Totems cast sequence not resetting after combat ends
- Fix Shield Charge Display "Hide When No Shields" option (now properly shows 0 when unchecked)
- Fix "Allow custom scripts?" warning when right-clicking totems (now uses Totemic Call instead of DestroyTotem)

## [v1.3.7](https://github.com/taubut/ShamanPower/releases/tag/v1.3.7) (2026-01-22)

### Pop-Out Individual Trackers
- Middle-click any button to pop it out as a standalone, movable tracker
- Supports: Individual totems (from flyout), entire element with flyout, cooldown bar items, Earth Shield, Drop All
- SHIFT+Middle-click on popped-out frame to open settings (scale, opacity, hide frame)
- ALT+drag to move popped-out frames
- Popped-out elements with flyouts can have custom flyout direction (Top/Bottom/Left/Right)
- Pop-out state and positions save per-profile and persist across /reload
- Main bar reflows when items are popped out

### Duration Bar Improvements
- Add duration bar position options: Left, Right, Top (Horizontal), Top (Vertical), Bottom (Horizontal), Bottom (Vertical)
- Add duration bar size slider for both totem bar and cooldown bar
- Add duration text position options: Inside Bar (Top), Inside Bar (Bottom), Above Bar, Below Bar, On Icon

### Pulse Bar Improvements (for pulsing totems like Tremor, Healing Stream)
- Add pulse bar position options: On Icon, Above (Horizontal/Vertical), Below (Horizontal/Vertical), Left, Right
- Add pulse time display options: Inside Bar (Top/Bottom), Above Bar, Below Bar, On Icon
- Pulse bar now respects position setting on active totem overlays

### Flyout Improvements
- Add flyout direction option for totem bar when in horizontal mode (Auto, Above, Below)
- Add flyout direction option for cooldown bar when in horizontal mode (Auto, Above, Below)
- Move flyout direction options to Look & Feel tab under Layout section

### Bug Fixes
- Fix cooldown bar hidden items still working with keybinds (buttons created but hidden)
- Fix Earth Shield tracker crash when leaving group (nil table error)
- Fix various option label abbreviations (Horiz/Vert changed to Horizontal/Vertical)
- Fix Windfury Totem range indicator on mini totem bar (now uses same broadcast system as SPRange)

## [v1.3.6](https://github.com/taubut/ShamanPower/releases/tag/v1.3.6) (2026-01-21)
- Fix profile system: Totem bar and cooldown bar positions now properly save and restore per-profile
- Fix all nested settings (display, colors, minimap, autobuff) to properly persist to profiles
- Add shield charge color coding: Green (full), Yellow (half), Red (low) based on remaining charges
- Add "Reset Frames to Center" button in Settings (same as `/spcenter`)
- Rename "Reset Frames" to "Reset to Defaults" for clarity
- Fix `/spcenter` to properly center cooldown bar when unlocked from totem bar

## [v1.3.5](https://github.com/taubut/ShamanPower/releases/tag/v1.3.5) (2026-01-21)
- Raid Cooldowns: Anyone can now set Heroism/Mana Tide assignments (not just raid leader/assist)
- Raid Cooldowns: Fix Mana Tide shaman list not showing for non-leaders
- Raid Cooldowns: Fix assignments not syncing when set to "None"
- Raid Cooldowns: Add Look & Feel options (button opacity, scale, warning icon/text/sound/animation toggles)
- SPRange: `/sprange` now opens the Totem Range config menu directly (`/sprange toggle` for overlay)
- SPRange: Move appearance settings (opacity, icon size, vertical, hide names, hide border) to Look & Feel
- Totem Flyouts: Add "Swap Flyout Click Buttons" option in Look & Feel to swap left/right click behavior

## [v1.3.4](https://github.com/taubut/ShamanPower/releases/tag/v1.3.4) (2026-01-20)
- Earth Shield tracking now works on any target (not just assigned target)
- Shows who currently has your Earth Shield with color-coded names (green=assigned, yellow=other, red=inactive)
- Smart re-apply: button casts on last ES target if assigned target is dead or unassigned
- Earth Shield assignments auto-clear when leaving group/raid/BG

## [v1.3.3](https://github.com/taubut/ShamanPower/releases/tag/v1.3.3) (2026-01-20)
- Add "Look & Feel" tab for UI customization (dedicated to FluffyKable)
- Add Button Padding sliders for Totem Bar and Cooldown Bar spacing
- Move Layout dropdown and Totem Assignments Scale to Look & Feel
- Reorganize options: move UI settings from Settings/Buttons tabs to Look & Feel

## [v1.3.2](https://github.com/taubut/ShamanPower/releases/tag/v1.3.2) (2026-01-20)
- Add "Unlock Cooldown Bar" option to move CD bar independently from totem bar
- Add separate scale sliders for Totem Bar and Cooldown Bar
- CD bar drag handle (green=movable, red=locked) when unlocked
- Position saves correctly across /reload
- ALT+drag support for moving CD bar when drag handle is disabled
- Add keybind options for all cooldown bar buttons (Shield, Recall, Ankh, NS, Mana Tide, BL, Imbue)
- Add option to show keybind text on buttons (top-right corner)
- Auto-update cooldown bar when changing talents/specs
- Add "Exclude from Drop All" toggles to skip specific totem types (Earth, Fire, Water, Air)

## [v1.3.1](https://github.com/taubut/ShamanPower/releases/tag/v1.3.1) (2026-01-19)
- Add cooldown bar order customization (drag to reorder Shield, Recall, Ankh, NS, MTT, BL, Imbue)
- Add totem bar order customization (drag to reorder Earth, Fire, Water, Air buttons)
- Fix locale initialization for non-English clients

## v1.3.0 (2026-01-18)
- Add cooldown bar with visual timers for Shield, Recall, Ankh, Nature's Swiftness, Mana Tide, Bloodlust/Heroism
- Add weapon imbue button with flyout menu
- Add shield button with Lightning/Water Shield toggle
- Cooldown bar shows below totem bar (horizontal) or beside it (vertical layouts)

## v1.2.0 (2026-01-17)
- Add SPRange: Totem Range Tracker overlay for all classes
- Add Raid Cooldown Coordination System for tracking raid-wide shaman cooldowns
- Add active totem overlay feature
- Add vertical layout options (Vertical Right, Vertical Left)
- Merge flyout fixes from Chairface30 fork

## v1.1.0 (2026-01-16)
- Add totem flyout menus (TotemTimers-style quick totem selection)
- Add ALT+drag to move the totem bar
- Add totem duration progress bars
- Add party range indicator dots on mini totem bar
- Add totem twisting support for Air totems
- Add GCD swipe animation on totem buttons
- Grey out totem icons when out of range

## v1.0.8 (2026-01-15)
- Fix macro system interfering with WoW macro UI
- Various bug fixes and stability improvements

## v1.0.2 (2026-01-14)
- Initial public release
- Fork of PallyPower adapted for Shaman totem management
- Mini totem bar with Earth, Fire, Water, Air buttons
- Drop All Totems button
- Totem assignment coordination for raids
- Earth Shield tracking and assignment
