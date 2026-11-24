-- F3XMINI.lua
-- Minimal JETI Lua application for a load test on DS-24 II.
-- It is deliberately tiny (about 1 kB), has no widgets, no gps, no pcall --
-- just: register a canvas form, write one line to the card.
--
-- How to read the result:
--   * "F3X MINI" appears in Menu -> Applications -> User Applications (F3 Plus)
--     and Apps/f3xmini.txt exists  -> the transmitter loads .lua files fine,
--                                     so the problem is in f3xc.lua itself
--   * it appears but there is no file -> loading works, writing to the card
--                                     from Lua does not (logging is blind)
--   * it does not appear at all     -> the loader/menu is the problem,
--                                     not the application code

local function draw(w, h)
  lcd.setColor(255, 255, 255)
  lcd.drawText(6, 8, "F3X MINI", FONT_BOLD)
  lcd.drawText(6, 34, "load test OK", FONT_NORMAL)
  lcd.drawText(6, 62, "0.0.1", FONT_MINI)
  lcd.drawText(6, 92, "F1 / ESC close", FONT_MINI)
end

local function key(k)
  if k == KEY_ESC or k == KEY_1 then
    system.exitScript()
  end
end

local function init(code)
  local f = io.open("Apps/f3xmini.txt", "w")
  if f then
    io.write(f, "init called, code=", tostring(code), "\n")
    io.close(f)
  end
  system.registerForm(1, MENU_APPS, "F3X MINI", nil, key, draw)
end

return {
  init    = init,
  loop    = function() end,
  author  = "permyakov344-png",
  version = "0.0.1",
  name    = "F3X MINI",
}
