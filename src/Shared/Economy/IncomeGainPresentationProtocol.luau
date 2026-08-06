--[[
	职责：定义并验证已入账房屋收入的客户端表现命令。
	输入：任意 command；合法命令包含收入来源 Kind 和逐栋正数收入 Entries。
	输出：是否合法及稳定失败原因。
	内部算法：验证 Kind、非空顺序数组、HouseId、金额，并拒绝重复房屋。
	不负责：计算或发放收入、查找运行时房屋、创建 UI 或播放动画。
]]

local ValueValidation = require(script.Parent.Parent.ValueValidation)

local IncomeGainPresentationProtocol = {}

IncomeGainPresentationProtocol.RemoteName = "IncomeGainPresentation"
IncomeGainPresentationProtocol.Kinds = table.freeze({
	Automatic = "Automatic",
	Touch = "Touch",
})

export type Entry = {
	HouseId: string,
	Amount: number,
}

export type Command = {
	Kind: "Automatic" | "Touch",
	Entries: { Entry },
}

function IncomeGainPresentationProtocol.Validate(command): (boolean, string?)
	if type(command) ~= "table" then
		return false, "InvalidCommand"
	end
	if command.Kind ~= IncomeGainPresentationProtocol.Kinds.Automatic
		and command.Kind ~= IncomeGainPresentationProtocol.Kinds.Touch
	then
		return false, "InvalidKind"
	end
	if type(command.Entries) ~= "table" or #command.Entries == 0 then
		return false, "InvalidEntries"
	end
	if command.Kind == IncomeGainPresentationProtocol.Kinds.Touch
		and #command.Entries ~= 1
	then
		return false, "InvalidTouchEntryCount"
	end

	local seenHouseIds = {}
	local entryCount = 0
	for index, entry in command.Entries do
		entryCount += 1
		if type(index) ~= "number" or index % 1 ~= 0
			or index < 1 or index > #command.Entries
		then
			return false, "InvalidEntryIndex"
		end
		if type(entry) ~= "table" then
			return false, "InvalidEntry"
		end
		if not ValueValidation.IsNonEmptyString(entry.HouseId) then
			return false, "InvalidHouseId"
		end
		if seenHouseIds[entry.HouseId] then
			return false, "DuplicateHouseId"
		end
		seenHouseIds[entry.HouseId] = true
		if not ValueValidation.IsFiniteNumber(entry.Amount) or entry.Amount <= 0 then
			return false, "InvalidAmount"
		end
	end
	if entryCount ~= #command.Entries then
		return false, "InvalidEntries"
	end

	return true, nil
end

return table.freeze(IncomeGainPresentationProtocol)
