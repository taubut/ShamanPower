-- ShamanPower_Config / Styles.lua
-- Style pictures and captions. The pictures are small schematic drawings of
-- each totem bar style made of plain textures: nothing to ship, no live frames
-- borrowed, cheap enough to draw six of them on one page. The setup tour's
-- style cards and the what's-new card use them; the captions sit next to the
-- live mocks so every surface describes a style with the same words.
local _, ns = ...
local Core = ns.Core
local SP = ShamanPower
if not (Core and SP) then return end

-- Earth, Fire, Water, Air - the bars' own element colours.
local ELE = { { 0.72, 0.52, 0.32 }, { 1.00, 0.36, 0.22 }, { 0.42, 0.58, 1.00 }, { 0.86, 0.88, 0.98 } }
local QUICKSLOT = "Interface\\Buttons\\UI-Quickslot2"   -- the game's own action button ring

ns.StyleCaptions = {
	normal = "Your assigned totems stay on the bar. Drop a different totem and it appears above its slot while the assigned one greys out until it expires.",
	totemtimers = "The dropped totem takes over the big icon and your assigned totem shrinks into the bottom-right corner until it expires.",
	dynamic = "The bar simply becomes whatever you last dropped - one totem per slot, nothing else. Great for PvP.",
	compact = "No icons: each slot is a colored line. The outline drains with the totem's duration and the pulse refills inside the line. Tiny icon squares are optional. Clicks and flyouts are unchanged.",
	grid = "Every totem of every element stays visible in rows. Click one to drop it; the assigned one is highlighted"
		.. " and the dropped one carries the timer. Split by Element (Totem Bar Style > Style Options)"
		.. " gives each row its own frame.",
	blizzard = "ShamanPower's bar hides and you play on Blizzard's own totem bar. ShamanPower draws its timers, duration bars, pulse and party dots on Blizzard's slots; you pick totems with Blizzard's flyout.",
}

local function Box(parent, x, y, w, h, r, g, b, a, layer, sub)
	local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub or 0)
	t:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
	t:SetSize(math.max(1, w), math.max(1, h))
	t:SetColorTexture(r, g, b, a or 1)
	return t
end

-- One slot: dark plate with an element-tinted face; dim = the greyed assigned totem.
local function Slot(parent, x, y, s, c, dim)
	Box(parent, x, y, s, s, 0, 0, 0, 0.75, "ARTWORK", 0)
	local k = dim and 0.4 or 0.85
	Box(parent, x + 1, y + 1, s - 2, s - 2, c[1] * k, c[2] * k, c[3] * k, 1, "ARTWORK", 1)
end

-- Draw the picture for a style into a new w x h frame on parent. The caller
-- anchors it. Unknown keys draw the plain four-slot bar.
function ns.DrawStyleThumb(parent, key, w, h)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(w, h)
	Box(f, 0, 0, w, h, 0, 0, 0, 0.55, "BACKGROUND")
	Core:MakeBorder(f, "borderSoft")
	local FILL = { 1, 0.55, 0.8, 0.3 }   -- how far each element's timer has run
	if key == "compact" then
		-- four stacked lines, each drained by a different amount
		local n, gap = 4, 3
		local lh = math.floor((h - 8 - gap * (n - 1)) / n)
		local lw = w - 12
		for i = 1, n do
			local y = 4 + (i - 1) * (lh + gap)
			local c = ELE[i]
			Box(f, 6, y, lw, lh, 0, 0, 0, 0.7, "ARTWORK", 0)
			Box(f, 7, y + 1, (lw - 2) * FILL[i], lh - 2, c[1], c[2], c[3], 1, "ARTWORK", 1)
		end
	elseif key == "grid" then
		-- four element columns, three totems each, spread across the picture so it
		-- fills the box like the other styles; the top one of each is the assigned one
		local rows, cols, vgap = 3, 4, 2
		local s = math.floor((h - 6 - vgap * (rows - 1)) / rows)
		local hgap = math.floor(math.min(s * 1.6, (w - 12 - cols * s) / (cols - 1)))
		local x0 = math.floor((w - (cols * s + (cols - 1) * hgap)) / 2)
		local y0 = math.floor((h - (rows * s + (rows - 1) * vgap)) / 2)
		for c = 1, cols do
			for r = 1, rows do
				Slot(f, x0 + (c - 1) * (s + hgap), y0 + (r - 1) * (s + vgap), s, ELE[c], r ~= 1)
			end
		end
	else
		-- four slots in a row; what the style does shows on the second one
		local n, gap = 4, 4
		local s = math.floor(math.min(h * 0.6, (w - 12 - gap * (n - 1)) / n))
		if key == "normal" then s = math.floor(math.min(s, (h - 9) / 1.7)) end   -- room for the pop-up above
		if key == "blizzard" then s = math.floor(math.min(s, h * 0.5)) end        -- room for the ring and the bar
		local x0 = math.floor((w - (n * s + (n - 1) * gap)) / 2)
		local y0 = (key == "normal") and (h - s - 3) or math.floor((h - s) / 2)
		for i = 1, n do
			local x = x0 + (i - 1) * (s + gap)
			local c = ELE[i]
			local second = (i == 2)
			if key == "normal" then
				Slot(f, x, y0, s, c, second)
				if second then   -- the dropped totem pops up above its slot
					local o = math.floor(s * 0.7)
					Slot(f, x + math.floor((s - o) / 2), y0 - o - 2, o, c)
				end
			elseif key == "totemtimers" then
				Slot(f, x, y0, s, c)
				if second then   -- the assigned totem shrinks into the corner
					local b = math.max(4, math.floor(s * 0.42))
					Box(f, x + s - b - 1, y0 + s - b - 1, b + 1, b + 1, 0, 0, 0, 0.9, "OVERLAY", 0)
					Box(f, x + s - b, y0 + s - b, b - 1, b - 1, 0.95, 0.95, 0.95, 1, "OVERLAY", 1)
				end
			elseif key == "blizzard" then
				Slot(f, x, y0, s, c)
				local ring = f:CreateTexture(nil, "OVERLAY", nil, 1)
				ring:SetTexture(QUICKSLOT)
				ring:SetPoint("CENTER", f, "TOPLEFT", x + s / 2, -(y0 + s / 2))
				ring:SetSize(s * 1.7, s * 1.7)
				-- ShamanPower's timer bar under Blizzard's slot
				Box(f, x, y0 + s + 2, s, 2, 0, 0, 0, 0.7, "ARTWORK", 0)
				Box(f, x, y0 + s + 2, s * FILL[i], 2, c[1], c[2], c[3], 1, "ARTWORK", 1)
			else   -- dynamic: the slot is simply whatever was dropped
				Slot(f, x, y0, s, c)
			end
		end
	end
	return f
end
