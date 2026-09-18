# Isolated saved-variable probes

These temporary addons diagnose the Forever beta settings-restoration problem.
They do not depend on or modify ShamanPower, AceDB, client settings, or other
addons' saved variables.

Metadata is copied from the installed ShamanPower_Mainline.toc:
Interface 120100, 16001; Version 2.1.1; Author Srumar; shaman icon.
The base TBC TOC's 20506 interface is intentionally not used for this beta test.
X-Probe-Version separately identifies this diagnostic revision as 1.

## The comparison

- SPSaveNormal owns SPSaveNormalDB and uses the default load order.
- SPSaveEarly owns SPSaveEarlyDB and declares LoadSavedVariablesFirst: 1.
- Probe.lua is identical in both addons. No saved table is created at file scope.
- Each has a single unsuffixed TOC to avoid client-flavor selection ambiguity.
- Neither declares a dependency or shares a saved-variable name with any addon.

## In-game test

1. Reload once to discover and load both addons. If chat shows neither probe,
   enable "SP Save Test - Normal" and "SP Save Test - Early" in the AddOns list.
2. The first session normally prints boot=nil->1 for both.
3. Reload a second time without completing ShamanPower's setup wizard.
4. Copy the two SPSaveNormal / SPSaveEarly lines from chat.
   /spsavenormal and /spsaveearly repeat their respective lines without changing data.

Interpret the SECOND load, not the first:

- Both advance to boot=1->2: basic persistence works for isolated addons.
  ShamanPower-specific causes still need investigation.
- Only Early advances: loading saved variables early is a candidate workaround.
- Neither advances: the failure also affects isolated, single-variable addons.
  This does not alone distinguish a client defect from an environment/path issue.
- Only Normal advances: the early-loading path is the failing variant.
- sameDB=no: the client replaced the saved table after our initialization;
  the printed counter belongs to the table observed at ADDON_LOADED.

loaded=yes means a table existed at the addon's ADDON_LOADED event.
file=yes means it existed before Probe.lua executed (expected only for Early
on subsequent successful loads). previousLogout=yes confirms a previously saved
logout marker returned, not merely a table allocated earlier this session.

A successful counter does not prove that ShamanPower's settings are fixed.
These probes do not restore any backed-up ShamanPower settings.

## Files and cleanup

Source copies are in tools/SPSaveNormal and tools/SPSaveEarly.
Matching copies are installed only in _classic_beta_/Interface/AddOns.
Disable both probe addons when testing is finished. They write only
SavedVariables/SPSaveNormal.lua and SavedVariables/SPSaveEarly.lua (plus the
client-created backups). Do not remove any ShamanPower saved-variable files.

## Offline checks

From the ShamanPower repository:

    luajit tools/tests/save-probes.lua

The harness simulates missing and restored data, both load orders, event
filtering, repeat reports, and late database replacement. A real beta reload
is still required to establish the client's actual behavior.

## Follow-up: declaration count and duplicate ownership

SPSaveMulti and SPSaveShare each declare eight variables. Their declaration
values are exactly 205 characters, matching ShamanPower's list after replacing
only the 11-character addon prefix. Both use normal loading and identical Lua.

- SPSaveMulti: all eight names are unique to that addon.
- SPSaveShare: two names are also declared by SPSaveShare_RaidCooldowns and
  SPSaveShare_SPRange. Those helpers depend on SPSaveShare, just like the real
  modules. Their Lua does nothing; only the client can replace those tables.

Leave the original Normal/Early controls enabled. Reload twice, then capture
the SPSaveMulti and SPSaveShare lines. Shared must report owners=2/2 for the
duplicate-ownership comparison to be valid. /spsavemulti and /spsaveshare repeat
the reports without changing the counters.

On a successful second load, DB and log advance from 1 to 2 with loaded=8/8.
replaced=5,6 in the Shared test can be normal: the dependent addons load their
copies of those two shared tables later. That alone does NOT explain a reset
of the distinct DB and ErrorLog tables. A failure of those distinct counters,
only in the Shared variant, would make duplicate ownership a stronger suspect.

If Multi fails too while the single-variable controls work, the eight-variable
declaration is implicated; a further test would separate count from line length.
If both new probes work, neither of these differences alone reproduces the bug.
These tests do not assume that every account-wide saved-variable file fails.

Run the additional offline harness with:

    luajit tools/tests/save-declarations.lua

The four follow-up addons own only SPSaveMulti* and SPSaveShare* variables.
No production ShamanPower variables, code, or settings are modified.
