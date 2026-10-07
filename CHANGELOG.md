# ShamanPower Changelog

## v3.0.6.3 (2026-10-07)

### New
- **Drop All Icon (Totem Bar > Drop All):** pick any icon for the Drop All button instead of the icon of the totem it drops next. It stays put, with Call of the Elements too. Next Totem puts the usual icon back.

### Fixes
- **Drop All button (the one-totem-per-click version):** a fast double-click, or a click that cast nothing, moved the button's icon on anyway, so from then on it showed one totem and dropped the next. The icon now asks the game where the button's sequence stands, so it moves only when a totem cast goes through, and forgets its place exactly when the button does: 15 seconds after the last press, at the end of a fight, or on death.
- **Support Code with Deadly Boss Mods installed (WoW: Forever):** pressing Support Code failed with "Division by zero" when DBM was loaded. DBM brings a newer copy of a shared library (LibSerialize) that WoW: Forever can't run, and the game uses whichever copy is newest. ShamanPower now ships the library's latest version, which has the fix, so the code builds with DBM on.
- **My Assignments Follow Blizzard's Totem Bar (WoW: Forever):** it did nothing unless Call of the Elements Follows My Assignments was on too (both are on the Buttons > Mini Totem Bar page). Each now works on its own: with only the first on, a totem you pick on Blizzard's bar still becomes your assignment, and when you log in your assignments take what is on the bar; with only the second on, Blizzard's bar still follows your assignments.

## v3.0.6.2 (2026-10-07)

### Fixes
- **WoW: Forever:** your Fire totem (or Water or Air) could turn to Empty on its own after a /reload or a loading screen, and the totem you put back on Blizzard's totem bar was wiped again the next time ShamanPower loaded. ShamanPower read Blizzard's totem bar before the game had finished loading it, took the empty slots for your choice, and then wrote that Empty back over the bar. Now only a totem you change on Blizzard's bar yourself counts, a totem on Blizzard's bar fills an Empty element instead of being wiped when ShamanPower loads, and a totem you pick on Blizzard's bar during a fight is kept when the fight ends.
- **Support Code:** on WoW: Forever, pressing Support Code could fail with "could not build the support code" when your settings held something the code can't carry. The code now always builds: anything it can't carry is left out, and the code says what was left out, so I can still see your setup.

## v3.0.6.1 (2026-10-06)

### Fixes
- **The totem bar came back after you turned it off:** with Enable Totem Bar off, or Use in Party / Use when Solo off, the totem buttons showed up again after a fight, or when you picked a totem on Blizzard's own totem bar. They now stay hidden. Turning Use in Party or Use when Solo on or off also takes effect right away.
- **Dynamic Mode with Hide Out of Combat:** no more loose totem buttons left on screen after every fight.
- **WoW: Forever, Compact style:** Your Shield Line and the Earth Shield line keep showing your charges in fights, instead of going dark and saying "Not active". With Hide Out of Combat, your shield line now comes and goes with the bar.
- **Hide Out of Combat:** a bar hidden since you logged in could show up in your first fight as plain icons instead of your style. It now shows the way you set it up.
- **WoW: Forever, cooldown bar:** the Grays Out and Fills Back In sweeps on the cooldown bar and the shield button no longer show a stretched copy of the icon with hard edges in fights.
- **Party Buff Tracker:** a party member far away (in another zone, or out of sight) no longer lights your party dots or the Coverage list. On WoW: Forever the dots also only light for an element you have a totem down for: another shaman's own totems lit them.
- **Keybind Mode** shows Compact's shield line with the rest of the bar.

## v3.0.6 (2026-10-04)

### New
- **Target Tracker** (Settings > Alerts & Reminders > Target Tracker): your Flame Shock, Frost Shock and Stormstrike on your target, where you want them: a spot you place, your target's nameplate, or under the target frame. **Warn When It's Missing** grays a shock out when it isn't on your target, **Show On Every Enemy's Nameplate** puts your shocks on every mob, and the **Purge** reminder lights up when your target has a Magic buff you can remove. **Rules** switch any part on or off in a place or against a boss. It starts off: turn it on with the switch beside it.
- **Every game language:** shields, totems, imbues, alerts and reminders now work in German, French, Spanish, Russian, Portuguese, Italian, Chinese and Korean. ShamanPower finds your spells by their ID, never their English name.
- **Ready Reminders, made simple:** every setting is in each icon's right-click menu, with sliders right in the menu and **Copy To All Icons**. New: **Out of Range** (red tint, gray or dim), **Ready Flash** (a big flash when a spell is ready, which you can move), and a sound per icon.
- **The cooldown bar follows your totem bar style:** the shield and imbue buttons work the way your totems do in your style (Normal, TotemTimers, Single, Dynamic or Grid). For a different one: Cooldown Bar > Display > **Do Not Mirror Totem Bar Style**.
- **A new look for the settings:** pages lit by each group's element, the logo and new fonts; **Preview** and **Reset This Page** on every page; a module's page grays out with a **Turn On** button while the module is off; menus and tooltips got the same look. **UI Animations** (at the top of the settings sidebar) lets the settings window drop in and fly away and Unlock UI's boxes rise into place. It's off to start.
- **Tremor Reminder at boss pulls:** in dungeons and raids it comes up the moment a fight with a fearing boss starts, even without targeting the boss.
- **Sound When Your Shield Drops:** now in fights too.

