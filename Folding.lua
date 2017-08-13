#!/usr/bin/lua

local Folding = {}

function Folding.foldl(foldf, initv, array)
    for _, val in ipairs(array) do
        initv = foldf(initv, val)
    end
    return initv
end

function Folding.mapFilter(mapf, filter, array)
    return Folding.foldl(function (acc, val) if filter(val) then acc[#acc + 1] = mapf(val) end return acc end, {}, array)
end

return Folding
