-- phira resource packs as skins: a pack (.zip) picked with android's file picker is unpacked in
-- phigros++/phira-skins/, and the one in use gives the notes, the hit effect and the hit sounds through the skin api.
-- its tab of the settings lists the packs with their notes and hit effect. using, importing or deleting a pack
-- reloads the mods, so the pack in use is only read as this file runs

local UE, IO, kit = CS.UnityEngine, CS.System.IO, phigrospp.ui
local TAB = "Phira skins"
local DIR = phigrospp.root .. "/phira-skins/"
local IN_USE = DIR .. "in-use" -- the folder of the pack in use, empty for the game's own notes
local IMAGES = { "click", "click_mh", "drag", "drag_mh", "flick", "flick_mh", "hold", "hold_mh", "hit_fx" }
local NOTES = { click = "tap", drag = "drag", flick = "flick" } -- the skin api's names, for sounds too
local ZIP = { "application/zip", "application/x-zip-compressed", "application/octet-stream" } -- providers disagree
local SLOPE = CS.SettingItemsManager.InverseSlope
local ROW, CARD, GAP = 112, 208, 16 -- the height of a row, of a pack's, and the space between two
local PERFECT, GOOD = 0xe1ffec9f, 0xebb4e1ff -- phira's colours of a perfect and of a good hit, for a pack without any
local WHITE, DIM, BLUE = { 1, 1, 1, 1 }, { 1, 1, 1, 0.5 }, { 0.56, 0.86, 1, 1 }
local FAINT, LIT = { 1, 1, 1, 0.08 }, { 1, 1, 1, 0.2 } -- a row, and the one in use

