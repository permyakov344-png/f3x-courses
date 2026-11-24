-- Runs the real Apps/F3x Courses.lua with stubbed JETI API.
--
-- The bug this guards against: the app showed up only in the telemetry/sensor
-- list and never in Menu -> Applications. A telemetry window is stored in the
-- model file, so it proves nothing; the form is what makes the app reachable.
-- The form disappears whenever system.registerForm() is not happy, e.g.
--   * the printFunction argument is missing,
--   * the initFunction is nil (a wrapper referring to a local declared below),
--   * the initFunction raises while building widgets.
--
-- Run: /tmp/node_modules/.bin/fengari tools/test-app.lua

-- ------------------------------------------------------------------ stubs ----
local formCalls, registered, logFiles, params, sensors
local telemetry, telButtons
local curLog, strictReg, failSetTitle, refuseWidgets

local function resetStubs()
  formCalls, registered, logFiles, params = {}, {}, {}, {}
  telemetry, telButtons = {}, {}
  curLog, strictReg, failSetTitle, refuseWidgets = nil, false, false, false

  sensors = {
    { id = 809083650, param = 0, label = "UniS-E",      unit = "na"  },
    { id = 809083650, param = 1, label = "Voltage",     unit = "V"   },
    { id = 823632641, param = 0, label = "GPSLog3",     unit = "na"  },
    { id = 823632641, param = 3, label = "Latitude",    unit = "LAT" },
    { id = 823632641, param = 4, label = "Longitude",   unit = "LON" },
    { id = 823632641, param = 5, label = "Speed",       unit = "kmh" },
    { id = 823632641, param = 9, label = "Flight Dir.", unit = "deg" },
  }

  io = {
    mkdir = function() return true end,
    open  = function(path, mode)
      if mode == "w" or mode == "a" then
        if not curLog then curLog = "" end
        return { path = path, mode = mode }
      end
      return nil
    end,
    write = function(f, ...)
      if type(f) == "table" then
        for _, v in ipairs({ ... }) do curLog = curLog .. tostring(v) end
      end
      return f
    end,
    close = function(f)
      if type(f) == "table" and f.mode == "w" then logFiles[f.path] = curLog end
      return true
    end,
    readall  = function() return nil end,
    readline = function() return nil end,
    remove   = function() return true end,
    rename   = function() return true end,
  }

  json = { encode = function() return "{}" end, decode = function() return {} end }

  KEY_1, KEY_2, KEY_3, KEY_4, KEY_5 = 1, 2, 3, 4, 5
  KEY_UP, KEY_DOWN, KEY_ESC, KEY_ENTER, KEY_RELEASED = 6, 7, 8, 9, 10
  MENU_APPS, MENU_MAIN, MENU_ADVANCED = 11, 12, 13
  FONT_MINI, FONT_NORMAL, FONT_BOLD, FONT_BIG, FONT_MAXI = 0, 1, 2, 3, 4
  ENABLED, DISABLED = true, false

  lcd = {
    getFgColor = function() return 0 end,
    setColor   = function() end,
    drawText   = function() end,
    drawLine   = function() end,
    drawRectangle = function() end,
    drawFilledRectangle = function() end,
    getTextWidth = function(font, text) return #tostring(text) * 7 end,
  }

  gps = {
    getPosition = function() return nil end,
    getValue    = function() return nil end,
    newPoint    = function(la, lo) return { la, lo } end,
    getDistance = function() return 0 end,
    getBearing  = function() return 0 end,
  }

  system = {
    getTimeCounter = function() return os.time() * 1000 end,
    getTime        = function() return os.time() end,
    getSensors     = function() return sensors end,
    getSensorByID  = function() return { valid = false, value = 0 } end,
    pLoad          = function(k, d) return params[k] or d end,
    pSave          = function(k, v) params[k] = v end,
    playBeep       = function() end,
    playFile       = function() end,
    messageBox     = function() end,
    exitScript     = function() end,
    registerTelemetry = function(no, label, size, printFn, keyFn)
      telemetry[#telemetry + 1] = { no = no, label = label, size = size,
                                    printFn = printFn, keyFn = keyFn }
      return no
    end,
    setTelemetryButton = function(no, btn, text, state)
      telButtons[#telButtons + 1] = { no = no, btn = btn, text = text, state = state }
    end,
    registerControl   = function() return 1 end,
    setControl        = function() end,
    -- the interesting one
    registerForm = function(no, menu, label, initFn, keyFn, printFn)
      -- refuseWidgets models the DS-24 II: it only accepts the shape the apps
      -- that already work there use (nil initFunction + key + print)
      if refuseWidgets and type(initFn) == "function" then return nil end
      if strictReg and type(initFn) ~= "function" then return nil end
      if strictReg and type(printFn) ~= "function" then return nil end
      if type(initFn) == "function" then
        local ok = pcall(initFn, 1)      -- some firmwares run it at register time
        if not ok and strictReg then return nil end
      end
      registered[#registered + 1] = { no = no, menu = menu, label = label,
                                      initFn = initFn, keyFn = keyFn,
                                      printFn = printFn }
      return no
    end,
  }

  local function add(name)
    return function(a, b, c, d, e)
      formCalls[#formCalls + 1] = { name = name, args = { a, b, c, d, e } }
      return #formCalls
    end
  end

  form = {
    addRow       = add("addRow"),
    addLabel     = add("addLabel"),
    addSelectbox = add("addSelectbox"),
    addIntbox    = add("addIntbox"),
    addTextbox   = add("addTextbox"),
    addLink      = add("addLink"),
    addIcon      = add("addIcon"),
    addNumber    = add("addNumber"),
    setButton    = add("setButton"),
    setTitle     = function(t)
      if failSetTitle then
        failSetTitle = false
        error("simulated widget failure")
      end
      formCalls[#formCalls + 1] = { name = "setTitle", args = { t } }
      return #formCalls
    end,
    getValue   = function() return nil end,
    reinit     = function() end,
    close      = function() end,
    setEnabled = function() end,
    setVisible = function() end,
  }
end

local function runApp()
  local chunk, err = loadfile("Apps/F3x Courses.lua")
  assert(chunk, "cannot load Apps/F3x Courses.lua: " .. tostring(err))
  local app = chunk()
  assert(type(app) == "table", "app must return a table")
  assert(type(app.init) == "function", "app.init missing")
  local ok, e = pcall(app.init)
  assert(ok, "init() raised: " .. tostring(e))
  return app
end

local function theLog()
  for path, txt in pairs(logFiles) do
    if path:find("lastrun") then return txt end
  end
  return nil
end

-- ============================================================== scenario 1 ====
-- normal firmware
resetStubs()
local app = runApp()

assert(type(app.name) == "string" and #app.name > 0, "app.name missing")
assert(type(app.version) == "string", "app.version missing")
print("PASS: app table is well formed (" .. app.name .. " " .. app.version .. ")")

assert(#registered > 0, "system.registerForm was never called")
local f = registered[#registered]
assert(type(f.initFn) == "function",
  "registerForm initFunction is " .. type(f.initFn) .. ", not a function")
assert(type(f.printFn) == "function",
  "registerForm printFunction is " .. type(f.printFn) ..
  " - firmware needs it to draw the form")
print("PASS: registerForm got init + print function (menu " ..
      tostring(f.menu) .. ", label '" .. tostring(f.label) .. "')")

formCalls = {}
local ok, e = pcall(f.initFn, 1)
assert(ok, "initForm(1) raised: " .. tostring(e))
assert(#formCalls > 5, "initForm(1) built too few widgets: " .. #formCalls)
print("PASS: initForm(1) built " .. #formCalls .. " widgets")

local buttons = 0
for _, c in ipairs(formCalls) do
  if c.name == "setButton" then buttons = buttons + 1 end
end
assert(buttons >= 5, "expected 5 function buttons, got " .. buttons)
print("PASS: courses page sets " .. buttons .. " function buttons")

formCalls = {}
ok, e = pcall(f.initFn, 2)
assert(ok, "initForm(2) raised: " .. tostring(e))
assert(#formCalls > 3, "initForm(2) built too few widgets: " .. #formCalls)
print("PASS: initForm(2) built " .. #formCalls .. " widgets")

if f.keyFn then
  for _, k in ipairs({ KEY_1, KEY_2, KEY_3, KEY_4, KEY_UP, KEY_ESC, 999 }) do
    ok, e = pcall(f.keyFn, k)
    assert(ok, "key handler raised on key " .. tostring(k) .. ": " .. tostring(e))
  end
  print("PASS: key handler survives every key incl. unknown ones")
end

if type(f.printFn) == "function" then
  ok, e = pcall(f.printFn, 320, 240)
  assert(ok, "printFunction raised: " .. tostring(e))
  print("PASS: printFunction draws without error")
end

local log = theLog()
assert(log, "no lastrun.txt was written")
assert(log:find("registerForm"), "log has no registerForm line:\n" .. log)
assert(not log:find("FORM NOT REGISTERED"), "log says the form was not registered")
print("PASS: lastrun.txt reports a registered form")

-- ============================================================== scenario 2 ====
-- strict firmware: initFunction must be a function AND must not raise,
-- printFunction must be present. This is what the DS-24 II behaves like
-- when the app only shows up in the telemetry list.
resetStubs()
strictReg = true
runApp()
assert(#registered > 0, "strict firmware: no form registered at all")
local g = registered[#registered]
assert(type(g.initFn) == "function", "strict firmware: initFunction missing")
assert(type(g.printFn) == "function", "strict firmware: printFunction missing")
print("PASS: strict firmware still registers the form")

-- ============================================================== scenario 3 ====
-- a widget raises during initForm: the form must still be registered, and the
-- error must be visible on screen and in the log
resetStubs()
strictReg = false
failSetTitle = true
runApp()
assert(#registered > 0, "widget failure: form was not registered at all")
local h = registered[#registered]
formCalls = {}
ok, e = pcall(h.initFn, 1)
assert(ok, "guarded initForm raised to the caller: " .. tostring(e))
local log3 = theLog()
assert(log3 and log3:find("initForm%(1%) error"), "widget error not in log")
assert(#formCalls > 0, "guard did not draw the error message")
print("PASS: widget failure is caught, form stays, error goes to screen and log")

-- ============================================================== scenario 4 ====
-- the transmitter this app targets: registerForm refuses the widget form
-- (returns nil) unless the arguments look exactly like the apps that already
-- work there: nil initFunction + key + print. The app must then register anyway
-- and the canvas page must drive the UI completely.
resetStubs()
refuseWidgets = true
runApp()
assert(#registered > 0, "canvas firmware: no form registered at all")
local k = registered[#registered]
assert(k.initFn == nil, "canvas firmware: initFunction should be nil here")
assert(type(k.printFn) == "function", "canvas firmware: printFunction missing")
assert(type(k.keyFn) == "function", "canvas firmware: keyFunction missing")
print("PASS: registers the form when widgets are refused (nil init + key + print)")

local log4 = theLog()
assert(log4 and log4:find("canvas%-only"), "log should show the canvas fallback")

-- the canvas page must draw real content and survive every key
formCalls = {}
local drew = 0
local realDrawText = lcd.drawText
lcd.drawText = function() drew = drew + 1; return realDrawText() end
ok, e = pcall(k.printFn, 320, 240)
lcd.drawText = realDrawText
assert(ok, "canvas printFunction raised: " .. tostring(e))
assert(drew >= 5, "canvas page drew too little: " .. drew .. " lines")
print("PASS: canvas page draws " .. drew .. " text items")

for _, key in ipairs({ KEY_UP, KEY_DOWN, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5,
                       KEY_ESC, KEY_ENTER, 999, KEY_RELEASED }) do
  ok, e = pcall(k.keyFn, key)
  assert(ok, "canvas key handler raised on key " .. tostring(key) .. ": " .. tostring(e))
end
print("PASS: canvas key handler survives every key (incl. F1..F5, ESC, unknown)")

-- sensors page must be reachable from the canvas UI and draw without error
formCalls = {}
drew = 0
lcd.drawText = function() drew = drew + 1; return realDrawText() end
ok, e = pcall(k.keyFn, KEY_5)          -- F5: Sensors >>
assert(ok, "switching to the canvas sensors page raised: " .. tostring(e))
ok, e = pcall(k.printFn, 320, 240)
lcd.drawText = realDrawText
assert(ok, "canvas sensors page raised: " .. tostring(e))
assert(drew >= 5, "canvas sensors page drew too little: " .. drew)
print("PASS: canvas sensors page draws " .. drew .. " text items")

-- ============================================================== scenario 5 ====
-- the full screen telemetry window: size 4 ("other" in API 1.7 = whole screen
-- with no firmware status bar), size 3 as the fallback. It draws with real
-- course data, and it survives every key and a missing GPS
resetStubs()
runApp()
assert(#telemetry > 0, "registerTelemetry was never called")
local tel = telemetry[#telemetry]
assert(tel.size == 4, "telemetry size is " .. tostring(tel.size) ..
       ", expected 4 (whole screen, no status bar)")
assert(type(tel.printFn) == "function", "telemetry has no printFunction")
assert(type(tel.keyFn) == "function",
       "telemetry has no keyPressedFunction - keys only work on full screen")
assert(#telButtons >= 5, "telemetry buttons not set: " .. #telButtons)
print("PASS: telemetry registered full screen (size 4) with keys and 5 buttons")

-- if the firmware refuses size 4 it must fall back to 3 (bar at the bottom)
resetStubs()
local realReg = system.registerTelemetry
system.registerTelemetry = function(no, label, size, printFn, keyFn)
  if size == 4 then return nil end
  return realReg(no, label, size, printFn, keyFn)
end
runApp()
local fb = telemetry[#telemetry]
assert(fb.size == 3, "fallback size is " .. tostring(fb.size) .. ", expected 3")
assert(type(fb.keyFn) == "function", "fallback lost the key handler")
print("PASS: size 4 refused -> falls back to size 3 with keys")

-- drawing must work with no GPS, no course, and an odd canvas size
local drew, filled = 0, 0
local realText, realFill = lcd.drawText, lcd.drawFilledRectangle
lcd.drawText = function() drew = drew + 1; return realText() end
lcd.drawFilledRectangle = function() filled = filled + 1; return realFill() end
for _, size in ipairs({ { 320, 240 }, { 800, 480 }, { 320, 120 }, { 200, 90 } }) do
  ok, e = pcall(tel.printFn, size[1], size[2])
  assert(ok, "telemetry printFunction raised at " .. size[1] .. "x" .. size[2] ..
         ": " .. tostring(e))
end
lcd.drawText, lcd.drawFilledRectangle = realText, realFill
assert(drew >= 10, "telemetry drew too little text: " .. drew)
assert(filled >= 5, "telemetry drew no panels: " .. filled)
print("PASS: telemetry draws " .. drew .. " texts, " .. filled ..
      " panels at 4 canvas sizes")

-- every key must be safe, including unknown ones
for _, key in ipairs({ KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_ENTER, KEY_ESC,
                       KEY_UP, KEY_DOWN, KEY_RELEASED, 999, -1 }) do
  ok, e = pcall(tel.keyFn, key)
  assert(ok, "telemetry key handler raised on key " .. tostring(key) .. ": " ..
         tostring(e))
end
print("PASS: telemetry key handler survives every key")

-- with a complete course and a GPS fix the window must show both bases
resetStubs()
runApp()
-- pretend the card holds this course
io.readall = function() return "{}" end
json = {
  encode = function() return "{}" end,
  decode = function()
    return { active = 1, courses = { {
      name = "Test course", typ = "F3B", dist = 150,
      aLat = 50.1, aLon = 14.2, bLat = 50.101, bLon = 14.203,
    } } }
  end,
}
local app2 = runApp()
tel = telemetry[#telemetry]        -- the instance that loaded the course
local seen = {}
lcd.drawText = function(x, y, t) seen[#seen + 1] = tostring(t) end
ok, e = pcall(tel.printFn, 800, 480)
lcd.drawText = realText
assert(ok, "telemetry raised with a course: " .. tostring(e))
local blob = table.concat(seen, "\n")

assert(blob:find("Test course"), "active course name not drawn:\n" .. blob)
assert(blob:find("ЛИНИЯ A%-B"), "no line gauge drawn:\n" .. blob)
assert(blob:find("ДАТЧИКИ"), "no sensor status drawn:\n" .. blob)
print("PASS: telemetry shows the course, the A-B gauge and the sensor status")

print("\nall app tests passed")
