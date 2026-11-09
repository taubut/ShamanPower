-- client: both
-- (3.0.9.9) Low-Mana Tint on Totem Rows (a Discord report: TotemTimers Style, the bar tinted, the
-- rows not). With Keep Flyouts on Main Totem Bar the rows are copies of the flyouts' buttons: a totem
-- you can't afford is tinted there too, a copy made after the tint as well. Mana back, or the tint
-- switched off: no tint anywhere.
local SP = ShamanPower
local A, W = __sim.A, __sim.W
if not (SP.UpdateManaTint and SP.SetTotemRows and SP.RowsCopies) then skip("no Low-Mana Tint or Totem Rows here") end
local was = { style = SP:GetTotemBarStyle(), rows = SP.opt.totemRows, keep = SP.opt.rowsKeepFlyouts, tint = SP.opt.manaTint }

local function counts()
	local tinted, total = 0, 0
	for e = 1, 4 do
		for _, c in ipairs(SP:RowsCopies(e) or {}) do
			if c:IsShown() and c.icon and c.totemIndex ~= 0 then
				total = total + 1
				local r, g = c.icon:GetVertexColor()
				if r < 0.9 and g < 0.9 then tinted = tinted + 1 end
			end
		end
	end
	return tinted, total
end
local function barTinted()
	local b = SP.totemButtons and SP.totemButtons[1]
	local r = b and b.icon and b.icon:GetVertexColor()
	return r ~= nil and r < 0.9
end

SP:SetTotemBarStyle("totemtimers")
SP.opt.rowsKeepFlyouts = nil
SP:SetTotemRows(true)
__sim.advance(0.3)
SP.opt.manaTint = true
for id in pairs(A.spells) do A.noMana[id] = true end   -- every spell: not enough mana
W.fireEvent("SPELL_UPDATE_USABLE"); __sim.advance(0.2)
check("the bar is tinted", barTinted())

-- Keep Flyouts on now: the copies are made after the tint ran, and get it with no event
SP.opt.rowsKeepFlyouts = true
SP:RefreshRowsStyle(); __sim.advance(0.3)
local tinted, total = counts()
check("Keep Flyouts: the rows are copies", total > 0)
checkEq("Keep Flyouts: every copy tinted", tinted .. "/" .. total, total .. "/" .. total)

-- mana back: the tint goes from the copies too
for id in pairs(A.noMana) do A.noMana[id] = nil end
W.fireEvent("SPELL_UPDATE_USABLE"); __sim.advance(0.2)
tinted = counts()
checkEq("mana back: no copy tinted", tinted, 0)
check("mana back: the bar untinted", not barTinted())

-- short again, then the tint switched off
for id in pairs(A.spells) do A.noMana[id] = true end
W.fireEvent("SPELL_UPDATE_USABLE"); __sim.advance(0.2)
tinted = counts()
check("short again: the copies tinted", tinted > 0)
SP.opt.manaTint = nil; SP:UpdateManaTint(); __sim.advance(0.2)
tinted = counts()
checkEq("tint off: no copy tinted", tinted, 0)

-- put back
for id in pairs(A.noMana) do A.noMana[id] = nil end
SP.opt.manaTint = was.tint
SP.opt.rowsKeepFlyouts = was.keep
SP:SetTotemRows(was.rows)
SP:SetTotemBarStyle(was.style or "normal")
__sim.advance(0.3)
finish()
