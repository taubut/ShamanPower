# ShamanPower Changelog

## [v1.3.2](https://github.com/taubut/ShamanPower/tree/beta) (2026-01-20)
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
