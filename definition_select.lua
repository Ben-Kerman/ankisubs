local dicts = require "dict.dicts"

local function format_def(def)
	local readings = table.concat(def.readings, "・")
	local variants
	if def.variants then
		variants = "【" .. table.concat(def.variants, "・") .. "】"
	else variants = "" end
	local defs = table.concat(def.defs, "; ")
	return string.format("%s%s: %s", readings, variants, defs)
end

local function def_renderer(def)
	return format_def(def)
end

local function sel_def_renderer(def)
	return "{\\b1}" .. format_def(def) .. "{\\b0}"
end

DefinitionSelect = {}
DefinitionSelect.__index = DefinitionSelect

function DefinitionSelect:new(word, prefix)
	for i, dict in ipairs(dicts) do
		local lookup_fn = prefix and dict.look_up_start or dict.look_up_exact
		local result = lookup_fn(word)
		if result then
			local def_sel = {
				_line_select = LineSelect:new(result, sel_def_renderer, def_renderer, nil, 5),
				lookup_result = {dict_index = i, defs = result}
			}
			def_sel._line_select:start()
			return setmetatable(def_sel, DefinitionSelect)
		end
	end
	return nil
end

function DefinitionSelect:finish(word)
	return dicts[self.lookup_result.dict_index].get_definition(self._line_select:finish().id)
end