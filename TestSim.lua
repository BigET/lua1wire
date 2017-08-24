#!/usr/bin/lua

local sim = require("OneWireSimulator")
local bit = require("bit")

local inst = sim.mkOneWireSimulator({sim.mkDS2401({1,2,3,4,5,6}), sim.mkDS2401({2,3,1,44,54,0})})

function forEachDevice(ownet, f)
    local function cont(faddr, naddr)
        if f(faddr) and not sim.isStartAddress(naddr) then
            return ownet.searchROM(naddr, cont)
        end
        return
    end
    ownet.searchROM(sim.getStartAddress(), cont)
end

local function listDevices()
    local function printDeviceAddres(addr)
        local str = "Found device:"
        for i = 1, 8 do str = str .. " " .. bit.tohex(addr[i], -2) end
        print(str)
        return true
    end
    forEachDevice(inst, printDeviceAddres)
end

listDevices()
listDevices()
