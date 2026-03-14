local serial = require("serialization")
local io     = require("io")
local M = {}
local CONFIG_PATH = "/gt_ore_config.cfg"

function M.load()
  local f = io.open(CONFIG_PATH, "r")
  if not f then return {} end
  local data = f:read("*a")
  f:close()
  return serial.unserialize(data) or {}
end

function M.save(routes)
  local f = io.open(CONFIG_PATH, "w")
  f:write(serial.serialize(routes))
  f:close()
end

function M.configPath() return CONFIG_PATH end
return M