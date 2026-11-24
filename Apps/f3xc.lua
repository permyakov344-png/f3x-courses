-- ###############################################################################################
-- #  F3X Courses  -  course manager / base-line helper for JETI DC/DS transmitters
-- #  Version 0.1.5  (Russian interface; full screen telemetry: bases A/B, A-B line)
-- #
-- #  Author of this app:  permyakov344-png
-- #
-- #  This app is inspired by, and in later steps will reuse the gate-detection approach of
-- #  "F3F Tool" by Frank Schreiber  ->  https://github.com/frank-sc/F3F-Tool-V2
-- #  All credit for that algorithm belongs to Frank Schreiber. See NOTICE.md.
-- #
-- #  This program is free software: you can redistribute it and/or modify it under the terms
-- #  of the GNU General Public License as published by the Free Software Foundation, either
-- #  version 3 of the License, or (at your option) any later version.
-- #  This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
-- #  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
-- #  See the GNU General Public License for more details: see the LICENSE file.
-- ###############################################################################################
-- #  What this version does (step A only):
-- #    - appears in Menu -> Applications as one entry: "F3X Courses"
-- #      with an internal "Sensors >>" page
-- #    - keeps a list of named courses in Apps/f3xc/courses.jsn  (survives power cycles)
-- #    - lets you create a course from the current GPS position, rename it, change type and
-- #      distance, delete it, choose the active one
-- #    - telemetry window shows the active course + live GPS state (proves sensor binding)
-- #    - sensor binding lists ALL telemetry values, not only type 9
-- #  Deliberately NOT in this version: A/B scan wizard, gate math, beeps. That is step B/C.
-- ###############################################################################################

local appName    = "F3X Courses"
local appVersion = "0.1.5"
local appAuthor  = "permyakov344-png"

local dataDir   = "Apps/f3xc"
local coursesFn = dataDir .. "/courses.jsn"

-- -----------------------------------------------------------------------------------------------
-- state
-- -----------------------------------------------------------------------------------------------
local S = { courses = {}, active = 1 }   -- persistent course store
local ui = { sel = 1 }                   -- current selection in the courses form
local C = {}                             -- form widget handles (courses form)
local SC = {}                            -- form widget handles (sensors form)
local msg = ""                           -- last status message shown in the courses form
local needReinit = false                 -- deferred form.reinit (safer than reinit inside a widget callback)
local sens = { lat = {}, lon = {}, spd = {}, hdg = {} }
local sensorMap = {}                     -- index -> {id=, param=, label=}
local sensorList = {}                    -- labels for the selectbox
local scrW, scrH = 0, 0

-- -----------------------------------------------------------------------------------------------
-- small helpers
-- -----------------------------------------------------------------------------------------------
local function beep(kind, length, freq)
  system.playBeep(kind or 0, length or 700, freq or 250)
end

local function ensureDir()
  pcall(function() io.mkdir("Apps") end)
  pcall(function() io.mkdir(dataDir) end)
end

local function readText(path)
  local txt = nil
  pcall(function() txt = io.readall(path) end)
  return txt
end

local function writeText(path, txt)
  local ok = false
  pcall(function()
    local f = io.open(path, "w")
    if f then
      io.write(f, txt)
      io.close(f)
      ok = true
    end
  end)
  return ok
end

-- -----------------------------------------------------------------------------------------------
-- course store
-- -----------------------------------------------------------------------------------------------
local function newCourse(name)
  return {
    name = name or "Новый курс",
    typ  = "F3B",
    dist = 150,
    aLat = nil, aLon = nil,
    bLat = nil, bLon = nil,
    brg  = nil,
    created = system.getTimeCounter(),
  }
end

local function loadCourses()
  S.courses = {}
  S.active  = 1
  local txt = readText(coursesFn)
  if txt and #txt > 0 then
    local ok, data = pcall(json.decode, txt)
    if ok and type(data) == "table" and type(data.courses) == "table" then
      S.courses = data.courses
      S.active  = tonumber(data.active) or 1
    end
  end
  if #S.courses == 0 then
    -- seed one empty course so the forms are never empty
    S.courses[1] = newCourse("Мой курс F3B")
  end
  if S.active < 1 or S.active > #S.courses then S.active = 1 end
end

local function saveCourses()
  local data = { appVersion = appVersion, active = S.active, courses = S.courses }
  local okEnc, txt = pcall(json.encode, data)
  if not okEnc or not txt then beep(2, 400, 400); return false end
  ensureDir()
  if not writeText(coursesFn, txt) then beep(2, 400, 400); return false end
  return true
end

local function activeCourse()
  return S.courses[S.active]
end

-- -----------------------------------------------------------------------------------------------
-- GPS / sensors
-- -----------------------------------------------------------------------------------------------
local function loadSensorCfg()
  local function get(key)
    local v = system.pLoad(key)
    if v == nil or v == 0 then return nil end
    return v
  end
  sens.lat.id = get("latId");  sens.lat.param = get("latParam")
  sens.lon.id = get("lonId");  sens.lon.param = get("lonParam")
  sens.spd.id = get("spdId");  sens.spd.param = get("spdParam")
  sens.hdg.id = get("hdgId");  sens.hdg.param = get("hdgParam")
end

local function saveSensorCfg(which)
  local s = sens[which]
  system.pSave(which .. "Id", s.id)
  system.pSave(which .. "Param", s.param)
end

local function bound(which)
  local s = sens[which]
  return s.id ~= nil and s.param ~= nil
end

-- returns lat, lon or nil
local function currentPos()
  if not (bound("lat") and bound("lon")) then return nil end
  local ok, p = pcall(gps.getPosition, sens.lat.id, sens.lat.param, sens.lon.param)
  if not ok or not p then return nil end
  local ok2, la, lo = pcall(gps.getValue, p)
  if not ok2 or la == nil or lo == nil then return nil end
  if la == 0 and lo == 0 then return nil end
  return la, lo
end

local function sensorValue(which)
  if not bound(which) then return nil end
  local ok, d = pcall(system.getSensorByID, sens[which].id, sens[which].param)
  if ok and d and d.valid then return d.value end
  return nil
end

