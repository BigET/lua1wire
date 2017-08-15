#!/usr/bin/lua

local bit = require("bit")
local band, blshift = bit.band, bit.lshift
local crc = require("OneWireCrc")

local OneWireSimulator = {}

local function mkReceiveByte(cont)
    local bitValue = 1
    local receivedByte = 0
    local funct = function(bitReceive)
        if bitReceive then receivedByte = receivedByte + bitValue end
        bitValue = bitValue * 2
        if bitValue > 128 then return bitReceive, cont(receivedByte)
        else return bitReceive, funct end
    end
    return funct
end

local function mkReadAddress(addr, cont)
    local currentBit = 0
    local currentByte = 1
    local funct = function(_)
        local rez = 0 ~= band(addr[currentByte], lshift(1, currentBit))
        if currentBit == 7 then
            currentByte = currentByte + 1
            currentBit = 0
        else currentBit = currentBit + 1 end
        if currentByte == 9 then return rez, cont()
        else return rez, funct end
    end
    return funct
end

local function mkSeachAddress(addr, constS, constF)
    local currentBit = 0
    local currentByte = 1
    local writeFunct = nil
    local function readFunct(bitValue)
        if (bitValue and 0 == band(addr[currentByte], lshift(1, currentBit)))
                or (not bitValue and 0 ~= band(addr[currentByte], lshift(1, currentBit)))
            then return bitValue, contF() end
        if currentBit == 7 then
            currentByte = currentByte + 1
            currentBit = 0
        else currentBit = currentBit + 1 end
        if currentByte == 9 then return bitValue, contS()
        else return bitValue, writeFunct end
    end
    local function writeNegFunct(bitValue)
        return 0 == band(addr[currentByte], lshift(1, currentBit)), readFunct
    end
    writeFunct = function(bitValue)
        return 0 ~= band(addr[currentByte], lshift(1, currentBit)), writeNegFunct
    end
    return writeFunct
end

local function mkDS2401(addr)
    local myDev = {}
    local myAddr = {1}
    for i = 1,6 do
        myAddr[i + 1] = addr[i]
    end
    myAddr[8] = crc.crc8(myAddr)
    local function waitReset() return true end
    local state = waitReset
    local function processROMCommand(romCommand)
        if romCommand == 0x33 or romCommand == 0x0f then return mkReadAddress(myAddr, waitReset) end
        if romCommand == 0xf0 then return mkSearchAddress(myAddr, waitReset, waitReset) end
        return waitReset
    end
    function myDev.resetPulse()
        state = mkReceiveByte(processROMCommand)
        return true
    end
    function myDev.bitAssert(bitValue)
        local resp, newState = state(bitValue)
        state = newState
        return resp
    end
    return myDev
end

return OneWireSimulator
