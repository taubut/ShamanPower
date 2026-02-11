# ShamanPower

A totem coordination addon for Shamans in World of Warcraft TBC Anniversary. Think of it as **PallyPower for Shamans** - coordinate totem assignments across your raid so every party gets the buffs they need.

## Features

### Totem Assignment Grid
- Visual grid showing all shamans in your raid and their totem assignments
- Assign Earth, Fire, Water, and Air totems per shaman
- See which totems each shaman has available (based on their spec and level)
- Raid leaders and assists can assign totems for all shamans

### Auto-Drop Button
- One-click totem dropping based on your assignments
- Cycles through your assigned totems (Earth → Fire → Water → Air)
- Configurable via keybinds for fast totem management

### Earth Shield Tracking
- Assign Earth Shield targets for Restoration shamans
- Visual button to quickly cast Earth Shield on your assigned target
- See Earth Shield assignments across all resto shamans in raid

### Raid Sync
- All shamans running ShamanPower automatically sync their assignments
- Changes made by raid leaders instantly update for everyone
- See real-time totem availability from all shamans

### Weapon Enchant Tracking
- Track Windfury, Flametongue, and other weapon enchants
- Coordinate weapon buffs for optimal raid DPS

## Installation

1. Download the latest release from the [Releases page](https://github.com/taubut/ShamanPower/releases)
2. Extract the `ShamanPower` folder to your `Interface/AddOns/` directory
3. Restart WoW or `/reload` if already in-game

## Commands

| Command | Description |
|---------|-------------|
| `/sp` | Open ShamanPower options |
| `/shamanpower` | Open ShamanPower options |

## Usage

### Opening the Assignment Window
- Click the ShamanPower minimap icon, or
- Right-click the drag handle on the ShamanPower frame, or
- Type `/sp`

### Assigning Totems
1. Open the assignment window
2. Click on a totem slot for any shaman
3. Select the totem from the dropdown
4. Assignments sync automatically to all shamans

### Auto-Drop Totems
1. Set up your totem assignments in the grid
2. Use the Auto-Drop button or keybind to drop totems in sequence
3. Each press drops the next totem in your rotation

### For Raid Leaders
- You can assign totems for all shamans in your raid
- Use "Auto-Assign" to automatically distribute totems based on party composition
- Use "Report" to post assignments to raid chat

## Totem Priority (Auto-Assign)

When using Auto-Assign, ShamanPower prioritizes totems based on party composition:

| Element | Melee Party | Caster Party | Healer Party |
|---------|-------------|--------------|--------------|
| Air | Windfury | Wrath of Air | Wrath of Air |
| Earth | Strength of Earth | Strength of Earth | Tremor |
| Fire | Searing/Totem of Wrath | Totem of Wrath | Searing |
| Water | Mana Spring | Mana Spring | Mana Spring |

## Migration from AncestralCouncil

If you previously used this addon under the name "AncestralCouncil", your settings will automatically migrate when you first load ShamanPower. No action needed!

## Credits

- **Author:** taubut
- **Based on:** [PallyPower](https://www.curseforge.com/wow/addons/pally-power) by Aznamir, Dyaxler, Es, gallantron
- Adapted from Paladin blessings to Shaman totems for TBC Anniversary

## Links

- [TotemTimers Fork](https://github.com/taubut/TotemTimers) - Recommended companion addon
- [Report Issues](https://github.com/taubut/ShamanPower/issues)

## License

See [LICENSE.txt](LICENSE.txt) for details.
