local component = require("component")
local sides     = require("sides")
local term      = require("term")
local io        = require("io")
local gtRoutes  = require("gt_routes")

local inv = component.inventory_controller
local INPUT_SIDE = sides.north

local function printHeader()
  term.clear()
  print("╔══════════════════════════════════════╗")
  print("║   GregTech 鉱石ルート登録システム    ║")
  print("╚══════════════════════════════════════╝")
  print("")
end

local function scanInputChest()
  local size = inv.getInventorySize(INPUT_SIDE)
  if not size then
    return nil, "入力チェストが見つかりません"
  end
  for slot = 1, size do
    local item = inv.getStackInSlot(INPUT_SIDE, slot)
    if item then return item, nil end
  end
  return nil, "チェストが空です"
end

local function listRegistered(routes)
  local count = 0
  for _ in pairs(routes) do count = count + 1 end
  print("─── 登録済み: " .. count .. " 種類 ───")
  if count == 0 then
    print("  (なし)")
  else
    for name, info in pairs(routes) do
      -- 登録内容をわかりやすく表示
      local steps = {}
      if info.route == "mac" then
        table.insert(steps, "Mac→ImpureDust")
        if info.skip_mac2 then
          table.insert(steps, "[完成]")
        else
          table.insert(steps, "Mac→Dust")
          if info.use_centrifuge then table.insert(steps, "Centrifuge") end
        end
      elseif info.route == "wash" then
        table.insert(steps, "OreWasher→PurifiedOre")
        if info.skip_mac_after_wash then
          table.insert(steps, "[完成]")
        else
          table.insert(steps, "Mac→Dust")
          if info.use_centrifuge then table.insert(steps, "Centrifuge") end
        end
      elseif info.route == "thermal" then
        table.insert(steps, "ThermalCent→Centrifuged")
        table.insert(steps, "Mac→Dust")
      end
      print(string.format("  %-36s → %s", name, table.concat(steps, " → ")))
    end
  end
  print("")
end

-- y/n を聞くヘルパー
local function askYN(prompt)
  io.write(prompt .. " (y/n) > ")
  local ans = io.read()
  return ans == "y" or ans == "Y"
end

local function registerItem(routes)
  printHeader()
  print("入力チェストにアイテムを1種類入れてEnterを押してください")
  io.write("> ")
  io.read()

  local item, err = scanInputChest()
  if not item then
    print("[!] " .. err)
    os.sleep(2)
    return
  end

  print("")
  print("検出: " .. item.name .. (item.label and (" (" .. item.label .. ")") or ""))
  if routes[item.name] then
    print("  ※ 既に登録済みです")
  end
  print("")

  -- ルート選択
  print("── ルート選択 ──")
  print("  [1] mac     (Crushed → ImpureDust)")
  print("  [2] wash    (Crushed → PurifiedOre)")
  print("  [3] thermal (Crushed → Centrifuged → Dust ※固定)")
  print("")
  io.write("番号 > ")
  local choice = io.read()
  local routeMap = {["1"]="mac", ["2"]="wash", ["3"]="thermal"}
  local route = routeMap[choice]
  if not route then
    print("[!] 無効な選択です")
    os.sleep(1)
    return
  end

  local info = { route = route }

  if route == "mac" then
    -- ImpureDust → Macerator を行うか
    print("")
    print("ImpureDust をさらに Macerator にかけますか?")
    print("  y → ImpureDust → Macerator → Dust")
    print("  n → ImpureDust で完成 (そのまま出力)")
    info.skip_mac2 = not askYN("Maceratorにかける")

    if not info.skip_mac2 then
      -- Centrifuge を使うか
      info.use_centrifuge = askYN("Dust を Centrifuge にかける")
    end

  elseif route == "wash" then
    -- PurifiedOre → Macerator を行うか
    print("")
    print("PurifiedOre をさらに Macerator にかけますか?")
    print("  y → PurifiedOre → Macerator → Dust")
    print("  n → PurifiedOre で完成 (そのまま出力)")
    info.skip_mac_after_wash = not askYN("Maceratorにかける")

    if not info.skip_mac_after_wash then
      info.use_centrifuge = askYN("Dust を Centrifuge にかける")
    end

  elseif route == "thermal" then
    -- thermalは固定ルート
    info.use_centrifuge = false
    print("")
    print("thermalルートは Centrifuged → Macerator → Dust で固定です")
    os.sleep(1.5)
  end

  routes[item.name] = info
  gtRoutes.save(routes)

  print("")
  print("登録完了!")
  os.sleep(1.5)
end

-- メイン
printHeader()
local routes = gtRoutes.load()

while true do
  printHeader()
  listRegistered(routes)

  print("─── 操作 ───")
  print("  [r] 登録")
  print("  [d] 削除")
  print("  [q] 終了")
  print("")
  io.write("選択 > ")
  local cmd = io.read()

  if cmd == "q" then
    print("終了")
    break

  elseif cmd == "r" then
    registerItem(routes)
    routes = gtRoutes.load()  -- 保存後に再読み込み

  elseif cmd == "d" then
    printHeader()
    listRegistered(routes)
    io.write("削除するアイテム名 (Enterでキャンセル) > ")
    local target = io.read()
    if target ~= "" then
      if routes[target] then
        routes[target] = nil
        gtRoutes.save(routes)
        print("削除しました: " .. target)
      else
        print("[!] 未登録: " .. target)
      end
      os.sleep(1.5)
    end
  end
end