-- build a flat list of every telemetry value (labels excluded)
local function buildSensorList()
  sensorList = { "---" }
  sensorMap  = { { id = nil, param = nil } }
  local ok, all = pcall(system.getSensors)
  if not ok or not all then return end
  local group = ""
  for _, s in ipairs(all) do
    if s.param == 0 then
      group = s.label or ""
    else
      local text = string.format("%s / %s [%s]", group, s.label or "?", s.unit or "")
      sensorList[#sensorList + 1] = text
      sensorMap[#sensorMap + 1]  = { id = s.id, param = s.param }
    end
  end
end

local function indexOfSensor(which)
  local s = sens[which]
  if s.id == nil then return 1 end
  for i = 2, #sensorMap do
    if sensorMap[i].id == s.id and sensorMap[i].param == s.param then return i end
  end
  return 1
end

-- known GPS sensors: group label -> param of lat / lon / speed / heading
-- GPSLog3 is the JETI GPS Logger 3; params taken from a real DS-24 II model file
local KNOWN = {
  { name = "gpslog3", lat = 3, lon = 4, spd = 5, hdg = 9 },
}

-- bind by the exact sensor/param known for a GPS we have seen in the field.
-- Returns 1 if a known profile was applied.
local function bindKnownProfile()
  local ok, all = pcall(system.getSensors)
  if not ok or type(all) ~= "table" then return 0 end

  local function lower(v) return string.lower(tostring(v or "")) end

  for _, k in ipairs(KNOWN) do
    -- 1) preferred: the group row (param 0) carries the sensor name, e.g. "GPSLog3"
    local id = nil
    for _, e in ipairs(all) do
      if e.param == 0 and e.id and lower(e.label) == k.name then id = e.id; break end
    end
    -- 2) fallback: any row labelled "Latitude" from a GPS of a different brand name
    if not id then
      for _, e in ipairs(all) do
        if e.param ~= 0 and e.id and lower(e.label) == "latitude" then id = e.id; break end
      end
    end

    if id then
      for _, e in ipairs(all) do
        if e.id == id and e.param ~= 0 then
          local pick
          if e.param == k.lat then pick = "lat"
          elseif e.param == k.lon then pick = "lon"
          elseif e.param == k.spd then pick = "spd"
          elseif e.param == k.hdg then pick = "hdg" end
          if pick and not bound(pick) then
            sens[pick].id, sens[pick].param = e.id, e.param
            saveSensorCfg(pick)
          end
        end
      end
      return 1
    end
  end
  return 0
end

-- one-time guess: pick plausible index for each of the four values
local function guessSensors()
  if #sensorMap < 2 then return end

  -- a GPS we know by name beats any heuristic
  bindKnownProfile()

  local keys = {
    lat = { "lat" },
    lon = { "lon" },
    spd = { "speed", "gspeed", "velocity" },
    hdg = { "head", "dir", "cour", "bear", "azim" },
  }
  for which, pats in pairs(keys) do
    if not bound(which) then
      for i = 2, #sensorMap do
        local low = string.lower(sensorList[i])
        for _, p in ipairs(pats) do
          if string.find(low, p, 1, true) then
            sens[which].id = sensorMap[i].id
            sens[which].param = sensorMap[i].param
            saveSensorCfg(which)
            break
          end
        end
        if bound(which) then break end
      end
    end
  end
end

-- -----------------------------------------------------------------------------------------------
-- telemetry window: full screen, bases A/B, line deviation, live diagnostics
-- size 3 reserves the whole screen (status bar stays at the bottom left) and is
-- the only size that also receives key presses        -- API 1.7, registerTelemetry
-- -----------------------------------------------------------------------------------------------
local TL = {
  bg     = {  10,  14,  18 },
  panel  = {  26,  32,  40 },
  panel2 = {  36,  44,  54 },
  edge   = {  58,  70,  84 },
  text   = { 236, 240, 244 },
  dim    = { 136, 146, 158 },
  ok     = {  62, 200, 112 },
  warn   = { 246, 190,  62 },
  bad    = { 236,  86,  86 },
  accent = {   0, 198, 255 },
}

local function tlColor(c) lcd.setColor(c[1], c[2], c[3]) end

local function tlFill(x, y, w, h, c)
  if w <= 0 or h <= 0 then return end
  tlColor(c)
  lcd.drawFilledRectangle(math.floor(x), math.floor(y),
                          math.floor(w), math.floor(h))
end

local function tlFrame(x, y, w, h, c)
  if w <= 0 or h <= 0 then return end
  tlColor(c)
  lcd.drawRectangle(math.floor(x), math.floor(y),
                    math.floor(w), math.floor(h))
end

local function tlText(x, y, text, font, c)
  tlColor(c or TL.text)
  lcd.drawText(math.floor(x), math.floor(y), tostring(text), font or FONT_NORMAL)
end

local function tlWidth(text, font)
  local ok, r = pcall(lcd.getTextWidth, font or FONT_NORMAL, tostring(text))
  if ok and type(r) == "number" then return r end
  return #tostring(text) * 7
end

local function tlTextRight(xr, y, text, font, c)
  tlText(xr - tlWidth(text, font), y, text, font, c)
end

local function tlTextCenter(x, w, y, text, font, c)
  tlText(x + (w - tlWidth(text, font)) / 2, y, text, font, c)
end

local function tlDivider(x, y, w, c)
  tlColor(c or TL.edge)
  lcd.drawLine(math.floor(x), math.floor(y), math.floor(x + w), math.floor(y))
end
-- -----------------------------------------------------------------------------------------------
-- live telemetry state (recomputed at most every 400 ms, drawing is on a timer)
-- -----------------------------------------------------------------------------------------------
local T = {
  la = nil, lo = nil, fix = false, fixAge = -1,
  spd = nil, hdg = nil, alt = nil,
  dA = nil, brgA = nil, dB = nil, brgB = nil,
  off = nil, along = nil,          -- deviation from the A->B line, metres
  at = 0,
}

local TEL_PERIOD = 400

-- short-lived toast for key actions (declared before the drawer uses it)
local telMsg, telMsgUntil = "", 0

