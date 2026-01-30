# ShamanPower Changelog

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
