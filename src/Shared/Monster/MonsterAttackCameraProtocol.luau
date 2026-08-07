--[[
	职责：定义怪兽攻击出罐后区域运镜的稳定网络命令。
	输入：任意 command table。
	输出：是否合法及稳定失败原因。
	不负责：解析 Plot、查找 CameraMarker、播放相机动画或改变怪兽状态。
]]

local ValueValidation = require(script.Parent.Parent.ValueValidation)

local MonsterAttackCameraProtocol = {}

MonsterAttackCameraProtocol.RemoteName = "MonsterAttackCameraPresentation"
MonsterAttackCameraProtocol.RequestRemoteName = "MonsterAttackCameraRequest"
MonsterAttackCameraProtocol.FocusRegionKind = "FocusRegion"
MonsterAttackCameraProtocol.FocusSoloRegionKind = "FocusSoloRegion"
MonsterAttackCameraProtocol.TransitionCompletedKind = "TransitionCompleted"

export type FocusRegionCommand = {
	Kind: "FocusRegion",
	CommandId: number,
	AttackerUserId: number,
	AttackerSpawnPointId: string,
	TargetOwnerUserId: number,
	RegionId: string,
}

export type FocusSoloRegionCommand = {
	Kind: "FocusSoloRegion",
	CommandId: number,
	AttackerUserId: number,
	AttackerSpawnPointId: string,
	TargetPlotName: string,
	RegionId: string,
}

export type Command = FocusRegionCommand | FocusSoloRegionCommand

export type TransitionCompletedRequest = {
	Kind: "TransitionCompleted",
	CommandId: number,
	AttackerUserId: number,
	AttackerSpawnPointId: string,
}

local function isPositiveInteger(value): boolean
	return type(value) == "number"
		and ValueValidation.IsFiniteNumber(value)
		and value % 1 == 0
		and value > 0
end

local function isNonZeroInteger(value): boolean
	return type(value) == "number"
		and ValueValidation.IsFiniteNumber(value)
		and value % 1 == 0
		and value ~= 0
end

function MonsterAttackCameraProtocol.Validate(command): (boolean, string?)
	if type(command) ~= "table" then
		return false, "InvalidCommand"
	end
	if command.Kind ~= MonsterAttackCameraProtocol.FocusRegionKind
		and command.Kind ~= MonsterAttackCameraProtocol.FocusSoloRegionKind
	then
		return false, "InvalidKind"
	end
	if not isPositiveInteger(command.CommandId) then
		return false, "InvalidCommandId"
	end
	if not isNonZeroInteger(command.AttackerUserId) then
		return false, "InvalidAttackerUserId"
	end
	if not ValueValidation.IsNonEmptyString(command.AttackerSpawnPointId) then
		return false, "InvalidAttackerSpawnPointId"
	end
	if command.Kind == MonsterAttackCameraProtocol.FocusRegionKind then
		if not isNonZeroInteger(command.TargetOwnerUserId) then
			return false, "InvalidTargetOwnerUserId"
		end
	elseif not ValueValidation.IsNonEmptyString(command.TargetPlotName) then
		return false, "InvalidTargetPlotName"
	end
	if not ValueValidation.IsNonEmptyString(command.RegionId) then
		return false, "InvalidRegionId"
	end
	return true, nil
end

function MonsterAttackCameraProtocol.ValidateRequest(
	request
): (boolean, string?)
	if type(request) ~= "table" then
		return false, "InvalidRequest"
	end
	if request.Kind ~= MonsterAttackCameraProtocol.TransitionCompletedKind then
		return false, "InvalidKind"
	end
	if not isPositiveInteger(request.CommandId) then
		return false, "InvalidCommandId"
	end
	if not isNonZeroInteger(request.AttackerUserId) then
		return false, "InvalidAttackerUserId"
	end
	if not ValueValidation.IsNonEmptyString(request.AttackerSpawnPointId) then
		return false, "InvalidAttackerSpawnPointId"
	end
	return true, nil
end

return table.freeze(MonsterAttackCameraProtocol)
