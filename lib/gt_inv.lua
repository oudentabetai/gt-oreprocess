-- /lib/gt_inv.lua
-- diamond_chest / minecraft:chest / inventory 等に対応した
-- 統一インベントリアクセスライブラリ
local component = require("component")
local M = {}

-- proxyキャッシュ
local cache = {}
local function proxy(addr)
  if not addr then return nil end
  if not cache[addr] then
    local ok, p = pcall(component.proxy, addr)
    cache[addr] = ok and p or false
  end
  return cache[addr] or nil
end

-- スロット総数
function M.size(addr)
  local p = proxy(addr)
  if not p then return nil end
  if p.size            then local ok,n = pcall(p.size);            return ok and n or nil end
  if p.getInventorySize then local ok,n = pcall(p.getInventorySize);return ok and n or nil end
  return nil
end

-- スロットのアイテム情報取得
-- 戻り値: { name, label, size/count } または nil
function M.getItem(addr, slot)
  local p = proxy(addr)
  if not p then return nil end
  local item = nil
  if p.getItemDetail  then local ok,v = pcall(p.getItemDetail, slot);  item = ok and v or nil end
  if not item and p.getStackInSlot then
    local ok,v = pcall(p.getStackInSlot, slot); item = ok and v or nil
  end
  if not item then return nil end
  -- countとsizeを統一
  item.count = item.count or item.size or 0
  return item
end

-- アイテムをfromのfromSlotからtoへ移動
-- toSlot=nilのとき自動で空きスロットへ
function M.transfer(fromAddr, fromSlot, toAddr, count, toSlot)
  local fromP = proxy(fromAddr)
  local toP   = proxy(toAddr)
  if not fromP or not toP then return 0 end

  count = count or 64

  -- pushItems(toAddr, fromSlot, count, toSlot) が使える場合
  if fromP.pushItems then
    local ok, n = pcall(fromP.pushItems, toAddr, fromSlot, count, toSlot)
    return ok and (n or 0) or 0
  end

  -- pullItems(fromAddr, fromSlot, count, toSlot) が使える場合
  if toP.pullItems then
    local ok, n = pcall(toP.pullItems, fromAddr, fromSlot, count, toSlot)
    return ok and (n or 0) or 0
  end

  -- transferItem(fromSlot, toAddr, toSlot, count) が使える場合
  if fromP.transferItem then
    local ok, n = pcall(fromP.transferItem, fromSlot, toAddr, toSlot, count)
    return ok and (n or 0) or 0
  end

  return 0
end

-- fromの全スロットをtoへ移動
function M.moveAll(fromAddr, toAddr)
  local size = M.size(fromAddr)
  if not size then return end
  for slot = 1, size do
    local item = M.getItem(fromAddr, slot)
    if item and item.count > 0 then
      M.transfer(fromAddr, slot, toAddr, item.count)
    end
  end
end

-- fromの全スロットをスキャンしてコールバックを呼ぶ
-- callback(slot, item) が true を返したらそのスロットの処理を続行
function M.scan(addr, callback)
  local size = M.size(addr)
  if not size then return end
  for slot = 1, size do
    local item = M.getItem(addr, slot)
    if item and item.count > 0 then
      callback(slot, item)
    end
  end
end

-- 接続中のインベントリ系コンポーネントを一覧取得
function M.listInventories()
  local list = {}
  for addr, ctype in component.list() do
    -- インベントリ系かどうかをproxyで確認
    local p = proxy(addr)
    if p and (p.size or p.getInventorySize or p.getItemDetail or p.getStackInSlot) then
      table.insert(list, { addr=addr, ctype=ctype })
    end
  end
  table.sort(list, function(a,b) return a.ctype < b.ctype end)
  return list
end

return M