-- Renders the full screen telemetry window to SVG with a real course and a
-- GPS fix, so the layout can be checked on the Mac before flashing the card.
--
-- Run: /tmp/node_modules/.bin/fengari tools/preview-telemetry.lua > /tmp/tel.svg
-- Then open /tmp/tel.svg in the browser pane.

local W, H = 320, 240
local out = {}

local COL = { 236, 240, 244 }

local function esc(s)
  s = tostring(s)
  s = s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
  return s
end

-- approximate DS-24 II glyph widths
local function textW(font, text)
  local n = #tostring(text)
  if font == 4 then return n * 12 end      -- FONT_MAXI
  if font == 3 then return n * 10 end      -- FONT_BIG
  if font == 2 then return n * 7 end       -- FONT_BOLD
  if font == 0 then return n * 5 end       -- FONT_MINI
  return n * 6
end

local function fontPx(font)
  if font == 4 then return 20 end
  if font == 3 then return 15 end
  if font == 2 then return 11 end
  if font == 0 then return 8 end
  return 10
end

local function fontFamily(font)
  if font == 2 or font == 3 or font == 4 then return "Helvetica,Arial,sans-serif" end
  return "Helvetica,Arial,sans-serif"
end

local function weight(font)
  if font == 2 or font == 3 or font == 4 then return "bold" end
  return "normal"
end

lcd = {
  getFgColor = function() return 0 end,
  setColor = function(r, g, b) COL = { r, g, b } end,
  drawText = function(x, y, text, font)
    font = font or 1
    out[#out + 1] = string.format(
      '<text x="%d" y="%d" font-family="%s" font-size="%d" font-weight="%s" fill="rgb(%d,%d,%d)">%s</text>',
      x, y + fontPx(font), fontFamily(font), fontPx(font), weight(font),
      COL[1], COL[2], COL[3], esc(text))
  end,
  drawLine = function(x1, y1, x2, y2)
    out[#out + 1] = string.format(
      '<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="rgb(%d,%d,%d)" stroke-width="1"/>',
      x1, y1, x2, y2, COL[1], COL[2], COL[3])
  end,
  drawRectangle = function(x, y, w, h, r)
    out[#out + 1] = string.format(
      '<rect x="%d" y="%d" width="%d" height="%d" rx="%d" fill="none" stroke="rgb(%d,%d,%d)" stroke-width="1"/>',
      x, y, w, h, r or 0, COL[1], COL[2], COL[3])
  end,
  drawFilledRectangle = function(x, y, w, h, alpha, specs)
    local op = (alpha and alpha < 255) and (alpha / 255) or 1
    out[#out + 1] = string.format(
      '<rect x="%d" y="%d" width="%d" height="%d" fill="rgb(%d,%d,%d)" fill-opacity="%.2f"/>',
      x, y, w, h, COL[1], COL[2], COL[3], op)
  end,
  getTextWidth = function(font, text) return textW(font, text) end,
}

KEY_1, KEY_2, KEY_3, KEY_4, KEY_5 = 1, 2, 3, 4, 5
KEY_UP, KEY_DOWN, KEY_ESC, KEY_ENTER, KEY_RELEASED = 6, 7, 8, 9, 10
MENU_APPS, MENU_MAIN, MENU_ADVANCED = 11, 12, 13
FONT_MINI, FONT_NORMAL, FONT_BOLD, FONT_BIG, FONT_MAXI = 0, 1, 2, 3, 4
ENABLED, DISABLED = true, false

local COURSE = {
  name = "Obri-obri", typ = "F3B", dist = 150,
  aLat = 50.60120, aLon = 14.20150,
  bLat = 50.60012, bLon = 14.20345,
}

-- model 4 m right of the A->B line, 60 m out
local MODEL = { 50.60096, 14.20262 }

local SENSORS = {
  { id = 823632641, param = 0, label = "GPSLog3",     unit = "na"  },
  { id = 823632641, param = 3, label = "Latitude",    unit = "LAT" },
  { id = 823632641, param = 4, label = "Longitude",   unit = "LON" },
  { id = 823632641, param = 5, label = "Speed",       unit = "kmh" },
  { id = 823632641, param = 9, label = "Flight Dir.", unit = "deg" },
}

local VALUES = { [5] = 27.4, [9] = 41 }

io = {
  mkdir = function() return true end,
  open = function() return nil end,
  readall = function() return '{"active":1}' end,
  write = function() return true end,
  close = function() return true end,
}
json = {
  encode = function() return "{}" end,
  decode = function() return { active = 1, courses = { COURSE } } end,
}

local rad = math.pi / 180
local function dist(la1, lo1, la2, lo2)
  local dLa, dLo = (la2 - la1) * rad, (lo2 - lo1) * rad
  local a = math.sin(dLa / 2) ^ 2 +
            math.cos(la1 * rad) * math.cos(la2 * rad) * math.sin(dLo / 2) ^ 2
  return 111320 * 2 * math.atan(math.sqrt(a), math.sqrt(1 - a))
end
local function brg(la1, lo1, la2, lo2)
  local dLo = (lo2 - lo1) * rad
  local y = math.sin(dLo) * math.cos(la2 * rad)
  local x = math.cos(la1 * rad) * math.sin(la2 * rad) -
            math.sin(la1 * rad) * math.cos(la2 * rad) * math.cos(dLo)
  return (math.atan(y, x) / rad) % 360
end

gps = {
  getPosition = function() return MODEL end,
  getValue    = function(p) return p[1], p[2] end,
  newPoint    = function(la, lo) return { la, lo } end,
  getDistance = function(p1, p2)
    return dist(p1[1], p1[2], p2[1], p2[2])
  end,
  getBearing = function(p1, p2) return brg(p1[1], p1[2], p2[1], p2[2]) end,
}

local params = {
  latId = 823632641, latParam = 3,
  lonId = 823632641, lonParam = 4,
  spdId = 823632641, spdParam = 5,
  hdgId = 823632641, hdgParam = 9,
}

system = {
  getTimeCounter = function() return 1000 end,
  getSensors = function() return SENSORS end,
  getSensorByID = function(id, param)
    return { valid = true, value = VALUES[param] or 0 }
  end,
  pLoad = function(k) return params[k] end,
  pSave = function() end,
  playBeep = function() end,
  messageBox = function() end,
  exitScript = function() end,
  registerTelemetry = function() return 1 end,
  setTelemetryButton = function() end,
  registerForm = function(no) return no end,
}

form = { addRow = function() return 1 end, addLabel = function() return 1 end,
         setButton = function() end, setTitle = function() end }

local app = assert(loadfile("Apps/f3xc.lua"))()
app.init()

-- the printFunction is captured by registerTelemetry; rebuild it by calling the
-- registered window through the same path the firmware uses
local telPrint
system.registerTelemetry = function(no, label, size, printFn, keyFn)
  telPrint = printFn
  return no
end
-- re-init so the registration goes through our capturing stub
app.init()

assert(telPrint, "no telemetry printFunction registered")
-- force one state update, then draw twice (first pass fills the cache)
telPrint(W, H)
out = {}
telPrint(W, H)

local svg = { string.format(
  '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">',
  W, H, W, H) }
svg[#svg + 1] = string.format('<rect width="%d" height="%d" fill="#000"/>', W, H)
for _, e in ipairs(out) do svg[#svg + 1] = e end
svg[#svg + 1] = "</svg>"

print(table.concat(svg, "\n"))
