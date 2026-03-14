-- /gt_processor.lua
local os         = require("os")
local gtRoutes   = require("gt_routes")
local gtMachines = require("gt_machines")
local gtInv      = require("gt_inv")

-- ============================================================
-- 鉱石逆引き
-- ============================================================
local function extractMetal(oreName)
  return oreName:match("ore_(.-)_?%d*$")
      or oreName:match(":(.+)_ore$")
      or oreName:match(":ore_(.+)$")
      or oreName:match(":(.+)$")
end

local function findInfo(itemName, routes)
  if routes[itemName] then return routes[itemName] end
  for oreName, info in pairs(routes) do
    local metal = extractMetal(oreName)
    if metal and itemName:lower():find(metal:lower(), 1, true) then
      return info
    end
  end
  return nil
end

-- ============================================================
-- アドレス取得ヘルパー
-- ============================================================
local function addr(config, key, field)
  local e = config[key]
  if not e then return nil end
  return e[field] or e.addr
end

-- ============================================================
-- 搬送ステージ
-- ============================================================

-- Stage1: 投入ストレージ → Mac#1 入力crate
-- 登録済みの鉱石だけ転送
local function stage1(routes, C)
  local src = addr(C, "input", "addr")
  local dst = addr(C, "mac1", "in_crate")
  if not src or not dst then return end

  gtInv.scan(src, function(slot, item)
    if routes[item.name] then
      gtInv.transfer(src, slot, dst, item.count)
    else
      print("[未登録] " .. item.name)
    end
  end)
end

-- Stage2: Mac#1 出力crate → ルート別入力crateへ振り分け
local function stage2(routes, C)
  local src = addr(C, "mac1", "out_crate")
  if not src then return end

  gtInv.scan(src, function(slot, item)
    local info = findInfo(item.name, routes)
    if not info then
      print("[振り分け不明] " .. item.name)
      return
    end
    local destKey = "mac2"
    if info.route == "wash"    then destKey = "wash"
    elseif info.route == "thermal" then destKey = "therm" end

    local dst = addr(C, destKey, "in_crate")
    if dst then
      gtInv.transfer(src, slot, dst, item.count)
    end
  end)
end

-- Stage3: 各第1処理機械の出力crate → 次ステージへ
local function stage3(routes, C)
  -- [mac] Mac#2出力 → Mac#3入力 or 完成ストレージ
  local mac2out = addr(C, "mac2", "out_crate")
  if mac2out then
    gtInv.scan(mac2out, function(slot, item)
      local info = findInfo(item.name, routes)
      local dst
      if info and not info.skip_mac2 then
        dst = addr(C, "mac3", "in_crate")
      else
        dst = addr(C, "output", "addr")
      end
      if dst then gtInv.transfer(mac2out, slot, dst, item.count) end
    end)
  end

  -- [wash] OreWasher出力 → Mac#4入力 or 完成ストレージ
  local washout = addr(C, "wash", "out_crate")
  if washout then
    gtInv.scan(washout, function(slot, item)
      local info = findInfo(item.name, routes)
      local dst
      if info and not info.skip_mac_after_wash then
        dst = addr(C, "mac4", "in_crate")
      else
        dst = addr(C, "output", "addr")
      end
      if dst then gtInv.transfer(washout, slot, dst, item.count) end
    end)
  end

  -- [thermal] ThermalCentrifuge出力 → Mac#5入力（固定）
  local thermout = addr(C, "therm", "out_crate")
  local mac5in   = addr(C, "mac5", "in_crate")
  if thermout and mac5in then
    gtInv.moveAll(thermout, mac5in)
  end
end

-- Stage4: 各最終Mac出力crate → Centrifuge入力 or 完成ストレージ
local function stage4(routes, C)
  local output = addr(C, "output", "addr")

  -- [mac] Mac#3出力
  local mac3out = addr(C, "mac3", "out_crate")
  if mac3out then
    gtInv.scan(mac3out, function(slot, item)
      local info = findInfo(item.name, routes)
      local dst
      if info and info.use_centrifuge then
        dst = addr(C, "cent_mac", "in_crate")
      else
        dst = output
      end
      if dst then gtInv.transfer(mac3out, slot, dst, item.count) end
    end)
  end

  -- [wash] Mac#4出力
  local mac4out = addr(C, "mac4", "out_crate")
  if mac4out then
    gtInv.scan(mac4out, function(slot, item)
      local info = findInfo(item.name, routes)
      local dst
      if info and info.use_centrifuge then
        dst = addr(C, "cent_wash", "in_crate")
      else
        dst = output
      end
      if dst then gtInv.transfer(mac4out, slot, dst, item.count) end
    end)
  end

  -- [thermal] Mac#5出力 → 完成ストレージ（固定）
  local mac5out = addr(C, "mac5", "out_crate")
  if mac5out and output then
    gtInv.moveAll(mac5out, output)
  end
end

-- Stage5: Centrifuge出力crate → 完成ストレージ
local function stage5(C)
  local output = addr(C, "output", "addr")
  if not output then return end
  for _, key in ipairs({"cent_mac", "cent_wash"}) do
    local src = addr(C, key, "out_crate")
    if src then gtInv.moveAll(src, output) end
  end
end

-- ============================================================
-- メインループ
-- ============================================================
print("╔═══════════════════════════════════════╗")
print("║  GregTech 鉱石処理システム 起動       ║")
print("╚═══════════════════════════════════════╝")
print("停止: Ctrl+T")
print("")

local tick = 0
while true do
  local routes = gtRoutes.load()
  local C      = gtMachines.load()

  if tick == 0 then
    local rc, mc = 0, 0
    for _ in pairs(routes) do rc = rc + 1 end
    for _ in pairs(C)      do mc = mc + 1 end
    print("登録済み鉱石: " .. rc .. " 種類 / 割り当て済みストレージ: " .. mc .. " 台")
  end

  local ok, err = pcall(function()
    stage1(routes, C)
    stage2(routes, C)
    stage3(routes, C)
    stage4(routes, C)
    stage5(C)
  end)

  if not ok then
    print("[エラー] " .. tostring(err))
  end

  tick = tick + 1
  os.sleep(1)
end