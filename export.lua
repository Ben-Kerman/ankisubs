local anki = require "anki"
local ankicon = require "ankiconnect"
local cfg = require "config"
local encoder = require "encoder"
local helper = require "helper"
local mpu = require "mp.utils"
local msg = require "message"
local series_id = require "series_id"
local sys = require "system"
local templater = require "templater"
local util = require "util"

local function anki_sound_tag(filename)
	return string.format("[sound:%s]", filename)
end

local function anki_image_tag(filename)
	return string.format([[<img src="%s">]], filename)
end

local function replace_field_vars(field_def, data, audio_file, image_file, word_audio_filename, start, stop)
	local abs_path = helper.current_path_abs()
	local _, filename = mpu.split_path(abs_path)

	local template_data = {
		-- exported files --
		audio_file = {data = audio_file},
		image_file = {data = image_file},
		audio = {data = anki_sound_tag(audio_file)},
		image = {data = anki_image_tag(image_file)},
		-- current file --
		path = {data = abs_path},
		filename = {data = filename},
		-- times --
		start = {data = helper.format_time(start, true)},
		["end"] = {data = helper.format_time(stop, true)},
		start_ms = {data = helper.format_time(start)},
		end_ms = {data = helper.format_time(stop)},
		start_seconds = {data = string.format("%.0f", math.floor(start))},
		end_seconds = {data = string.format("%.0f", math.floor(stop))},
		start_seconds_ms = {data = string.format("%.3f", start)},
		end_seconds_ms = {data = string.format("%.3f", stop)},
		end_seconds_ms = {data = string.format("%.3f", stop)},
		end_seconds_ms = {data = string.format("%.3f", stop)},
		-- optional values --
		word_audio_file = false,
		word_audio = false,
		sentences = false,
		word = false,
		definitions = false
	}
	if word_audio_filename then
		template_data.word_audio_file = {data = word_audio_filename}
		template_data.word_audio = {
			data = anki_sound_tag(word_audio_filename)
		}
	end
	if data.subtitles and #data.subtitles ~= 0 then
		template_data.sentences = {
			data = util.list_map(data.subtitles, function(sub) return sub.text end),
			sep = "<br>"
		}
	end
	if data.definitions and #data.definitions ~= 0 then
		template_data.word = data.definitions[1].word
		template_data.definitions = {
			data = util.list_map(data.definitions, function(def) return def.definition end),
			sep = "<br>"
		}
	end
	return templater.render(field_def, template_data)
end

local function export_word_audio(data)
	if data.word_audio_file then
		local src_path = data.word_audio_file.path
		local base_fn = string.format("%s-%s.", cfg.values.forvo_prefix, data.word_audio_file.word)

		local function check_file(extension, action)
			local full_fn = base_fn .. extension
			local tgt_path = mpu.join_path(anki.media_dir(), full_fn)
			if not mpu.file_info(tgt_path) then
				action(tgt_path)
			else msg.info("Word audio file " .. full_fn .. " already exists") end
			return full_fn
		end

		if cfg.values.forvo_reencode then
			return check_file(cfg.values.forvo_extension, function(tgt_path)
				encoder.any_audio{
					src_path = src_path,
					tgt_path = tgt_path,
					format = cfg.values.forvo_format,
					codec = cfg.values.forvo_codec,
					bitrate = cfg.values.forvo_bitrate
				}
			end)
		else
			return check_file(data.word_audio_file.extension, function(tgt_path)
				sys.move_file(src_path, tgt_path)
			end)
		end
	end
end

local export = {}

function export.verify_times(data, warn)
	local start = data.times.start and data.times.start >= 0
	local stop = data.times.stop and data.times.stop >= 0

	if not data.times or not (start or stop) then
		if warn then msg.warn("Select subtitles or set times manually") end
		return false
	end

	if not (start and stop) then
		if warn then msg.warn("Start or end time missing") end
		return false
	end
	return true
end

function export.verify(data, warn)
	-- subs present → times can be derived
	if #data.subtitles ~= 0 then return true end

	return export.verify_times(data, warn)
end

function export.resolve_times(data)
	local ts = util.map_merge({
		scrot = -1,
		start = -1,
		stop = -1
	}, data.times)

	local start = ts.start < 0 and data.subtitles[1]:real_start() or ts.start
	local stop = ts.stop < 0 and util.list_max(data.subtitles, function(a, b)
		return a.stop < b.stop
	end):real_stop() or ts.stop
	local scrot = ts.scrot < 0 and mp.get_property_number("time-pos") or ts.scrot

	return start, stop, scrot
end

local function prepare_fields(data)
	local tgt = anki.active_target("could not execute export")
	if not tgt then return end

	if not ankicon.prepare_target(tgt) then
		return nil
	end

	local tgt_cfg = tgt.config
	local start, stop, scrot = export.resolve_times(data)

	local audio_filename = anki.generate_filename(series_id.id(), tgt_cfg.audio.extension)
	local image_filename = anki.generate_filename(series_id.id(), tgt_cfg.image.extension)
	encoder.audio(mpu.join_path(anki.media_dir(), audio_filename), start, stop)
	encoder.image(mpu.join_path(anki.media_dir(), image_filename), scrot)
	local word_audio_filename = export_word_audio(data)

	local fields = {}
	for name, def in pairs(tgt_cfg.anki.fields) do
		fields[name] = replace_field_vars(def, data, audio_filename, image_filename, word_audio_filename, start, stop)
	end

	return fields, tgt
end

local function fill_first_field(fields, tgt, ignore_nil)
	local field_names = ankicon.model_field_names(tgt.note_type)
	local first_field = fields[field_names[1]]
	if (not first_field and not ignore_nil) or (first_field and #first_field == 0) then
		fields[field_names[1]] = "<i>placeholder</i>"
	end
	return fields
end

function export.execute(data)
	local fields = fill_first_field(prepare_fields(data))
	if fields then
		if ankicon.add_note(fields) then
			msg.info("note added successfully")
		else msg.warn("note couldn't be added") end
	end
end

function export.execute_gui(data)
	local fields = prepare_fields(data)
	if fields then
		if ankicon.gui_add_cards(fields) then
			msg.info("'Add' GUI opened")
		else msg.warn("'Add' GUI couldn't be opened") end
	end
end

local function combine_fields(note, fields, tgt)
	local new_fields = {}
	for name, content in pairs(note.fields) do
		if fields[name] then
			local new_value = fields[name]
			if tgt.add_mode == "append" then
				new_value = content.value .. fields[name]
			elseif tgt.add_mode == "prepend" then
				new_value = fields[name] .. content.value
			elseif tgt.add_mode == "overwrite" then
				new_value = fields[name]
			else new_value = content.value end
			new_fields[name] = new_value
		else new_fields[name] = content.value end
	end
	return new_fields
end

function export.execute_add(data, note)
	local fields, tgt = prepare_fields(data)
	if fields then
		local new_fields = fill_first_field(combine_fields(note, fields, tgt), tgt, true)

		if ankicon.update_note_fields(note.noteId, new_fields) then
			msg.info("note updated successfully")
		else msg.warn("note couldn't be updated") end
	end
end

return export
