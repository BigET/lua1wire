#!/usr/bin/lua

local bit = require("bit")
local band, bor, blshift, tohex, brshift, bxor = bit.band, bit.bor, bit.lshift, bit.tohex, bit.rshift, bit.bxor
local crc = require("OneWireCrc")

local OneWireSimulator = {}

local function mkReceiveByte(cont)
    local bitValue = 1
    local receivedByte = 0
    local function funct(bitReceive)
        if bitReceive then receivedByte = receivedByte + bitValue end
        bitValue = bitValue * 2
        if bitValue > 128 then return bitReceive, cont(receivedByte) end
        return bitReceive, funct
    end
    return funct
end

local function mkReceiveBytes(count, cont)
    local receivedBytes = {}
    local function byteCont(receivedByte)
        receivedBytes[#receivedBytes + 1] = receivedByte
        if #receivedBytes == count then return cont(receivedBytes) end
        return mkReceiveByte(byteCont)
    end
    return mkReceiveByte(byteCont)
end

local function mkSendByte(byteToSend, cont)
    local currentBit = 0
    local function funct(bitReceive)
        local rez = 0 ~= band(byteToSend, blshift(1, currentBit))
        currentBit = currentBit + 1
        if currentBit > 7 then return rez, cont() end
        return rez, funct
    end
    return funct
end

local function mkROMDevice(addr, devIO, isAlerted)
    local isSelected = false
    local romDev = {}
    addr[8] = crc.crc8(addr)
    local function waitReset() return true, waitReset end
    local state = waitReset

    local function goWaitReset() return waitReset end

    local function mkReadAddress()
        local currentBit = 0
        local currentByte = 1
        local function funct(_)
            local rez = 0 ~= band(addr[currentByte], blshift(1, currentBit))
            if currentBit == 7 then
                currentByte = currentByte + 1
                currentBit = 0
            else currentBit = currentBit + 1 end
            if currentByte == 9 then return rez, devIO()
            else return rez, funct end
        end
        return funct
    end

    local function mkMatchAddress()
        local function funct(recvAddress)
            for i = 1, 8 do if recvAddress[i] ~= addr[i] then return waitReset end end
            isSelected = true
            return devIO()
        end
        return mkReceiveBytes(8, funct)
    end

    local function mkSearchAddress()
        local currentBit = 0
        local currentByte = 1
        local writeFunct = nil
        local function readFunct(bitValue)
            if (bitValue and 0 == band(addr[currentByte], blshift(1, currentBit)))
                    or (not bitValue and 0 ~= band(addr[currentByte], blshift(1, currentBit)))
                then return bitValue, waitReset end
            if currentBit == 7 then
                currentByte = currentByte + 1
                currentBit = 0
            else currentBit = currentBit + 1 end
            if currentByte == 9 then isSelected = true return bitValue, devIO()
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

    local function processROMCommand(romCommand)
        if romCommand == 0x33 then isSelected = false return mkReadAddress() end
        if romCommand == 0x55 then isSelected = false return mkMatchAddress() end
        if romCommand == 0xf0 then return mkSearchAddress() end
        if romCommand == 0xcc then isSelected = false return devIO() end
        if romCommand == 0xa5 and isSelected then return devIO() end
        if romCommand == 0xec and isAlerted() then return mkSearchAddress() end
        return waitReset
    end
    function romDev.resetPulse()
        state = mkReceiveByte(processROMCommand)
        return true
    end
    function romDev.bitAssert(bitValue)
        local resp, newState = state(bitValue)
        state = newState
        return resp
    end
    return romDev, waitReset
end


function OneWireSimulator.mkDS2401(addr)
    local myAddr = {1}
    for i = 1,6 do
        myAddr[i + 1] = addr[i]
    end
    local myDev, waitReset = nil, nil
    myDev, waitReset = mkROMDevice(myAddr, function() return waitReset end, function() return false end)
    return myDev
end

function OneWireSimulator.mkDS2413(addr, readIO, writeIO)
    local myAddr = {0x3a}
    local myPIOA, myPIOB = false, true
    for i = 1,6 do
        myAddr[i + 1] = addr[i]
    end
    local waitReset = nil
    local function samplePIO()
        local pioa, piob = readIO()
        local octet = 0
        if pioa then octet = 1 end
        if myPIOA then octet = octet + 2 end
        if piob then octet = octet + 4 end
        if myPIOB then octet = octet + 8 end
        octet = bxor (octet + blshift(octet, 4), 0xf0)
        return octet
    end
    local function redoSample()
        return mkSendByte(samplePIO, redoSample)
    end
    local redoPIOWrite = nil
    local function sampleOnce()
        return mkSendByte(samplePIO(), redoPIOWrite)
    end
    local function setPIO(bytes)
        if 0xff ~= bxor(bytes[1], bytes[2]) then return function() return waitReset end end
        myPIOA = 0 ~= band(bytes[1], 1)
        myPIOB = 0 ~= band(bytes[1], 2)
        writeIO(myPIOA, myPIOB)
        return mkSendByte(0xaa, sampleOnce)
    end
    redoPIOWrite = function()
        return mkReceiveBytes(2, setPIO)
    end
    local function processPIO(pioCommand)
        if pioCommand == 0xf5 then return redoSample() end
        if pioCommand == 0x5a then return redoPIOWrite() end
        return waitReset
    end
    local function pioFunction()
        return mkReceiveByte(processPIO)
    end
    local myDev = nil
    myDev, waitReset =  mkROMDevice(myAddr, pioFunction, function() return false end)
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
            if bitBang(true) then rezByte = rezByte + blshift(1, i) end
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
    function myNet.matchROM(addr, cont)
        if not sendReset() then return end
        writeByte(0x55)
        writeBytes(addr)
        return cont(readBytes, writeBytes)
    end
    function myNet.skipROM(cont)
        if not sendReset() then return end
        writeByte(0xcc)
        return cont(readBytes, writeBytes)
    end
    local function searchAcc(addrStart, cont)
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
        if 0 == crc.crc8(foundAddr) then return cont(foundAddr, addrStart, readBytes, writeBytes) end
    end
    function myNet.searchROM(addrStart, cont)
        if not sendReset() then return end
        writeByte(0xf0)
        searchAcc(addrStart, cont)
    end
    function myNet.condSearchROM(addrStart, cont)
        if not sendReset() then return end
        writeByte(0xec)
        searchAcc(addrStart, cont)
    end
    function myNet.resumeROM(cont)
        if not sendReset() then return end
        writeByte(0xa5)
        return cont(readBytes, writeBytes)
    end
    return myNet
end

function OneWireSimulator.getStartAddress() return {0,0,0,0,0,0,0,0} end
function OneWireSimulator.isStartAddress(addr)
    for i = 1, 8 do if addr[i] ~= 0 then return false end end
    return true
end

return OneWireSimulator