local function geoDist(la1, lo1, la2, lo2)
  local ok, d = pcall(function()
    return gps.getDistance(gps.newPoint(la1, lo1), gps.newPoint(la2, lo2))
  end)
  if ok and type(d) == "number" then return d end
  -- fallback: haversine
  local rad = math.pi / 180
  local dLa = (la2 - la1) * rad
  local dLo = (lo2 - lo1) * rad
  local a = math.sin(dLa / 2) ^ 2 +
            math.cos(la1 * rad) * math.cos(la2 * rad) * math.sin(dLo / 2) ^ 2
  if a < 0 then a = 0 end
  if a > 1 then a = 1 end
  return 111320 * 2 * math.atan(math.sqrt(a), math.sqrt(1 - a))
end

local function geoBrg(la1, lo1, la2, lo2)
  local ok, b = pcall(function()
    return gps.getBearing(gps.newPoint(la1, lo1), gps.newPoint(la2, lo2))
  end)
  if ok and type(b) == "number" then return b % 360 end
  local rad = math.pi / 180
  local dLo = (lo2 - lo1) * rad
  local y = math.sin(dLo) * math.cos(la2 * rad)
  local x = math.cos(la1 * rad) * math.sin(la2 * rad) -
            math.sin(la1 * rad) * math.cos(la2 * rad) * math.cos(dLo)
  return (math.atan(y, x) / rad) % 360
end

-- position of the model relative to the A->B baseline:
--   off   = signed perpendicular distance, metres (+ = right of A->B direction)
--   along = distance already covered from A towards B
local function baselineOffset(c, la, lo)
  if not (c and c.aLat and c.aLon and c.bLat and c.bLon and la) then return nil, nil end
  local brg = geoBrg(c.aLat, c.aLon, c.bLat, c.bLon)
  local brgP = geoBrg(c.aLat, c.aLon, la, lo)
  local dAP = geoDist(c.aLat, c.aLon, la, lo)
  local rad = math.pi / 180
  local dAng = (brgP - brg) * rad
  return dAP * math.sin(dAng), dAP * math.cos(dAng)
end

local function updateTelemetry()
  local now = system.getTimeCounter()
  if now - T.at < TEL_PERIOD then return end
  T.at = now

  local la, lo = currentPos()
  if la then
    if not T.fix or T.la ~= la or T.lo ~= lo then T.fixAge = 0 end
    T.fix = true
    T.la, T.lo = la, lo
    if T.fixAge >= 0 then T.fixAge = T.fixAge + TEL_PERIOD end
  else
    T.fix = false
    T.la, T.lo = nil, nil
    T.fixAge = -1
  end

  T.spd = sensorValue("spd")
  T.hdg = sensorValue("hdg")

  local c = activeCourse()
  T.dA, T.brgA, T.dB, T.brgB, T.off, T.along = nil, nil, nil, nil, nil, nil

  if la and c then
    if c.aLat and c.aLon then
      T.dA   = geoDist(la, lo, c.aLat, c.aLon)
      T.brgA = geoBrg(la, lo, c.aLat, c.aLon)
    end
    if c.bLat and c.bLon then
      T.dB   = geoDist(la, lo, c.bLat, c.bLon)
      T.brgB = geoBrg(la, lo, c.bLat, c.bLon)
    end
    T.off, T.along = baselineOffset(c, la, lo)
  end
end

-- what is missing for a course, in plain words, with a colour
local function sensorsBoundCount()
  local n = 0
  for _, k in ipairs({ "lat", "lon", "spd", "hdg" }) do
    if bound(k) then n = n + 1 end
  end
  return n
end
-- -----------------------------------------------------------------------------------------------
-- drawing blocks
-- -----------------------------------------------------------------------------------------------
local function fmtDist(d)
  if d == nil then return "--" end
  if d >= 1000 then return string.format("%.2f км", d / 1000) end
  return string.format("%.1f м", d)
end

local function fmtBearing(b)
  if b == nil then return "--" end
  return string.format("%03.0f", b % 360)
end

-- compass letter for a bearing, so the number reads at a glance
local function brgLetter(b)
  if b == nil then return "?" end
  local dirs = { "С", "СВ", "В", "ЮВ", "Ю", "ЮЗ", "З", "СЗ" }
  local i = math.floor((b % 360) / 45 + 0.5) % 8 + 1
  return dirs[i]
end

local function drawHeader(x, y, w)
  local c = activeCourse()
  local name = c and tostring(c.name) or "нет активного курса"
  tlFill(x, y, w, 26, TL.panel)
  tlFill(x, y, 4, 26, c and TL.accent or TL.bad)
  tlText(x + 10, y + 5, name, FONT_BOLD, TL.text)

  local pillW = 92
  local px = x + w - pillW - 6
  tlFill(px, y + 4, pillW, 18, T.fix and TL.ok or TL.bad)
  tlTextCenter(px, pillW, y + 6, T.fix and "GPS ЕСТЬ" or "GPS НЕТ",
               FONT_BOLD, TL.bg)
end

-- one base tile: A or B
local function drawBaseTile(x, y, w, h, letter, c, dist, brg, which)
  local has = c and c[which .. "Lat"] and c[which .. "Lon"]
  tlFill(x, y, w, h, TL.panel)
  tlFrame(x, y, w, h, has and TL.edge or TL.warn)

  local badge = 28
  tlFill(x + 7, y + 7, badge, badge, has and TL.accent or TL.warn)
  tlTextCenter(x + 7, badge, y + 11, letter, FONT_BIG, TL.bg)

  local tx = x + 7 + badge + 7
  if has then
    tlText(tx, y + 4, fmtDist(dist), FONT_BIG, TL.text)
    tlText(tx, y + 28,
           (brg and (brgLetter(brg) .. " " .. fmtBearing(brg) .. "°")) or "--",
           FONT_NORMAL, TL.accent)
    tlText(tx, y + 46, string.format("%.5f", c[which .. "Lat"]), FONT_MINI, TL.dim)
    tlText(tx, y + 58, string.format("%.5f", c[which .. "Lon"]), FONT_MINI, TL.dim)
  else
    tlText(tx, y + 6, "не задана", FONT_BOLD, TL.warn)
    tlText(tx, y + 28, which == "a" and "нажмите F1" or "шаг B: мастер",
           FONT_MINI, TL.dim)
  end
