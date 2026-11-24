-- test for bindKnownProfile: both discovery paths
--   1) group row carries the sensor name ("GPSLog3")
--   2) no group row, but a row is labelled "Latitude"
-- Uses the sensor rows found on the real DS-24 II.

local saved = {}
local current = {}

system = {
  getSensors = function() return current end,
  pSave      = function(k, v) saved[k] = v end,
}

local sens
local function reset()
  sens, saved = { lat = {}, lon = {}, spd = {}, hdg = {} }, {}
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

local KNOWN = {
  { name = "gpslog3", lat = 3, lon = 4, spd = 5, hdg = 9 },
}

local function bindKnownProfile()
  local ok, all = pcall(system.getSensors)
  if not ok or type(all) ~= "table" then return 0 end

  local function lower(v) return string.lower(tostring(v or "")) end

  for _, k in ipairs(KNOWN) do
    local id = nil
    for _, e in ipairs(all) do
      if e.param == 0 and e.id and lower(e.label) == k.name then id = e.id; break end
    end
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

-- full telemetry as seen on the transmitter -----------------------------------
local FULL = {
  { id = 809083650, param = 0,  label = "UniS-E",      unit = "na"   },
  { id = 809083650, param = 1,  label = "Voltage",     unit = "V"    },
  { id = 809083650, param = 5,  label = "Altitude",    unit = "m"    },
  { id = 809083650, param = 6,  label = "Vario",       unit = "m/s"  },
  { id = 823632641, param = 0,  label = "GPSLog3",     unit = "na"   },
  { id = 823632641, param = 1,  label = "Time",        unit = ""     },
  { id = 823632641, param = 3,  label = "Latitude",    unit = "LAT"  },
  { id = 823632641, param = 4,  label = "Longitude",   unit = "LON"  },
  { id = 823632641, param = 5,  label = "Speed",       unit = "kmh"  },
  { id = 823632641, param = 9,  label = "Flight Dir.", unit = "deg"  },
  { id = 823632641, param = 14, label = "Satellites",  unit = "SAT"  },
}

local function checkAll(tag)
  local expect = { lat = 3, lon = 4, spd = 5, hdg = 9 }
  for which, param in pairs(expect) do
    assert(sens[which].id == 823632641,
      tag .. ": " .. which .. " id = " .. tostring(sens[which].id))
    assert(sens[which].param == param,
      tag .. ": " .. which .. " param = " .. tostring(sens[which].param))
    assert(saved[which .. "Id"] == 823632641, tag .. ": " .. which .. " not persisted")
  end
end

-- 1: named group row ----------------------------------------------------------
reset(); current = FULL
assert(bindKnownProfile() == 1, "named profile should match")
checkAll("named")
print("PASS: bound via group row GPSLog3 -> 3/4/5/9")

-- 2: no group row at all (some firmwares drop param 0) ------------------------
reset()
current = {}
for _, e in ipairs(FULL) do
  if e.param ~= 0 then current[#current + 1] = e end
end
assert(bindKnownProfile() == 1, "fallback by Latitude should match")
checkAll("lat-fallback")
print("PASS: bound without group row, via Latitude")

-- 3: unrelated sensor only -> nothing bound ----------------------------------
reset()
current = {
  { id = 111, param = 0, label = "UniS-E",   unit = "na" },
  { id = 111, param = 1, label = "Voltage",  unit = "V"  },
}
assert(bindKnownProfile() == 0, "must not bind on unrelated telemetry")
assert(not bound("lat") and not bound("lon"), "nothing should be bound")
print("PASS: unrelated telemetry is left alone")

-- 4: idempotent ---------------------------------------------------------------
reset(); current = FULL
bindKnownProfile()
local before = {}
for k, v in pairs(sens) do before[k] = { v.id, v.param } end
bindKnownProfile()
for k, v in pairs(before) do
  assert(sens[k].id == v[1] and sens[k].param == v[2], k .. " changed on rerun")
end
print("PASS: rebinding is idempotent")

print("all bind tests passed")
