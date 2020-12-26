local helper = require "helper"
local mpu = require "mp.utils"
local msg require "message"
local sys = require "system"
local utf_8 = require "utf_8"
local util = require "util"

local dict_util = {}

function dict_util.cache_path(dict)
	local config_dir =  mp.find_config_file("."):sub(1, -3)
	local cache_dir = mpu.join_path(config_dir, script_name .. "-dict-cache")
	if not sys.create_dir(cache_dir) then
		msg.error("failed to create dictionary cache directory")
	end
	return mpu.join_path(cache_dir, dict.id .. ".json")
end

function dict_util.is_imported(dict)
	return not not mpu.file_info(dict_util.cache_path(dict))
end

function dict_util.generic_load(dict, import_fn, force_import)
	if not force_import and dict_util.is_imported(dict) then
		return helper.parse_json_file(dict_util.cache_path(dict))
	end
	return import_fn(dict)
end

function dict_util.create_index(entries, search_term_gen)
	local function index_insert(index, key, value)
		if index[key] then table.insert(index[key], value)
		else index[key] = {value} end
	end

	local index, start_index = {}, {}
	for entry_pos, entry in ipairs(entries) do
		-- find all unique readings/spelling variants
		local search_terms = search_term_gen(entry)

		-- build index from search_terms and find first characters
		local initial_chars = {}
		for _, term in ipairs(search_terms) do
			initial_chars[utf_8.string(utf_8.codepoints(term, 1, 1))] = true

			index_insert(index, term, entry_pos)
		end

		-- build first character index
		for initial_char, _ in pairs(initial_chars) do
			index_insert(start_index, initial_char, entry_pos)
		end
	end

	return index, start_index
end

function dict_util.load_exporter(dict_type, exporter)
	local exporter_id = exporter and exporter or "default"
	local success, exporter = pcall(require, "dict." .. dict_type .. "." .. exporter_id)
	if not success then
		local err_msg = "could not load exportert '" ..
		                exporter_id ..
		                "' for dictionary type '" ..
		                dict_type ..
		                "', falling back to default"
		msg.error(err_msg)
		return require("dict." .. dict_type .. ".default")
	else return exporter end
end

function dict_util.find_start_matches(term, data, search_term_fn)
	local first_char = utf_8.string(utf_8.codepoints(term, 1, 1))
	local start_matches = data.start_index[first_char]
	return util.list_filter(start_matches, function(id)
		if util.list_find(search_term_fn(data.entries[id]), function(search_term)
			return util.string_starts(search_term, term)
		end) then return true end
	end)
end

return dict_util
