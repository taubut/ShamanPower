-- ShamanPower_Config :: Tree
-- Reads the existing AceConfig-3.0 option table (ShamanPower.options) and
-- turns it into a flat render list. Nothing in ShamanPowerOptions.lua changes;
-- this module only consumes it.
--
-- AceConfig semantics reproduced here:
--   * get/set/func/disabled/hidden/handler inherit from ancestor groups
--   * any of those may be a function(info) or a string naming a handler method
--   * children sort by numeric `order` (default 100), ties broken by name
--   * `inline` groups render as a section header plus their children

local ADDON, ns = ...

local Tree = {}
ns.Tree = Tree

local INHERITED = {
	handler = true, get = true, set = true, func = true,
	disabled = true, hidden = true, confirm = true,
}

-- ---------------------------------------------------------------------------
-- Root access
-- ---------------------------------------------------------------------------
function Tree:Root()
	return ShamanPower and ShamanPower.options or nil
end

-- Walk a path array from the root, returning the node and the chain of
-- ancestors (root first) so inherited properties can be resolved.
function Tree:Resolve(path)
	local node = self:Root()
	if not node then return nil, nil end
	local chain = { node }
	for i = 1, #path do
		local args = node.args
		if not args then return nil, chain end
		node = args[path[i]]
		if not node then return nil, chain end
		table.insert(chain, node)
	end
	return node, chain
end

-- ---------------------------------------------------------------------------
-- info table -- what AceConfig get/set callbacks receive
-- ---------------------------------------------------------------------------
function Tree:BuildInfo(path, node, chain)
	local info = {}
	for i = 1, #path do info[i] = path[i] end
	info.options = self:Root()
	info.option  = node
	info.type    = node and node.type
	info.uiType  = "dialog"
	info.uiName  = "ShamanPower_Config"
	info.arg     = node and node.arg
	info.handler = self:Inherited(chain, "handler")
	return info
end

-- Last value defined for `key` anywhere along the ancestor chain.
function Tree:Inherited(chain, key)
	if not chain then return nil end
	local found
	for i = 1, #chain do
		local v = chain[i][key]
		if v ~= nil then found = v end
	end
	return found
end

-- ---------------------------------------------------------------------------
-- Value evaluation
-- A property may be a literal, a function(info, ...), or a string naming a
-- method on the inherited handler.
-- ---------------------------------------------------------------------------
function Tree:Eval(value, info, handler, ...)
	if type(value) == "function" then
		return value(info, ...)
	elseif type(value) == "string" then
		if handler and type(handler[value]) == "function" then
			return handler[value](handler, info, ...)
		end
		return value
	end
	return value
end

-- Properties that are only ever literal-or-function (never a handler method).
function Tree:EvalPlain(value, info, ...)
	if type(value) == "function" then
		return value(info, ...)
	end
	return value
end

function Tree:GetName(node, info)
	local n = self:EvalPlain(node.name, info)
	return n and tostring(n) or ""
end

function Tree:GetDesc(node, info)
	local d = self:EvalPlain(node.desc, info)
	return d and tostring(d) or nil
end

function Tree:IsHidden(node, chain, info)
	local h = node.hidden
	if h == nil then h = self:Inherited(chain, "hidden") end
	if h == nil then return false end
	return self:Eval(h, info, info.handler) and true or false
end

function Tree:IsDisabled(node, chain, info)
	local d = node.disabled
	if d == nil then d = self:Inherited(chain, "disabled") end
	if d == nil then return false end
	return self:Eval(d, info, info.handler) and true or false
end

-- ---------------------------------------------------------------------------
-- get / set bound to a specific node
-- ---------------------------------------------------------------------------
function Tree:MakeGetter(node, chain, info)
	local getter = node.get
	if getter == nil then getter = self:Inherited(chain, "get") end
	if getter == nil then
		return function() return nil end
	end
	return function(...)
		return self:Eval(getter, info, info.handler, ...)
	end
end

function Tree:MakeSetter(node, chain, info)
	local setter = node.set
	if setter == nil then setter = self:Inherited(chain, "set") end
	if setter == nil then
		return function() end
	end
	return function(...)
		return self:Eval(setter, info, info.handler, ...)
	end
end

function Tree:MakeFunc(node, chain, info)
	local fn = node.func
	if fn == nil then fn = self:Inherited(chain, "func") end
	if fn == nil then
		return function() end
	end
	return function(...)
		return self:Eval(fn, info, info.handler, ...)
	end
end

-- `values` and `sorting` accept a table, a function, OR a string naming a
-- method on the inherited handler -- AceDBOptions uses the string form
-- ("ListProfiles"), which EvalPlain returned verbatim, leaving the dropdown
-- with no items.
function Tree:MakeValues(node, info)
	return function()
		local v = self:Eval(node.values, info, info.handler)
		return type(v) == "table" and v or {}
	end
end