end
-- deviation from the A->B line: a bar with the centre at zero
local GAUGE_RANGE = 30      -- metres shown either side of the line

local function drawGauge(x, y, w, h, off, along, c)
  tlFill(x, y, w, h, TL.panel)

  local has = (off ~= nil)
  local title = "ЛИНИЯ A-B"
  local value, color, word
  if not (c and c.aLat and c.bLat) then
    value, color, word = "--", TL.dim, "задайте базы"
  elseif not T.fix then
    value, color, word = "--", TL.dim, "нет GPS"
  elseif has then
    if math.abs(off) < 0.5 then
      word = "НА ЛИНИИ"
      color = TL.ok
    elseif off > 0 then
      word = "ПРАВЕЕ"
      color = TL.warn
    else
      word = "ЛЕВЕЕ"
      color = TL.warn
    end
    value = string.format("%.1f м", math.abs(off))
  else
    value, color, word = "--", TL.dim, "нет данных"
  end

  tlText(x + 8, y + 4, title, FONT_MINI, TL.dim)
  tlText(x + 8, y + 14, word, FONT_BOLD, color)
  tlTextRight(x + w - 8, y + 12, value, FONT_BIG, color)

  -- distance covered along the line, in the title row, clear of the bar
  if along and c and c.dist then
    tlTextRight(x + w - 8, y + 4,
                string.format("%.0f / %.0f м", along, tonumber(c.dist) or 0),
                FONT_MINI, TL.dim)
  end

  -- bar geometry
  local bx, bw = x + 8, w - 16
  local by = y + h - 26
  if bw < 40 or by < y + 30 then return end

  tlFill(bx, by, bw, 8, TL.panel2)
  -- centre tick = the line itself
  tlFill(bx + bw / 2 - 1, by - 3, 2, 14, TL.accent)

  if has then
    local clamped = off
    if clamped > GAUGE_RANGE then clamped = GAUGE_RANGE end
    if clamped < -GAUGE_RANGE then clamped = -GAUGE_RANGE end
    local px = bx + bw / 2 + (clamped / GAUGE_RANGE) * (bw / 2)
    tlFill(px - 3, by - 2, 6, 12, color)
  end

  -- scale marks so the bar has a meaning
  tlText(bx, by + 10, "-" .. GAUGE_RANGE, FONT_MINI, TL.dim)
  tlTextCenter(bx, bw, by + 10, "0", FONT_MINI, TL.dim)
  tlTextRight(bx + bw, by + 10, "+" .. GAUGE_RANGE .. " м", FONT_MINI, TL.dim)
end

-- bottom strip: sensor chips + speed/heading, so a missing piece is obvious
local function drawStatus(x, y, w, h)
  tlFill(x, y, w, h, TL.panel)
  local rowY = y + 6

  local okFix = T.fix
  tlFill(x + 6, rowY, 56, 18, okFix and TL.ok or TL.bad)
  tlTextCenter(x + 6, 56, rowY + 2, okFix and "ФИКС" or "НЕТ", FONT_MINI, TL.bg)

  local spd = T.spd
  tlText(x + 68, rowY + 2,
         spd and string.format("%.1f км/ч", spd) or "скор --", FONT_NORMAL,
         spd and TL.text or TL.dim)

  local hdg = T.hdg
  tlText(x + 168, rowY + 2,
         hdg and string.format("%03.0f° %s", hdg, brgLetter(hdg)) or "курс --",
         FONT_NORMAL, hdg and TL.text or TL.dim)

  -- binding summary: how many of the four values are bound
  local n = sensorsBoundCount()
  local col = (n >= 4) and TL.ok or ((n >= 2) and TL.warn or TL.bad)
  local label = string.format("ДАТЧИКИ %d/4", n)
  tlTextRight(x + w - 8, rowY + 2, label, FONT_MINI, col)
end
-- the one line that tells you what to do next; a key action's toast takes it over
local function nextHint(c)
  if not (bound("lat") and bound("lon")) then
    return "GPS не привязан: нажмите F3", TL.bad
  end
  if not T.fix then
    return "GPS привязан, ждём фикс (модель, приёмник)", TL.warn
  end
  if not c then
    return "Нет активного курса: F1 создаст здесь", TL.warn
  end
  if not (c.aLat and c.aLon) then
    return "База A пуста: встаньте на A, нажмите F1", TL.warn
  end
  if not (c.bLat and c.bLon) then
    return "База B пуста: мастер A/B ещё не сделан", TL.warn
  end
  if T.off == nil then
    return "Обе базы есть, ждём позицию для линии", TL.dim
  end
  return "Готово: до A и линия A-B считаются", TL.ok
end

local function drawHint(x, y, w, c)
  local text, color
  if #telMsg > 0 and system.getTimeCounter() < telMsgUntil then
    text, color = telMsg, TL.accent
  else
    text, color = nextHint(c)
  end
  tlFill(x, y, w, 16, TL.panel2)
  tlText(x + 6, y + 3, text, FONT_MINI, color)
end

