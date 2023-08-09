--[[
    Copyright (C) 2017 AMM

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]--
--[[
    mpv_thumbnail_script.lua 0.1.0 - commit 7074706 (branch master)
    https://github.com/TheAMM/mpv_thumbnail_script
    Built on 2017-12-05 20:20:02
]]--
local assdraw = require 'mp.assdraw'
local msg = require 'mp.msg'
local opt = require 'mp.options'
local utils = require 'mp.utils'

-- Determine platform --
ON_WINDOWS = (package.config:sub(1,1) ~= '/')

-- Some helper functions needed to parse the options --
function isempty(v) return (v == false) or (v == nil) or (v == "") or (v == 0) or (type(v) == "table" and next(v) == nil) end

function divmod (a, b)
  return math.floor(a / b), a % b
end

-- Better modulo
function bmod( i, N )
  return (i % N + N) % N
end

function join_paths(...)
  local sep = ON_WINDOWS and "\\" or "/"
  local result = "";
  for i, p in pairs({...}) do
    if p ~= "" then
      if is_absolute_path(p) then
        result = p
      else
        result = (result ~= "") and (result:gsub("[\\"..sep.."]*$", "") .. sep .. p) or p
      end
    end
  end
  return result:gsub("[\\"..sep.."]*$", "")
end

-- /some/path/file.ext -> /some/path, file.ext
function split_path( path )
  local sep = ON_WINDOWS and "\\" or "/"
  local first_index, last_index = path:find('^.*' .. sep)

  if last_index == nil then
    return "", path
  else
    local dir = path:sub(0, last_index-1)
    local file = path:sub(last_index+1, -1)

    return dir, file
  end
end

function is_absolute_path( path )
  local tmp, is_win  = path:gsub("^[A-Z]:\\", "")
  local tmp, is_unix = path:gsub("^/", "")
  return (is_win > 0) or (is_unix > 0)
end

function Set(source)
  local set = {}
  for _, l in ipairs(source) do set[l] = true end
  return set
end

---------------------------
-- More helper functions --
---------------------------

-- Removes all keys from a table, without destroying the reference to it
function clear_table(target)
  for key, value in pairs(target) do
    target[key] = nil
  end
end
function shallow_copy(target)
  local copy = {}
  for k, v in pairs(target) do
    copy[k] = v
  end
  return copy
end

-- Rounds to given decimals. eg. round_dec(3.145, 0) => 3
function round_dec(num, idp)
  local mult = 10^(idp or 0)
  return math.floor(num * mult + 0.5) / mult
end

function file_exists(name)
  local f = io.open(name, "rb")
  if f ~= nil then
    local ok, err, code = f:read(1)
    io.close(f)
    return code == nil
  else
    return false
  end
end

function path_exists(name)
  local f = io.open(name, "rb")
  if f ~= nil then
    io.close(f)
    return true
  else
    return false
  end
end

function create_directories(path)
  local cmd
  if ON_WINDOWS then
    cmd = { args = {"cmd", "/c", "mkdir", path} }
  else
    cmd = { args = {"mkdir", "-p", path} }
  end
  utils.subprocess(cmd)
end

-- Find an executable in PATH or CWD with the given name
function find_executable(name)
  local delim = ON_WINDOWS and ";" or ":"

  local pwd = os.getenv("PWD") or utils.getcwd()
  local path = os.getenv("PATH")

  local env_path = pwd .. delim .. path -- Check CWD first

  local result, filename
  for path_dir in env_path:gmatch("[^"..delim.."]+") do
    filename = join_paths(path_dir, name)
    if file_exists(filename) then
      result = filename
      break
    end
  end

  return result
end

local ExecutableFinder = { path_cache = {} }
-- Searches for an executable and caches the result if any
function ExecutableFinder:get_executable_path( name, raw_name )
  name = ON_WINDOWS and not raw_name and (name .. ".exe") or name

  if self.path_cache[name] == nil then
    self.path_cache[name] = find_executable(name) or false
  end
  return self.path_cache[name]
end

-- Format seconds to HH.MM.SS.sss
function format_time(seconds, sep, decimals)
  decimals = decimals == nil and 3 or decimals
  sep = sep and sep or "."
  local s = seconds
  local h, s = divmod(s, 60*60)
  local m, s = divmod(s, 60)

  local second_format = string.format("%%0%d.%df", 2+(decimals > 0 and decimals+1 or 0), decimals)

  return string.format("%02d"..sep.."%02d"..sep..second_format, h, m, s)
end

-- Format seconds to 1h 2m 3.4s
function format_time_hms(seconds, sep, decimals, force_full)
  decimals = decimals == nil and 1 or decimals
  sep = sep ~= nil and sep or " "

  local s = seconds
  local h, s = divmod(s, 60*60)
  local m, s = divmod(s, 60)

  if force_full or h > 0 then
    return string.format("%dh"..sep.."%dm"..sep.."%." .. tostring(decimals) .. "fs", h, m, s)
  elseif m > 0 then
    return string.format("%dm"..sep.."%." .. tostring(decimals) .. "fs", m, s)
  else
    return string.format("%." .. tostring(decimals) .. "fs", s)
  end
end

-- Writes text on OSD and console
function log_info(txt, timeout)
  timeout = timeout or 1.5
  msg.info(txt)
  mp.osd_message(txt, timeout)
end

-- Join table items, ala ({"a", "b", "c"}, "=", "-", ", ") => "=a-, =b-, =c-"
function join_table(source, before, after, sep)
  before = before or ""
  after = after or ""
  sep = sep or ", "
  local result = ""
  for i, v in pairs(source) do
    if not isempty(v) then
      local part = before .. v .. after
      if i == 1 then
        result = part
      else
        result = result .. sep .. part
      end
    end
  end
  return result
end

function wrap(s, char)
  char = char or "'"
  return char .. s .. char
end
-- Wraps given string into 'string' and escapes any 's in it
function escape_and_wrap(s, char, replacement)
  char = char or "'"
  replacement = replacement or "\\" .. char
  return wrap(string.gsub(s, char, replacement), char)
end
-- Escapes single quotes in a string and wraps the input in single quotes
function escape_single_bash(s)
  return escape_and_wrap(s, "'", "'\\''")
end

-- Returns (a .. b) if b is not empty or nil
function joined_or_nil(a, b)
  return not isempty(b) and (a .. b) or nil
end

-- Put items from one table into another
function extend_table(target, source)
  for i, v in pairs(source) do
    table.insert(target, v)
  end
end

-- Creates a handle and filename for a temporary random file (in current directory)
function create_temporary_file(base, mode, suffix)
  local handle, filename
  suffix = suffix or ""
  while true do
    filename = base .. tostring(math.random(1, 5000)) .. suffix
    handle = io.open(filename, "r")
    if not handle then
      handle = io.open(filename, mode)
      break
    end
    io.close(handle)
  end
  return handle, filename
end


function get_processor_count()
  local proc_count

  if ON_WINDOWS then
    proc_count = tonumber(os.getenv("NUMBER_OF_PROCESSORS"))
  else
    local cpuinfo_handle = io.open("/proc/cpuinfo")
    if cpuinfo_handle ~= nil then
      local cpuinfo_contents = cpuinfo_handle:read("*a")
      local _, replace_count = cpuinfo_contents:gsub('processor', '')
      proc_count = replace_count
    end
  end

  if proc_count and proc_count > 0 then
      return proc_count
  else
    return nil
  end
end

function substitute_values(string, values)
  local substitutor = function(match)
    if match == "%" then
       return "%"
    else
      -- nil is discarded by gsub
      return values[match]
    end
  end

  local substituted = string:gsub('%%(.)', substitutor)
  return substituted
end

-- ASS HELPERS --
function round_rect_top( ass, x0, y0, x1, y1, r )
  local c = 0.551915024494 * r -- circle approximation
  ass:move_to(x0 + r, y0)
  ass:line_to(x1 - r, y0) -- top line
  if r > 0 then
      ass:bezier_curve(x1 - r + c, y0, x1, y0 + r - c, x1, y0 + r) -- top right corner
  end
  ass:line_to(x1, y1) -- right line
  ass:line_to(x0, y1) -- bottom line
  ass:line_to(x0, y0 + r) -- left line
  if r > 0 then
      ass:bezier_curve(x0, y0 + r - c, x0 + r - c, y0, x0 + r, y0) -- top left corner
  end
end

function round_rect(ass, x0, y0, x1, y1, rtl, rtr, rbr, rbl)
    local c = 0.551915024494
    ass:move_to(x0 + rtl, y0)
    ass:line_to(x1 - rtr, y0) -- top line
    if rtr > 0 then
        ass:bezier_curve(x1 - rtr + rtr*c, y0, x1, y0 + rtr - rtr*c, x1, y0 + rtr) -- top right corner
    end
    ass:line_to(x1, y1 - rbr) -- right line
    if rbr > 0 then
        ass:bezier_curve(x1, y1 - rbr + rbr*c, x1 - rbr + rbr*c, y1, x1 - rbr, y1) -- bottom right corner
    end
    ass:line_to(x0 + rbl, y1) -- bottom line
    if rbl > 0 then
        ass:bezier_curve(x0 + rbl - rbl*c, y1, x0, y1 - rbl + rbl*c, x0, y1 - rbl) -- bottom left corner
    end
    ass:line_to(x0, y0 + rtl) -- left line
    if rtl > 0 then
        ass:bezier_curve(x0, y0 + rtl - rtl*c, x0 + rtl - rtl*c, y0, x0 + rtl, y0) -- top left corner
    end
end
local SCRIPT_NAME = "mpv_thumbnail_script"

local default_cache_base = ON_WINDOWS and os.getenv("TEMP") or "/tmp/"

local thumbnailer_options = {
    -- The thumbnail directory
    cache_directory = join_paths(default_cache_base, "mpv_thumbs_cache"),

    -- Automatically generate the thumbnails on video load, without a keypress
    autogenerate = true,

    -- Only automatically thumbnail videos shorter than this (seconds)
    autogenerate_max_duration = 3600, -- 1 hour

    -- Use mpv to generate thumbnail even if ffmpeg is found in PATH
    -- Note: mpv is a bit slower, but includes eg. subtitles in the previews!
    prefer_mpv = false,

    -- Disable the built-in keybind ("T") to add your own
    disable_keybinds = false,

    -- The maximum dimensions of the thumbnails (pixels)
    thumbnail_width = 200,
    thumbnail_height = 200,

    -- The thumbnail count target
    -- (This will result in a thumbnail every ~10 seconds for a 25 minute video)
    thumbnail_count = 150,

    -- The above target count will be adjusted by the minimum and
    -- maximum time difference between thumbnails.
    -- The thumbnail_count will be used to calculate a target separation,
    -- and min/max_delta will be used to constrict it.

    -- In other words, thumbnails will be:
    --   at least min_delta seconds apart (limiting the amount)
    --   at most max_delta seconds apart (raising the amount if needed)
    min_delta = 5,
    -- 120 seconds aka 2 minutes will add more thumbnails when the video is over 5 hours!
    max_delta = 90,
}

read_options(thumbnailer_options, SCRIPT_NAME)
local Thumbnailer = {
    cache_directory = thumbnailer_options.cache_directory,

    state = {
        ready = false,
        available = false,
        enabled = false,

        thubmnail_template = nil,

        thumbnail_delta = nil,
        thumbnail_count = 0,

        thumbnail_size = nil,

        finished_thumbnails = 0,
        thumbnails = {}
    }
}

function Thumbnailer:clear_state()
    clear_table(self.state)
    self.state.ready = false
    self.state.available = false
    self.state.finished_thumbnails = 0
    self.state.thumbnails = {}
end


function Thumbnailer:on_file_loaded()
    self:clear_state()
end

function Thumbnailer:on_thumb_ready(index)
    self.state.thumbnails[index] = true

    -- Recount (just in case)
    self.state.finished_thumbnails = 0
    for i in pairs(self.state.thumbnails) do
        self.state.finished_thumbnails = self.state.finished_thumbnails + 1
    end
end

function Thumbnailer:on_video_change(params)
    self:clear_state()
    if params ~= nil then
        if not self.state.ready then
            self:update_state()
        end
    end
end


function Thumbnailer:update_state()
    self.state.thumbnail_delta = self:get_delta()
    self.state.thumbnail_count = self:get_thumbnail_count()

    self.state.thubmnail_template = self:get_thubmnail_template()
    self.state.thumbnail_size = self:get_thumbnail_size()

    self.state.ready = true

    self.state.available = false

    -- Make sure the file has video (and not just albumart)
    local track_list = mp.get_property_native("track-list")
    local has_video = false
    for i, track in pairs(track_list) do
        if track.type == "video" and not track.external and not track.albumart then
            has_video = true
            break
        end
    end

    if has_video and self.state.thumbnail_delta ~= nil and self.state.thumbnail_size ~= nil and self.state.thumbnail_count > 0 then
        self.state.available = true
    end

end


function Thumbnailer:get_thubmnail_template()
    local file_key = ("%s-%d"):format(mp.get_property_native("filename/no-ext"), mp.get_property_native("file-size"))
    local file_template = join_paths(self.cache_directory, file_key, "%06d.bgra")
    return file_template
end


function Thumbnailer:get_thumbnail_size()
    local video_dec_params = mp.get_property_native("video-dec-params")
    local video_width = video_dec_params.dw
    local video_height = video_dec_params.dh
    if not (video_width and video_height) then
        return nil
    end

    local w, h
    if video_width > video_height then
        w = thumbnailer_options.thumbnail_width
        h = math.floor(video_height * (w / video_width))
    else
        h = thumbnailer_options.thumbnail_height
        w = math.floor(video_width * (h / video_height))
    end
    return { w=w, h=h }
end


function Thumbnailer:get_delta()
    local file_path = mp.get_property_native("path")
    local file_duration = mp.get_property_native("duration")
    local is_seekable = mp.get_property_native("seekable")

    if file_path:find("://") ~= nil or not is_seekable or not file_duration then
        -- Not a local path, not seekable or lacks duration
        return nil
    end

    local target_delta = (file_duration / thumbnailer_options.thumbnail_count)
    local delta = math.max(thumbnailer_options.min_delta, math.min(thumbnailer_options.max_delta, target_delta))

    return delta
end


function Thumbnailer:get_thumbnail_count()
    local delta = self:get_delta()
    if delta == nil then
        return 0
    end
    local file_duration = mp.get_property_native("duration")

    return math.floor(file_duration / delta)
end

function Thumbnailer:get_closest(thumbnail_index)
    local min_distance = self.state.thumbnail_count+1
    local closest = nil

    for index, value in pairs(self.state.thumbnails) do
        local distance = math.abs(index - thumbnail_index)
        if distance < min_distance then
            min_distance = distance
            closest = index
        end
    end
    return closest, min_distance
end

function Thumbnailer:get_thumbnail_path(time_position)
    local thumbnail_index = math.min(math.floor(time_position / self.state.thumbnail_delta), self.state.thumbnail_count-1)

    local closest, distance = self:get_closest(thumbnail_index)

    if closest ~= nil then
        return self.state.thubmnail_template:format(closest), thumbnail_index, closest
    else
        return nil, thumbnail_index, nil
    end
end

function Thumbnailer:register_client()
    mp.register_script_message("mpv_thumbnail_script-ready", function(index, path) self:on_thumb_ready(tonumber(index), path) end)
    -- Wait for server to tell us we're live
    mp.register_script_message("mpv_thumbnail_script-enabled", function() self.state.enabled = true end)

    -- Notify server to generate thumbnails when video loads/changes
    mp.observe_property("video-dec-params", "native", function()
        local duration = mp.get_property_native("duration")
        local max_duration = thumbnailer_options.autogenerate_max_duration

        if duration and thumbnailer_options.autogenerate then
            -- Notify if autogenerate is on and video is not too long
            if duration < max_duration or max_duration == 0 then
                mp.commandv("script-message", "mpv_thumbnail_script-generate")
            end
        end
    end)
end

mp.observe_property("video-dec-params", "native", function(name, params) Thumbnailer:on_video_change(params) end)

function create_thumbnail_mpv(file_path, timestamp, size, output_path)
    local mpv_command = {
        "mpv",
        file_path,
        "--start=" .. tostring(timestamp),
        "--frames=1",
        "--hr-seek=yes",
        "--no-audio",

        ("--vf=scale=%d:%d"):format(size.w, size.h),
        "--vf-add=format=bgra",
        "--of=rawvideo",
        "--ovc=rawvideo",
        "--o", output_path
    }
    return utils.subprocess({args=mpv_command})
end


function create_thumbnail_ffmpeg(file_path, timestamp, size, output_path)
    local ffmpeg_command = {
        "ffmpeg",
        "-loglevel", "quiet",
        "-noaccurate_seek",
        "-ss", format_time(timestamp, ":"),
        "-i", file_path,

        "-frames:v", "1",
        "-an",

        "-vf", ("scale=%d:%d"):format(size.w, size.h),
        "-c:v", "rawvideo",
        "-pix_fmt", "bgra",
        "-f", "rawvideo",

        "-y", output_path
    }
    return utils.subprocess({args=ffmpeg_command})
end


function check_output(ret, output_path)
    if ret.killed_by_us then
        return nil
    end

    if ret.error or ret.status ~= 0 then
        msg.error("Thumbnailing command failed!")
        msg.error(ret.error or ret.stdout)

        return false
    end

    if not file_exists(output_path) then
        msg.error("Output file missing!")
        return false
    end

    return true
end


function generate_thumbnails(from_keypress)
    if not Thumbnailer.state.available then
        if from_keypress then
            mp.osd_message("Nothing to thumbnail", 2)
        end
        return
    end

    local thumbnail_count = Thumbnailer.state.thumbnail_count
    local thumbnail_delta = Thumbnailer.state.thumbnail_delta
    local thumbnail_size = Thumbnailer.state.thumbnail_size
    local file_template = Thumbnailer.state.thubmnail_template
    local file_duration = mp.get_property_native("duration")
    local file_path = mp.get_property_native("path")

    msg.info(("Generating %d thumbnails @ %dx%d"):format(thumbnail_count, thumbnail_size.w, thumbnail_size.h))

    -- Create directory for the thumbnails
    local thumbnail_directory = split_path(file_template)
    local l, err = utils.readdir(thumbnail_directory)
    if err then
        msg.info("Creating", thumbnail_directory)
        create_directories(thumbnail_directory)
    end

    local thumbnail_func = create_thumbnail_mpv
    if not thumbnailer_options.prefer_mpv then
        if ExecutableFinder:get_executable_path("ffmpeg") then
            thumbnail_func = create_thumbnail_ffmpeg
        else
            msg.warning("Could not find ffmpeg in PATH! Falling back on mpv.")
        end
    end

    mp.commandv("script-message", "mpv_thumbnail_script-enabled")

    local generate_thumbnail_for_index = function(thumbnail_index)
        local thumbnail_path = file_template:format(thumbnail_index)
        local timestamp = math.min(file_duration, thumbnail_index * thumbnail_delta)

        -- The expected size (raw BGRA image)
        local thumbnail_raw_size = (thumbnail_size.w * thumbnail_size.h * 4)

        local need_thumbnail_generation = false

        -- Check if the thumbnail already exists and is the correct size
        local thumbnail_file = io.open(thumbnail_path, "rb")
        if thumbnail_file == nil then
            need_thumbnail_generation = true
        else
            local existing_thumbnail_filesize = thumbnail_file:seek("end")
            if existing_thumbnail_filesize ~= thumbnail_raw_size then
                -- Size doesn't match, so (re)generate
                msg.warn("Thumbnail", thumbnail_index, "did not match expected size, regenerating")
                need_thumbnail_generation = true
            end
            thumbnail_file:close()
        end

        if need_thumbnail_generation then
            local ret = thumbnail_func(file_path, timestamp, thumbnail_size, thumbnail_path)
            local success = check_output(ret, thumbnail_path)

            if success == nil then
                -- Killed by us, changing files, ignore
                return true
            elseif not success then
                -- Failure
                mp.osd_message("Thumbnailing failed, check console for details", 3.5)
                return true
            end
        end

        -- Verify thumbnail size
        -- Sometimes ffmpeg will output an empty file when seeking to a "bad" section (usually the end)
        thumbnail_file = io.open(thumbnail_path, "rb")

        -- Bail if we can't read the file (it should really exist by now, we checked this in check_output!)
        if thumbnail_file == nil then
            msg.error("Thumbnail suddenly disappeared!")
            return true
        end

        -- Check the size of the generated file
        local thumbnail_file_size = thumbnail_file:seek("end")
        thumbnail_file:close()

        -- Check if the file is big enough
        local missing_bytes = math.max(0, thumbnail_raw_size - thumbnail_file_size)
        if missing_bytes > 0 then
            -- Pad the file if it's missing content (eg. ffmpeg seek to file end)
            thumbnail_file = io.open(thumbnail_path, "ab")
            thumbnail_file:write(string.rep(string.char(0) * missing_bytes))
            thumbnail_file:close()
        end

        mp.commandv("script-message", "mpv_thumbnail_script-ready", tostring(thumbnail_index), thumbnail_path)
    end

    -- Keep track of which thumbnails we've checked during the passes (instead of proper math for no-overlap)
    local generated_thumbnails = {}

    -- Do several passes over the thumbnails with increasing frequency
    for res = 6, 0, -1 do
        local nth = (2^res)

        for thumbnail_index = 0, thumbnail_count-1, nth do
            if not generated_thumbnails[thumbnail_index] then
                local bail = generate_thumbnail_for_index(thumbnail_index)
                if bail then return end
                generated_thumbnails[thumbnail_index] = true
            end
        end
    end
end


function on_script_keypress()
    mp.osd_message("Starting thumbnail generation", 2)
    generate_thumbnails(true)
    mp.osd_message("All thumbnails generated", 2)
end

-- Set up listeners and keybinds

mp.register_script_message("mpv_thumbnail_script-generate", generate_thumbnails)

local thumb_script_key = not thumbnailer_options.disable_keybinds and "T" or nil
mp.add_key_binding(thumb_script_key, "generate-thumbnails", on_script_keypress)
