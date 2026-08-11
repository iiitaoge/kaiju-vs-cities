--[[
	职责：把服务器任务状态转换成 LeftTask 单卡片快照，并通过 Remote 提供初始状态和实时更新。
	输入：客户端 GetState 请求，以及服务器内部 TaskEventBus 业务事实。
	输出：Visible、Text、Current/Target、RewardKind/RewardAmount；无任务时返回隐藏快照。
	内部算法：等待玩家存档就绪 → 同步已在历史状态中完成的区域任务 → 按任务 Order 选择首个未完成任务
	→ 使用纯 TaskPresentationRules 生成快照 → RemoteEvent 推送。
	不负责：计算区域解锁权限、发放奖励、修改任务状态或操作 UI Instance。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataReadyService = require(script.Parent.PlayerDataReadyService)
local ServerRemoteAccess = require(script.Parent.ServerRemoteAccess)
local TaskEventBus = require(script.Parent.TaskEventBus)
local TaskService = require(script.Parent.TaskService)
local TaskStateService = require(script.Parent.TaskStateService)
local TaskConfigs = require(ReplicatedStorage.Shared.Task.TaskConfigs)
local TaskPresentationProtocol = require(
	ReplicatedStorage.Shared.Task.TaskPresentationProtocol
)
local TaskPresentationRules = require(
	ReplicatedStorage.Shared.Task.TaskPresentationRules
)
local ZoneCatalog = require(ReplicatedStorage.Shared.World.ZoneCatalog)
local ZoneStateService = require(script.Parent.ZoneStateService)

local TaskPresentationService = {}

local started = false
local presentationRemote: RemoteEvent? = nil
local queryRemote: RemoteFunction? = nil
local lastSnapshots: { [Player]: TaskPresentationProtocol.Snapshot } = setmetatable(
	{},
	{ __mode = "k" }
)

local function getPresentationRemote(): RemoteEvent
	if presentationRemote and presentationRemote.Parent then
		return presentationRemote
	end
	presentationRemote = ServerRemoteAccess.EnsureEvent(
		TaskPresentationProtocol.RemoteName
	)
	return presentationRemote
end

local function getQueryRemote(): RemoteFunction
	if queryRemote and queryRemote.Parent then
		return queryRemote
	end
	queryRemote = ServerRemoteAccess.EnsureFunction(
		TaskPresentationProtocol.QueryRemoteName
	)
	return queryRemote
end

local function canRead(player: Player): (boolean, string?)
	local readiness = PlayerDataReadyService.Get(player)
	if readiness.Status == "Unmanaged" then
		return true, nil
	end
	if readiness.Status ~= "Ready" then
		return false, "PlayerDataNotReady"
	end
	return true, nil
end

local function getZoneStates(player: Player)
	local states = {}
	for _, definition in ZoneCatalog.GetAll() do
		states[definition.ZoneId] = ZoneStateService.Get(player, definition.ZoneId)
	end
	return states
end

local function buildSnapshot(player: Player): TaskPresentationProtocol.Snapshot
	return TaskPresentationRules.Build(
		TaskConfigs,
		TaskStateService.GetAll(player),
		getZoneStates(player)
	)
end

local function sameSnapshot(
	left: TaskPresentationProtocol.Snapshot?,
	right: TaskPresentationProtocol.Snapshot
): boolean
	if not left then
		return false
	end
	return left.Visible == right.Visible
		and left.TaskId == right.TaskId
		and left.Text == right.Text
		and left.Current == right.Current
		and left.Target == right.Target
		and left.RewardKind == right.RewardKind
		and left.RewardAmount == right.RewardAmount
end

local function publish(player: Player): boolean
	if player.Parent ~= Players then
		return false
	end

	local snapshot = buildSnapshot(player)
	local valid, reason = TaskPresentationProtocol.Validate(snapshot)
	if not valid then
		warn("任务卡片快照无效：" .. tostring(reason))
		return false
	end
	if sameSnapshot(lastSnapshots[player], snapshot) then
		return true
	end

	local succeeded, publishError = pcall(function()
		getPresentationRemote():FireClient(player, snapshot)
	end)
	if not succeeded then
		warn("任务卡片快照推送失败：", publishError)
		return false
	end
	lastSnapshots[player] = snapshot
	return true
end

local function reconcileAndPublish(player: Player)
	local ready = PlayerDataReadyService.Wait(player)
	if not ready or player.Parent ~= Players then
		return
	end
	TaskService.Reconcile(player)
	publish(player)
end

local function onRequest(player: Player, requestKind)
	if requestKind ~= TaskPresentationProtocol.RequestKinds.GetState then
		return {
			Succeeded = false,
			Reason = "InvalidRequestKind",
			Snapshot = nil,
		}
	end

	local ready, reason = canRead(player)
	if not ready then
		return {
			Succeeded = false,
			Reason = reason,
			Snapshot = nil,
		}
	end

	TaskService.Reconcile(player)
	local snapshot = buildSnapshot(player)
	lastSnapshots[player] = snapshot
	return {
		Succeeded = true,
		Reason = nil,
		Snapshot = snapshot,
	}
end

local function watchPlayer(player: Player)
	task.spawn(function()
		reconcileAndPublish(player)
	end)
end

function TaskPresentationService.Start()
	if started then
		return
	end
	started = true

	getPresentationRemote()
	getQueryRemote().OnServerInvoke = onRequest
	TaskEventBus.Connect(function(player: Player)
		-- TaskService 的监听器先注册，因此此处读取到的是更新后的任务状态。
		publish(player)
	end)

	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(player)
		lastSnapshots[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
end

return table.freeze(TaskPresentationService)
