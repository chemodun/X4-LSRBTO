-- Filename: get_loadouts.lua
local ffi = require("ffi")
local C = ffi.C
ffi.cdef [[

  typedef uint64_t UniverseID;
	typedef uint64_t FleetUnitID;
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
	typedef struct {
		const char* ammomacroname;
		const char* weaponmode;
	} UILoadoutWeaponSetting;
	typedef struct {
		const char* macro;
		const char* upgradetypename;
		size_t slot;
		bool optional;
		UILoadoutWeaponSetting weaponsetting;
	} UILoadoutMacroData2;;
	typedef struct {
		const char* macro;
		const char* path;
		const char* group;
		uint32_t count;
		bool optional;
		UILoadoutWeaponSetting weaponsetting;
	} UILoadoutGroupData2;
	typedef struct {
		const char* macro;
		uint32_t amount;
		bool optional;
	} UILoadoutAmmoData;
	typedef struct {
		const char* roleid;
		uint32_t count;
		bool optional;
	} UILoadoutCrewData;
	typedef struct {
		const char* ware;
	} UILoadoutSoftwareData;
	typedef struct {
		const char* macro;
		bool optional;
	} UILoadoutVirtualMacroData;
	typedef struct {
		UILoadoutMacroData2* weapons;
		uint32_t numweapons;
		UILoadoutMacroData2* turrets;
		uint32_t numturrets;
		UILoadoutMacroData2* shields;
		uint32_t numshields;
		UILoadoutMacroData2* engines;
		uint32_t numengines;
		UILoadoutGroupData2* turretgroups;
		uint32_t numturretgroups;
		UILoadoutGroupData2* shieldgroups;
		uint32_t numshieldgroups;
		UILoadoutAmmoData* ammo;
		uint32_t numammo;
		UILoadoutAmmoData* units;
		uint32_t numunits;
		UILoadoutSoftwareData* software;
		uint32_t numsoftware;
		UILoadoutVirtualMacroData thruster;
		uint32_t numcrew;
		UILoadoutCrewData* crew;
		bool hascrewexperience;
	} UILoadout2;

	typedef struct {
		FleetUnitID fleetunitid;
		const char* name;
		const char* idcode;
		const char* macro;
		BuildTaskID buildtaskid;
		UniverseID replacementid;
	} FleetUnitInfo;

	uint32_t GetNumLoadoutsInfo(UniverseID componentid, const char* macroname);
	bool IsLoadoutValid(UniverseID defensibleid, const char* macroname, const char* loadoutid, uint32_t* numinvalidpatches);
    uint32_t GetLoadoutsInfo(UILoadoutInfo* result, uint32_t resultlen, UniverseID componentid, const char* macroname);

	uint32_t GetLoadoutCounts2(UILoadoutCounts2* result, UniverseID defensibleid, const char* macroname, const char* loadoutid);
	void GetLoadout2(UILoadout2* result, UniverseID defensibleid, const char* macroname, const char* loadoutid);
	void SetFleetUnitLoadout(FleetUnitID fleetunitid, const char* macroname, UILoadout2 uiloadout);

	uint32_t GetNumAllFleetUnits(UniverseID controllableid);
	uint32_t GetAllFleetUnits(FleetUnitID* result, uint32_t resultlen, UniverseID controllableid);

	FleetUnitInfo GetFleetUnitInfo(FleetUnitID fleetunitid);
]]
-- Local functions/data.
local L = {
  replacementLoadoutName = "ReplacementShip",
}

local function Init()
  RegisterEvent("GetShipLoadoutsInfoRequest", L.GetLoadoutsInfo)
  RegisterEvent("LSRBTO.ProcessBuildTasks", L.ProcessBuildTasks)
  RegisterEvent("LSRBTO.Rename", L.Rename)
end

