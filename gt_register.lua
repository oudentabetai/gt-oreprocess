-- /gt_register.lua
local component  = require("component")
local term       = require("term")
local io         = require("io")
local os         = require("os")
local gtRoutes   = require("gt_routes")
local gtMachines = require("gt_machines")
local gtInv      = require("gt_inv")

local function printHeader()
  term.clear()
  print("╔══════════════════════════════════════╗")
  print("║   GregTech 鉱石処理 設定システム     ║")
  print("╚══════════════════════════════════════╝")
  print("")
end

local function askYN(prompt)
  io.write(prompt .. " (y/n) > ")
  local ans = io.read()
  return ans == "y" or ans == "Y"
end

local function shortAddr(addr)
  if not addr then return "[ 未設定 ]" end
  return addr:sub(1,8) .. "..."
end

-- ============================================================
-- ストレージ割り当てモード
-- ============================================================
local function storageConfigMode()
  local config = gtMachines.load()

  while true do
    printHeader()
    print("─── ストレージ割り当て ───")
    print("")

    -- 現在の割り当て一覧を表示
    for i, def in ipairs(gtMachines.MACHINE_DEFS) do
      local entry = config[def.key] or {}
      -- input/outputは単体ストレージ、それ以外はin_crate/out_crate
      if def.key == "input" or def.key == "output" then
        local addr = entry.addr and shortAddr(entry.addr) or "[ 未設定 ]"
        print(string.format("  [%2d] %-12s %-12s  %s",
          i, def.key, addr, def.label))
      else
        local inAddr  = entry.in_crate  and shortAddr(entry.in_crate)  or "[ 未設定 ]"
        local outAddr = entry.out_crate and shortAddr(entry.out_crate) or "[ 未設定 ]"
        print(string.format("  [%2d] %-12s in:%-12s out:%-12s  %s",
          i, def.key, inAddr, outAddr, def.label))
      end
    end

    print("")
    print("  [a] 全ストレージを順番に割り当て")
    print("  [s] 接続ストレージ一覧を表示")
    print("  [q] 戻る")
    print("")
    io.write("番号 or a/s/q > ")
    local input = io.read()

    if input == "q" then
      break

    elseif input == "s" then
      printHeader()
      print("─── 接続中のストレージ ───")
      print("")
      local invs = gtInv.listInventories()
      if #invs == 0 then
        print("  ストレージが見つかりません")
        print("  AdapterとCableの接続を確認してください")
      else
        for i, v in ipairs(invs) do
          local sz = gtInv.size(v.addr) or "?"
          print(string.format("  [%2d] %-20s  slots:%-4s  %s",
            i, v.ctype, sz, v.addr))
        end
      end
      print("")
      io.write("Enterで戻る > ")
      io.read()

    elseif input == "a" then
      -- 全ストレージを順番に割り当て
      local invs = gtInv.listInventories()
      if #invs == 0 then
        print("ストレージが見つかりません")
        os.sleep(2)
      else
        for _, def in ipairs(gtMachines.MACHINE_DEFS) do
          -- input/outputは単体、それ以外はin/outペア
          local slots = {}
          if def.key == "input" or def.key == "output" then
            table.insert(slots, { field="addr", label=def.label })
          else
            table.insert(slots, { field="in_crate",  label=def.label .. " [入力]  " .. (def.in_label or "") })
            table.insert(slots, { field="out_crate", label=def.label .. " [出力]  " .. (def.out_label or "") })
          end

          for _, slot in ipairs(slots) do
            printHeader()
            print("割り当て中: " .. def.key .. "." .. slot.field)
            print("  " .. slot.label)
            local cur = (config[def.key] or {})[slot.field]
            print("  現在: " .. (cur and shortAddr(cur) or "未設定"))
            print("")

            -- ストレージ一覧
            print("─── 接続中のストレージ ───")
            for i, v in ipairs(invs) do
              local sz = gtInv.size(v.addr) or "?"
              -- 既に使用中かチェック
              local usedBy = ""
              for k, e in pairs(config) do
                if type(e) == "table" then
                  if e.addr == v.addr or e.in_crate == v.addr or e.out_crate == v.addr then
                    if k ~= def.key then
                      usedBy = "  ← " .. k .. " で使用中"
                    end
                  end
                end
              end
              print(string.format("  [%2d] %-20s slots:%-4s %s%s",
                i, v.ctype, sz, v.addr:sub(1,8).."...", usedBy))
            end
            print("  [0] スキップ")
            print("")
            io.write("番号 > ")
            local ans = io.read()
            local idx = tonumber(ans)

            if idx and idx > 0 and invs[idx] then
              if not config[def.key] then config[def.key] = {} end
              config[def.key][slot.field] = invs[idx].addr
              gtMachines.save(config)
              print("設定: " .. invs[idx].addr:sub(1,8) .. "...")
              os.sleep(0.4)
            elseif idx == 0 then
              print("スキップ")
              os.sleep(0.3)
            else
              print("[!] 無効な入力。スキップします")
              os.sleep(0.4)
            end
          end
        end
        print("")
        print("全割り当てを保存しました")
        os.sleep(1.5)
      end

    else
      -- 個別割り当て
      local idx = tonumber(input)
      if not idx or not gtMachines.MACHINE_DEFS[idx] then
        print("[!] 無効な入力です")
        os.sleep(0.8)
      else
        local def = gtMachines.MACHINE_DEFS[idx]
        local invs = gtInv.listInventories()
        local fields = {}
        if def.key == "input" or def.key == "output" then
          table.insert(fields, { field="addr", label=def.label })
        else
          table.insert(fields, { field="in_crate",  label=def.label .. " [入力]" })
          table.insert(fields, { field="out_crate", label=def.label .. " [出力]" })
        end

        for _, f in ipairs(fields) do
          printHeader()
          print("割り当て: " .. def.key .. "." .. f.field)
          print("  " .. f.label)
          local cur = (config[def.key] or {})[f.field]
          print("  現在: " .. (cur and shortAddr(cur) or "未設定"))
          print("")

          print("─── 接続中のストレージ ───")
          for i, v in ipairs(invs) do
            local sz = gtInv.size(v.addr) or "?"
            print(string.format("  [%2d] %-20s slots:%-4s %s",
              i, v.ctype, sz, v.addr:sub(1,8).."..."))
          end
          print("  [0] リセット")
          print("")
          io.write("番号 > ")
          local ans = io.read()
          local cidx = tonumber(ans)

          if cidx == 0 then
            if config[def.key] then config[def.key][f.field] = nil end
            gtMachines.save(config)
            print("リセットしました")
          elseif cidx and invs[cidx] then
            if not config[def.key] then config[def.key] = {} end
            config[def.key][f.field] = invs[cidx].addr
            gtMachines.save(config)
            print("設定しました: " .. invs[cidx].addr:sub(1,8) .. "...")
          else
            print("[!] 無効な入力です")
          end
          os.sleep(1)
        end
      end
    end
  end
