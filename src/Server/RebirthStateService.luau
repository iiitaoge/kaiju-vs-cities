--[[
	职责：保存在线玩家的重生次数和本轮累计收入运行时状态。
	输入：player，以及要写入的有限非负次数/收入。
	输出：当前快照或写入后的字段值。
	内部算法：使用 PlayerStateService.Progression 分区的 Attributes 保存权威状态。
	不负责：计算倍率、判断资格、监听金钱变化、执行重生或读写 DataStore。
]]

local PlayerStateService = require(script.Parent.PlayerStateService)

local RebirthStateService = {}

export type Snapshot = {
	Count: number,
	RunEarnings: number,
}

local DEFAULT_COUNT = 0
local DEFAULT_RUN_EARNINGS = 0

local function assertFiniteNonNegative(value: number, name: string)
	assert(
		type(value) == "number"
			and value == value
			and value < math.huge
			and value >= 0,
		name .. " 必须是有限非负数"
	)
end

local function getSection(player: Player): Folder
	local section = PlayerStateService.GetSection(player, "Progression")
	if section:GetAttribute("RebirthCount") == nil then
		section:SetAttribute("RebirthCount", DEFAULT_COUNT)
	end
	if section:GetAttribute("RebirthRunEarnings") == nil then
		section:SetAttribute("RebirthRunEarnings", DEFAULT_RUN_EARNINGS)
	end
	return section
end

function RebirthStateService.Get(player: Player): Snapshot
	local section = getSection(player)
	return {
		Count = section:GetAttribute("RebirthCount") or DEFAULT_COUNT,
		RunEarnings = section:GetAttribute("RebirthRunEarnings") or DEFAULT_RUN_EARNINGS,
	}
end

function RebirthStateService.SetCount(player: Player, count: number): number
	assertFiniteNonNegative(count, "count")
	assert(count % 1 == 0, "count 必须是整数")
	getSection(player):SetAttribute("RebirthCount", count)
	return count
end

function RebirthStateService.SetRunEarnings(player: Player, amount: number): number
	assertFiniteNonNegative(amount, "amount")
	getSection(player):SetAttribute("RebirthRunEarnings", amount)
	return amount
end

function RebirthStateService.AddRunEarnings(player: Player, amount: number): number
	assertFiniteNonNegative(amount, "amount")
	return RebirthStateService.SetRunEarnings(
		player,
		RebirthStateService.Get(player).RunEarnings + amount
	)
end

function RebirthStateService.Restore(
	player: Player,
	count: number,
	runEarnings: number
): Snapshot
	RebirthStateService.SetCount(player, count)
	RebirthStateService.SetRunEarnings(player, runEarnings)
	return RebirthStateService.Get(player)
end

return RebirthStateService
