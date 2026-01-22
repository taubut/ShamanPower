# ShamanPower Project Notes

## IMPORTANT PATHS - DO NOT FORGET

**WoW Addons Folder:**
```
/home/taubut/Faugus/battlenet/drive_c/Program Files (x86)/World of Warcraft/_anniversary_/Interface/AddOns/ShamanPower/
```

**Working Directory:**
```
/tmp/ShamanPower_git/
```

## After Making Changes

ALWAYS copy files to the addons folder:
```bash
cp /tmp/ShamanPower_git/ShamanPower.lua /tmp/ShamanPower_git/ShamanPowerOptions.lua "/home/taubut/Faugus/battlenet/drive_c/Program Files (x86)/World of Warcraft/_anniversary_/Interface/AddOns/ShamanPower/"
```

## Key Files

- `ShamanPower.lua` - Main addon code
- `ShamanPowerOptions.lua` - Options panel (AceConfig)
- `ShamanPower_TBC.xml` - XML templates for TBC/Anniversary

## Game Version

TBC / Anniversary Edition (not retail, not Wrath)

## Testing

User must /reload in-game to test changes. NEVER mark tasks complete until user has tested.

## FEATURE LIST

1. [DONE] Separate Layout Options - Independent horizontal/vertical for totem bar & CD bar
2. [DONE] Opacity Sliders - For totem bar, CD bar, and possibly flyout icons
3. [DONE] Increased Scale Range - Allow scaling up to 3x (currently 1.5x max)
4. [DONE] Hide Totem Bar Items - Hide individual totems/Earth Shield from totem bar
5. [DONE] Raid Earth Shield Tracker - New panel showing all raid Earth Shields
6. [ ] Pop-Out Individual Trackers - Pop out any button to standalone tracker (removes from bar)
7. [DONE] Totem duration bar improvements - larger bar, duration time inside bar, duration on icon
8. [DONE] Pulsating duration bars - bars pulse/glow when totem is about to expire
9. [DONE] Vertical duration bar option, ABOVE OR BELOW the totem icon
10. [DONE] Move Totem Bar Items, order, CD bar order/items to Look & Feel tab
11. [DONE] Earth Shield flyout - party/raid member names to quickly cast ES on target
