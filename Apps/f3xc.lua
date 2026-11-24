-- ###############################################################################################
-- #  F3X Courses  -  course manager / base-line helper for JETI DC/DS transmitters
-- #  Version 0.1.3  (step A: skeleton, single menu, JSON course storage)
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
local appVersion = "0.1.3"
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
local distToA, distToAtime = nil, 0    -- cached distance to base A (avoids heavy math in the draw loop)

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
    name = name or "New course",
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
    S.courses[1] = newCourse("My F3B course")
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
-- telemetry window
-- -----------------------------------------------------------------------------------------------
local function drawTelemetryBody(w, h)
  scrW, scrH = w, h
  local y, dy = 6, 20
  local function line(text, font)
    if y + dy > h then return end
    lcd.drawText(4, y, text, font or FONT_NORMAL)
    y = y + dy
  end

  lcd.setColor(lcd.getFgColor())
  line(appName .. " " .. appVersion, FONT_BOLD)
  y = y + 4

  local c = activeCourse()
  if c then
    line("ACTIVE  " .. tostring(c.name), FONT_BOLD)
    line(string.format("%s  %.0f m", tostring(c.typ), tonumber(c.dist) or 0))
    if c.brg then
      line(string.format("bearing %.0f deg", c.brg))
    else
      line("bearing  -- (step B)")
    end
  else
    line("no course", FONT_BOLD)
  end

  y = y + 4
  local la, lo = currentPos()
  if la then
    line(string.format("GPS  %.5f", la))
    line(string.format("     %.5f", lo))
    if c and c.aLat and c.aLon then
      local now = system.getTimeCounter()
      if distToA == nil or now - distToAtime > 1000 then
        distToAtime = now
        local ok, d = pcall(function()
          return gps.getDistance(gps.newPoint(c.aLat, c.aLon), gps.newPoint(la, lo))
        end)
        distToA = (ok and d) and d or -1
      end
      if distToA and distToA >= 0 then line(string.format("to A %.1f m", distToA)) end
    else
      line("A not set yet")
    end
  else
    line("GPS  no fix / not bound")
  end

  local spd = sensorValue("spd")
  if spd then line(string.format("speed %.1f", spd)) end
  line(string.format("courses %d   active %d", #S.courses, S.active))
end

-- telemetry windows are drawn on a timer; never let a runtime error kill the widget
local function drawTelemetry(w, h)
  local ok = pcall(drawTelemetryBody, w, h)
  if not ok then
    lcd.setColor(lcd.getFgColor())
    lcd.drawText(4, 6, appName, FONT_BOLD)
    lcd.drawText(4, 30, "draw error", FONT_NORMAL)
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
  form.addLabel({ label = "Courses: " .. #S.courses, font = FONT_BOLD })

  form.addRow(2)
  form.addLabel({ label = "Course", width = 95 })
  C.sel = form.addSelectbox(list, ui.sel, true, function(v)
    applyCourseEdits()          -- keep what was typed before switching
    ui.sel = v
    needReinit = true
  end, { width = 250 })

  local c = S.courses[ui.sel]
  if not c then return end

  form.addRow(2)
  form.addLabel({ label = "Name", width = 95 })
  C.name = form.addTextbox(tostring(c.name), 24, nil, { width = 250 })

  form.addRow(2)
  form.addLabel({ label = "Type", width = 95 })
  C.typ = form.addSelectbox({ "F3B", "F3F" }, (c.typ == "F3F") and 2 or 1, true, nil, { width = 250 })

  form.addRow(2)
  form.addLabel({ label = "Distance", width = 95 })
  C.dist = form.addIntbox(tonumber(c.dist) or 150, 5, 500, 150, 0, 5, nil, { width = 90 })

  local function posText(lat, lon)
    if lat == nil or lon == nil then return "not set" end
    return string.format("%.5f  %.5f", lat, lon)
  end

  form.addRow(1)
  form.addLabel({ label = "A: " .. posText(c.aLat, c.aLon), font = FONT_MINI })
  form.addRow(1)
  form.addLabel({ label = "B: " .. posText(c.bLat, c.bLon), font = FONT_MINI })

  form.addLink(function() form.reinit(2) end, { label = "Sensors >>" })

  if #msg > 0 then
    form.addRow(1)
    form.addLabel({ label = msg, font = FONT_MINI })
  end

  form.setButton(1, "New",     ENABLED)
  form.setButton(2, "Delete",  #S.courses > 1 and ENABLED or DISABLED)
  form.setButton(3, "Active",  ENABLED)
  form.setButton(4, "Reload",  ENABLED)
  form.setButton(5, "Save",    ENABLED)
end

local function keyFormCourses(key)
  if key == KEY_1 then                       -- new course from current GPS position
    applyCourseEdits()
    local la, lo = currentPos()
    if not la then
      beep(2, 500, 250)
      msg = "No GPS position. Bind sensors first (Sensors >>)."
      form.reinit(1)
      return
    end
    local c = newCourse(string.format("Course %d", #S.courses + 1))
    c.aLat, c.aLon = la, lo
    S.courses[#S.courses + 1] = c
    ui.sel = #S.courses
    saveCourses()
    beep(0, 600, 650)
    msg = string.format("New course from GPS: %.5f %.5f", la, lo)
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
  form.setTitle(appName .. " - Sensors")

  if #sensorMap <= 1 then
    form.addRow(1)
    form.addLabel({ label = "No telemetry sensors found.", font = FONT_BOLD })
    form.addRow(1)
    form.addLabel({ label = "Switch the model on and", font = FONT_MINI })
    form.addRow(1)
    form.addLabel({ label = "check the receiver link.", font = FONT_MINI })
    form.addLink(function() form.reinit(1) end, { label = "<< Courses" })
    form.setButton(1, "Back", ENABLED)
    return
  end

  -- if nothing bound yet, try to guess
  if not bound("lat") then guessSensors() end

  local function row(title, which)
    form.addRow(2)
    form.addLabel({ label = title, width = 75 })
    SC[which] = form.addSelectbox(sensorList, indexOfSensor(which), true,
      sensorChanged(which), { width = 270 })
  end

  form.addRow(1)
  form.addLabel({ label = "Sensor binding  (" .. (#sensorList - 1) .. " values)", font = FONT_BOLD })

  row("Lat", "lat")
  row("Lon", "lon")
  row("Speed", "spd")
  row("Dir", "hdg")

  form.addRow(1)
  form.addLabel({ label = "Bind at least Lat + Lon.", font = FONT_MINI })
  form.addRow(1)
  form.addLabel({ label = "Dir is optional (step C).", font = FONT_MINI })

  form.addLink(function() form.reinit(1) end, { label = "<< Courses" })
  form.setButton(1, "Back", ENABLED)
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
      form.addLabel({ label = "F3X: init error", font = FONT_BOLD })
      form.addLabel({ label = tostring(err):sub(1, 58), font = FONT_MINI })
      form.setButton(1, "Close", ENABLED)
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
    add(string.format("Courses: %d   active: %d", #S.courses, S.active), FONT_BOLD)
    if c then
      add(string.format("%d. %s%s", canvasSel, tostring(c.name),
                        canvasSel == S.active and "  *" or ""), FONT_BIG)
      add(string.format("%s   %.0f m", tostring(c.typ), tonumber(c.dist) or 0))
      if c.aLat and c.aLon then
        add(string.format("A %.5f %.5f", c.aLat, c.aLon), FONT_MINI)
      else
        add("A not set  (F1 New from GPS)", FONT_MINI)
      end
      if c.bLat and c.bLon then
        add(string.format("B %.5f %.5f", c.bLat, c.bLon), FONT_MINI)
      else
        add("B not set  (step B)", FONT_MINI)
      end
    else
      add("no courses", FONT_BOLD)
    end
    add("", FONT_MINI)
    local la, lo = currentPos()
    if la then
      add(string.format("GPS %.5f %.5f", la, lo), FONT_MINI)
      if c and c.aLat and c.aLon then
        local ok, d = pcall(function()
          return gps.getDistance(gps.newPoint(c.aLat, c.aLon), gps.newPoint(la, lo))
        end)
        if ok and d then add(string.format("to A  %.1f m", d), FONT_MINI) end
      end
    else
      add("GPS no fix / not bound", FONT_MINI)
    end
    if #canvasMsg > 0 then add(canvasMsg, FONT_MINI) end
    add("", FONT_MINI)
    add("F1 New  F2 Del  F3 Act", FONT_MINI)
    add("UP/DN select   F5 Sensors >>", FONT_MINI)
  else
    -- sensors page: run the same auto-binding the widget page runs, so the
    -- canvas mode is not a dead end (on this transmitter it is the only mode)
    buildSensorList()
    if not (bound("lat") and bound("lon")) then
      local ok = pcall(guessSensors)
      if ok then canvasMsg = "auto-bound from telemetry" end
    end

    local n = #sensorList - 1
    if n < 0 then n = 0 end
    add("Sensor binding  (" .. n .. " values)", FONT_BOLD)

    local function nameOf(which)
      if not bound(which) then return "-- not bound --" end
      for i = 2, #sensorMap do
        local m = sensorMap[i]
        if m.id == sens[which].id and m.param == sens[which].param then
          return sensorList[i]
        end
      end
      return string.format("id %d / p %d", sens[which].id or 0, sens[which].param or 0)
    end

    add("Lat " .. nameOf("lat"), FONT_MINI)
    add("Lon " .. nameOf("lon"), FONT_MINI)
    add("Spd " .. nameOf("spd"), FONT_MINI)
    add("Dir " .. nameOf("hdg"), FONT_MINI)

    add("", FONT_MINI)
    local la, lo = currentPos()
    if la then
      add(string.format("fix %.5f %.5f", la, lo), FONT_MINI)
    else
      add("no fix (model off?)", FONT_MINI)
    end
    local spd, hdg = sensorValue("spd"), sensorValue("hdg")
    if spd then add(string.format("speed %.1f", spd), FONT_MINI) end
    if hdg then add(string.format("dir   %.0f", hdg), FONT_MINI) end
    if #canvasMsg > 0 then add(canvasMsg, FONT_MINI) end

    add("", FONT_MINI)
    add("F4  rebind (auto)", FONT_MINI)
    add("ESC / F1  << Courses", FONT_MINI)
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
      canvasMsg = ok and "rebound" or "rebind failed"
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
      canvasMsg = "No GPS. F5 for sensors."
      return
    end
    local c = newCourse(string.format("Course %d", #S.courses + 1))
    c.aLat, c.aLon = la, lo
    S.courses[#S.courses + 1] = c
    canvasSel = #S.courses
    saveCourses()
    beep(0, 600, 650)
    canvasMsg = string.format("New: %.5f %.5f", la, lo)
  elseif key == KEY_2 then                       -- delete
    if #S.courses <= 1 then
      canvasMsg = "Cannot delete the last course"
      return
    end
    table.remove(S.courses, canvasSel)
    if canvasSel > #S.courses then canvasSel = #S.courses end
    if S.active > #S.courses then S.active = #S.courses end
    saveCourses()
    beep(1, 300, 350)
    canvasMsg = "Deleted"
  elseif key == KEY_3 then                       -- set active
    S.active = canvasSel
    saveCourses()
    beep(0, 600, 800)
    canvasMsg = string.format("Active: %s", tostring(S.courses[canvasSel].name))
  elseif key == KEY_4 then                       -- reload from card
    loadCourses()
    canvasSel = S.active
    beep(0, 400, 500)
    canvasMsg = "Reloaded from card"
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

  local okT, retT = pcall(system.registerTelemetry, 1, appName, 2, drawTelemetry)
  log("registerTelemetry -> ok=" .. tostring(okT) .. " ret=" .. tostring(retT))

  if not registered then
    log("FORM NOT REGISTERED")
    pcall(system.messageBox, appName .. ": form not registered, see log")
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
