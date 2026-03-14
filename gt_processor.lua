-- /gt_processor.lua
local component = require("component")
local sides     = require("sides")
local os        = require("os")
local gtRoutes  = require("gt_routes")

local inv = component.inventory_controller

local C = {
  input          = sides.north,

  mac1_in        = sides.south,   -- Macerator#1 入力  (Ore → Crushed)
  mac1_out       = sides.east,    -- Macerator#1 出力

  mac2_in        = sides.west,    -- Macerator#2 入力  (Crushed → ImpureDust)
  mac2_out       = sides.up,      -- Macerator#2 出力

  mac3_in        = sides.down,    -- Macerator#3 入力  (ImpureDust → Dust)
  mac3_out       = sides.north,   -- Macerator#3 出力

  cent_mac_in    = sides.south,   -- Centrifuge入力    [mac + use_centrifuge]
  cent_mac_out   = sides.east,    -- Centrifuge出力

  wash_in        = sides.west,    -- OreWasher 入力
  wash_out       = sides.up,      -- OreWasher 出力

  mac4_in        = sides.down,    -- Macerator#4 入力  (PurifiedOre → Dust)
  mac4_out       = sides.north,   -- Macerator#4 出力

  cent_wash_in   = sides.south,   -- Centrifuge入力    [wash + use_centrifuge]
  cent_wash_out  = sides.east,    -- Centrifuge出力

  therm_in       = sides.west,    -- ThermalCentrifuge 入力
  therm_out      = sides.up,      -- ThermalCentrifuge 出力

  mac5_in        = sides.down,    -- Macerator#5 入力  (Centrifuged → Dust)
  mac5_out       = sides.north,   -- Macerator#5 出力

  output         = sides.south,
}

-- ============================================================
-- ユーティリティ
-- ============================================================
local function moveAll(from, to)
  local size = inv.getInventorySize(from)
  if not size then return end
  for slot = 1, size do
    local item = inv.getStackInSlot(from, slot)
    if item then
      inv.transferItem(from, to, item.size, slot)
    end
  end
end

local function extractMetal(oreName)
  return oreName:match("ore_(.-)_?%d*$")
      or oreName:match(":(.+)_ore$")
      or oreName:match(":ore_(.+)$")
      or oreName:match(":(.+)$")
end

local function findInfo(itemName, routes)
  -- 直接一致（生鉱石）
  if routes[itemName] then return routes[itemName] end
  -- 中間品から逆引き
  for oreName, info in pairs(routes) do
    local metal = extractMetal(oreName)
    if metal and itemName:lower():find(metal:lower(), 1, true) then
      return info
    end
  end
  return nil
end

-- ============================================================
-- 搬送ステージ
-- ============================================================

-- Stage1: 入力チェスト → Mac#1
local function stage1(routes)
  local size = inv.getInventorySize(C.input)
  if not size then return end
  for slot = 1, size do
    local item = inv.getStackInSlot(C.input, slot)
    if item then
      if routes[item.name] then
        inv.transferItem(C.input, C.mac1_in, item.size, slot)
      else
        print("[未登録] " .. item.name)
      end
    end
  end
end

-- Stage2: Crushed* → 各ルートの第1機械へ
local function stage2(routes)
  local size = inv.getInventorySize(C.mac1_out)
  if not size then return end
  for slot = 1, size do
    local item = inv.getStackInSlot(C.mac1_out, slot)
    if item then
      local info = findInfo(item.name, routes)
      if info then
        local dest = C.mac2_in
        if info.route == "wash"    then dest = C.wash_in
        elseif info.route == "thermal" then dest = C.therm_in end
        inv.transferItem(C.mac1_out, dest, item.size, slot)
      else
        print("[振り分け不明] " .. item.name)
      end
    end
  end
end

-- Stage3: 各第1機械の出力 → 次へ
local function stage3(routes)
  -- [mac] ImpureDust → Mac#3 or 出力（skip_mac2フラグで分岐）
  local s = inv.getInventorySize(C.mac2_out)
  if s then
    for slot = 1, s do
      local item = inv.getStackInSlot(C.mac2_out, slot)
      if item then
        local info = findInfo(item.name, routes)
        local dest = C.output
        if info and not info.skip_mac2 then
          dest = C.mac3_in
        end
        inv.transferItem(C.mac2_out, dest, item.size, slot)
      end
    end
  end

  -- [wash] PurifiedOre → Mac#4 or 出力（skip_mac_after_washフラグで分岐）
  local s2 = inv.getInventorySize(C.wash_out)
  if s2 then
    for slot = 1, s2 do
      local item = inv.getStackInSlot(C.wash_out, slot)
      if item then
        local info = findInfo(item.name, routes)
        local dest = C.output
        if info and not info.skip_mac_after_wash then
          dest = C.mac4_in
        end
        inv.transferItem(C.wash_out, dest, item.size, slot)
      end
    end
  end

  -- [thermal] Centrifuged → Mac#5（固定）
  moveAll(C.therm_out, C.mac5_in)
end

-- Stage4: 各最終Mac出力 → Centrifuge or 完成
local function stage4(routes)
  -- [mac] Dust
  local s = inv.getInventorySize(C.mac3_out)
  if s then
    for slot = 1, s do
      local item = inv.getStackInSlot(C.mac3_out, slot)
      if item then
        local info = findInfo(item.name, routes)
        local dest = (info and info.use_centrifuge) and C.cent_mac_in or C.output
        inv.transferItem(C.mac3_out, dest, item.size, slot)
      end
    end
  end

  -- [wash] Dust
  local s2 = inv.getInventorySize(C.mac4_out)
  if s2 then
    for slot = 1, s2 do
      local item = inv.getStackInSlot(C.mac4_out, slot)
      if item then
        local info = findInfo(item.name, routes)
        local dest = (info and info.use_centrifuge) and C.cent_wash_in or C.output
        inv.transferItem(C.mac4_out, dest, item.size, slot)
      end
    end
  end

  -- [thermal] Dust → 出力（固定）
  moveAll(C.mac5_out, C.output)
end

-- Stage5: Centrifuge出力 → 完成
local function stage5()
  moveAll(C.cent_mac_out,  C.output)
  moveAll(C.cent_wash_out, C.output)
end

-- ============================================================
-- メインループ
-- ============================================================
print("╔═══════════════════════════════════════╗")
print("║  GregTech 鉱石処理システム 起動       ║")
print("╚═══════════════════════════════════════╝")
print("停止: Ctrl+T")

local tick = 0
while true do
  local routes = gtRoutes.load()

  if tick == 0 then
    local count = 0
    for _ in pairs(routes) do count = count + 1 end
    print("登録済み: " .. count .. " 種類")
  end

  local ok, err = pcall(function()
    stage1(routes)
    stage2(routes)
    stage3(routes)
    stage4(routes)
    stage5()
  end)

  if not ok then print("[エラー] " .. tostring(err)) end

  tick = tick + 1
  os.sleep(1)
end