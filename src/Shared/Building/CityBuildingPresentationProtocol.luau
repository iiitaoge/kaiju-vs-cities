--[[
	职责：定义并验证服务器城市建筑表现命令的稳定外形。
	输入：任意 command。
	输出：是否合法及稳定失败原因。
	内部算法：按 Kind 验证公共字段和各命令专有字段；不读取 Instance 或配置。
]]

local ValueValidation = require(script.Parent.Parent.ValueValidation)

local CityBuildingPresentationProtocol = {}

CityBuildingPresentationProtocol.RemoteName = "CityBuildingPresentation"

export type RegionUpgradeCommand = {
	Kind: "RegionUpgrade",
	OwnerUserId: number,
	RegionId: string,
	PreviousLevel: number,
	NewLevel: number,
	PresentationId: string,
	BuildSpeedMultiplier: number,
	HouseIds: { string },
}

export type HouseLifecycleCommand = {
	Kind: "HouseDestroyed" | "HouseRebuilding",
	OwnerUserId: number,
	RegionId: string,
	HouseId: string,
	Level: number,
	PresentationId: string,
	BuildSpeedMultiplier: number,
}

export type Command = RegionUpgradeCommand | HouseLifecycleCommand

local function isInteger(value): boolean
	return type(value) == "number"
		and value == value
		and value < math.huge
		and value > -math.huge
		and value % 1 == 0
end

function CityBuildingPresentationProtocol.Validate(command): (boolean, string?)
	if type(command) ~= "table" then
		return false, "InvalidCommand"
	end
	if not isInteger(command.OwnerUserId) or command.OwnerUserId == 0 then
		return false, "InvalidOwnerUserId"
	end
	if not ValueValidation.IsNonEmptyString(command.RegionId) then
		return false, "InvalidRegionId"
	end
	if not ValueValidation.IsNonEmptyString(command.PresentationId) then
		return false, "InvalidPresentationId"
	end
	if not ValueValidation.IsFiniteNumber(command.BuildSpeedMultiplier)
		or command.BuildSpeedMultiplier <= 0
	then
		return false, "InvalidBuildSpeedMultiplier"
	end

	if command.Kind == "RegionUpgrade" then
		if not isInteger(command.PreviousLevel) or command.PreviousLevel < 0 then
			return false, "InvalidPreviousLevel"
		end
		if not isInteger(command.NewLevel)
			or command.NewLevel ~= command.PreviousLevel + 1
		then
			return false, "InvalidNewLevel"
		end
		if type(command.HouseIds) ~= "table" then
			return false, "InvalidHouseIds"
		end
		for _, houseId in command.HouseIds do
			if not ValueValidation.IsNonEmptyString(houseId) then
				return false, "InvalidHouseId"
			end
		end
		return true, nil
	end

	if command.Kind == "HouseDestroyed" or command.Kind == "HouseRebuilding" then
		if not ValueValidation.IsNonEmptyString(command.HouseId) then
			return false, "InvalidHouseId"
		end
		if not isInteger(command.Level) or command.Level < 1 then
			return false, "InvalidLevel"
		end
		return true, nil
	end

	return false, "InvalidKind"
end

return table.freeze(CityBuildingPresentationProtocol)
