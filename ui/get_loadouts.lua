-- Filename: get_loadouts.lua
local ffi = require("ffi")
local C = ffi.C
ffi.cdef [[
    typedef uint64_t UniverseID;
    typedef struct {
        const char* id;
        const char* name;
        const char* iconid;
        bool deleteable;
    } UILoadoutInfo;
    typedef struct {
        const char* id;
        const char* name;
        int32_t state;
        const char* requiredversion;
        const char* installedversion;
    } InvalidPatchInfo;
	uint32_t GetNumLoadoutsInfo(UniverseID componentid, const char* macroname);
	bool IsLoadoutValid(UniverseID defensibleid, const char* macroname, const char* loadoutid, uint32_t* numinvalidpatches);
    uint32_t GetLoadoutsInfo(UILoadoutInfo* result, uint32_t resultlen, UniverseID componentid, const char* macroname);
]]
-- Local functions/data.
local L = {
}

local function Init()
    RegisterEvent("GetShipLoadoutsInfoRequest", L.GetLoadoutsInfo)
end


function L.GetLoadoutsInfo(_, macro)
    local loadouts = {}
    local n = C.GetNumLoadoutsInfo(0, macro)
    -- DebugError(string.format("GLI_Collect: macro = %s, count = %s", macro, n))
    local buf = ffi.new("UILoadoutInfo[?]", n)
    n = C.GetLoadoutsInfo(buf, n, 0, macro)
    for i = 0, n - 1 do
        local id = ffi.string(buf[i].id)
        local name = ffi.string(buf[i].name)
        -- DebugError(string.format("GLI_Collect: i = %s, id = %s, name = %s", i, id, name))
        local numInvalidPatches = ffi.new("uint32_t[?]", 1)
        if C.IsLoadoutValid(0, macro, id, numInvalidPatches) then
            -- DebugError(string.format("GLI_Collect:  loadout is valid"))
            local item = {}
            item.id = id
            item.name = ffi.string(buf[i].name)
            table.insert(loadouts, item)
        end
    end
    -- DebugError(string.format("GLI_Collect:  loadoutList = %s", #loadouts))
    return AddUITriggeredEvent('GetShipLoadoutsInfoResult', 'Result', {macro = macro, loadouts = loadouts})
end


Init()

return
