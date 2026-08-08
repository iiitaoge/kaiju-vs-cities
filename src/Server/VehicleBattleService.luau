--[[
	职责：按固定攻击间隔运行一场载具攻防战。
	输入：Begin 接收防守方、攻击方和结束回调；CancelForPlayer 处理玩家离服。
	输出：战斗结束时回调 Defender 或 Attacker 胜者，以及双方当前生命值。
	内部算法：默认每 10 秒双方同时攻击一次；同时归零时防守方获胜。
	不负责：Nest 队列、胜者归位、奖励或 UI。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local VehicleBattleConfigs = require(
	ReplicatedStorage.Shared.Vehicle.VehicleBattleConfigs
)
local VehicleBattleRules = require(ReplicatedStorage.Shared.Vehicle.VehicleBattleRules)

local VehicleBattleService = {}

export type Combatant = {
	Player: Player,
	VehicleInstanceId: string,
	MaxHealth: number,
	Health: number,
	Attack: number,
	Model: Model?,
}

export type BattleResult = {
	BattleId: string,
	Outcome: "Defender" | "Attacker",
	Reason: string?,
	Defender: Combatant,
	Attacker: Combatant,
}

export type BeginResult = {
	Succeeded: boolean,
	Reason: string?,
	BattleId: string?,
}

type Battle = {
	BattleId: string,
	Defender: Combatant,
	Attacker: Combatant,
	NextRoundAt: number,
	OnResolved: (BattleResult) -> (),
}

assert(
	type(VehicleBattleConfigs.AttackIntervalSeconds) == "number"
		and VehicleBattleConfigs.AttackIntervalSeconds > 0,
	"载具攻击间隔必须是正数"
)

local activeById: { [string]: Battle } = {}
local started = false
local nextBattleSerial = 0

local function now(): number
	return workspace:GetServerTimeNow()
end

local function assertCombatant(combatant: Combatant)
	assert(type(combatant) == "table", "combatant 必须是 table")
	assert(
		type(combatant.VehicleInstanceId) == "string"
			and combatant.VehicleInstanceId ~= "",
		"VehicleInstanceId 无效"
	)
	assert(typeof(combatant.Player) == "Instance" and combatant.Player:IsA("Player"), "Player 无效")
	assert(type(combatant.MaxHealth) == "number" and combatant.MaxHealth > 0, "MaxHealth 无效")
	assert(type(combatant.Health) == "number" and combatant.Health > 0, "Health 无效")
	assert(type(combatant.Attack) == "number" and combatant.Attack > 0, "Attack 无效")
end

local function syncHealth(combatant: Combatant)
	if combatant.Model and combatant.Model.Parent then
		combatant.Model:SetAttribute("VehicleHealth", combatant.Health)
	end
end

local function finish(battleId: string, outcome: "Defender" | "Attacker", reason: string?)
	local battle = activeById[battleId]
	if not battle then
		return
	end
	activeById[battleId] = nil
	local ok, errorMessage = xpcall(function()
		battle.OnResolved({
			BattleId = battle.BattleId,
			Outcome = outcome,
			Reason = reason,
			Defender = battle.Defender,
			Attacker = battle.Attacker,
		})
	end, debug.traceback)
	if not ok then
		warn(string.format("载具战斗结算回调异常：%s", tostring(errorMessage)))
	end
end

function VehicleBattleService.Begin(
	defender: Combatant,
	attacker: Combatant,
	onResolved: (BattleResult) -> ()
): BeginResult
	assertCombatant(defender)
	assertCombatant(attacker)
	assert(type(onResolved) == "function", "onResolved 必须是 function")
	if defender == attacker then
		return { Succeeded = false, Reason = "SameCombatant", BattleId = nil }
	end
	for _, battle in activeById do
		if battle.Defender == defender
			or battle.Attacker == defender
			or battle.Defender == attacker
			or battle.Attacker == attacker
		then
			return { Succeeded = false, Reason = "CombatantBusy", BattleId = nil }
		end
	end

	nextBattleSerial += 1
	local battleId = string.format("Battle%d", nextBattleSerial)
	defender.Health = defender.MaxHealth
	attacker.Health = attacker.MaxHealth
	syncHealth(defender)
	syncHealth(attacker)
	activeById[battleId] = {
		BattleId = battleId,
		Defender = defender,
		Attacker = attacker,
		NextRoundAt = now() + VehicleBattleConfigs.AttackIntervalSeconds,
		OnResolved = onResolved,
	}
	return { Succeeded = true, Reason = nil, BattleId = battleId }
end

function VehicleBattleService.CancelForPlayer(player: Player)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	local cancellations = {}
	for battleId, battle in activeById do
		if battle.Defender.Player == player then
			table.insert(cancellations, { BattleId = battleId, Outcome = "Attacker" })
		elseif battle.Attacker.Player == player then
			table.insert(cancellations, { BattleId = battleId, Outcome = "Defender" })
		end
	end
	for _, cancellation in cancellations do
		finish(cancellation.BattleId, cancellation.Outcome, "PlayerLeft")
	end
end

function VehicleBattleService.IsBusy(combatant: Combatant): boolean
	for _, battle in activeById do
		if battle.Defender == combatant or battle.Attacker == combatant then
			return true
		end
	end
	return false
end

function VehicleBattleService.Start()
	if started then
		return
	end
	started = true
	RunService.Heartbeat:Connect(function()
		local currentTime = now()
		local rounds = {}
		for battleId, battle in activeById do
			if battle.Defender.Player.Parent ~= Players then
				finish(battleId, "Attacker", "PlayerLeft")
			elseif battle.Attacker.Player.Parent ~= Players then
				finish(battleId, "Defender", "PlayerLeft")
			elseif currentTime >= battle.NextRoundAt then
				table.insert(rounds, battleId)
			end
		end

		for _, battleId in rounds do
			local battle = activeById[battleId]
			if battle then
				local round = VehicleBattleRules.ResolveRound(
					battle.Defender.Health,
					battle.Defender.Attack,
					battle.Attacker.Health,
					battle.Attacker.Attack
				)
				battle.Defender.Health = round.DefenderHealth
				battle.Attacker.Health = round.AttackerHealth
				syncHealth(battle.Defender)
				syncHealth(battle.Attacker)
				if round.Outcome == "Continue" then
					battle.NextRoundAt = currentTime + VehicleBattleConfigs.AttackIntervalSeconds
				else
					finish(battleId, round.Outcome, nil)
				end
			end
		end
	end)
end

return VehicleBattleService
