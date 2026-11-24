-- ###############################################################################################
-- #  sensors_dump.lua  -  one-off telemetry diagnostic for F3X Courses
-- #
-- #  Writes EVERY telemetry value the transmitter sees into  Apps/f3xc/sensors.txt  :
-- #    index | id | param | type | unit | label | current value
-- #  Copy that file to a computer — we need it to bind Lat/Lon/Speed/Dir exactly.
-- #
-- #  Install:  put as  Apps/sensors_dump.lua  on the SD card, power-cycle the transmitter,
-- #            Menu -> Applications -> "F3X Sensors Dump".
-- #  It changes nothing on the model and saves nothing except that one txt file.
-- #  Diagnostic tool only, it is not part of F3X Courses.
-- ###############################################################################################

local APP = "F3X Sensors Dump"

local function s(v)
  if v == nil then return "nil" end
  local t = type(v)
  if t == "string" then return v end
  if t == "number" then
    if v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%d", v) end
    return string.format("%.6f", v)
  end
  return tostring(v)
end

-- collects the report as a list of lines, returns lines, count
local function buildReport()
  local L = {}
  local function add(x) L[#L + 1] = x end
  local values = 0

  add("F3X Courses - telemetry dump")
  local okT, tc = pcall(system.getTimeCounter)
  add("timeCounter: " .. (okT and s(tc) or "n/a"))
  add("")

  local ok, all = pcall(system.getSensors)
  if not ok or type(all) ~= "table" then
    add("ERROR: system.getSensors() failed")
  else
    add("entries: " .. tostring(#all))
    add("idx | id | param | type | unit | label | value")
    add(string.rep("-", 78))
    local group = ""
    for i = 1, #all do
      local e = all[i]
      if type(e) == "table" then
        if e.param == 0 then
          group = tostring(e.label or "?")
          add(string.format("%3d | %s | GROUP %s", i, s(e.id), group))
        else
          values = values + 1
          local val = "n/a"
          local okv, d = pcall(system.getSensorByID, e.id, e.param)
          if okv and type(d) == "table" and d.valid then val = s(d.value) end
          add(string.format("%3d | %s | %s | %s | %s | %s | %s",
            i, s(e.id), s(e.param), s(e.type), s(e.unit), s(e.label), val))
        end
      end
    end
  end

  add("")
  add("values (param ~= 0): " .. values)
  return L, values
end

local function writeFile(lines)
  pcall(function() io.mkdir("Apps") end)
  pcall(function() io.mkdir("Apps/f3xc") end)
  local ok = false
  local txt = table.concat(lines, "\n") .. "\n"
  pcall(function()
    local f = io.open("Apps/f3xc/sensors.txt", "w")
    if f then
      io.write(f, txt)
      io.close(f)
      ok = true
    end
  end)
  return ok
end

local reportLines, reportCount, reportWrote = {}, 0, false

local function initForm()
  form.setTitle(APP)
  reportLines, reportCount = buildReport()
  reportWrote = writeFile(reportLines)

  form.addRow(1)
  form.addLabel({ label = "Telemetry values: " .. reportCount, font = FONT_BOLD })

  form.addRow(1)
  if reportWrote then
    form.addLabel({ label = "Written to:", font = FONT_MINI })
    form.addRow(1)
    form.addLabel({ label = "Apps/f3xc/sensors.txt", font = FONT_MINI })
  else
    form.addLabel({ label = "WRITE FAILED - check SD card", font = FONT_BOLD })
  end

  -- show the first 20 lines right on screen, so it works even without a card reader
  form.addRow(1)
  form.addLabel({ label = "Preview:", font = FONT_MINI })
  for i = 1, math.min(#reportLines, 20) do
    form.addRow(1)
    form.addLabel({ label = reportLines[i], font = FONT_MINI })
  end

  form.setButton(1, "Close", ENABLED)
end

local function keyForm(key)
  if key == KEY_1 or key == KEY_ESC then
    form.close()
  end
end

local function init()
  system.registerForm(1, MENU_APPS, APP, initForm, keyForm)
end

local function loop()
end

return {
  init    = init,
  loop    = loop,
  author  = "permyakov344-png",
  version = "0.1",
  name    = APP,
}