function Tree:MakeSorting(node, info)
	if node.sorting == nil then return nil end
	return function()
		local s = self:Eval(node.sorting, info, info.handler)
		return type(s) == "table" and s or nil
	end
end

-- ---------------------------------------------------------------------------
-- Child ordering
-- ---------------------------------------------------------------------------
function Tree:SortedChildren(node, path, chain)
	local out = {}
	if not node or not node.args then return out end

	for key, child in pairs(node.args) do
		if type(child) == "table" and child.type then
			local childPath = {}
			for i = 1, #path do childPath[i] = path[i] end
			childPath[#childPath + 1] = key

			local childChain = {}
			for i = 1, #chain do childChain[i] = chain[i] end
			childChain[#childChain + 1] = child

			local info = self:BuildInfo(childPath, child, childChain)
			local order = self:EvalPlain(child.order, info)
			if type(order) ~= "number" then order = 100 end

			table.insert(out, {
				key   = key,
				node  = child,
				path  = childPath,
				chain = childChain,
				info  = info,
				order = order,
				name  = self:GetName(child, info),
			})
		end
	end

	table.sort(out, function(a, b)
		if a.order ~= b.order then return a.order < b.order end
		return tostring(a.name) < tostring(b.name)
	end)
	return out
end

-- ---------------------------------------------------------------------------
-- Render list
-- Flattens a page node into an ordered list of section headers and options.
-- Nested inline groups become additional sections.
-- ---------------------------------------------------------------------------
local RENDERABLE = {
	toggle = true, range = true, select = true, color = true,
	input = true, execute = true, description = true, header = true,
	multiselect = true, keybinding = true,
}

function Tree:BuildRenderList(pageNode, pagePath, pageChain, out, depth)
	out = out or {}
	depth = depth or 0
	if not pageNode then return out end

	local children = self:SortedChildren(pageNode, pagePath, pageChain)
	for _, c in ipairs(children) do
		if not self:IsHidden(c.node, c.chain, c.info) then
			local t = c.node.type
			if t == "group" then
				-- Inline groups and nested groups both become sections here.
				table.insert(out, {
					kind  = "section",
					label = self:GetName(c.node, c.info),
					desc  = self:GetDesc(c.node, c.info),
					depth = depth,
				})
				self:BuildRenderList(c.node, c.path, c.chain, out, depth + 1)
			elseif t == "header" then
				table.insert(out, {
					kind  = "section",
					label = self:GetName(c.node, c.info),
					depth = depth,
				})
			elseif RENDERABLE[t] then
				table.insert(out, {
					kind  = "option",
					type  = t,
					node  = c.node,
					path  = c.path,
					chain = c.chain,
					info  = c.info,
					label = self:GetName(c.node, c.info),
					desc  = self:GetDesc(c.node, c.info),
					depth = depth,
				})
			end
		end
	end
	return out
end

-- ---------------------------------------------------------------------------
-- Width hint -- AceConfig `width` mapped to a column span.
-- "full"/"double" occupy the whole row; everything else takes one column.
-- ---------------------------------------------------------------------------
function Tree:ColumnSpan(node, info)
	local w = self:EvalPlain(node.width, info)
	if w == "full" or w == "double" then return 2 end
	if type(w) == "number" and w > 1.4 then return 2 end
	return 1
end

-- ---------------------------------------------------------------------------
-- Enable-toggle discovery
-- A module section that contains a toggle whose name begins with "Enable"
-- gets that toggle promoted to a power button on the sidebar row.
-- ---------------------------------------------------------------------------
function Tree:FindEnableToggle(pageNode, pagePath, pageChain)
	local list = self:BuildRenderList(pageNode, pagePath, pageChain)
	for _, entry in ipairs(list) do
		if entry.kind == "option" and entry.type == "toggle" then
			local n = entry.label or ""
			if strfind(strlower(n), "^enable") then
				return entry
			end
		end
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- Search index
-- Flattens every option under a page into lowercase label/desc strings so the
-- sidebar can answer "does this page contain a match?" without rendering it.
-- ---------------------------------------------------------------------------
function Tree:IndexPage(pageNode, pagePath, pageChain)
	local terms = {}
	local list = self:BuildRenderList(pageNode, pagePath, pageChain)
	for _, entry in ipairs(list) do
		if entry.label and entry.label ~= "" then
			table.insert(terms, strlower(entry.label))
		end
		if entry.desc and entry.desc ~= "" then
			table.insert(terms, strlower(entry.desc))
		end
	end
	return terms
end

function Tree:TermsMatch(terms, query)
	if not query or query == "" then return true end
	for _, t in ipairs(terms) do
		if strfind(t, query, 1, true) then return true end
	end
	return false
end

-- Strip WoW color escapes so search and sidebar labels read cleanly.
function Tree:StripColor(s)
	if not s then return "" end
	s = gsub(s, "|c%x%x%x%x%x%x%x%x", "")
	s = gsub(s, "|r", "")
	s = gsub(s, "^%s+", "")
	s = gsub(s, "%s+$", "")
	return s
end

return Tree
