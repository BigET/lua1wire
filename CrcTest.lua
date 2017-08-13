#!/usr/bin/lua

local Folding = require("Folding")
local OneWireCrc = require("OneWireCrc")
local bit = require("bit")

local is16BitCrc = false

for _,val in ipairs(arg) do
    if nil ~= string.find(val, "-16") then is16BitCrc = true break end
end

local hexes = Folding.mapFilter(
        function(str) return tonumber(str, 16) end,
        function(str) return nil == string.find(str, "-") end,
        arg
    )

if is16BitCrc
    then print (bit.tohex(OneWireCrc.crc16(hexes)))
    else print (bit.tohex(OneWireCrc.crc8(hexes)))
end