-- a value of info.yml: a number (0x... for a colour), true or false, a list, or a text with or without quotes
local function value(text)
  local list = text:match("^%[(.*)%]$")
  if list then
    local values = {}
    for item in list:gmatch("[^,]+") do values[#values + 1] = value(item:match("^%s*(.-)%s*$")) end
    return values
  end
  if text == "true" or text == "false" then return text == "true" end
  return tonumber(text) or text:match('^"(.*)"$') or text:match("^'(.*)'$") or text
end

-- info.yml has a key and its value per line. a list's values can also follow its key, a line with a dash each
local function parse(yaml)
  local info, key = {}, nil
  for line in yaml:gsub("^\239\187\191", ""):gmatch("[^\r\n]+") do
    line = line:gsub("%s+#.*$", "")
    local name, text = line:match("^(%a%w*)%s*:%s*(.-)%s*$")
    local item = line:match("^%s*%-%s*(.-)%s*$")
    if name then
      key, info[name] = name, text == "" and {} or value(text)
    elseif item and key then
      table.insert(info[key], value(item))
    end
  end
  return info
end

-- importing ------------------------------------------------------------------------------------------------------

-- a pack is someone else's data: what's wrong with it is an error written for the player
local function check(wrong, why)
  if wrong then error(why, 0) end
end

-- two whole numbers of info.yml, at least `least` each
local function pair(info, key, least)
  local list = info[key]
  check(type(list) ~= "table" or #list ~= 2, ("Its info.yml has no %s: [a, b]."):format(key))
  for _, n in ipairs(list) do
    check(math.type(n) ~= "integer" or n < least, ("%s of its info.yml isn't made of two whole numbers."):format(key))
  end
  return list[1], list[2]
end

-- unpacks the pack of a zip in its folder, named after the pack's name so importing it again replaces it. returns the
-- folder
local function unpack(data)
  local files, root = phigrospp.unzip(data), nil
  -- zipped with or without the folder it's in: the info.yml nearest to the top is the pack's
  for path in pairs(files) do
    local folder = path:match("^(.-)info%.yml$")
    if folder and (folder == "" or folder:sub(-1) == "/") and (not root or #folder < #root) then root = folder end
  end
  check(not root, "It has no info.yml, the file describing a Phira resource pack.")
  local info, scratch, kept = parse(files[root .. "info.yml"]), UE.Texture2D(2, 2), { "info.yml" }
  check(info.name == nil, "Its info.yml has no name.")
  for _, name in ipairs(IMAGES) do
    local png = files[root .. name .. ".png"]
    if png then
      check(not UE.ImageConversion.LoadImage(scratch, il2cpp.bytes(png)), name .. ".png isn't an image.")
      kept[#kept + 1] = name .. ".png"
      if name == "hit_fx" then
        -- a frame a third into the effect is the pack's picture in the list
        local columns, rows = pair(info, "hitFx", 1)
        local width, height, frame = scratch.width // columns, scratch.height // rows, columns * rows // 3
        check(width * height == 0, "hitFx of its info.yml has more frames than hit_fx.png has pixels.")
        local still = UE.Texture2D(width, height)
        still:SetPixels(scratch:GetPixels(frame % columns * width, scratch.height - (frame // columns + 1) * height,
          width, height))
        files[root .. "still.png"], kept[#kept + 1] = il2cpp.unbytes(UE.ImageConversion.EncodeToPNG(still)), "still.png"
      end
      if name:find("^hold") then
        local key = name == "hold" and "holdAtlas" or "holdAtlasMH"
        local tail, head = pair(info, key, 0)
        check(tail + head >= scratch.height, ("%s of its info.yml is taller than %s.png."):format(key, name))
      end
    end
  end
  for name in pairs(NOTES) do
    if files[root .. name .. ".ogg"] then kept[#kept + 1] = name .. ".ogg" end
  end
  check(#kept == 1, "It has none of the images and sounds of a Phira resource pack.")
  local folder = phigrospp.hex(phigrospp.crypto.sha512(tostring(info.name))):sub(1, 16)
  local dir = DIR .. folder
  if IO.Directory.Exists(dir) then IO.Directory.Delete(dir, true) end
  IO.Directory.CreateDirectory(dir)
  for _, name in ipairs(kept) do phigrospp.write(dir .. "/" .. name, files[root .. name]) end
  return folder
end

local function use(folder)
  phigrospp.write(IN_USE, folder)
  phigrospp.reload()
end

local function refuse(why) kit.confirm({ title = "This pack can't be used", message = why, yes = "OK", no = false }) end

local function import()
  local data, why = phigrospp.pick(table.unpack(ZIP))
  if not data then return why and refuse(why) end -- nothing when the player backed out
  local unpacked, folder = pcall(unpack, data)
  if not unpacked then return refuse(folder) end
  use(folder)
end

-- the packs ------------------------------------------------------------------------------------------------------

IO.Directory.CreateDirectory(DIR)
if not IO.File.Exists(IN_USE) then phigrospp.write(IN_USE, "") end
local inUse, packs, used = phigrospp.read(IN_USE), {}, nil

local folders = IO.DirectoryInfo(DIR):GetDirectories()
for i = 0, #folders - 1 do
  local folder = folders[i].Name
  local info = parse(phigrospp.read(DIR .. folder .. "/info.yml"))
  packs[#packs + 1] = { folder = folder, dir = DIR .. folder .. "/", info = info, name = tostring(info.name) }
  if folder == inUse then used = packs[#packs] end
end
table.sort(packs, function(a, b) return a.name:lower() < b.name:lower() end)

-- an image of a pack, read when the settings or a level first need it
local textures = {}
local function texture(path)
  textures[path] = textures[path] or phigrospp.texture(phigrospp.read(path))
  return textures[path]
end

-- a colour of info.yml, 0xaarrggbb or 0xrrggbb when it isn't see-through: its red, green, blue and alpha up to 255
local function channels(c) return c >> 16 & 255, c >> 8 & 255, c & 255, c > 0xffffff and c >> 24 or 255 end

local function delete(pack)
  if not kit.confirm({ title = "Delete " .. pack.name, message = "The pack can be imported again from its .zip.",
        yes = "Delete", danger = true }) then
    return
  end
  IO.Directory.Delete(pack.dir, true)
  use(pack == used and "" or inUse)
end

-- the tab: a row to import a pack, one for the game's own notes, then a card per pack with its hit effect, its name
-- and its tap, drag and flick. the one in use is lit and says so, a tap uses another
tab(TAB, nil, function(view, font)
  local area = view.rect
  local list = kit.list(view, "phira-skins", { 0, 0 }, { area.m_Width, area.m_Height }, math.floor(area.m_Width * 0.8))
  local y = 0
  -- names come from other people: texts never read markup
  local function write(parent, pos, size, said, tint, alignment, pivot)
    local text = kit.text(parent, "phira-skins-text", font, pos, { 0, 0 }, size, alignment or 3, pivot) -- MiddleLeft
    text.text, text.color, text.supportRichText = said, tint, false
  end
  local function tappable(shape, fn)
    shape.raycastTarget = true
    phigrospp.click(shape.gameObject:AddComponent(UE.UI.Button), fn)
  end
  -- a row with a title and a dimmer line under it, x from its left and `top` under its top. right is where what it
  -- says on its right ends
  local function row(height, x, top, title, line, lit, right, tap)
    local shape = kit.bar(list.rows, "phira-skins-row", { -y * SLOPE, -y }, { list.width, height },
      lit and LIT or FAINT)
    write(shape.transform, { x, height - top + 22 }, 36, title, WHITE)
    write(shape.transform, { x, height - top - 21 }, 26, line, DIM)
    if lit then write(shape.transform, { right, height - top }, 30, "In use", BLUE, 5, { 1, 0.5 }) end -- MiddleRight
    if not lit then tappable(shape, tap) end
    y = y + height + GAP
    return shape.transform
  end
  local right = list.width - 48
  row(ROW, 40, ROW / 2, "Import a pack", "Pick the .zip of a Phira resource pack", false, right, import)
  row(ROW, 40, ROW / 2, "Phigros", "The game's own notes, hit effect and sounds", not used, right,
    function() use("") end)
  for _, pack in ipairs(packs) do
    local function has(file) return IO.File.Exists(pack.dir .. file) end
    local card = row(CARD, 224, 52, pack.name, tostring(pack.info.author or ""), pack == used, right - 76,
      function() use(pack.folder) end)
    local function show(file, pos, box, tint)
      if not has(file) then return end
      local picture = kit.place(card, "phira-skins-picture", UE.UI.RawImage, pos, box)
      picture.color = tint
      kit.fit(picture, texture(pack.dir .. file))
    end
    -- its hit effect in the colour of a perfect hit, then its notes up to where the card's slanted end starts
    local r, g, b = channels(pack.info.hitFxTinted ~= false and (pack.info.colorPerfect or PERFECT) or 0xffffff)
    show("still.png", { 28, CARD / 2 }, { 168, 168 }, { r / 255, g / 255, b / 255, 1 })
    local width = (list.width - 224 - CARD * SLOPE - 48) / 3
    for i, file in ipairs({ "click.png", "drag.png", "flick.png" }) do
      show(file, { 224 + (i - 1) * width, 56 }, { width - 24, 84 }, WHITE)
    end
    local bin = kit.rect(card, "phira-skins-delete", { right, CARD - 52 }, { 44, 44 }, kit.danger, { 1, 0.5 })
    bin.sprite = kit.icon("trash-2")
    -- easier to hit than the bin
    local around = kit.rect(card, "phira-skins-delete-area", { right + 24, CARD - 52 }, { 92, 92 }, { 0, 0, 0, 0 },
      { 1, 0.5 })
    tappable(around, function() delete(pack) end)
  end
  list.content.sizeDelta = { 0, y + GAP }
end)

if not used then return end

-- the pack in use ------------------------------------------------------------------------------------------------

local dir, info = used.dir, used.info
local function has(file) return IO.File.Exists(dir .. file) end

-- phira draws a note's image as wide as the game draws its own, and its _mh image (the look of notes hit together,
-- wider by its glow) at the same scale: the pixels per unit of each group of kinds, set by its plain image
local units = {}

-- a kind of note wears what part(image, game) gives of an image, a texture and the rectangle to show of it, at the
-- pivot of the game's sprite
local function wear(kind, name, part)
  skin.note(kind, function(game)
    local image, group, size = texture(dir .. name .. ".png"), kind:match("^%a+"), game.rect
    units[group] = units[group] or image.width * game.pixelsPerUnit / size.m_Width
    local from, rect = part(image, game)
    return UE.Sprite.Create(from, rect, { game.pivot.x / size.m_Width, game.pivot.y / size.m_Height }, units[group])
  end)
end

local function whole(image) return image, { 0, 0, image.width, image.height } end

for file, kind in pairs(NOTES) do
  if has(file .. ".png") then
    wear(kind, file, whole)
    wear(kind .. "_multi", has(file .. "_mh.png") and file .. "_mh" or file, whole)
  end
  if has(file .. ".ogg") then hitsound(kind, dir .. file .. ".ogg") end
end

-- hold.png is a hold's tail over its body over its head, holdAtlas the heights of the tail and of the head. the game
-- stretches its body over the hold, the pack's is brought to the height of the game's first
local function hold(name, atlas, suffix)
  local tail, head = atlas[1], atlas[2]
  wear("hold_head" .. suffix, name, function(image) return image, { 0, 0, image.width, head } end)
  wear("hold" .. suffix, name, function(image, game)
    local rows = math.floor(game.rect.m_Height / game.pixelsPerUnit * units.hold + 0.5)
    return skin.stretch(image, head, image.height - head - tail, rows), { 0, 0, image.width, rows }
  end)
  -- the game has one tail for every hold
  if suffix == "" then
    wear("hold_tail", name, function(image) return image, { 0, image.height - tail, image.width, tail } end)
  end
end

if has("hold.png") then
  hold("hold", info.holdAtlas, "")
  if has("hold_mh.png") then hold("hold_mh", info.holdAtlasMH, "_multi") else hold("hold", info.holdAtlas, "_multi") end
end

local function hex(c) return ("#%02x%02x%02x%02x"):format(channels(c)) end
local perfect, good = hex(info.colorPerfect or PERFECT), hex(info.colorGood or GOOD)
if has("hit_fx.png") then
  local tinted = info.hitFxTinted ~= false
  skin.effect(dir .. "hit_fx.png", { columns = info.hitFx[1], rows = info.hitFx[2], seconds = info.hitFxDuration or 0.5,
    scale = info.hitFxScale or 1, perfect = tinted and perfect, good = tinted and good,
    sparks = not info.hideParticles })
end
-- phira's lines are of the same colours on an all perfect and on a full combo, the game's own unless the pack says
if info.colorPerfect or info.colorGood then skin.line({ ap = perfect:sub(1, 7), fc = good:sub(1, 7) }) end