function L.ProcessBuildTasks(_, commander)
  DebugError(string.format("LSRBTO.ProcessBuildTasks:  commander: %s", commander))
  if not commander then
    DebugError("LSRBTO.ProcessBuildTasks:  invalid build task data in blackboard")
    return
  end
  local commander64 = ConvertStringTo64Bit(tostring(commander))
  local n = C.GetNumAllFleetUnits(commander64)
  if n > 0 then
    local buf = ffi.new("FleetUnitID[?]", n)
    n = C.GetAllFleetUnits(buf, n, commander64)
    for i = 0, n - 1 do
      local fleetUnitItem = buf[i]
      local info = C.GetFleetUnitInfo(fleetUnitItem)
      local name = ffi.string(info.name)
      local idcode = ffi.string(info.idcode)
      local macro = ffi.string(info.macro)
      local buildTaskId = info.buildtaskid
      local replacementId = info.replacementid
      DebugError(string.format("LSRBTO.ProcessBuildTasks:  fleetUnit: %s, name: %s, idcode: %s, buildTaskId: %s, replacementId: %s", fleetUnitItem, name, idcode,
        buildTaskId, replacementId))
      if buildTaskId == 0 and replacementId ~= 0 then
        local fleetUnit = fleetUnitItem
        local fleetUnitInfo = info
        DebugError(string.format("LSRBTO.ProcessBuildTasks:  found fleet unit: %s with macro: %s", fleetUnit, macro))
        -- local macro, name, idcode, isunit = GetComponentData(object64, "macro", "name", "idcode", "isunit")
        -- DebugError(string.format("LSRBTO.ProcessBuild:  object: %s, macro: %s, name: %s (%s), isunit: %s", object, macro, name, idcode, isunit))
        local n = C.GetNumLoadoutsInfo(0, macro)
        -- DebugError(string.format("GLI_Collect: macro = %s, count = %s", macro, n))
        local loadoutId = ""
        local buf = ffi.new("UILoadoutInfo[?]", n)
        n = C.GetLoadoutsInfo(buf, n, 0, macro)
        for i = 0, n - 1 do
          local id = ffi.string(buf[i].id)
          local name = ffi.string(buf[i].name)
          -- DebugError(string.format("GLI_Collect: i = %s, id = %s, name = %s", i, id, name))
          local numInvalidPatches = ffi.new("uint32_t[?]", 1)
          if C.IsLoadoutValid(0, macro, id, numInvalidPatches) and name == L.replacementLoadoutName then
            -- DebugError(string.format("GLI_Collect:  loadout is valid"))
            loadoutId = id
            break
          end
        end
        if loadoutId ~= "" then
          DebugError(string.format("LSRBTO.ProcessBuildTasks:  found valid loadout for macro: %s, loadoutId: %s", macro, loadoutId))
          local loadout = Helper.getLoadoutHelper2(C.GetLoadout2, C.GetLoadoutCounts2, "UILoadout2", 0, macro, loadoutId)
          DebugError(string.format("LSRBTO.ProcessBuildTasks:  loadout: %s", loadout))
          C.SetFleetUnitLoadout(fleetUnit, macro, loadout)
          DebugError(string.format("LSRBTO.ProcessBuildTasks:  loadout applied to fleet unit: %s", fleetUnit))
          local playerId = ConvertStringTo64Bit(tostring(C.GetPlayerID()))
          local renameTable = GetNPCBlackboard(playerId, "$lsrbtoRenameTable") or {}
          renameTable[idcode] = name
          SetNPCBlackboard(playerId, "$lsrbtoRenameTable", renameTable)
          DebugError(string.format("LSRBTO.ProcessBuildTasks:  added rename entry for fleet unit: %s, name: %s, idcode: %s", fleetUnit, renameTable[idcode], idcode))
        end
      end
    end
  end
end

function L.Rename(_, commander)
  local playerId = ConvertStringTo64Bit(tostring(C.GetPlayerID()))
  local renameTable = GetNPCBlackboard(playerId, "$lsrbtoRenameTable") or {}
  if next(renameTable) == nil then
    DebugError("LSRBTO.Rename:  no rename entries found in blackboard")
    return
  end
  local commander64 = ConvertStringTo64Bit(tostring(commander))
  local n = C.GetNumAllFleetUnits(commander64)
  if n > 0 then
    local buf = ffi.new("FleetUnitID[?]", n)
    n = C.GetAllFleetUnits(buf, n, commander64)
    for i = 0, n - 1 do
      local fleetUnitItem = buf[i]
      local info = C.GetFleetUnitInfo(fleetUnitItem)
      local name = ffi.string(info.name)
      local idcode = ffi.string(info.idcode)
      local replacementId = ConvertStringTo64Bit(tostring(info.replacementid))
      DebugError(string.format("LSRBTO.Rename:  fleetUnit: %s, name: %s, idcode: %s, replacementId: %s", fleetUnitItem, name, idcode, replacementId))
      if renameTable[idcode] and replacementId ~= nil and replacementId ~= 0 then
        local newName = renameTable[idcode]
        local replacementName, replacementIdCode = GetComponentData(replacementId, "name", "idcode")
        DebugError(string.format("LSRBTO.Rename:  fleet unit: %s has replacement: %s (%s), renaming to: %s", fleetUnitItem, replacementName, replacementIdCode, newName))
        SetComponentName(replacementId, newName)
        DebugError(string.format("LSRBTO.Rename:  name %s applied to replacement fleet unit: %s (%s)", newName, replacementName, replacementIdCode))
        renameTable[idcode] = nil
        SetNPCBlackboard(playerId, "$lsrbtoRenameTable", renameTable)
      end
    end
  end
end

function L.GetLoadoutsInfo(_, macro)
  local loadouts = {}
  if not macro then
    DebugError(string.format("GLI_Collect:  invalid input: %s", macro))
    return
  end
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
  return AddUITriggeredEvent('GetShipLoadoutsInfoResult', 'Result', { macro = macro, loadouts = loadouts })
end

Init()

return
