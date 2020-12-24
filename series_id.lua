local cfg = require "config"
local util = require "util"

local config = util.map_map(cfg.load_subcfg("series"), function(_, series)
	if not cfg.check_required(series.entries, {"keywords"}) then
		return nil
	end
	return series.name, {
		title = series.entries.title,
		keywords = util.string_split(series.entries.keywords:lower(), " ", true)
	}
end)

local function generate_title(filename)
	return (filename:gsub("%.[^%.]+$", "")        -- file extension
	                :gsub("[_%.]", " ")
	                :gsub("%s*%[[^%]]+%]%s*", "") -- tags in []
	                :gsub("%s*%([^%)]+%)%s*", "") -- tags in ()
	                :gsub("%s+%-?%s*[SsEePpVv%d%.]+$", "")) -- episode number at end
end

local function generate_id(filename)
	local title = generate_title(filename)
	return (title:lower()
	             :gsub("[^%w%s%-\128-\255]", "")  -- all non-alnum ASCII chars
	             :gsub("%s+", "-")                -- replace spaces with dash
	             :gsub("%-+", "-")                -- duplicated dashes
	             :gsub("^%-+", "")                -- leading dashes
	             :gsub("%-+$", ""))               -- trailing dashes
end

local function match_filename(filename)
	local filename_lc = filename:lower()
	for id, values in pairs(config) do
		local match = true
		for _, kw in ipairs(values.keywords) do
			if not filename_lc:find(kw) then
				match = false
				break
			end
		end
		if match then
			return id, values
		end
	end
	return false
end

local series_id = {}

function series_id.id()
	local filename = mp.get_property("filename")
	if not filename then return nil end

	local filename_lc = filename:lower()
	local id = match_filename(filename_lc)
	if id then return id, true
	else return generate_id(filename_lc), false end
end

function series_id.title()
	local filename = mp.get_property("filename")
	if not filename then return nil end

	local id, values = match_filename(filename)
	if id and values.title then
		return values.title, true
	else return generate_title(filename), false end
end

return series_id
