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
-- アドレスリスト取得ヘルパー（単一文字列・リスト・未設定に対応）
-- ============================================================
local function getAddrs(config, key, field)
  local e = config[key]
  if not e then return {} end
  local v = e[field]
  if not v then return {} end
  if type(v) == "string" then return {v} end
  return v
end

-- fromListの各スロットをtoListへ移動（複数チェスト対応）
local function moveAllMulti(fromList, toList)
  for _, from in ipairs(fromList) do
    local size = gtInv.size(from)
    if size then
      for slot = 1, size do
        local item = gtInv.getItem(from, slot)
        if item and item.count > 0 then
          local remaining = item.count
          for _, to in ipairs(toList) do
            if remaining <= 0 then break end
            local moved = gtInv.transfer(from, slot, to, remaining)
            remaining = remaining - (moved or 0)
          end
        end
      end
    end
  end
end

-- 1スロットのアイテムを複数の宛先へ順番に転送する
local function transferToMultiDest(src, slot, dsts, count)
  local remaining = count
  for _, dst in ipairs(dsts) do
    if remaining <= 0 then break end
    local moved = gtInv.transfer(src, slot, dst, remaining)
    remaining = remaining - (moved or 0)
  end
end

-- ============================================================
-- 搬送ステージ
-- ============================================================

-- Stage1: 投入ストレージ → Mac#1 入力crate
-- 登録済みの鉱石だけ転送
local function stage1(routes, C)
  local srcs = getAddrs(C, "input", "addr")
  local dsts = getAddrs(C, "mac1", "in_crate")
  if #srcs == 0 or #dsts == 0 then return end

  for _, src in ipairs(srcs) do
    gtInv.scan(src, function(slot, item)
      if routes[item.name] then
        transferToMultiDest(src, slot, dsts, item.count)
      else
        print("[未登録] " .. item.name)
      end
    end)
  end
end

-- Stage2: Mac#1 出力crate → ルート別入力crateへ振り分け
local function stage2(routes, C)
  local srcs = getAddrs(C, "mac1", "out_crate")
  if #srcs == 0 then return end

  for _, src in ipairs(srcs) do
    gtInv.scan(src, function(slot, item)
      local info = findInfo(item.name, routes)
      if not info then
        print("[振り分け不明] " .. item.name)
        return
      end
      local destKey = "mac2"
      if info.route == "wash"    then destKey = "wash"
      elseif info.route == "thermal" then destKey = "therm" end

      local dsts = getAddrs(C, destKey, "in_crate")
      transferToMultiDest(src, slot, dsts, item.count)
    end)
  end
end

-- Stage3: 各第1処理機械の出力crate → 次ステージへ
local function stage3(routes, C)
  -- [mac] Mac#2出力 → Mac#3入力 or 完成ストレージ
  local mac2outs = getAddrs(C, "mac2", "out_crate")
  for _, mac2out in ipairs(mac2outs) do
    gtInv.scan(mac2out, function(slot, item)
      local info = findInfo(item.name, routes)
      local dsts
      if info and not info.skip_mac2 then
        dsts = getAddrs(C, "mac3", "in_crate")
      else
        dsts = getAddrs(C, "output", "addr")
      end
      transferToMultiDest(mac2out, slot, dsts, item.count)
    end)
  end

  -- [wash] OreWasher出力 → Mac#4入力 or 完成ストレージ
  local washouts = getAddrs(C, "wash", "out_crate")
  for _, washout in ipairs(washouts) do
    gtInv.scan(washout, function(slot, item)
      local info = findInfo(item.name, routes)
      local dsts
      if info and not info.skip_mac_after_wash then
        dsts = getAddrs(C, "mac4", "in_crate")
      else
        dsts = getAddrs(C, "output", "addr")
      end
      transferToMultiDest(washout, slot, dsts, item.count)
    end)
  end

  -- [thermal] ThermalCentrifuge出力 → Mac#5入力（固定）
  local thermouts = getAddrs(C, "therm", "out_crate")
  local mac5ins   = getAddrs(C, "mac5", "in_crate")
  if #thermouts > 0 and #mac5ins > 0 then
    moveAllMulti(thermouts, mac5ins)
  end
end

-- Stage4: 各最終Mac出力crate → Centrifuge入力 or 完成ストレージ
local function stage4(routes, C)
  local outputs = getAddrs(C, "output", "addr")

  -- [mac] Mac#3出力
  local mac3outs = getAddrs(C, "mac3", "out_crate")
  for _, mac3out in ipairs(mac3outs) do
    gtInv.scan(mac3out, function(slot, item)
      local info = findInfo(item.name, routes)
      local dsts
      if info and info.use_centrifuge then
        dsts = getAddrs(C, "cent_mac", "in_crate")
      else
        dsts = outputs
      end
      transferToMultiDest(mac3out, slot, dsts, item.count)
    end)
  end

  -- [wash] Mac#4出力
  local mac4outs = getAddrs(C, "mac4", "out_crate")
  for _, mac4out in ipairs(mac4outs) do
    gtInv.scan(mac4out, function(slot, item)
      local info = findInfo(item.name, routes)
      local dsts
      if info and info.use_centrifuge then
        dsts = getAddrs(C, "cent_wash", "in_crate")
      else
        dsts = outputs
      end
      transferToMultiDest(mac4out, slot, dsts, item.count)
    end)
  end

  -- [thermal] Mac#5出力 → 完成ストレージ（固定）
  local mac5outs = getAddrs(C, "mac5", "out_crate")
  if #mac5outs > 0 and #outputs > 0 then
    moveAllMulti(mac5outs, outputs)
  end
end

-- Stage5: Centrifuge出力crate → 完成ストレージ
local function stage5(C)
  local outputs = getAddrs(C, "output", "addr")
  if #outputs == 0 then return end
  for _, key in ipairs({"cent_mac", "cent_wash"}) do
    local srcs = getAddrs(C, key, "out_crate")
    if #srcs > 0 then
      moveAllMulti(srcs, outputs)
    end
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