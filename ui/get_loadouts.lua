-- Filename: get_loadouts.lua
local ffi = require("ffi")
local C = ffi.C
ffi.cdef [[

  typedef uint64_t UniverseID;
	typedef uint64_t BuildTaskID;
	typedef uint64_t FleetUnitID;
    typedef struct {
        const char* id;
        const char* name;
        const char* iconid;
        bool deleteable;
    } UILoadoutInfo;
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
	} UILoadoutMacroData2;
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
		uint32_t numweapons;
		uint32_t numturrets;
		uint32_t numshields;
		uint32_t numengines;
		uint32_t numturretgroups;
		uint32_t numshieldgroups;
		uint32_t numammo;
		uint32_t numunits;
		uint32_t numsoftware;
		uint32_t numcrew;
	} UILoadoutCounts2;

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

	UniverseID GetPlayerID(void);

	uint32_t GetNumAllFleetUnits(UniverseID controllableid);
	uint32_t GetAllFleetUnits(FleetUnitID* result, uint32_t resultlen, UniverseID controllableid);

	FleetUnitInfo GetFleetUnitInfo(FleetUnitID fleetunitid);
]]
-- Local functions/data.
local lsrbto = {
  logPrefix = "LSRBTO",
  replacementLoadoutName = "ReplacementShip",
  renameBlackboard = "$lsrbtoRenameTable",
  configBlackboard = "$LSRBTOConfig",
  debugLevel = "none", -- "none" = off, "debug" = debug, "trace" = trace
}

local function init()
  RegisterEvent("LSRBTO.SetDebugLevel", lsrbto.SetDebugLevel)
  RegisterEvent("LSRBTO.GetLoadoutId", lsrbto.RequestLoadoutId)
  RegisterEvent("LSRBTO.ProcessBuildTasks", lsrbto.ProcessBuildTasks)
  RegisterEvent("LSRBTO.Rename", lsrbto.Rename)
  lsrbto.ReadDebugLevel()
end

local function Write(message, ...)
  DebugError(lsrbto.logPrefix .. ": " .. string.format(message, ...))
end

function lsrbto.Error(message, ...)
  Write(message, ...)
end

function lsrbto.Debug(message, ...)
  if lsrbto.debugLevel == "debug" or lsrbto.debugLevel == "trace" then
    Write(message, ...)
  end
end

function lsrbto.Trace(message, ...)
  if lsrbto.debugLevel == "trace" then
    Write(message, ...)
  end
end

-- The MD event may arrive before or after the config exists, so the blackboard is the fallback source on load.
function lsrbto.ReadDebugLevel()
  local playerId = ConvertStringTo64Bit(tostring(C.GetPlayerID()))
  local config = GetNPCBlackboard(playerId, lsrbto.configBlackboard)
  if config and config.debugLevel then
    lsrbto.debugLevel = tostring(config.debugLevel)
  end
  lsrbto.Debug("ReadDebugLevel: level: %s", lsrbto.debugLevel)
end

function lsrbto.SetDebugLevel(_, level)
  if level and level ~= "" then
    lsrbto.debugLevel = tostring(level)
    lsrbto.Debug("SetDebugLevel: level: %s", lsrbto.debugLevel)
  else
    lsrbto.ReadDebugLevel()
  end
end

function lsrbto.FindLoadoutId(macro)
  local count = C.GetNumLoadoutsInfo(0, macro)
  if count == 0 then
    lsrbto.Trace("FindLoadoutId: macro: %s has no saved loadouts", macro)
    return nil
  end
  local buf = ffi.new("UILoadoutInfo[?]", count)
  count = C.GetLoadoutsInfo(buf, count, 0, macro)
  local numInvalidPatches = ffi.new("uint32_t[1]")
  for i = 0, count - 1 do
    if ffi.string(buf[i].name) == lsrbto.replacementLoadoutName then
      local id = ffi.string(buf[i].id)
      numInvalidPatches[0] = 0
      if not C.IsLoadoutValid(0, macro, buf[i].id, numInvalidPatches) or numInvalidPatches[0] > 0 then
        lsrbto.Debug("FindLoadoutId: macro: %s, loadout: %s is invalid, invalid patches: %s", macro, id, numInvalidPatches[0])
        return nil
      end
      lsrbto.Trace("FindLoadoutId: macro: %s, loadout: %s", macro, id)
      return id
    end
  end
  lsrbto.Trace("FindLoadoutId: macro: %s has no '%s' loadout", macro, lsrbto.replacementLoadoutName)
  return nil