### Changes
- Flyouts and the totem bar only show totems you've learned.
- Party dots and Totem Coverage count only your own totems.
- Every vertical sweep has a **Sweep Direction**.
- Cooldown bar flyouts never repeat what's on the button, and a right-click assign stays put.
- With two weapons, a right-click imbue pick is your off hand's, and the button's right-click applies it again.
- WoW: Forever: Raid Cooldowns' sound plays at its own volume, not your Dialog volume.
- WoW: Forever: Trainer Reminder matches your trainer exactly.
- WoW: Forever: keybinds for Call of the Elements, Ancestors and Spirits.
- Expiring Alerts stay quiet after logging in and after loading screens.
- Tooltips in ShamanPower's windows show at the mouse.
- The setup tour (`/spsetup`) has a Target Tracker step, right after Ready Reminders.

### Fixes
- Shields, totems and alerts didn't work in German and other non-English clients.
- In Spanish, and for a few totems in Portuguese, French, Russian and Chinese, the bar couldn't tell which totem was down: no timer, duration bar, pulse, range or party dot for it.
- TBC Anniversary: the Earth Shield macro showed a question mark on non-English clients.
- Tauren saw Nature Resistance Totem from level 1, and Flametongue and Windfury Totem showed as soon as the weapon imbue was learned.
- WoW: Forever: the shield-gone sound didn't play in fights.
- WoW: Forever: the totem bar's vertical cooldown sweeps drew a squashed second icon, hard edges and all, over the real one.
- The What's New card could run off the bottom of the screen.
- The imbue flyout showed the imbue already on the button.

## v3.0.5.1 (2026-10-02)

### Fixes
- **WoW: Forever, after the October 1 patch:** ShamanPower thought it was running on TBC Anniversary. Forever's own options (Right-Click to Destroy Totems, Raid Resistance and more) went missing, Totem Twisting options showed up, and settings could look reset. Everything is back, and a future change to how the game names itself won't do this again.
- **WoW: Forever:** no more Lua errors in combat from the shield check and the Earth Shield Tracker ("attempt to perform boolean test on field 'isFullUpdate'").
- **WoW: Forever, Reactive Totems:** the Tremor Totem alert shows only while you're feared, charmed or asleep. Roots, Frost Nova, stuns and other debuffs no longer set it off. It's for you only now: the game doesn't tell addons what kind of crowd control is on someone else, so a party member's root would have looked like a fear.

### Changes
- **Get Help: Copy Support Code** also says whether ShamanPower and each of its modules loaded (and why not), when your settings were last saved, BugSack's ShamanPower errors and anything the game blocked, so #help can answer without asking you to type commands.

## v3.0.5 (2026-09-30)

