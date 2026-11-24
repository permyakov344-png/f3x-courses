-- test for bindKnownProfile / guessSensors logic using the sensor rows
-- found on the real transmitter (GPSLog3 + UniS-E)
package.path = package.path

-- mock Jeti API ---------------------------------------------------------------
local saved = {}
local sensors = {
  -- UniS-E, ID 809083650
  { id = 809083650, param = 0,  label = "UniS-E",     unit = "na"   },
  { id = 809083650, param = 1,  label = "Voltage",    unit = "V"    },
  { id = 809083650, param = 5,  label = "Altitude",   unit = "m"    },
  { id = 809083650, param = 6,  label = "Vario",      unit = "m/s"  },
  -- GPSLog3, ID 823632641
  { id = 823632641, param = 0,  label = "GPSLog3",    unit = "na"   },
  { id = 823632641, param = 1,  label = "Time",       unit = ""     },
  { id = 823632641, param = 3,  label = "Latitude",   unit = "LAT"  },
  { id = 823632641, param = 4,  label = "Longitude",  unit = "LON"  },
  { id = 823632641, param = 5,  label = "Speed",      unit = "kmh"  },
  { id = 823632641, param = 9,  label = "Flight Dir.",unit = "deg"  },
  { id = 823632641, param = 14, label = "Satellites", unit = "SAT"  },
}

system = {
  getSensors   = function() return sensors end,
  pSave        = function(k, v) saved[k] = v end,
  pLoad        = function(k) return saved[k] end,
}

-- the code under test, copied verbatim from Apps/f3xc.lua -------------------
local sens = { lat = {}, lon = {}, spd = {}, hdg = {} }

local function saveSensorCfg(which)
  local s = sens[which]
  system.pSave(which .. "Id", s.id)
  system.pSave(which .. "Param", s.param)
end

local function bound(which)
  local s = sens[which]
  return s.id ~= nil and s.param ~= nil
end

local KNOWN = {
  { name = "gpslog3", lat = 3, lon = 4, spd = 5, hdg = 9 },
}

local function bindKnownProfile()
  local ok, all = pcall(system.getSensors)
  if not ok or type(all) ~= "table" then return 0 end
  for _, g in ipairs(all) do
    if g.param == 0 and g.id then
      local low = string.lower(tostring(g.label or ""))
      for _, k in ipairs(KNOWN) do
        if low == k.name then
          for _, e in ipairs(all) do
            if e.id == g.id and e.param ~= 0 then
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
    end
  end
  return 0
end

-- run ------------------------------------------------------------------------
local r = bindKnownProfile()
assert(r == 1, "profile should match, got " .. r)

local expect = { lat = 3, lon = 4, spd = 5, hdg = 9 }
for which, param in pairs(expect) do
  assert(sens[which].id == 823632641,
    which .. " id wrong: " .. tostring(sens[which].id))
  assert(sens[which].param == param,
    which .. " param wrong: " .. tostring(sens[which].param) .. " expected " .. param)
  assert(saved[which .. "Id"] == 823632641, which .. " not persisted")
end

-- second run must not overwrite anything (bound() guard)
local before = {}
for k, v in pairs(sens) do before[k] = { id = v.id, param = v.param } end
bindKnownProfile()
for k, v in pairs(before) do
  assert(sens[k].id == v.id and sens[k].param == v.param, k .. " changed on rerun")
end

print("PASS: GPSLog3 bound to lat=3 lon=4 spd=5 hdg=9, id=823632641")
print("PASS: rebinding is idempotent")
