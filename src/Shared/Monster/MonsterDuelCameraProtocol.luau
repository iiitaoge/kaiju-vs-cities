--[[
	职责：定义决斗场景镜头的服务端发布、客户端请求和网络校验合同。
	输入：任意 command/request table。
	输出：是否合法及稳定失败原因。
	不负责：查找场景、判断玩家身份、控制镜头或显示按钮。
]]

local ValueValidation = require(script.Parent.Parent.ValueValidation)

local MonsterDuelCameraProtocol = {}

MonsterDuelCameraProtocol.RemoteName = "MonsterDuelCameraPresentation"
MonsterDuelCameraProtocol.RequestRemoteName = "MonsterDuelCameraRequest"

MonsterDuelCameraProtocol.AvailableKind = "DuelAvailable"
MonsterDuelCameraProtocol.FocusKind = "DuelFocus"
MonsterDuelCameraProtocol.RestoreKind = "DuelRestore"
MonsterDuelCameraProtocol.ToggleKind = "ToggleDuelCamera"
MonsterDuelCameraProtocol.TransitionCompletedKind = "DuelCameraTransitionCompleted"

export type Role = "Attacker" | "Defender"

export type CameraCommand = {
	Kind: "DuelAvailable" | "DuelFocus",
	CommandId: number,
	DuelId: string,
	Role: Role,
	AttackerUserId: number,
	AttackerSpawnPointId: string,
	DefenderUserId: number,
	CameraCFrame: CFrame,
	FieldOfView: number,
	TransitionDuration: number,
	RestoreDuration: number,
}

export type RestoreCommand = {
	Kind: "DuelRestore",
	CommandId: number,
	DuelId: string,
	Role: Role,
	AttackerUserId: number,
	AttackerSpawnPointId: string,
	DefenderUserId: number,
	TransitionDuration: number,
	RestoreToRegion: boolean,
}

export type Command = CameraCommand | RestoreCommand

export type ToggleRequest = {
	Kind: "ToggleDuelCamera",
	DuelId: string,
	Enabled: boolean,
}

export type TransitionCompletedRequest = {
	Kind: "DuelCameraTransitionCompleted",
	CommandId: number,
	DuelId: string,
	Role: "Attacker",
	AttackerUserId: number,
	AttackerSpawnPointId: string,
	DefenderUserId: number,
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

local function isValidRole(value): boolean
	return value == "Attacker" or value == "Defender"
end

local function isFiniteCFrame(value): boolean
	if typeof(value) ~= "CFrame" then
		return false
	end
	for _, component in { value:GetComponents() } do
		if not ValueValidation.IsFiniteNumber(component) then
			return false
		end
	end
	return true
end

local function validateCommon(command): (boolean, string?)
	if type(command) ~= "table" then
		return false, "InvalidCommand"
	end
	if not isPositiveInteger(command.CommandId) then
		return false, "InvalidCommandId"
	end
	if not ValueValidation.IsNonEmptyString(command.DuelId) then
		return false, "InvalidDuelId"
	end
	if not isValidRole(command.Role) then
		return false, "InvalidRole"
	end
	if not isNonZeroInteger(command.AttackerUserId) then
		return false, "InvalidAttackerUserId"
	end
	if not ValueValidation.IsNonEmptyString(command.AttackerSpawnPointId) then
		return false, "InvalidAttackerSpawnPointId"
	end
	if not isNonZeroInteger(command.DefenderUserId) then
		return false, "InvalidDefenderUserId"
	end
	if not ValueValidation.IsFiniteNumber(command.TransitionDuration)
		or command.TransitionDuration < 0
	then
		return false, "InvalidTransitionDuration"
	end
	return true, nil
end

function MonsterDuelCameraProtocol.ValidateCommand(command): (boolean, string?)
	local commonValid, commonReason = validateCommon(command)
	if not commonValid then
		return false, commonReason
	end

	if command.Kind == MonsterDuelCameraProtocol.AvailableKind
		or command.Kind == MonsterDuelCameraProtocol.FocusKind
	then
		if command.Kind == MonsterDuelCameraProtocol.AvailableKind
			and command.Role ~= "Defender"
		then
			return false, "AvailableMustTargetDefender"
		end
		if not isFiniteCFrame(command.CameraCFrame) then
			return false, "InvalidCameraCFrame"
		end
		if not ValueValidation.IsFiniteNumber(command.FieldOfView)
			or command.FieldOfView <= 0
			or command.FieldOfView >= 180
		then
			return false, "InvalidFieldOfView"
		end
		if not ValueValidation.IsFiniteNumber(command.RestoreDuration)
			or command.RestoreDuration < 0
		then
			return false, "InvalidRestoreDuration"
		end
		return true, nil
	end

	if command.Kind == MonsterDuelCameraProtocol.RestoreKind then
		if type(command.RestoreToRegion) ~= "boolean" then
			return false, "InvalidRestoreToRegion"
		end
		return true, nil
	end

	return false, "InvalidKind"
end

function MonsterDuelCameraProtocol.ValidateRequest(request): (boolean, string?)
	if type(request) ~= "table" then
		return false, "InvalidRequest"
	end
	if request.Kind == MonsterDuelCameraProtocol.ToggleKind then
		if not ValueValidation.IsNonEmptyString(request.DuelId) then
			return false, "InvalidDuelId"
		end
		if type(request.Enabled) ~= "boolean" then
			return false, "InvalidEnabled"
		end
		return true, nil
	end
	if request.Kind == MonsterDuelCameraProtocol.TransitionCompletedKind then
		if not isPositiveInteger(request.CommandId) then
			return false, "InvalidCommandId"
		end
		if not ValueValidation.IsNonEmptyString(request.DuelId) then
			return false, "InvalidDuelId"
		end
		if request.Role ~= "Attacker" then
			return false, "InvalidRole"
		end
		if not isNonZeroInteger(request.AttackerUserId) then
			return false, "InvalidAttackerUserId"
		end
		if not ValueValidation.IsNonEmptyString(request.AttackerSpawnPointId) then
			return false, "InvalidAttackerSpawnPointId"
		end
		if not isNonZeroInteger(request.DefenderUserId) then
			return false, "InvalidDefenderUserId"
		end
		return true, nil
	end
	return false, "InvalidKind"
end

return table.freeze(MonsterDuelCameraProtocol)
