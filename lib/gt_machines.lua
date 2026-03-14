local serial = require("serialization")
local io     = require("io")
local M = {}
local CONFIG_PATH = "/gt_machine_config.cfg"

-- 機械定義
-- key       : 内部ID
-- label     : GUI表示名
-- in_label  : 入力crate の説明
-- out_label : 出力crate の説明
M.MACHINE_DEFS = {
  { key="input",   label="投入ストレージ",              in_label=nil,               out_label="生鉱石を入れる"           },
  { key="mac1",    label="Macerator #1 (Ore→Crushed)", in_label="生鉱石を投入",     out_label="Crushed*を回収"           },
  { key="mac2",    label="Macerator #2 [mac]→Impure",  in_label="Crushed*を投入",   out_label="ImpureDust*を回収"        },
  { key="mac3",    label="Macerator #3 [mac]→Dust",    in_label="ImpureDust*を投入",out_label="Dustを回収"               },
  { key="cent_mac",label="Centrifuge   [mac+cent]",    in_label="Dustを投入",       out_label="精製Dustを回収"           },
  { key="wash",    label="OreWasher    [wash]",         in_label="Crushed*を投入",   out_label="PurifiedOre*を回収"       },
  { key="mac4",    label="Macerator #4 [wash]→Dust",   in_label="PurifiedOre*を投入",out_label="Dustを回収"              },
  { key="cent_wash",label="Centrifuge  [wash+cent]",   in_label="Dustを投入",       out_label="精製Dustを回収"           },
  { key="therm",   label="ThermalCentrifuge [thermal]",in_label="Crushed*を投入",   out_label="Centrifuged*を回収"       },
  { key="mac5",    label="Macerator #5 [thermal]→Dust",in_label="Centrifuged*を投入",out_label="Dustを回収"             },
  { key="output",  label="完成品ストレージ",             in_label="完成品を受け取る", out_label=nil                        },
}

function M.load()
  local f = io.open(CONFIG_PATH, "r")
  if not f then return {} end
  local data = f:read("*a")
  f:close()
  return serial.unserialize(data) or {}
end

function M.save(config)
  local f = io.open(CONFIG_PATH, "w")
  f:write(serial.serialize(config))
  f:close()
end

function M.configPath() return CONFIG_PATH end
return M