end

-- ============================================================
-- 鉱石ルート登録
-- ============================================================
local function listRegistered(routes)
  local count = 0
  for _ in pairs(routes) do count = count + 1 end
  print("─── 登録済み鉱石: " .. count .. " 種類 ───")
  if count == 0 then
    print("  (なし)")
  else
    for name, info in pairs(routes) do
      local steps = {}
      if info.route == "mac" then
        table.insert(steps, "→ImpureDust")
        if info.skip_mac2 then
          table.insert(steps, "[完成]")
        else
          table.insert(steps, "→Dust")
          if info.use_centrifuge then table.insert(steps, "→Centrifuge") end
        end
      elseif info.route == "wash" then
        table.insert(steps, "→PurifiedOre")
        if info.skip_mac_after_wash then
          table.insert(steps, "[完成]")
        else
          table.insert(steps, "→Dust")
          if info.use_centrifuge then table.insert(steps, "→Centrifuge") end
        end
      elseif info.route == "thermal" then
        table.insert(steps, "→Centrifuged→Dust")
      end
      print(string.format("  %-36s %s", name, table.concat(steps, " ")))
    end
  end
  print("")
end

local function registerItem(routes)
  local config = gtMachines.load()
  local inputEntry = config["input"]
  if not inputEntry or not inputEntry.addr then
    print("[!] 投入ストレージが未設定です。先に [s] で設定してください")
    os.sleep(2)
    return
  end

  printHeader()
  print("投入ストレージにアイテムを1種類入れてEnterを押してください")
  print("(" .. inputEntry.addr .. ")")
  io.write("> ")
  io.read()

  -- スキャン
  local found = nil
  gtInv.scan(inputEntry.addr, function(slot, item)
    if not found then found = item end
  end)

  if not found then
    print("[!] ストレージが空です")
    os.sleep(2)
    return
  end

  print("")
  print("検出: " .. found.name .. (found.label and (" (" .. found.label .. ")") or ""))
  if routes[found.name] then print("  ※ 既に登録済みです") end
  print("")

  print("── ルート選択 ──")
  print("  [1] mac     (Crushed → ImpureDust)")
  print("  [2] wash    (Crushed → PurifiedOre)")
  print("  [3] thermal (Crushed → Centrifuged → Dust)")
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
    print("")
    info.skip_mac2 = not askYN("ImpureDust を Macerator にかける")
    if not info.skip_mac2 then
      info.use_centrifuge = askYN("Dust を Centrifuge にかける")
    end
  elseif route == "wash" then
    print("")
    info.skip_mac_after_wash = not askYN("PurifiedOre を Macerator にかける")
    if not info.skip_mac_after_wash then
      info.use_centrifuge = askYN("Dust を Centrifuge にかける")
    end
  elseif route == "thermal" then
    info.use_centrifuge = false
    print("thermalルートは Centrifuged → Macerator → Dust で固定です")
    os.sleep(1)
  end

  routes[found.name] = info
  gtRoutes.save(routes)
  print("")
  print("登録完了!")
  os.sleep(1.5)
end

-- ============================================================
-- メイン
-- ============================================================
printHeader()
local routes = gtRoutes.load()

while true do
  printHeader()
  listRegistered(routes)

  print("─── 操作 ───")
  print("  [r] 鉱石ルートを登録")
  print("  [d] 登録を削除")
  print("  [s] ストレージを割り当て")
  print("  [q] 終了")
  print("")
  io.write("選択 > ")
  local cmd = io.read()

  if cmd == "q" then
    print("終了")
    break
  elseif cmd == "r" then
    registerItem(routes)
    routes = gtRoutes.load()
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
  elseif cmd == "s" then
    storageConfigMode()
  end
end