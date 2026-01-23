# ShamanPower Changelog

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