-- -----------------------------------------------------------------------------------------------
-- full screen layout: two base tiles on top, line gauge, status strip
-- -----------------------------------------------------------------------------------------------
local function drawTelemetryBody(w, h)
  scrW, scrH = w, h
  updateTelemetry()
  local c = activeCourse()

  tlFill(0, 0, w, h, TL.bg)

  -- size 3 keeps the transmitter status bar at the bottom left: reserve it
  local bottom = (h >= 200) and 22 or 4
  local pad = 5
  local avail = h - bottom

  drawHeader(pad, pad, w - pad * 2)

  local gap = 5
  local y = pad + 26 + gap
  local tileH = 74
  local gaugeH = 62
  local statusH = 26
  local hintH = 16

  -- shrink gracefully: gauge first, then the tiles, then drop the hint line
  local room = avail - y - pad
  local tileH, gaugeH, statusH, hintH = 74, 62, 26, 16
  local need = tileH + gap + gaugeH + gap + statusH + gap + hintH
  if room < need then
    local short = need - room
    local cut = math.min(short, gaugeH - 44)          -- 1) shorter gauge
    gaugeH = gaugeH - cut
    short = short - cut
    if short > 0 then
      local cut2 = math.min(short, tileH - 46)        -- 2) shorter tiles
      tileH = tileH - cut2
      short = short - cut2
    end
    if short > 0 then hintH = 0 end                   -- 3) no hint line
  end

  local tileW = (w - pad * 2 - gap) / 2
  drawBaseTile(pad, y, tileW, tileH, "A", c, T.dA, T.brgA, "a")
  drawBaseTile(pad + tileW + gap, y, tileW, tileH, "B", c, T.dB, T.brgB, "b")
  y = y + tileH + gap

  if gaugeH >= 44 then
    drawGauge(pad, y, w - pad * 2, gaugeH, T.off, T.along, c)
    y = y + gaugeH + gap
  end

  drawStatus(pad, y, w - pad * 2, statusH)
  y = y + statusH + gap

  if hintH > 0 then
    drawHint(pad, y, w - pad * 2, c)
  end
end

-- telemetry windows are drawn on a timer; never let a runtime error kill the widget
local telLastErr = nil
local function drawTelemetry(w, h)
  local ok, err = pcall(drawTelemetryBody, w, h)
  if not ok then
    telLastErr = tostring(err)
    pcall(function()
      tlFill(0, 0, w, h, TL.bg)
      tlText(6, 6, appName .. " " .. appVersion, FONT_BOLD, TL.text)
      tlText(6, 30, "ошибка отрисовки", FONT_BOLD, TL.bad)
      tlText(6, 50, telLastErr:sub(1, 60), FONT_MINI, TL.dim)
    end)
  end
end

-- keys of the full screen telemetry window (API 1.7: only size 3+ gets keys)
local function telSay(text)
  telMsg = tostring(text)
  telMsgUntil = system.getTimeCounter() + 2500
end

