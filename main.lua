-- raycaster --

local w, h = term.getSize(2)

local textures = {}
local texWidth, texHeight = 64, 64

local world = {}
local floorColor = 0x0
local ceilColor = 0x1

local function loadWorld()
  local n, cn = 0, 0
  for line in io.lines(shell.dir().."/world.txt") do
    world[n] = {}
    for c in line:gmatch(".") do
      world[n][cn] = tonumber("0x"..c) or 0
      cn = cn + 1
    end
    n = n + 1
    cn = 0
  end
end

-- textures use a custom format:
-- 1 byte: length of palette section
-- for each palette entry:
-- 1 byte: color ID
-- 3 bytes: RGB value
-- then raw texture data
local lastSetPal = 1
local function loadTexture(id, file)
  textures[id] = {}
  local tex = textures[id]
  local n = 0
  local handle = assert(io.open(shell.dir().."/textures/"..file))
  local palConv = {}
  local palLen = handle:read(1):byte()
  local r = 0
  local eq = 0
  while r < palLen do
    r = r + 4
    local colID = handle:read(1):byte()
    local rgb = string.unpack("<I3", handle:read(3))
    print("checking " .. lastSetPal .. " colors")
    for i=0, lastSetPal, 1 do
      local mr, mg, mb = term.getPaletteColor(i)
      mr, mg, mb = mr * 255, mg * 255, mb * 255
      local r, g, b = bit32.band(rgb, 0xff0000), bit32.band(rgb, 0x00ff00),
        bit32.band(rgb, 0x0000ff)
      if math.floor(r/16) == math.floor(mr/16) and
         math.floor(b/16) == math.floor(mb/16) and
         math.floor(g/16) == math.floor(mg/16) then
        palConv[colID] = i
        print(string.format("found match (%d,%d,%d) and (%d,%d,%d)",
          r, g, b, mr, mg, mb))
        eq = eq + 1
        break
      end
    end
    if not palConv[colID] then
      lastSetPal = lastSetPal + 2
      assert(lastSetPal < 256, "too many texture colors!")
      term.setPaletteColor(lastSetPal - 1,
        bit32.band(bit32.rshift(rgb, 1), 8355711))
      term.setPaletteColor(lastSetPal, rgb)
      palConv[colID] = lastSetPal
    end
  end
  print("found " .. eq .. " equal colors")
  --[[
  repeat
    local byte, rlen = (handle:read(1) or "0"):byte(),
      (handle:read(1) or "0"):byte()
    assert(byte == 0 or palConv[byte], "bad color " .. byte)
    for i=1, rlen, 1 do
      tex[n] = palConv[byte]
      n = n + 1
    end
  until rlen == 0
  --]]
  repeat
    local byte = handle:read(1)
    if byte then
      tex[n] = palConv[string.byte(byte)]
      n = n + 1
    end
  until not byte
  handle:close()
end

loadWorld()

local posX, posY = 2, 2
local dirX, dirY = -1, 0
local planeX, planeY = 0, 0.66

local time, oldTime = 0, 0

term.setGraphicsMode(2)

term.setPaletteColor(floorColor, 0x707070)
term.setPaletteColor(ceilColor, 0x383838)

loadTexture(1, "bluestone.tex")
loadTexture(2, "wood.tex")
loadTexture(3, "eagle.tex")
loadTexture(4, "purplestone.tex")
loadTexture(5, "redbrick.tex")
loadTexture(6, "greystone.tex")
loadTexture(7, "colorstone.tex")

local pressed = {}

local lastTimerID

