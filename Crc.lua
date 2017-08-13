#!/usr/bin/lua

bit = require("bit")
local bxor, band, brshift, blshift = bit.bxor, bit.band, bit.rshift, bit.lshift

local function crc8byte(crc, inbyte)
    local tmp = bxor(crc, inbyte)
    crc = 0
    if band(tmp, 0x01)~=0 then crc = bxor(crc, 0x5e) end
    if band(tmp, 0x02)~=0 then crc = bxor(crc, 0xbc) end
    if band(tmp, 0x04)~=0 then crc = bxor(crc, 0x61) end
    if band(tmp, 0x08)~=0 then crc = bxor(crc, 0xc2) end
    if band(tmp, 0x10)~=0 then crc = bxor(crc, 0x9d) end
    if band(tmp, 0x20)~=0 then crc = bxor(crc, 0x23) end
    if band(tmp, 0x40)~=0 then crc = bxor(crc, 0x46) end
    if band(tmp, 0x80)~=0 then crc = bxor(crc, 0x8c) end
    return crc
end

local function crc16Byte(crc, byte)
    local xpp = band(0xff, bxor(crc, byte))
    local xppp = bxor(xpp, brshift(xpp, 4))
    local xq = bxor(xppp, brshift(xppp, 2))
    local xqq = band(1, bxor(xq, brshift(xq, 1)))
    return band(0xffff, bxor(bxor(bxor(xqq, blshift(xqq, 15)), bxor(blshift(xqq, 14), band(0xff, brshift(crc, 8)))), bxor(blshift(xpp, 6), blshift(xpp, 7))))
end

function foldl(foldf, initv, array)
    for _, val in ipairs(array) do
        initv = foldf(initv, val)
    end
    return initv
end

function mapFilter(mapf, filter, array)
    return foldl(function (acc, val) if filter(val) then acc[#acc + 1] = mapf(val) end return acc end, {}, array)
end

function crc8 (array) return foldl(crc8byte, 0, array) end

function crc16 (array) return foldl(crc16Byte, 0, array) end

local is16BitCrc = false

for _,val in ipairs(arg) do
    if nil ~= string.find(val, "-16") then is16BitCrc = true break end
end

local hexes = mapFilter(
        function(str) return tonumber(str, 16) end,
        function(str) return nil == string.find(str, "-") end,
        arg
    )

if is16BitCrc
    then print (bit.tohex(crc16(hexes)))
    else print (bit.tohex(crc8(hexes)))
end
--foldl(function(acc, val) print(val) return acc end, 0, hexes)
