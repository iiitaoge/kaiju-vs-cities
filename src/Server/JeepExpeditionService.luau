--[[
	职责：让已解锁 R3 的 Jeep 围绕 Workspace/Nests/Nest1 探险，并在结束时发放钻石。

	输入：
	- StartExpedition 接收在线 Player；由后续按钮、Prompt 或其他服务器入口调用。
	- GetStatus 接收 Player，返回当前探险倒计时快照。
	- Start 注册服务器 Heartbeat 和离服结算监听。

	输出：
	- StartExpedition 返回是否成功、失败原因、时长和奖励。
	- 探险完成后自动发放配置的钻石，并把 Jeep 放回 R3/Vehiclespawn。
	- 每个玩家独立维护一条探险记录，允许多个玩家同时探险。

	内部算法：服务器记录 StartedAt/EndsAt → 每帧按角度计算 Nest1 周围的目标 CFrame
	并移动 Jeep → 到达 EndsAt 后只结算一次奖励；玩家离服时立即完成当前探险并在持久化
	快照前写入钻石。

	不负责：探险触发器、UI、R3 解锁、Jeep 生成或跨服恢复探险进度。
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local DiamondService = require(script.Parent.DiamondService)
local JeepExpeditionConfigs = require(script.Parent.JeepExpeditionConfigs)
local JeepRuntimeService = require(script.Parent.JeepRuntimeService)

local JeepExpeditionService = {}

export type StartResult = {
	Succeeded: boolean,
	Reason: string?,
	DurationSeconds: number,
	RewardDiamonds: number,
}

export type Status = {
	Active: boolean,
	RemainingSeconds: number,
	DurationSeconds: number,
	RewardDiamonds: number,
}

type ExpeditionRecord = {
	Model: Model,
	Target: Model,
	HomeCFrame: CFrame,
	StartedAt: number,
	EndsAt: number,
	StartAngle: number,
	HeightOffset: number,
	AnchoredStates: { [BasePart]: boolean },
	CollisionStates: { [BasePart]: boolean },
}

local TAU = math.pi * 2
local TARGET_ROOT_NAME = "Nests"
local TARGET_NAME = "Nest1"

assert(
	type(JeepExpeditionConfigs.DurationSeconds) == "number"
		and JeepExpeditionConfigs.DurationSeconds > 0,
	"Jeep 探险时长必须是正数"
)
assert(
	type(JeepExpeditionConfigs.RewardDiamonds) == "number"
		and JeepExpeditionConfigs.RewardDiamonds >= 0,
	"Jeep 探险钻石奖励必须是非负数"
)
assert(
	type(JeepExpeditionConfigs.OrbitRadius) == "number"
		and JeepExpeditionConfigs.OrbitRadius > 0,
	"Jeep 绕圈半径必须是正数"
)

local activeByPlayer: { [Player]: ExpeditionRecord } = setmetatable({}, { __mode = "k" })
local started = false

local function startResult(
	succeeded: boolean,
	reason: string?,
	durationSeconds: number?,
	rewardDiamonds: number?
): StartResult
	return {
		Succeeded = succeeded,
		Reason = reason,
		DurationSeconds = durationSeconds or JeepExpeditionConfigs.DurationSeconds,
		RewardDiamonds = rewardDiamonds or JeepExpeditionConfigs.RewardDiamonds,
	}
end

local function getTarget(): (Model?, string?)
	local nests = workspace:FindFirstChild(TARGET_ROOT_NAME)
	if not nests then
		return nil, "NestRootUnavailable"
	end

	local target = nests:FindFirstChild(TARGET_NAME)
	if not target then
		return nil, "NestTargetUnavailable"
	end
	if not target:IsA("Model") then
		return nil, "NestTargetInvalid"
	end
	return target, nil
end

local function setExpeditionAttributes(model: Model, active: boolean, endsAt: number?)
	model:SetAttribute("JeepExpeditionActive", active)
	model:SetAttribute("JeepExpeditionEndsAt", endsAt)
	model:SetAttribute(
		"JeepExpeditionRewardDiamonds",
		if active then JeepExpeditionConfigs.RewardDiamonds else nil
	)
end

local function prepareModel(model: Model): ({ [BasePart]: boolean }, { [BasePart]: boolean })
	local anchoredStates = {}
	local collisionStates = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			anchoredStates[descendant] = descendant.Anchored
			collisionStates[descendant] = descendant.CanCollide
			descendant.Anchored = true
			descendant.CanCollide = false
		end
	end
	return anchoredStates, collisionStates
end

local function restoreModel(
	model: Model,
	anchoredStates: { [BasePart]: boolean },
	collisionStates: { [BasePart]: boolean }
)
	for part, anchored in anchoredStates do
		if part.Parent then
			part.Anchored = anchored
			part.CanCollide = collisionStates[part]
		end
	end
end

local function currentTime(): number
	return workspace:GetServerTimeNow()
end

local function getStartAngle(modelPosition: Vector3, targetPosition: Vector3): number
	local horizontal = modelPosition - targetPosition
	local magnitude = Vector3.new(horizontal.X, 0, horizontal.Z).Magnitude
	if magnitude <= 0.001 then
		return 0
	end
	return math.atan2(horizontal.Z, horizontal.X)
end

local function getOrbitCFrame(record: ExpeditionRecord, progress: number): CFrame
	local center = record.Target:GetPivot().Position
	local angle = record.StartAngle + progress * TAU
	local position = center + Vector3.new(
		math.cos(angle) * JeepExpeditionConfigs.OrbitRadius,
		record.HeightOffset,
		math.sin(angle) * JeepExpeditionConfigs.OrbitRadius
	)
	local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
	return CFrame.lookAt(position, position + tangent, Vector3.yAxis)
end

local function restoreHome(record: ExpeditionRecord)
	if not record.Model:IsDescendantOf(workspace) then
		return
	end
	record.Model:PivotTo(record.HomeCFrame)
	restoreModel(record.Model, record.AnchoredStates, record.CollisionStates)
end

local function settle(
	player: Player,
	record: ExpeditionRecord,
	grantReward: boolean
): number
	if activeByPlayer[player] ~= record then
		return 0
	end
	activeByPlayer[player] = nil
	setExpeditionAttributes(record.Model, false, nil)
	restoreHome(record)

	if not grantReward then
		return 0
	end
	DiamondService.Add(player, JeepExpeditionConfigs.RewardDiamonds)
	return JeepExpeditionConfigs.RewardDiamonds
end

local function updateRecord(player: Player, record: ExpeditionRecord, now: number)
	if activeByPlayer[player] ~= record then
		return
	end
	if not record.Model:IsDescendantOf(workspace) then
		settle(player, record, false)
		return
	end
	if not record.Target:IsDescendantOf(workspace) then
		settle(player, record, false)
		return
	end

	local progress = math.clamp(
		(now - record.StartedAt) / (record.EndsAt - record.StartedAt),
		0,
		1
	)
	record.Model:PivotTo(getOrbitCFrame(record, progress))
	if progress >= 1 then
		settle(player, record, true)
	end
end

function JeepExpeditionService.StartExpedition(player: Player): StartResult
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	if player.Parent ~= Players then
		return startResult(false, "PlayerUnavailable")
	end
	if activeByPlayer[player] then
		return startResult(false, "ExpeditionAlreadyActive")
	end

	local target, targetReason = getTarget()
	if not target then
		return startResult(false, targetReason or "NestTargetUnavailable")
	end

	local spawned = JeepRuntimeService.Spawn(player)
	if not spawned.Succeeded or not spawned.Model then
		return startResult(false, spawned.Reason or "JeepUnavailable")
	end

	local model = spawned.Model
	local homeCFrame = model:GetPivot()
	local targetPosition = target:GetPivot().Position
	local modelPosition = homeCFrame.Position
	local anchoredStates, collisionStates = prepareModel(model)
	local now = currentTime()
	local record: ExpeditionRecord = {
		Model = model,
		Target = target,
		HomeCFrame = homeCFrame,
		StartedAt = now,
		EndsAt = now + JeepExpeditionConfigs.DurationSeconds,
		StartAngle = getStartAngle(modelPosition, targetPosition),
		HeightOffset = modelPosition.Y - targetPosition.Y,
		AnchoredStates = anchoredStates,
		CollisionStates = collisionStates,
	}
	activeByPlayer[player] = record
	setExpeditionAttributes(model, true, record.EndsAt)
	model:PivotTo(getOrbitCFrame(record, 0))

	return startResult(true, nil)
end

function JeepExpeditionService.GetStatus(player: Player): Status
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	local record = activeByPlayer[player]
	if not record then
		return {
			Active = false,
			RemainingSeconds = 0,
			DurationSeconds = JeepExpeditionConfigs.DurationSeconds,
			RewardDiamonds = JeepExpeditionConfigs.RewardDiamonds,
		}
	end

	return {
		Active = true,
		RemainingSeconds = math.max(0, record.EndsAt - currentTime()),
		DurationSeconds = JeepExpeditionConfigs.DurationSeconds,
		RewardDiamonds = JeepExpeditionConfigs.RewardDiamonds,
	}
end

function JeepExpeditionService.Start()
	if started then
		return
	end
	started = true

	RunService.Heartbeat:Connect(function()
		local now = currentTime()
		for player, record in activeByPlayer do
			updateRecord(player, record, now)
		end
	end)

	-- 必须在 PlayerPersistenceCoordinator.Start() 之前注册，确保离服即时奖励进入最终快照。
	Players.PlayerRemoving:Connect(function(player)
		local record = activeByPlayer[player]
		if record then
			settle(player, record, true)
		end
	end)
end

return JeepExpeditionService