local function castRay(x, invertX, invertY, drawBuf)
  local mapX = math.floor(posX + 0.5)
  local mapY = math.floor(posY + 0.5)

  local cameraX = 2 * x / w - 1
  local rayDirX = dirX + planeX * cameraX
  local rayDirY = dirY + planeY * cameraX
  if invertX then
    rayDirX = -rayDirX
  end
  if invertY then
    rayDirY = -rayDirY
  end
    
  local sideDistX, sideDistY

  local deltaDistX = (rayDirX == 0) and 1e30 or math.abs(1 / rayDirX)
  local deltaDistY = (rayDirY == 0) and 1e30 or math.abs(1 / rayDirY)
  local perpWallDist

  local stepX, stepY

  local hit = false
  local side

  if rayDirX < 0 then
    stepX = -1
    sideDistX = (posX - mapX) * deltaDistX
  else
    stepX = 1
    sideDistX = (mapX + 1 - posX) * deltaDistX
  end

  if rayDirY < 0 then
    stepY = -1
    sideDistY = (posY - mapY) * deltaDistY
  else
    stepY = 1
    sideDistY = (mapY + 1 - posY) * deltaDistY
  end

  while not hit do
    if sideDistX < sideDistY then
      sideDistX = sideDistX + deltaDistX
      mapX = mapX + stepX
      side = 0
    else
      sideDistY = sideDistY + deltaDistY
      mapY = mapY + stepY
      side = 1
    end
    if not (world[mapY] and world[mapY][mapX]) then
      hit = 0x0
    elseif world[mapY][mapX] ~= 0x0 then
      hit = world[mapY][mapX]
    end
  end

  if side == 0 then perpWallDist = (sideDistX - deltaDistX)
  else perpWallDist = sideDistY - deltaDistY end

  if drawBuf then
    local lineHeight = math.floor(h / perpWallDist)

    local drawStart = math.max(0, -lineHeight / 2 + h / 2)
    local drawEnd = math.min(h, lineHeight / 2 + h / 2)

    local color = hit
    if side == 0 then
      color = color + 1
      if color > 0xf then color = 0 end
    end

    local tex = textures[hit] or {}
    if #tex < texWidth*texHeight-2 then
      for i=0, h, 1 do
        drawBuf[i] = drawBuf[i] ..
          (i >= drawStart and i <= drawEnd and string.char(color)
       or (i < drawStart and "\x01")
       or "\x00")
      end
    else
      local wallX
      if side == 0 then wallX = posY + perpWallDist * rayDirY
      else wallX = posX + perpWallDist * rayDirX end
      wallX = wallX - math.floor(wallX)
      
      local texX = math.floor(wallX * texWidth)
      if side == 0 and rayDirX > 0 then texX = texWidth - texX - 1 end
      if side == 1 and rayDirY < 0 then texX = texWidth - texX - 1 end

      local step = texHeight / lineHeight
      local texPos = (drawStart - h / 2 + lineHeight / 2) * step
      for i=0, h, 1 do
        local color = "\x00"
        if (i >= drawStart and i < drawEnd) then
          local texY = bit32.band(math.floor(texPos+0.5), (texHeight - 1))
          texPos = texPos + step
          local _color = tex[texHeight * texY + texX] or 255
          if side == 1 then _color = math.max(0,math.min(255,_color - 1)) end
          color = string.char(_color)
        elseif i < drawStart then
          color = "\x01"
        end
        drawBuf[i] = drawBuf[i] .. color
      end
    end
  end

  return perpWallDist
end

local ftavg = 0
while true do
  local moveSpeed, rotSpeed

  local drawBuf = {}
  for i=0, h, 1 do drawBuf[i] = "" end
  for x = 0, w-1, 1 do
    castRay(x, false, false, drawBuf)
  end
  term.drawPixels(0, 0, drawBuf)
 
  oldTime = time
  time = os.epoch("utc")
  local frametime = (time - oldTime) / 1000
  ftavg = (ftavg + frametime) / (ftavg == 0 and 1 or 2)
  local fps = 1 / ftavg
  moveSpeed = frametime * 7
  rotSpeed = frametime * 3

  -- input handling
  if not lastTimerID then
    lastTimerID = os.startTimer(0)
  end
  local sig, code, rep = os.pullEventRaw()
  if sig == "terminate" then break end
  if sig == "timer" and code == lastTimerID then
    lastTimerID = nil
  elseif sig == "key" and not rep then
    pressed[code] = true
  elseif sig == "key_up" then
    pressed[code] = false
  end
  if pressed[keys.up] then
    local nposX = posX + dirX * moveSpeed
    local nposY = posY + dirY * moveSpeed
    local dist = math.min(castRay(math.floor(w * 0.5)),
      castRay(math.floor(w * 0.75)), castRay(math.floor(w * 0.25)))
    if dist > 0.8 then
    --if world[math.floor(posY+0.5)][math.floor(nposX+0.5)] == 0 then
      posX, posY = nposX, nposY end
  elseif pressed[keys.down] then
    local nposX = posX - dirX * moveSpeed
    local nposY = posY - dirY * moveSpeed
    local dist = math.min(castRay(math.floor(w * 0.5), true, true),
      castRay(math.floor(w * 0.75), true, true),
      castRay(math.floor(w * 0.25), true, true))
    if dist > 0.8 then
    --if world[math.floor(nposY+0.5)][math.floor(posX+0.5)] == 0 then
      posX, posY = nposX, nposY end
  end if pressed[keys.right] then
    local oldDirX = dirX
    dirX = dirX * math.cos(-rotSpeed) - dirY * math.sin(-rotSpeed)
    dirY = oldDirX * math.sin(-rotSpeed) + dirY * math.cos(-rotSpeed)
    local oldPlaneX = planeX
    planeX = planeX * math.cos(-rotSpeed) - planeY * math.sin(-rotSpeed)
    planeY = oldPlaneX * math.sin(-rotSpeed) + planeY * math.cos(-rotSpeed)
  end if pressed[keys.left] then
    local oldDirX = dirX
    dirX = dirX * math.cos(rotSpeed) - dirY * math.sin(rotSpeed)
    dirY = oldDirX * math.sin(rotSpeed) + dirY * math.cos(rotSpeed)
    local oldPlaneX = planeX
    planeX = planeX * math.cos(rotSpeed) - planeY * math.sin(rotSpeed)
    planeY = oldPlaneX * math.sin(rotSpeed) + planeY * math.cos(rotSpeed)
  end
end
term.setGraphicsMode(0)
print("Average FPS: " .. 1/ftavg)
