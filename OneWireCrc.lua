#!/usr/bin/lua

local OneWireCrc = {}

local bit = require("bit")
local Folding = require("Folding")
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

function OneWireCrc.crc8 (array) return Folding.foldl(crc8byte, 0, array) end

function OneWireCrc.crc16 (array) return Folding.foldl(crc16Byte, 0, array) end

return OneWireCrc
