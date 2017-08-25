#!/usr/bin/lua

local sim = require("OneWireSimulator")
local bit = require("bit")
local crc = require("OneWireCrc")

function printPIO(pioa,piob) print("activat pio.",pioa, piob) end
function readDown() return false, false end

local inst = sim.mkOneWireSimulator({
        sim.mkDS2401({1,2,3,4,5,6}),
        sim.mkDS2401({2,3,1,44,54,0}),
        sim.mkDS2413({1,2,3,4,5,6},readDown,printPIO),
        sim.mkDS2413({1,2,3,4,5,7},readDown,printPIO)
    })

function forEachDevice(ownet, f)
    local function cont(faddr, naddr, readBytes, writeBytes)
        if 0 == crc.crc8(faddr) and f(faddr, readBytes, writeBytes) and not sim.isStartAddress(naddr) then
            return ownet.searchROM(naddr, cont)
        end
        return
    end
    ownet.searchROM(sim.getStartAddress(), cont)
end

local function listDevices()
    local function printDeviceAddres(addr, readBytes, writeBytes)
        local str = "Found device:"
        for i = 1, 8 do str = str .. " " .. bit.tohex(addr[i], -2) end
        print(str)
        if addr[1] == 0x3a then
            writeBytes({0x5a, 3, 0xfc})
            local rez = readBytes(2)
            print("rezultat", bit.tohex(rez[1], -2), bit.tohex(rez[2], -2))
        end
        return true
    end
    forEachDevice(inst, printDeviceAddres)
end

local function writePIO(pioa, piob)
    return function (readB, writeB)
        local txt = {0x5a,0}
        if pioa then txt[2] = 1 end
        if piob then txt[2] = txt[2] + 2 end
        txt[3] = bit.bxor(txt[2], 0xff)
        writeB(txt)
        local rez = readB(2)
        print("rezultat", bit.tohex(rez[1], -2), bit.tohex(rez[2], -2))
    end
end

listDevices()
listDevices()
print "match"
inst.matchROM({0x3a,1,2,3,4,5,6,0x1f}, writePIO(true, false))
print "resume"
inst.resumeROM(writePIO(false, false))
print "skip"
inst.skipROM(writePIO(true, true))
print "read"
inst.readROM(writePIO(false, true))
print "This should fail"
inst.resumeROM(writePIO(false, false))
