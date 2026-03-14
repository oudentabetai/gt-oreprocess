-- /lib/gt_routes.lua
local serial = require("serialization")
local io     = require("io")

local M = {}
local CONFIG_PATH = "/gt_ore_config.cfg"

-- ルート定義
-- use_centrifuge: Dust後にCentrifugeを通すか
M.ROUTE_DEFS = {
  mac = {
    label         = "Macerator直行 (→ImpureDust→Dust)",
    use_centrifuge = false,  -- 変更可
  },
  wash = {
    label         = "OreWasher経由 (→PurifiedOre→Dust)",
    use_centrifuge = false,  -- 変更可
  },
  thermal = {
    label         = "ThermalCentrifuge経由 (→Centrifuged→Dust)",
    use_centrifuge = false,  -- thermalはCentrifuge不可
  },
}

function M.load()
  local f = io.open(CONFIG_PATH, "r")
  if not f then return {} end
  local data = f:read("*a")
  f:close()
  return serial.unserialize(data) or {}
end

function M.save(routes)
  local f = io.open(CONFIG_PATH, "w")
  if not f then error("設定ファイルを書き込めません: " .. CONFIG_PATH) end
  f:write(serial.serialize(routes))
  f:close()
end

function M.configPath()
  return CONFIG_PATH
end

return M