local function keyTelemetryBody(key)
  if key == KEY_1 then                        -- new course from here
    local la, lo = currentPos()
    if not la then
      beep(2, 500, 250)
      telSay("нет GPS")
      return
    end
    local c = newCourse(string.format("Курс %d", #S.courses + 1))
    c.aLat, c.aLon = la, lo
    S.courses[#S.courses + 1] = c
    S.active = #S.courses
    saveCourses()
    beep(0, 600, 650)
    telSay(string.format("новый курс, A = %.5f %.5f", la, lo))

  elseif key == KEY_2 then                    -- next course
    if #S.courses > 1 then
      S.active = S.active % #S.courses + 1
      saveCourses()
      beep(0, 400, 700)
      telSay("курс " .. S.active .. ": " .. tostring(activeCourse().name))
    else
      telSay("курс только один")
    end

  elseif key == KEY_3 then                    -- rebind sensors from live telemetry
    buildSensorList()
    sens.lat.id, sens.lat.param = nil, nil
    local ok = pcall(guessSensors)
    beep(ok and 0 or 2, 400, ok and 800 or 300)
    telSay(string.format("датчики %d/4 привязаны", sensorsBoundCount()))

  elseif key == KEY_4 then                    -- reload the course list from card
    loadCourses()
    beep(0, 400, 500)
    telSay(string.format("прочитано курсов: %d", #S.courses))

  elseif key == KEY_5 or key == KEY_ENTER then -- save
    if saveCourses() then
      beep(0, 400, 700)
      telSay("сохранено")
    else
      beep(2, 500, 300)
      telSay("ошибка записи")
    end
  end
end

local function keyTelemetry(key)
  local ok, err = pcall(keyTelemetryBody, key)
  if not ok then
    telSay("ошибка клавиши: " .. tostring(err))
  end
end

-- -----------------------------------------------------------------------------------------------
-- courses form
-- -----------------------------------------------------------------------------------------------
local function courseLabel(c, i)
  local s = string.format("%d. %s", i, tostring(c.name))
  if i == S.active then s = s .. " *" end
  return s
end

local function applyCourseEdits()
  local c = S.courses[ui.sel]
  if not c then return end
  if C.name then
    local ok, v = pcall(form.getValue, C.name)
    if ok and v and #v > 0 then c.name = v end
  end
  if C.dist then
    local ok, v = pcall(form.getValue, C.dist)
    if ok and v then c.dist = v end
  end
  if C.typ then
    local ok, v = pcall(form.getValue, C.typ)
    if ok and v then c.typ = (v == 2) and "F3F" or "F3B" end
  end
end

local function initFormCourses()
  C = {}
  needReinit = false
  if ui.sel > #S.courses then ui.sel = 1 end

  form.setTitle(appName .. " " .. appVersion)

  local list = {}
  for i, c in ipairs(S.courses) do list[i] = courseLabel(c, i) end
  if #list == 0 then list[1] = "---" end

  form.addRow(1)
  form.addLabel({ label = "Курсов: " .. #S.courses, font = FONT_BOLD })

  form.addRow(2)
  form.addLabel({ label = "Курс", width = 95 })
  C.sel = form.addSelectbox(list, ui.sel, true, function(v)
    applyCourseEdits()          -- keep what was typed before switching
    ui.sel = v
    needReinit = true
  end, { width = 250 })

  local c = S.courses[ui.sel]
  if not c then return end

  form.addRow(2)
  form.addLabel({ label = "Название", width = 95 })
  C.name = form.addTextbox(tostring(c.name), 24, nil, { width = 250 })

  form.addRow(2)
  form.addLabel({ label = "Тип", width = 95 })
  C.typ = form.addSelectbox({ "F3B", "F3F" }, (c.typ == "F3F") and 2 or 1, true, nil, { width = 250 })

  form.addRow(2)
  form.addLabel({ label = "Дистанция", width = 95 })
  C.dist = form.addIntbox(tonumber(c.dist) or 150, 5, 500, 150, 0, 5, nil, { width = 90 })

  local function posText(lat, lon)
    if lat == nil or lon == nil then return "не задана" end
    return string.format("%.5f  %.5f", lat, lon)
  end

  form.addRow(1)
  form.addLabel({ label = "A: " .. posText(c.aLat, c.aLon), font = FONT_MINI })
  form.addRow(1)
  form.addLabel({ label = "B: " .. posText(c.bLat, c.bLon), font = FONT_MINI })

  form.addLink(function() form.reinit(2) end, { label = "Датчики >>" })

  if #msg > 0 then
    form.addRow(1)
    form.addLabel({ label = msg, font = FONT_MINI })
  end

  form.setButton(1, "Новый",   ENABLED)
  form.setButton(2, "Удалить", #S.courses > 1 and ENABLED or DISABLED)
  form.setButton(3, "Активный", ENABLED)
  form.setButton(4, "Читать",  ENABLED)
  form.setButton(5, "Сохранить", ENABLED)
end

local function keyFormCourses(key)
  if key == KEY_1 then                       -- new course from current GPS position
    applyCourseEdits()
    local la, lo = currentPos()
    if not la then
      beep(2, 500, 250)
      msg = "Нет GPS. Сначала привяжите датчики (Датчики >>)."
      form.reinit(1)
      return
    end
    local c = newCourse(string.format("Курс %d", #S.courses + 1))
    c.aLat, c.aLon = la, lo
    S.courses[#S.courses + 1] = c
    ui.sel = #S.courses
    saveCourses()
    beep(0, 600, 650)
    msg = string.format("Новый курс с GPS: %.5f %.5f", la, lo)
    form.reinit(1)

  elseif key == KEY_2 then                   -- delete selected
    if #S.courses <= 1 then return end
    applyCourseEdits()
    table.remove(S.courses, ui.sel)
    if ui.sel > #S.courses then ui.sel = #S.courses end
    if S.active > #S.courses then S.active = #S.courses end
    saveCourses()
    beep(1, 300, 350)
    form.reinit(1)

  elseif key == KEY_3 then                   -- set active
    applyCourseEdits()
    S.active = ui.sel
    saveCourses()
    beep(0, 600, 800)
    form.reinit(1)

  elseif key == KEY_4 then                   -- reload from SD
    loadCourses()
    ui.sel = S.active
    beep(0, 400, 500)
    form.reinit(1)

  elseif key == KEY_5 then                   -- close / save
    applyCourseEdits()
    saveCourses()
    beep(0, 400, 700)
    form.close()
  end
end

-- -----------------------------------------------------------------------------------------------
-- sensors form
-- -----------------------------------------------------------------------------------------------
local function sensorChanged(which)
  return function(v)
    local m = sensorMap[v]
    if m and m.id == nil then                  -- "---" selected: unbind
      sens[which].id = nil
      sens[which].param = nil
      system.pSave(which .. "Id", 0)
      system.pSave(which .. "Param", 0)
      return
    end
    if m then
      sens[which].id = m.id
      sens[which].param = m.param
      saveSensorCfg(which)
      beep(0, 300, 600)
    end
  end
end

local function initFormSensors()
  SC = {}
  buildSensorList()
  form.setTitle(appName .. " - Датчики")

  if #sensorMap <= 1 then
    form.addRow(1)
    form.addLabel({ label = "Датчики телеметрии не найдены.", font = FONT_BOLD })
    form.addRow(1)
    form.addLabel({ label = "Включите модель и", font = FONT_MINI })
    form.addRow(1)
    form.addLabel({ label = "проверьте связь с приёмником.", font = FONT_MINI })
    form.addLink(function() form.reinit(1) end, { label = "<< Курсы" })
    form.setButton(1, "Назад", ENABLED)
    return
  end

  -- if nothing bound yet, try to guess
  if not bound("lat") then guessSensors() end

  local function row(title, which)
    form.addRow(2)
    form.addLabel({ label = title, width = 85 })
    SC[which] = form.addSelectbox(sensorList, indexOfSensor(which), true,
      sensorChanged(which), { width = 270 })
  end

  form.addRow(1)
  form.addLabel({ label = "Привязка датчиков  (" .. (#sensorList - 1) .. ")", font = FONT_BOLD })

  row("Широта", "lat")
  row("Долгота", "lon")
  row("Скорость", "spd")
  row("Курс", "hdg")

  form.addRow(1)
  form.addLabel({ label = "Привяжите минимум широту и долготу.", font = FONT_MINI })
  form.addRow(1)
  form.addLabel({ label = "Курс необязателен (шаг C).", font = FONT_MINI })

  form.addLink(function() form.reinit(1) end, { label = "<< Курсы" })
  form.setButton(1, "Назад", ENABLED)
end

local function keyFormSensors(key)
  if key == KEY_1 or key == KEY_ESC then
    beep(0, 400, 700)
    form.reinit(1)
  end
end

-- -----------------------------------------------------------------------------------------------
-- app entry
-- -----------------------------------------------------------------------------------------------
local currentForm = 1

-- diagnostics: every start writes what happened into Apps/f3xc/lastrun.txt,
-- so a failure on the transmitter can be read back as a file instead of guessed
local logLines = {}
local function log(s)
  logLines[#logLines + 1] = tostring(s)
  -- flush immediately: if the next call kills the app, the file still has the trail
  pcall(function()
    local txt = table.concat(logLines, "\n") .. "\n"
    pcall(function() io.mkdir("Apps") end)
    pcall(function() io.mkdir(dataDir) end)
    for _, path in ipairs({ dataDir .. "/lastrun.txt", "lastrun.txt" }) do
      local f = io.open(path, "w")
      if f then
        io.write(f, txt)
        io.close(f)
        if path == dataDir .. "/lastrun.txt" then break end
      end
    end
  end)
end

local lastError = nil

-- set once the widget form is built; the canvas printer must stay silent then,
-- otherwise its text would be drawn on top of the form layout
local formBuilt = false

-- canvas fallback mode: the form was registered WITHOUT an initFunction, or a
-- widget raised while building. The whole page is then drawn with lcd, which is
-- exactly how the apps that already work on this transmitter are built.
local canvasMode = false
local canvasPage = 1        -- 1 = courses, 2 = sensors

-- real form builder, never called directly by the firmware
local function initForm(formID)
  currentForm = formID
  if formID == 2 then
    initFormSensors()
  else
    initFormCourses()
  end
end

-- a broken widget must never break the form registration: if it does, the app
-- silently disappears from Menu -> Applications while its telemetry window stays
local function initFormGuarded(formID)
  local ok, err = pcall(initForm, formID)
  if not ok then
    lastError = tostring(err)
    log("initForm(" .. tostring(formID) .. ") error: " .. lastError)
    formBuilt = false
    pcall(function()
      form.addLabel({ label = "F3X: ошибка запуска", font = FONT_BOLD })
      form.addLabel({ label = tostring(err):sub(1, 58), font = FONT_MINI })
      form.setButton(1, "Закрыть", ENABLED)
    end)
  else
    lastError = nil
    formBuilt = true               -- widgets own the canvas, prints stay silent
  end
end

-- -----------------------------------------------------------------------------------------------
-- canvas page (fallback): the same two pages, drawn with lcd only
-- -----------------------------------------------------------------------------------------------
local canvasSel = 1     -- highlighted course index
local canvasMsg = ""

local function canvasLines(w, h)
  local out = {}
  local function add(text, font, color)
    out[#out + 1] = { text = text, font = font or FONT_NORMAL, color = color }
  end

  add(appName .. " " .. appVersion, FONT_BOLD, { 0, 220, 255 })
  add("", FONT_MINI)

  if canvasPage == 1 then
    local c = S.courses[canvasSel]
    add(string.format("Курсов: %d   активный: %d", #S.courses, S.active), FONT_BOLD)
    if c then
      add(string.format("%d. %s%s", canvasSel, tostring(c.name),
                        canvasSel == S.active and "  *" or ""), FONT_BIG)
      add(string.format("%s   %.0f м", tostring(c.typ), tonumber(c.dist) or 0))
      if c.aLat and c.aLon then
        add(string.format("A %.5f %.5f", c.aLat, c.aLon), FONT_MINI)
      else
        add("A не задана  (F1 — с GPS)", FONT_MINI)
      end
      if c.bLat and c.bLon then
        add(string.format("B %.5f %.5f", c.bLat, c.bLon), FONT_MINI)
      else
        add("B не задана  (шаг B)", FONT_MINI)
      end
    else
      add("курсов нет", FONT_BOLD)
    end
    add("", FONT_MINI)
    local la, lo = currentPos()
    if la then
      add(string.format("GPS %.5f %.5f", la, lo), FONT_MINI)
      if c and c.aLat and c.aLon then
        local ok, d = pcall(function()
          return gps.getDistance(gps.newPoint(c.aLat, c.aLon), gps.newPoint(la, lo))
        end)
        if ok and d then add(string.format("до A  %.1f м", d), FONT_MINI) end
      end
    else
      add("GPS нет фикса / не привязан", FONT_MINI)
    end
    if #canvasMsg > 0 then add(canvasMsg, FONT_MINI) end
    add("", FONT_MINI)
    add("F1 Нов  F2 Удал  F3 Акт", FONT_MINI)
    add("ВВЕРХ/ВНИЗ выбор   F5 Датчики >>", FONT_MINI)
  else
    -- sensors page: run the same auto-binding the widget page runs, so the
    -- canvas mode is not a dead end (on this transmitter it is the only mode)
    buildSensorList()
    if not (bound("lat") and bound("lon")) then
      local ok = pcall(guessSensors)
      if ok then canvasMsg = "привязано автоматически" end
    end

    local n = #sensorList - 1
    if n < 0 then n = 0 end
    add("Привязка датчиков  (" .. n .. ")", FONT_BOLD)

    local function nameOf(which)
      if not bound(which) then return "-- не привязан --" end
      for i = 2, #sensorMap do
        local m = sensorMap[i]
        if m.id == sens[which].id and m.param == sens[which].param then
          return sensorList[i]
        end
      end
      return string.format("id %d / p %d", sens[which].id or 0, sens[which].param or 0)
    end

    add("Широта " .. nameOf("lat"), FONT_MINI)
    add("Долгота " .. nameOf("lon"), FONT_MINI)
    add("Скорость " .. nameOf("spd"), FONT_MINI)
    add("Курс " .. nameOf("hdg"), FONT_MINI)

    add("", FONT_MINI)
    local la, lo = currentPos()
    if la then
      add(string.format("фикс %.5f %.5f", la, lo), FONT_MINI)
    else
      add("нет фикса (модель выкл?)", FONT_MINI)
    end
    local spd, hdg = sensorValue("spd"), sensorValue("hdg")
    if spd then add(string.format("скорость %.1f", spd), FONT_MINI) end
    if hdg then add(string.format("курс   %.0f", hdg), FONT_MINI) end
    if #canvasMsg > 0 then add(canvasMsg, FONT_MINI) end

    add("", FONT_MINI)
    add("F4  привязать (авто)", FONT_MINI)
    add("ESC / F1  << Курсы", FONT_MINI)
  end
  return out
end

local function drawCanvas(w, h)
  w, h = w or 320, h or 240
  lcd.setColor(lcd.getFgColor())
  local y, lines = 4, canvasLines(w, h)
  for _, ln in ipairs(lines) do
    if ln.color then
      lcd.setColor(ln.color[1], ln.color[2], ln.color[3])
    else
      lcd.setColor(lcd.getFgColor())
    end
    if #ln.text > 0 then lcd.drawText(4, y, ln.text, ln.font) end
    y = y + ((ln.font == FONT_BIG) and 24 or 18)
    if y > h - 8 then break end
  end
end

-- keys in canvas mode: the whole UI is driven from here
local function keyCanvas(key)
  if canvasPage == 2 then
    if key == KEY_4 then                 -- rebind from the current telemetry
      buildSensorList()
      local ok = pcall(guessSensors)
      canvasMsg = ok and "привязано" or "не удалось привязать"
      beep(0, 400, 700)
      return
    end
    if key == KEY_1 or key == KEY_ESC then
      canvasPage = 1
      beep(0, 400, 700)
    end
    return
  end

  if key == KEY_UP then
    canvasSel = canvasSel - 1
    if canvasSel < 1 then canvasSel = #S.courses end
  elseif key == KEY_DOWN then
    canvasSel = canvasSel + 1
    if canvasSel > #S.courses then canvasSel = 1 end
  elseif key == KEY_1 then                       -- new course from GPS
    local la, lo = currentPos()
    if not la then
      beep(2, 500, 250)
      canvasMsg = "Нет GPS. F5 — датчики."
      return
    end
    local c = newCourse(string.format("Курс %d", #S.courses + 1))
    c.aLat, c.aLon = la, lo
    S.courses[#S.courses + 1] = c
    canvasSel = #S.courses
    saveCourses()
    beep(0, 600, 650)
    canvasMsg = string.format("Новый: %.5f %.5f", la, lo)
  elseif key == KEY_2 then                       -- delete
    if #S.courses <= 1 then
      canvasMsg = "Нельзя удалить последний курс"
      return
    end
    table.remove(S.courses, canvasSel)
    if canvasSel > #S.courses then canvasSel = #S.courses end
    if S.active > #S.courses then S.active = #S.courses end
    saveCourses()
    beep(1, 300, 350)
    canvasMsg = "Удалено"
  elseif key == KEY_3 then                       -- set active
    S.active = canvasSel
    saveCourses()
    beep(0, 600, 800)
    canvasMsg = string.format("Активный: %s", tostring(S.courses[canvasSel].name))
  elseif key == KEY_4 then                       -- reload from card
    loadCourses()
    canvasSel = S.active
    beep(0, 400, 500)
    canvasMsg = "Прочитано с карты"
  elseif key == KEY_5 then                       -- sensors page
    canvasPage = 2
    beep(0, 400, 800)
  elseif key == KEY_ESC then
    pcall(system.exitScript)
  end
end

-- printFunction: the firmware calls it to draw the form. In widget mode the
-- widgets own the canvas and this stays silent; in canvas mode it draws the page.
local function printForm(w, h)
  if not canvasMode and formBuilt then return end
  drawCanvas(w, h)      -- canvas mode, or widgets never built: show something
end

local function keyPressed(key)
  local ok, err = pcall(function()
    -- adaptive routing: if the widget form was never built (canvas-only
    -- registration, the way every working app on this transmitter is built),
    -- the whole UI is driven by the canvas page
    if canvasMode or not formBuilt then
      keyCanvas(key)
    elseif currentForm == 2 then
      keyFormSensors(key)
    else
      keyFormCourses(key)
    end
  end)
  if not ok then
    lastError = tostring(err)
    log("keyPressed(" .. tostring(key) .. ") error: " .. lastError)
  end
end

-- register the form into the first menu that accepts it; MENU_* constants are
-- globals of the firmware and a missing one must not abort the whole init
local function registerFormAnywhere()
  local menus = {
    { id = MENU_APPS,     name = "MENU_APPS"     },
    { id = MENU_ADVANCED, name = "MENU_ADVANCED" },
    { id = MENU_MAIN,     name = "MENU_MAIN"     },
  }
  for _, m in ipairs(menus) do
    if m.id ~= nil then
      -- 1) normal widget form
      local ok, ret = pcall(system.registerForm, 1, m.id, appName,
                            initFormGuarded, keyPressed, printForm)
      log("registerForm " .. m.name .. "(" .. tostring(m.id) .. ") -> ok=" ..
          tostring(ok) .. " ret=" .. tostring(ret))
      if ok and ret then return true, m.name end

      -- 2) canvas-only form (nil initFunction). This is the shape used by every
      -- app that works on this transmitter: nil, key, draw. Nothing is built at
      -- registration time, so nothing can fail there.
      local ok2, ret2 = pcall(system.registerForm, 1, m.id, appName,
                              nil, keyPressed, printForm)
      log("registerForm " .. m.name .. " canvas-only -> ok=" ..
          tostring(ok2) .. " ret=" .. tostring(ret2))
      if ok2 and ret2 then
        canvasMode = true
        return true, m.name .. "/canvas"
      end
    else
      log("registerForm " .. m.name .. " -> constant is nil")
    end
  end
  return false
end

local function initBody()
  log("init " .. appName .. " " .. appVersion .. "  lua " .. tostring(_VERSION))

  local okDir, errDir = pcall(ensureDir)
  if not okDir then log("ensureDir: " .. tostring(errDir)) end

  local okC, errC = pcall(loadCourses)
  if not okC then log("loadCourses: " .. tostring(errC)) end

  local okS, errS = pcall(loadSensorCfg)
  if not okS then log("loadSensorCfg: " .. tostring(errS)) end

  ui.sel = S.active

  -- the form goes first: it is the visible entry in the menus, telemetry alone
  -- would leave the app reachable only from the telemetry screen list
  local registered = registerFormAnywhere()

  -- size 3 = the whole screen, and the only size that also passes key presses
  local okT, retT = pcall(system.registerTelemetry, 1, appName, 3, drawTelemetry,
                          keyTelemetry)
  log("registerTelemetry(3) -> ok=" .. tostring(okT) .. " ret=" .. tostring(retT))
  if not (okT and retT) then
    local okT2, retT2 = pcall(system.registerTelemetry, 1, appName, 2, drawTelemetry)
    log("registerTelemetry(2) -> ok=" .. tostring(okT2) .. " ret=" .. tostring(retT2))
  end

  -- button labels of the full screen window (V6.05+, has no effect on small ones)
  if okT and retT then
    local labels = { "Новый", "Далее", "Датч", "Читать", "Сохр" }
    for i, text in ipairs(labels) do
      local okB = pcall(system.setTelemetryButton, 1, i, text, ENABLED)
      if not okB then log("setTelemetryButton(" .. i .. ") failed") break end
    end
  end

  if not registered then
    log("FORM NOT REGISTERED")
    pcall(system.messageBox, appName .. ": форма не зарегистрирована, см. журнал")
  else
    log("ready")
  end
end

local function init(code)
  local ok, err = pcall(initBody)
  if not ok then log("init failed: " .. tostring(err)) end
end

local function loop()
  if needReinit then
    needReinit = false
    form.reinit(1)
  end
end

return {
  init    = init,
  loop    = loop,
  author  = appAuthor,
  version = appVersion,
  name    = appName,
}