### New
- **Your Themes** (Settings > General > Themes): save your look under a name, pick it on any character, and share it with a code (**Share** / **Import Theme**).
- **Get Help: Copy Support Code** (the Discord section of General > Main, ShamanPower's page in Esc > Options, or `/sp support`): paste it in #help on the ShamanPower Discord and I can see what's going on without asking you to run commands. Nothing personal goes in it.
- **Unlock UI, upgraded:** boxes snap to each other and to the screen center as you drag them, with gold lines showing what they lined up with. Click a box and nudge it with the arrow keys (Shift for 10 px). The mouse wheel changes its size and Ctrl + wheel its opacity, and right-click opens its settings page. **Snapping**, **Show Grid** and **Grid Size** are on the bar.
- **Ready Reminders:** **Show: Only while on cooldown** (the icon counts down while the spell recharges and goes away when it's ready), and **Placement: Grid** (one block you move as a whole, filled in the order the icons appear, with no gaps: Icons Per Row, New Rows Go, Align Rows).
- **Keybinds tab** (General > Keybinds): Keybind Mode, Show Keybinds on Buttons, and the new **Keybind Shown**: your action bar key first (as before), ShamanPower's own key first, or ShamanPower's key only. Keys you set in Keybind Mode now show on the buttons.

### Changes
- **Themes:** Standard, ShamanPower and ShamanPower Minimal are now fixed presets that always give exactly that look. Anything you change becomes your **Custom** look, which waits until you save it or discard it. Your look from 3.0.4 is kept as a theme called **My Look**.
- **Performance:** about half the CPU out of combat, and less in fights. On TBC Anniversary, buff changes that can't affect your shield or Earth Shield no longer make ShamanPower read your buffs again, which matters most in raids.
- Cooldown Bar > Display: **Duration Text Location** and **Duration Text Size** moved up next to **Show Cooldown Text**.
- WoW: Forever: Ready Reminders' **Gray Out The Icon** now also grays the icon under a sweep.
- The settings' live preview pauses while Unlock UI is on.

### Fixes
- **WoW: Forever with Questie:** the cooldown bar's shield never lit up, and other buff checks could be wrong, because Questie brings its own version of a game function ShamanPower used. ShamanPower now uses its own.
- Unlock UI's grid centers boxes properly.
- The cooldown bar's **Radial** sweep no longer shows the game's own countdown ("10m") when Show Cooldown Text is off.
- WoW: Forever: the cooldown bar's shield shows right after a reload in combat, and Mana Tide's level 48 and 58 ranks end the cooldown bar alert.
- **Reset All Colors** keeps every color it clears on the Custom card.
- Party dots no longer leave a gap outside a group with Dot Position Below, Above, Left or Right.
- TBC Anniversary: Flametongue Totem is no longer tracked (its dots were always red).
- Ready Reminders' **Reset Position** resets only the placement you're using.
- Unlock UI: Shield Charges gets one box per real frame, with the right names.
- Raid Cooldowns: the Mana Tide call buttons no longer pile up in memory every time the group syncs.

Thanks to Miska for the new Ready Reminders modes, and to ShamanForever's author for the ideas behind Unlock UI's snapping and nudging.

## v3.0.4.1 (2026-09-29)

### Fixes
- **No more Lua error** in TotemBarGeometry when ShamanPower put the totem bar or the cooldown bar on its default spot, if the totem bar's button size was missing from your settings.
- **Importing a setup** (a shared code, a backup or Srumar's Layout) fills in any setting the code leaves out straight away, instead of only after the next reload.

## v3.0.4 (2026-09-29)

### New
- **Shapes & Textures** (Settings > General > Themes, and each bar's own page; everything stays at today's look until you pick something):
  - **Icon Shape** for the totem bar, the cooldown bar and Ready Reminders: Square (today's), Flat, Rounded or Circle. Borders follow the shape as a ring, including the dropped-totem and Earth Shield overlays; **Keep Borders Square** keeps them square.
  - **Bar Gradient** and **Outline Gradient**: Flat, Shade, Glass, Two-Tone or Fade Out, with a direction for each kind of bar (duration, pulse, cooldown bar, Ready Reminders).
  - **Glow Shape** (Square or Round), **Dot Shape** (Round, Diamond, Square, Soft Orb or Ring) and **Frame Edge** (Plain, Bevel, Drop Shadow or Thick).
- **Class Colors** for the party dots and Totem Coverage's dots: WoW's, Subtle, Stronger, Vibrant or Muted, as cards on the Themes tab and a choice per part. The ShamanPower themes use Subtle; Standard always shows WoW's. **Gem Dot Finish** gives every dot a darker rim and a soft highlight.
- **Shield Charges: orbs.** Show each shield's charges as orbs instead of the bar: Glowing, Flat, the shield's icon, Storm, and Water and Earth Shield looks of their own (Tide, Bubble, Foam, Stone Ring, Leaf Wreath, Spiked Stone). Each shield has its own look, Charge Color, Charge Bar Gradient and texture, an optional animation, and the orbs can stand up beside you (Charge Bar Direction Right or Left).
- **Combined Shocks** (Ready Reminders, off by default): one reminder for Earth, Flame and Frost Shock. **Shock Icon** cycles through the three or shows them split in thirds. Turning it on offers to hide the three single shock reminders.
- **Flyout Requires Right-Click** and **Shift+Right-Click Pulls That Totem Back** (Totem Bar > Clicks): open a totem's flyout with a right-click, and pull just that totem back with Shift+Right-Click. Swap Left and Right Click turns it around.
- **Patch Notes** (Settings > Patch Notes): every version's notes since 2.0.0, newest first. Open or close each version, show only what applies to one game, search, and click a setting's path to go straight to it.
- **What's New** now shows only what is new since the version you last saw, with a See All Patch Notes button.
- **ShamanPower's page in WoW's Options window** (Esc > Options > AddOns > ShamanPower): open the settings, the setup tour, What's New or the Discord link from there.
- **Windfury on WoW: Forever:** Windfury Totem is a party buff there now, so the party dots, Totem Coverage and the Totem Range Tracker follow it like Strength of Earth.

### Changes
- **Reset Everything** (top of the Themes tab) puts every setting on the tab back to default. **Reset All Colors and Theme** and **Reset Colors for Current Theme** sit next to it. Both reset buttons keep everything they clear on the Custom card, which now holds your whole look: colors, shapes, gradients, borders and class colors.
- The colors from the other settings pages (pulse bar and flash, Compact outline, background colors, Mana Tint, Ready Reminders) also sit in their section on the Themes tab, and the Themes tab is in the settings search.
- **Border Size** for the Element-Colored Borders, and borders on the cooldown bar's shield and imbue flyouts.
- **Duration Bar Background** (Totem Bar > Duration Bars): turn off the dark track behind the duration bars.
- Shield Charges have their own bar texture, gradient and colors: Bar Texture and Bar Gradient never change them.
- Ready Reminders: Icon Shape and Hide Border.
- **Only Show Pulse Flash for Specific Totems:** the pulse flash gets its own totem list.
- WoW: Forever: the Windfury-only mode is gone, since Windfury Totem is a party buff there.
- The Element Colors cards no longer show hex codes, and the section titles in the settings are easier to spot.

### Fixes
- **Anniversary: Totem of Wrath** is a Fire totem again: its timer, duration bar and cooldown show, and dropping it no longer counts as an Earth totem.
- WoW: Forever: a cooldown shortened or reset mid-fight counts down its real time on the bars.
- Totem Range Tracker: Show Overlay switches off even while the settings preview is open.
- Hovering any part of a settings button shows its tooltip, not only its border.
- Volume sliders move in 1% steps.
- The Duration Bars preview follows Only Show Pulse Bars for Specific Totems.

## v3.0.3 (2026-09-28)

### New
- **Themes** (Settings > General > Themes). Pick a look for all of ShamanPower at once: **Standard** (the look you have today), **ShamanPower** (the logo's element colors, white cooldown text, navy frames, and WoW's own green / yellow / red for counts) or **ShamanPower Minimal** (the ShamanPower colors with flat element-colored boxes and letters in place of the totem icons). A theme sets your existing options, and you can still change any of them on their own page; picking Standard puts your own settings back. Every module has its own section on the Themes tab with a Theme dropdown for each part, so you can mix looks, down to a single dot color. Change anything and your setup is saved as a **Custom** card you can switch back to at any time. Also on the tab: **Element-Colored Borders** for the totem bar, its flyouts and the cooldown bar. Closing settings after a theme change offers a reload. Nothing changes until you pick a theme.
- **ShamanPower's own color picker** for every color option: a color square, hex box, the ShamanPower / Blizzard / Classic palettes and WoW's own colors, with Cancel putting the old color back.
- **Reset All Colors** (Settings > General > Themes): the emergency button. It puts every color in ShamanPower back to how it came, the Standard theme and every color option on every page, then reloads. A Custom look is kept on the Custom card first.
- **Single Totem** (a new Totem Bar Style, both clients). The button shows the totem that is down, like Dynamic, but your assignments never change: a click always drops your assigned totem, and the button goes back to it the moment the dropped totem is gone. Drop a Tremor or Grounding in PvP without losing your set.
- **Hide Blizzard's Totem Timers** (Settings > General > Main): hides the small totem icons and timers WoW shows under your player frame. They come back when you turn it off, or when ShamanPower is switched off.
- **More control over the duration and pulse bars** (Totem Bar > Duration Bars, all at today's look until you change them): Duration Bar Opacity, Pulse Bar Opacity, Pulse Flash Opacity (0% turns the flash off), Pulse Bar Color and Pulse Flash Color, and **Only Show Pulse Bars for Specific Totems** to pick which pulsing totems get a pulse bar. The rows are now called Duration Bar Position, Size and Opacity, and the preview follows them. Pulse Bar Color works with the themes like Cooldown Text Color: a theme sets it, you can still change it, and Standard puts yours back.
- **What's New and the setup tour:** the What's New card shows your bar next to the ShamanPower look (Try it opens the Themes tab, Keep my look changes nothing), and brand-new installs get a "Pick your look" step in the setup tour.
- **Shield Charges: new looks** (all off by default, the plain number stays as it is). Show the shield's icon with the count on it, in the center or small in the bottom-right corner, and/or a charge bar with one segment per charge. **Charge Bar Direction** puts the bar below or above the display, or stands it up on the right or left; with the icon and number off, a vertical bar is a slim bar you can place next to your character. With no shield up the icon is grayed out with a red 0, in combat too; on WoW: Forever the red 0 is left out in combat below 100% opacity, so it never shows through the live count. The setup tour's Shield Charges step has the new options.
- **Cooldown bar: Show Shield Charge Bar** (off by default). The same charge bar along the bottom of the shield button, in and out of combat. **Show Shield Charge Count** (on by default) turns the corner number off, to show just the bar. Both are on the Display tab and in the setup tour's Cooldown Bar step.
- **Effects** (the Effects tab on Totem Bar and on Cooldown Bar, and a new step in the setup tour; all off until you turn them on). A short animation on a button when something happens to it, so you notice it mid-fight: on the totem bar a totem destroyed (with an optional red X until you drop it again), a totem that ran out, and a pulse or glow over a totem's last seconds; on the cooldown bar a cooldown ready again, a weapon imbue gone, and your shield gone. Pick shake, pop, flash or glow for each, or one of 12 more styles (Crumble, Frame blink, Ring draws in, Underline runs out, Frame drains, Bar under it, Shine, Dot, Element flare, Corner flag, Shield burst, Frame blink + flag). Each bar also has an **Effects Look** (Standard, Elemental or Signal) with **Signature Moves** that switch every effect to that look's own styles, and your own picks come back when you turn it off. The preview plays the ones you turn on, and Test buttons play them on your bars. Themes never change your effects. They work in combat; on WoW: Forever, where the game hides the moment a shield goes, the shield button pulses red while no shield is up instead (at 100% cooldown bar opacity).
- **Ready Reminders: Chain Lightning** is in the spell list (off until you switch it on), and **Only In Combat** sits at the top next to Show, to hide the reminders out of combat.
- **Party dots: Only Show Who's Missing** (Party Buff Tracker > Dots & Counters): a class-colored dot only for party members without the totem's buff, so no dots means everyone is covered.
- **Totem Coverage** (WoW: Forever): **Show Dots Instead of Names** (with Dot Position, Size and Outline), **Only Show Who's Missing**, **Show Totem Time Left** in place of the "1 OUT" count, and **Plain Totem Icon** (no dimming or colored outline).
- **Stoneclaw Totem** gets the pulse bar and glow, timed to its taunt every 2 seconds.
- **A little polish on the settings, the setup tour and ShamanPower's pop-up windows:** buttons have depth now (a lit top edge, a shadow, and they sink when you click them), the main button on each page stands out in a stronger blue, and the close X is a clean drawn X that turns into a red square when you point at it.

### Changes
- **Lighter in combat.** Shield Charges now reads your shield only when it actually changed, Reactive Totems only checks your party when a harmful effect could matter, and the combat code makes far fewer temporary tables. In a party in combat, ShamanPower's update loops took about 0.1% of the frame time.
- **License:** ShamanPower is now All Rights Reserved. Please ask me before modifying the code for your own use.
- **Totem Range Tracker: Show the Overlay.** Pick where the overlay may be up: in a group with a shaman (the default), in any group, or always, solo too. It holds for an overlay you opened yourself as well: it steps aside when you leave the group and comes back when you join one, so it no longer sits on screen while you play solo.

### Fixes
- **Totem "Expired" alerts now show in combat on WoW: Forever.** A totem that simply ran out mid-fight never announced itself, because ShamanPower dropped it a moment before the game reported it gone. Destroyed alerts were not affected.
- **Expiring Alerts in raids:** far less work on every buff change. It used to read all of your buffs (and your Earth Shield target's) on each aura event; now it only reads when the change could involve a shield.
- **Earth Shield fade alerts** no longer go missing when the raid moves your Earth Shield target to another slot, or after switching ShamanPower off and back on.
- **No false "Lightning Shield FADED!" at the start of a fight** on Forever.
- **A totem picked from a flyout mid-fight** now shows everywhere on the bar right away (icon, tooltip, cooldown, Compact and Grid marks, keybind text, mana tint), stops flickering back to the old one, and is saved even if something goes wrong as the fight ends.
- **Anniversary:** a totem picked mid-fight for an element with nothing assigned now casts from its button.
- **TotemTimers Style with Empty assigned:** a running totem shows as the big icon instead of being covered by the empty-slot art.
- **Bar frames** grow to wrap the flyout arrows in combat, so nothing sticks out past the frame.
- **Totem flyouts after switching loadouts** are sorted around the new totems straight away; the first hover used to show the old layout, with gaps.
- **Tremor Totem's pulse timer on WoW: Forever** follows its real 4-second pulse (it was timed at 3, as on Anniversary).
- **Ready Check** (WoW: Forever): casting Fire Nova with no Fire totem down no longer warns that your Fire Totem is missing from your bags.
- **No more BugSack errors** from hovering the bars and party frames in combat on WoW: Forever.
- **Dragging a slider in the settings no longer slows the whole game.** Every step of a drag used to redraw the entire settings page and its preview; now the setting follows the drag smoothly and the page catches up when you let go. Percentage sliders also move in 1% steps instead of 5%.
- **Settings > Totem Bar > Style:** the old on/off switches for each style (Compact Style, Dynamic Mode, Grid Style, Use Blizzard's Totem Bar, TotemTimers Style Display) are gone; the Totem Bar Style dropdown does it. Blizzard's Totem Bar keeps TotemTimers Style Display, where it is still its own option.
- **TotemTimers Style flyouts** no longer show a gap or a button sitting under another after you drop a totem with the flyout still open; they redraw straight away.
- **Cooldown bar flyouts** offer a weapon imbue or shield as soon as you learn it at the trainer, instead of after a /reload (the bar rebuilds itself, after the fight if you are in one).

## v3.0.2 (2026-09-26)

### Fixes
- **Cooldown bar shield key** (WoW: Forever): I'm working on reports that your action-bar key for Lightning or Water Shield stops casting. With Blizzard-Style Flyout Arrows and Swap Left and Right Click both on, ShamanPower routed that key to the wrong click of its shield flyout, so it cast nothing; it now presses the right one, and weapon imbue keys go to the main hand again. If your shield key still misbehaves, please tell me on the Discord.

## v3.0.1 (2026-09-26)

### New
- **Hover flyouts on WoW: Forever.** The totem, cooldown bar and loadout flyouts open when you hover the button, in combat too, exactly like Anniversary. No arrows to click.
- **Blizzard-Style Flyout Arrows** (Forever, off by default). Prefer the click-to-open arrows of Blizzard's totem bar? Turn this on under Settings > Bars > Appearance > Flyouts > Shared Look, then reload.
- **Empty Totem in Flyouts** (Forever) works with the hover flyouts and now sits on Totem Bar > Style. Pick Empty, in or out of combat, to leave an element with no totem so Call of the Elements skips it; turn the toggle off to keep it out of your flyouts.
- **Setup tour and settings preview** (Forever): the Blizzard's Totem Bar style shows Blizzard's flyout arrows, and the tour's pretend cursor plays how Blizzard's flyout opens (arrow, pick, close) next to ShamanPower's hover.

### Fixes
- **Assigning a totem from a flyout in combat now really assigns it** (both clients). The right-click changed the button's icon, but the button kept casting the old totem until the fight ended. It now casts the new one straight away, and on Forever Blizzard's totem bar follows too, so Call of the Elements drops it.
- No more gap between the loadout flyout's buttons.
- Importing a setup code only ever writes ShamanPower's own settings.
- Players updating straight from 2.x now see the 3.0 What's New card; anyone who saw it at 3.0.0 is not shown it again.

## v3.0.0 (2026-09-25)

### New
- **WoW: Forever support.** ShamanPower runs on the Forever beta from the same download as Anniversary. Where the game hides combat data from addons, the game itself draws the totem timers and countdown numbers, the party buff dots, the reactive and expiring alerts and the cooldown sweeps, so they keep working in combat. Spells that do not exist on Forever (Earth Shield, Bloodlust / Heroism, Drums of Battle, Totem of Wrath, Wrath of Air, the Elementals, Fire Nova Totem) are hidden everywhere: pages, previews, dropdowns, assignments, Auto-Assign. Forever characters start with the setup tour, which has a WoW: Forever step and a Totem Sets step.
- **Blizzard's totem bar as a style** (Forever). Settings > General > Main > Totem Bar Style, or Totem Bar > Style: keep the game's own bar and get ShamanPower's timers, duration bars, text, pulse bars, party dots and counters on its slots, with an optional scale override. Picking a totem on Blizzard's bar sets your assignment, and the other way round.
- **Totem sets** (Forever). Call of the Elements always holds your assignments. Ancestors and Spirits can each take a saved loadout (Loadouts > Loadouts > Set Page); that loadout's bar button then casts the set in one press. Drop All can cast the set.
- **Grid style** (both clients). Every totem of every element visible in rows: click to drop, the assigned one highlighted, the timer on the dropped one. "Split by Element" makes each row its own movable frame with its own direction.
- **Totem Bar Style in one place.** Settings > General > Main has a dropdown with every style (Normal, TotemTimers, Dynamic, Compact, Grid, and Blizzard's bar on Forever). Hovering a style there, or on Totem Bar > Style, shows it in the live preview without changing anything. The setup tour shows the styles as cards with a picture each; hovering a card plays it in the preview.
- **Totem Coverage** (Party Buff Tracker, Forever). The reverse of Totem Range: under each of your totems, the names of party members who do NOT have its buff, red or class color. Per-totem placement and sizes; choose which totems to watch; hides itself once everyone is covered, in combat too.
- **Minimap totem markers** (Forever, open world). A pin where each totem was dropped with a ring for its reach, turning with the minimap. Totem Range Tracker page. Off inside instances.
- **Auto-Assign picks by who is in the group.** Stoneskin for caster-only groups, Strength of Earth with melee; Mana Spring with mana users, else Healing Stream; the Air totem by who benefits. This changes what Anniversary players get from Auto-Assign too.
- **Live preview pane** in the settings window (arrow tab on the right): every module page shows its frames with your current settings, updating as you change them. The Loadouts page previews the bar and, on Forever, the three set pages.
- **Every window from its page.** Totem Range picker, Totem Coverage, Raid Cooldowns assignments, the fear-caster mob list, Totem Assignments: one button on the module's page, and every option those windows hold is on the page too. Test buttons hide the settings window while they run and bring it back after.
- **Ready Reminders** (new module). Placeable icons that light up when a spell comes off cooldown: shocks, Stormstrike, Lava Burst, Riptide, Rage of the Farseer, Nature's Swiftness, Mana Tide, Grounding, Earthbind and more. Show only when ready, always, or always dimmed with a countdown. On by default on Forever; **off by default on Anniversary** (Alerts & Reminders > Ready Reminders, or the setup tour, turns it on). On Forever each character keeps its own list, and the setup tour's spec pick fills it from Forever's talent tree.
- **Fonts** (both clients). Settings > General > Fonts & Textures: pick the font and outline for every number and label ShamanPower draws on screen, or give timers, shield charges, alerts and names their own. Uses WoW's fonts plus every font other addons share through LibSharedMedia (ElvUI, SharedMedia and the like). Hover a font in the list to preview it on your frames. Default keeps the designed look.
- **Bundled fonts and sounds.** Ten fonts (Barlow Condensed, Bebas Neue, Black Ops One, Chakra Petch, Fira Sans, Oxanium, Rajdhani, Russo One, Saira Semi Condensed, Teko; SIL Open Font License) and seven ShamanPower alert sounds (Totem Chime, Shield Pop, Ready Ping, War Horn, Water Drop, Earth Thud, Thunder) in every font and sound list, also for other addons that use LibSharedMedia.
- **Bar textures** (both clients). Settings > General > Fonts & Textures: pick the texture of every bar ShamanPower draws (totem duration bars, cooldown bar, pulse sweeps), or give each its own, from WoW's bar, ShamanPower's four and every texture other addons share. Hover to preview on your bars. **Apply This Look Everywhere** puts your chosen font, outline and texture on everything at once, Compact's lines included; **Reset Look** goes back to the designed look.
- **Mana tint** (option, Appearance > Textures & Colors): totem, flyout and cooldown buttons turn blue while you cannot afford them, like Blizzard's action bars. Color of your choice.
- **Minimap quick menu:** right-click the minimap icon to switch totem bar style, apply a loadout, open assignments, Unlock UI, Keybind Mode, What's New or settings. Shift-right-click opens settings straight away.
- **Raid resistance requests** (Forever). On Forever, Fire, Frost and Nature Resistance totems reach the whole raid. Tick Need Fire / Frost / Nature Resistance in the assignments window (any shaman, or the raid leader or an assistant) and ShamanPower asks the one shaman whose group loses least; they Accept or Pass, or it applies at once with Free Assign or auto-accept. Nobody can change another shaman's totems without that. Unticking gives their old totem back. Loadout Auto-Switch zone and boss rules can request one. `/sp resisttest` practises the whole flow alone.
- **Call of the Elements / Ancestors / Spirits in combat** (Forever): every totem a set places now shows its icon, timer and pulse mid-fight.
- **Ready Reminders follow the real cooldown in combat** (Forever): the icon brightens or appears exactly when the spell is ready, even when the addon's estimate lags.
- **Loadout Auto-Switch** (Loadouts > Auto-Switch, off by default). Pick a loadout for raids, dungeons, battlegrounds and the open world (or go back to the one you had when you leave an instance), and add rules like an equipment manager: loadout + zone + the mob you target (Blackwing Lair + Firemaw -> Fire Resist) or a boss encounter. Never switches in combat; a switch that comes up in a fight happens as soon as it ends. On Forever, target rules only work in the open world (the game hides mob names in instances).
- **Cooldown Announce** (Group Tools > Cooldown Announce, all off by default): announce Mana Tide (and Bloodlust / Heroism where they exist) when used and a set time before it is back, even in combat on Forever; answer "tide" and your own trigger words in group chat with ready / seconds left (throttled); optionally show the Mana Tide call on your own screen when a group member asks. Chat is never read or sent while the game has chat locked down.
- **Ready Check sweep** (both clients). On a ready check (optionally on entering a dungeon or raid, or with /sp check) ShamanPower lists what you are missing: shield, weapon imbue, totem items in your bags (Forever), assigned totems not down, low mana. Pick what it checks and how it shows it: an on-screen list with icons, a line in your chat window, a sound. On Forever it also warns when one of your totem items leaves your bags.
- **Keybind mode.** /sp bind, or Settings > General > Keybind Mode: every ShamanPower button that can take a key lights up with its current key. Hover one and press a key (Shift, Ctrl and Alt work) to bind it; Escape over a button clears its key. Done saves, Cancel puts every key back. Out of combat only.
- **Trainer Reminder** (Forever, Alerts & Reminders > Trainer Reminder). When you level up, ShamanPower lists the shaman spells and ranks now waiting at your trainer (and anything you skipped earlier), with one summary line at login. Only you see it; a big on-screen note is optional.
- **Fade rules** for the totem bar (Appearance > Visibility, off by default). With Hide Out of Combat or Hide When No Totems on, the bar can fade to an opacity you choose instead of disappearing, and can come back while you target something attackable. Fading is only a change of opacity, so it also works in combat.
- **Share My Setup** (General, /sp share, or the end of the setup tour): a short code listing which ShamanPower features you use - nothing personal - to paste in #setup-stats on the ShamanPower Discord, so the developer can see what people actually use. ShamanPower now also remembers how your setup ended (tour, quick setup, skipped).
- **Unlock UI (move everything).** One button (General > Main, or `/sp unlock`) shows a labelled box on every frame ShamanPower draws; drag them, put each back with its own Reset (all but the Party Range counters, the Totem Range overlay, the Raid Cooldown callers and the Earth Shield tracker), and snap to an optional alignment grid.
- **ShamanPower Discord** on General: help, bug reports, feature voting and early builds. Copy Link button.
- **Loadouts:** the bar has a Move button (Loadouts > Loadout Bar) and a box in Unlock All; a loadout's chosen icon shows on its button; the icon picker is rebuilt on the settings look with a search box.
- **Loadout bar:** hover the button for a flyout of your other loadouts (one column, names beside each), or turn on Click the Button to Cycle Loadouts (Loadouts > Loadout Bar) to step through them by clicking (right-click: previous), with the flyout optionally off. Each loadout keeps its own Drop All exclusions (Exclude Earth / Fire / Water / Air on its Loadouts entry): switching swaps them in, and Call of the Elements follows on Forever.
- **Raid call practice:** `/sp calltest` makes a shaman take Mana Tide calls (from a caller button or someone typing "tide") as if it knew Mana Tide, so the whole flow can be tried at any level.
- **Settings, reorganized.** The sidebar reads General, Bars, Group Tools, Alerts & Reminders and Other. Totem Bar holds Style, Clicks, Bar, Items, Order, Drop All, Duration Bars, Flyouts and Macros (and Twisting on Anniversary); Loadouts is its own page (Loadouts, Loadout Bar, Auto-Switch); Party Buff Tracker splits into Dots & Counters and Coverage; every module page reads in one order (on/off, what it shows, look, behavior, sound, position, test and reset). Search still finds every setting, and every "open settings" link lands on its new page.
- **Enable ShamanPower turns the whole addon off** (General > Main): no bars, alerts, sounds, chat, addon messages or key bindings, and Blizzard's own totem bar comes back, while every setting stays open to change. The minimap icon stays; any click on it offers Turn ShamanPower Back On. A switch made in combat lands when the fight ends.
- **Srumar's Layout for WoW: Forever.** The one-click layout has its own Forever capture with Forever's options; Anniversary keeps its own. After it reloads, ShamanPower offers once to move everything into place.
- **Enable Raid Cooldowns** (Group Tools > Raid Cooldowns), and on/off squares in the sidebar for Raid Cooldowns and Raid Resistance.

### Changes
- Compact style has a new look and defaults; a Compact profile already in use keeps its old look.
- Element color palettes, flyout sizes separate from the bar, and a reset for each settings section.
- Settings window: sizes and opacity show as percentages, long labels wrap instead of being cut off, inputs fit their values, and search highlights the right tab.
- **First login is a small choice, not the whole tour:** take the setup tour, or use Srumar's setup in one click (your spec is read from your talents, or asked when you have none yet). Other classes get the quick tour or Windfury-only mode. "Not now" asks again next login; the tour is always at /sp setup.
- The setup tour has spec cards listing what each pick sets up, a Ready Reminders step and a Position step that moves every frame. Picking a spec only sets starting defaults on a brand-new install.
- Non-shamans get a short tour and a settings list with only what runs for them (Totem Range, Raid Cooldowns, Totem Plates, the Earth Shield tracker, and the Windfury Companion on Anniversary). Tremor Reminder, Shield Charges, Ready Reminders, Expiring Alerts and Reactive Totems no longer load on other classes.
- **Windfury-only mode** for non-shamans: one button on their setup screen (or General > Windfury-Only Mode) turns off every window, bar, icon and nameplate, and keeps only the report that tells the group's shamans whether their weapon has Windfury. That report now runs whenever a shaman is in your party, even with the Totem Range overlay closed, and goes only to your own party (your subgroup in a raid), when it changes plus every 6 s, instead of to the whole raid every 2 s.
- What's New opens by itself once per release on a shaman; any character can open it from the settings header.
- The /spthanks auto-whisper is gone (it was off by default; automated whispers read as spam).
- Reactive Totems: the old configuration window is gone; everything is on its settings page. Optional debuff icon (Forever).
- A new setup starts with the totem bar low in the middle of the screen and the cooldown bar straight under it; the totem bar's Reset in Unlock UI puts both back there.
- A saved sound that no longer exists plays Raid Warning instead of nothing.
- The flyout keybindings are for Forever's click-to-open flyouts; on Anniversary they are labelled as such and do nothing.
- Totem cooldown numbers use the game's own countdown on Forever; ShamanPower turns the game option on for you.
- "Totemic Call" reads "Totemic Recall" where the game names it so.
- The Earth Shield column, tracker and options do not appear on a client without Earth Shield.
- Settings text says "ShamanPower's bar" and "Blizzard's bar" throughout.
- Raid Resistance has its own entry in the settings sidebar (it was the tenth Totem Bar tab); tab rows wrap instead of running off the window; the What's New button sits on General > Main only.
- Loadout totem pickers mark totems your character has not learned yet; the Set Page picker appears once Call of the Ancestors or Call of the Spirits is known; the Blizzard sets preview lists totems in Blizzard's order (Earth, Fire, Water, Air) and shows ones left out of Drop All dimmed.
- Every chat line ShamanPower prints starts with the same blue ShamanPower.
- Ready Check: the weapon imbue line shows the Windfury Weapon icon; the sound has a Test Sound button.
- Every totem bar style keeps its own spot, as Compact did: move Grid into a corner and Normal, TotemTimers and Dynamic stay where you put them. A style you have never moved starts where the Normal bar is.
- Windfury-only mode keeps the minimap icon; its right-click menu then has one entry, Turn On Other Features.
- New installs start with both bars running across (Horizontal) and no frame or border behind the totem bar, cooldown bar, caller buttons, Earth Shield tracker or range tracker, whether you take the setup tour or skip it. Profiles you already have keep the look they had.
- Totem twisting is not offered on WoW: Forever: its Windfury Totem is an aura there and no longer stacks with Grace of Air or Tranquil Air. Anniversary keeps twisting.
- In a fight, pulse bars, duration bars and their numbers, party dots, the dropped-totem icon and the cooldown bar's shield and imbue bars move out past the flyout arrows instead of hiding behind them, and back when it ends.
- Setup tour: gold step headings and style names; Layout, Size and the frame come first on the totem bar and cooldown bar steps; the Ready Reminders preview is a life-size grid.
- Minimap menu: Open Settings (and Turn ShamanPower Back On) are gold.

### Fixes
- Party buff dots drawn by the game were never built on Forever; they are now.
- The loadout bar could not be moved from the settings, and the game's layout cache kept putting it back where an old drag left it.
- Idle CPU and garbage: loops now sleep until a totem, cooldown or aura actually changes, and party and shield buff checks are cached until the buffs change (both clients). On Forever the weapon-imbue and spell lookups, which build a new table per call there, are cached too.
- **Built for 40-player raids:** ShamanPower's core now only listens to the units it uses (your casts; your and your party's buffs; your Earth Shield target) instead of every raid member and nameplate; the Earth Shield tracker re-reads only the player whose buffs changed; Raid Cooldowns watches the shamans' casts instead of the whole combat log; received messages no longer redraw the totem bar unless they change it; a shaman leaving the raid no longer sets off a flood of replies (which could hold up raid calls for half a minute); raid calls go out on their own channel at high priority; other addons' messages cost a single comparison.
- **Smoother and cheaper animations:** totem pulse bars, the raid-call alert, the cooldown bar alert and the new fades run as game-engine animations instead of Lua every frame; Totem Plates' pulse timers and the Anniversary imbue check stop running every frame.
- **/spperf stress** pretends to be a 40-player raid (buffs, casts, addon messages, roster changes) so the cost can be measured solo.
- Newly trained totems appear in the flyouts without a reload; the cooldown bar keeps a custom order when a spell is unavailable.
- Expiring Alerts: "Totem Destroyed" now works in combat on Forever (from ShamanPower's own record of your totems, which the game cannot hide), and can also add a line to your own chat window (on by default on Forever, only you see it), show big text on your screen, or tell your group in chat.
- Tremor Reminder "Hide When Tremor Active" never hid in combat on Forever.
- Expiring Alerts: totems that died in combat were announced minutes later with stale timing on Forever.
- Wrath of Air, Totem of Wrath and Fire Nova Totem could be assigned, tracked or listed on a client that lacks them.
- Flametongue Totem's party buff did not match on Forever (spell 8215 is "Rapid Cast" there).
- **Names:** on Forever players are matched by name alone (the realm part the game reports can differ between players), and two-part names ("First Last") stay whole in assignments, twisting, Earth Shield assignments, leader checks and Windfury reports. On Anniversary, Windfury reports and a shaman's own assignments from another realm (battlegrounds) now arrive. `/spdiag names` shows what the game reports and the names ShamanPower uses.
- The cooldown bar's raid-call alert (glow and icon pulse on a Mana Tide or Bloodlust call) never showed; it does now, and a repeat call keeps it going.
- Pulse bars stayed invisible after Pulse Bar Position had been set to None and back, until a /reload.
- Assignments, twisting and Earth Shield targets set while the game blocks addon messages (Forever instance fights) are sent to that group once it lifts, instead of never; leaving the group first drops them.
- **Forever surnames:** the game gives a character's first name and surname separately; ShamanPower now joins them as the game's own interface does, so you no longer appear twice in the assignments window ("Srumar" and "Srumar Bagels") and raid calls addressed to you are recognised.
- **"Unknown" on a cold login** (Forever): when the game had not given the character's name yet as addons loaded, ShamanPower and its settings filed that session under a character called "Unknown" (assignments, learned totem lengths, per-character profile). It now waits for the real name and moves anything written meanwhile.
- "Totem Destroyed" in combat knows every totem's length from its first drop (a table read from Forever's spell data) instead of learning it out of combat first.
- The loadout bar's flyout never opened on Forever.
- Grid: turning Split by Element off stacked the rows on each other until the next click.
- A totem assigned with right-click during a fight counts at once: the dropped-totem icon showed the same totem twice, or none, until the fight ended.
- Applying Srumar's Layout replaced your saved loadouts with the author's; a shared layout never touches your loadouts now.
- Changing the totem bar style could raise a Lua error from the Compact option.

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
