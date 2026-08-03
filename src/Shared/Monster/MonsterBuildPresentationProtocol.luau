--[[
	职责：定义并验证培养罐/怪兽建造表现命令的稳定外形。
	输入：任意 command。
	输出：是否合法及稳定失败原因。
	内部算法：验证公共身份，并按 Kind 验证怪兽模板身份。
	不负责：读取配置、Instance、播放动画或等待表现。
]]

local MonsterBuildPresentationProtocol = {}

export type IncubatorBuildCommand = {
	Kind: "IncubatorBuild",
	OwnerUserId: number,
	SpawnPointId: string,
	PresentationId: string,
}

export type MonsterBuildCommand = {
	Kind: "MonsterBuild",
	OwnerUserId: number,
	SpawnPointId: string,
	PresentationId: string,
	MonsterKey: string,
}

export type MonsterUpgradeCommand = {
	Kind: "MonsterUpgrade",
	OwnerUserId: number,
	SpawnPointId: string,
	PresentationId: string,
	PreviousMonsterKey: string,
	MonsterKey: string,
}

export type Command = IncubatorBuildCommand | MonsterBuildCommand | MonsterUpgradeCommand

local function isNonEmptyString(value): boolean
	return type(value) == "string" and value ~= ""
end

local function isNonZeroInteger(value): boolean
	return type(value) == "number"
		and value == value
		and value < math.huge
		and value > -math.huge
		and value % 1 == 0
		and value ~= 0
end

function MonsterBuildPresentationProtocol.Validate(command): (boolean, string?)
	if type(command) ~= "table" then
		return false, "InvalidCommand"
	end
	if not isNonZeroInteger(command.OwnerUserId) then
		return false, "InvalidOwnerUserId"
	end
	if not isNonEmptyString(command.SpawnPointId) then
		return false, "InvalidSpawnPointId"
	end
	if not isNonEmptyString(command.PresentationId) then
		return false, "InvalidPresentationId"
	end

	if command.Kind == "IncubatorBuild" then
		return true, nil
	end
	if command.Kind == "MonsterBuild" then
		if not isNonEmptyString(command.MonsterKey) then
			return false, "InvalidMonsterKey"
		end
		return true, nil
	end
	if command.Kind == "MonsterUpgrade" then
		if not isNonEmptyString(command.PreviousMonsterKey) then
			return false, "InvalidPreviousMonsterKey"
		end
		if not isNonEmptyString(command.MonsterKey) then
			return false, "InvalidMonsterKey"
		end
		if command.PreviousMonsterKey == command.MonsterKey then
			return false, "MonsterKeyUnchanged"
		end
		return true, nil
	end
	return false, "InvalidKind"
end

return MonsterBuildPresentationProtocol
