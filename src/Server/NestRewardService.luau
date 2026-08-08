--[[
	职责：为当前驻留载具按 Nest 配置定时发放钻石。
	输入：Begin 接收占用 ID、Player、Nest 基础产出和载具倍率；End 结算并结束占用。
	输出：每次结算的钻石数量；GetStatus 返回占用快照。
	内部算法：Heartbeat 检查已完成的基础周期 → 按基础钻石 × 载具倍率向下取整 → 写入 DiamondService。
	不负责：Nest 占用、载具派遣、战斗或 UI。
]]

local RunService = game:GetService("RunService")

local DiamondService = require(script.Parent.DiamondService)
local NestRewardRules = require(
	game:GetService("ReplicatedStorage").Shared.Nest.NestRewardRules
)

local NestRewardService = {}

export type RewardStatus = {
	Active: boolean,
	OccupationId: string,
	Player: Player,
	NestId: string,
	StartedAt: number,
	LastSettledAt: number,
	NextSettlementAt: number,
	BaseIntervalSeconds: number,
	BaseDiamonds: number,
	DiamondMultiplier: number,
}

type Occupation = RewardStatus

local occupations: { [string]: Occupation } = {}
local started = false

local function now(): number
	return workspace:GetServerTimeNow()
end

local function assertPlayer(player: Player)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
end

local function settle(occupation: Occupation, currentTime: number): number
	local elapsed = math.max(0, currentTime - occupation.LastSettledAt)
	local completedIntervals = math.floor(elapsed / occupation.BaseIntervalSeconds)
	if completedIntervals <= 0 then
		return 0
	end

	local amount = NestRewardRules.CalculatePayout(
		occupation.BaseDiamonds,
		occupation.DiamondMultiplier,
		completedIntervals
	)
	if amount > 0 then
		DiamondService.Add(occupation.Player, amount)
	end
	occupation.LastSettledAt += completedIntervals * occupation.BaseIntervalSeconds
	return amount
end

function NestRewardService.Begin(
	occupationId: string,
	player: Player,
	nestId: string,
	baseIntervalSeconds: number,
	baseDiamonds: number,
	diamondMultiplier: number,
	startedAt: number?
): (boolean, string?)
	assert(type(occupationId) == "string" and occupationId ~= "", "occupationId 无效")
	assertPlayer(player)
	assert(
		type(baseIntervalSeconds) == "number"
			and baseIntervalSeconds == baseIntervalSeconds
			and baseIntervalSeconds < math.huge
			and baseIntervalSeconds > 0,
		"baseIntervalSeconds 必须是有限正数"
	)
	assert(type(baseDiamonds) == "number" and baseDiamonds >= 0, "baseDiamonds 无效")
	assert(
		type(diamondMultiplier) == "number"
			and diamondMultiplier == diamondMultiplier
			and diamondMultiplier < math.huge
			and diamondMultiplier > 0,
		"diamondMultiplier 必须是有限正数"
	)
	if occupations[occupationId] then
		return false, "OccupationAlreadyActive"
	end

	local beginAt = startedAt or now()
	occupations[occupationId] = {
		Active = true,
		OccupationId = occupationId,
		Player = player,
		NestId = nestId,
		StartedAt = beginAt,
		LastSettledAt = beginAt,
		NextSettlementAt = beginAt + baseIntervalSeconds,
		BaseIntervalSeconds = baseIntervalSeconds,
		BaseDiamonds = baseDiamonds,
		DiamondMultiplier = diamondMultiplier,
	}
	return true, nil
end

function NestRewardService.End(occupationId: string, endedAt: number?): number
	local occupation = occupations[occupationId]
	if not occupation then
		return 0
	end
	local amount = settle(occupation, endedAt or now())
	occupations[occupationId] = nil
	return amount
end

function NestRewardService.GetStatus(occupationId: string): RewardStatus?
	return occupations[occupationId]
end

function NestRewardService.EndPlayer(player: Player, endedAt: number?): number
	assertPlayer(player)
	local ids = {}
	for occupationId, occupation in occupations do
		if occupation.Player == player then
			table.insert(ids, occupationId)
		end
	end
	local total = 0
	for _, occupationId in ids do
		total += NestRewardService.End(occupationId, endedAt)
	end
	return total
end

function NestRewardService.Start()
	if started then
		return
	end
	started = true
	RunService.Heartbeat:Connect(function()
		local currentTime = now()
		for _, occupation in occupations do
			settle(occupation, currentTime)
		end
	end)
end

return NestRewardService
