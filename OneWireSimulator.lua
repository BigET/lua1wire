#!/usr/bin/lua

local bit = require("bit")
local band, bor, blshift, tohex, brshift = bit.band, bit.bor, bit.lshift, bit.tohex, bit.rshift
local crc = require("OneWireCrc")

local OneWireSimulator = {}

local function mkReceiveByte(cont)
    local bitValue = 1
    local receivedByte = 0
    local function funct(bitReceive)
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
        local rez = 0 ~= band(addr[currentByte], blshift(1, currentBit))
        if currentBit == 7 then
            currentByte = currentByte + 1
            currentBit = 0
        else currentBit = currentBit + 1 end
        if currentByte == 9 then return rez, cont()
        else return rez, funct end
    end
    return funct
end

local function mkSearchAddress(addr, contS, contF)
    local currentBit = 0
    local currentByte = 1
    local writeFunct = nil
    local function readFunct(bitValue)
        if (bitValue and 0 == band(addr[currentByte], blshift(1, currentBit)))
                or (not bitValue and 0 ~= band(addr[currentByte], blshift(1, currentBit)))
            then return bitValue, contF end
        if currentBit == 7 then
            currentByte = currentByte + 1
            currentBit = 0
        else currentBit = currentBit + 1 end
        if currentByte == 9 then return bitValue, contS
        else return bitValue, writeFunct end
    end
    local function writeNegFunct(bitValue)
        return 0 == band(addr[currentByte], blshift(1, currentBit)), readFunct
    end
    writeFunct = function(bitValue)
        return 0 ~= band(addr[currentByte], blshift(1, currentBit)), writeNegFunct
    end
    return writeFunct
end

function OneWireSimulator.mkDS2401(addr)
    local myDev = {}
    local myAddr = {1}
    for i = 1,6 do
        myAddr[i + 1] = addr[i]
    end
    myAddr[8] = crc.crc8(myAddr)
    local function waitReset() return true, waitReset end
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

function OneWireSimulator.mkOneWireSimulator(deviceArray)
    local myNet = {}
    local function sendReset()
        local presence = false
        for _, dev in ipairs(deviceArray) do
            presence = dev.resetPulse() or presence
        end
        return presence
    end
    local function bitBang(bitValue)
        local bitResponse = bitValue
        for _, dev in ipairs(deviceArray) do
            bitResponse = dev.bitAssert(bitValue) and bitResponse
        end
        --print(bitValue, bitResponse)
        return bitResponse
    end
    local function writeByte(byteValue)
        local byteResponse = 0
        for i = 0, 7 do
            local bitMask = blshift(1, i)
            if bitBang(0 ~= band(byteValue, bitMask)) then byteResponse = byteResponse + bitMask end
        end
        if byteResponse ~= byteValue then
            print("trimis:", tohex(byteValue), "primit:", tohex(byteResponse))
        end
    end
    local function writeBytes(byteValues, cont)
        for _, byteValue in ipairs(byteValues) do writeByte(byteValue) end
    end
    local function readByte()
        local rezByte = 0
        for i = 0,7 do
            if bitBang(true) then rezByte = rezByte + lshift(1, i) end
        end
        return rezByte
    end
    local function readBytes(count)
        local rez = {}
        for i = 1, count do rez[#rez + 1] = readByte() end
        return rez
    end
    function myNet.readROM(cont)
        if not sendReset() then return end
        writeByte(0x33)
        return readBytes(8), cont(readBytes, writeBytes)
    end
    function myNet.matchROM(cont)
        if not sendReset() then return end
        writeByte(0x55)
        return cont(readBytes, writeBytes)
    end
    function myNet.skipROM(cont)
        if not sendReset() then return end
        writeByte(0xcc)
        return cont(readBytes, writeBytes)
    end
    function myNet.searchROM(addrStart, cont)
        if not sendReset() then return end
        writeByte(0xf0)
        local lastForkByte, lastForkBit, foundAddr = 0, 0, {0,0,0,0,0,0,0,0}
        for currentByte = 1, 8 do
            for currentBit = 0, 7 do
                local directBit, inverseBit = bitBang(true), bitBang(true)
                local bitDecis = directBit
                if directBit and inverseBit then return {0,0,0,0,0,0,0,0}
                elseif not directBit and not inverseBit then
                    if 0 == band(addrStart[currentByte], blshift(1, currentBit)) then
                        lastForkBit = currentBit
                        lastForkByte = currentByte
                    else bitDecis = true end
                end
                if bitBang(bitDecis) then
                    foundAddr[currentByte] = foundAddr[currentByte] + blshift(1, currentBit)
                end
            end
        end
        if lastForkByte == 0 then
            for currentByte = 1, 8 do addrStart[currentByte] = 0 end
        else
            for currentByte = 1, lastForkByte do addrStart[currentByte] = foundAddr[currentByte] end
            addrStart[lastForkByte] = bor(band(addrStart[lastForkByte], brshift(0xff, 7 - lastForkBit)), brshift(0x80, 7 - lastForkBit))
            for currentByte = lastForkByte + 1, 8 do
                addrStart[currentByte] = 0
            end
        end
        return cont(foundAddr, addrStart)
    end
    return myNet
end

function OneWireSimulator.getStartAddress() return {0,0,0,0,0,0,0,0} end
function OneWireSimulator.isStartAddress(addr)
    for i = 1, 8 do if addr[i] ~= 0 then return false end end
    return true
end

return OneWireSimulator