end

function lsrbto.ProcessBuildTasks(_, commander)
  if not commander then
    lsrbto.Error("ProcessBuildTasks: no commander given")
    return
  end
  lsrbto.Debug("ProcessBuildTasks: commander: %s", commander)
  local commander64 = ConvertStringTo64Bit(tostring(commander))
  local count = C.GetNumAllFleetUnits(commander64)
  if count == 0 then
    lsrbto.Trace("ProcessBuildTasks: commander: %s has no fleet units", commander)
    return
  end
  local units = ffi.new("FleetUnitID[?]", count)
  count = C.GetAllFleetUnits(units, count, commander64)
  local playerId = ConvertStringTo64Bit(tostring(C.GetPlayerID()))
  local renameTable = GetNPCBlackboard(playerId, lsrbto.renameBlackboard) or {}
  local stored = false
  for i = 0, count - 1 do
    local unit = units[i]
    local info = C.GetFleetUnitInfo(unit)
    local name = ffi.string(info.name)
    local idcode = ffi.string(info.idcode)
    local macro = ffi.string(info.macro)
    lsrbto.Trace("ProcessBuildTasks: fleet unit: %s, name: %s, idcode: %s, buildTaskId: %s, replacementId: %s", unit, name, idcode, info.buildtaskid,
      info.replacementid)
    -- Only units without a build task yet: the loadout is snapshotted into the task when it is created.
    if info.buildtaskid == 0 and info.replacementid == 0 then
      local loadoutId = lsrbto.FindLoadoutId(macro)
      if loadoutId then
        local loadout = Helper.getLoadoutHelper2(C.GetLoadout2, C.GetLoadoutCounts2, "UILoadout2", 0, macro, loadoutId)
        C.SetFleetUnitLoadout(unit, macro, loadout)
        -- SetFleetUnitLoadout clears the unit's name, and it can only be restored on the replacement, which does not exist yet.
        renameTable[idcode] = name
        stored = true
        lsrbto.Debug("ProcessBuildTasks: fleet unit: %s (%s) got loadout: %s, name: %s stored for rename", unit, idcode, loadoutId, name)
      end
    end
  end
  if stored then
    SetNPCBlackboard(playerId, lsrbto.renameBlackboard, renameTable)
  end
end

function lsrbto.Rename(_, commander)
  if not commander then
    lsrbto.Error("Rename: no commander given")
    return
  end
  local playerId = ConvertStringTo64Bit(tostring(C.GetPlayerID()))
  local renameTable = GetNPCBlackboard(playerId, lsrbto.renameBlackboard) or {}
  if next(renameTable) == nil then
    lsrbto.Trace("Rename: nothing to rename")
    return
  end
  local commander64 = ConvertStringTo64Bit(tostring(commander))
  local count = C.GetNumAllFleetUnits(commander64)
  if count == 0 then
    lsrbto.Trace("Rename: commander: %s has no fleet units", commander)
    return
  end
  local units = ffi.new("FleetUnitID[?]", count)
  count = C.GetAllFleetUnits(units, count, commander64)
  local renamed = false
  for i = 0, count - 1 do
    local info = C.GetFleetUnitInfo(units[i])
    local idcode = ffi.string(info.idcode)
    local newName = renameTable[idcode]
    local replacementId = ConvertStringTo64Bit(tostring(info.replacementid))
    lsrbto.Trace("Rename: fleet unit: %s, idcode: %s, replacementId: %s, stored name: %s", units[i], idcode, replacementId, newName)
    if newName and replacementId ~= nil and replacementId ~= 0 then
      SetComponentName(replacementId, newName)
      lsrbto.Debug("Rename: replacement of fleet unit %s renamed to: %s", idcode, newName)
      renameTable[idcode] = nil
      renamed = true
    end
  end
  if renamed then
    SetNPCBlackboard(playerId, lsrbto.renameBlackboard, renameTable)
  end
end

function lsrbto.RequestLoadoutId(_, macro)
  if not macro then
    lsrbto.Error("RequestLoadoutId: no macro given")
    return
  end
  local loadoutId = lsrbto.FindLoadoutId(macro)
  if not loadoutId then
    return
  end
  lsrbto.Debug("RequestLoadoutId: macro: %s, loadout: %s", macro, loadoutId)
  return AddUITriggeredEvent("LSRBTO.LoadoutId", "Result", { macro = macro, id = loadoutId })
end

Register_OnLoad_Init(init)

return
