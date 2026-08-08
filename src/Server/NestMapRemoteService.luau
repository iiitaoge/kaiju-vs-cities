--[[
	职责：把巢穴 Map 的查询、载具派遣和召回请求适配为稳定 RemoteFunction。
	输入：GetState 无参数；Dispatch 接收 VehicleInstanceId、NestId；Recall 接收 VehicleInstanceId。
	输出：当前九个 Nest 状态，以及 VehicleDispatchService 的动作结果。
	内部算法：Ready 校验 → 调用既有派遣领域服务 → 返回按当前玩家标记的 OwnVehicle 状态。
	不负责：占用、战斗、奖励、载具拥有关系或 UI 表现。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NestCatalog = require(ReplicatedStorage.Shared.Nest.NestCatalog)
local NestMapProtocol = require(ReplicatedStorage.Shared.Nest.NestMapProtocol)
local PlayerDataReadyService = require(script.Parent.PlayerDataReadyService)
local ServerRemoteAccess = require(script.Parent.ServerRemoteAccess)
local VehicleDispatchService = require(script.Parent.VehicleDispatchService)
local VehicleFleetService = require(script.Parent.VehicleFleetService)

local NestMapRemoteService = {}

local actionBusy: { [Player]: boolean } = setmetatable({}, { __mode = "k" })
local started = false

local function assertPlayer(player: Player)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
end

local function isReady(player: Player): (boolean, string?)
	local readiness = PlayerDataReadyService.Get(player)
	if readiness.Status == "Unmanaged" then
		return true, nil
	end
	if readiness.Status ~= "Ready" or not readiness.CanSave then
		return false, "PlayerDataNotReady"
	end
	return true, nil
end

local function getOwnVehicle(player: Player, nestId: string)
	for _, vehicle in VehicleFleetService.List(player) do
		local status = VehicleDispatchService.GetStatus(player, vehicle.InstanceId)
		if status.Active and status.NestId == nestId then
			return {
				VehicleInstanceId = status.VehicleInstanceId,
				State = status.State,
				CanRecall = status.State ~= "Battle",
			}
		end
	end
	return nil
end

local function getState(player: Player)
	local nests = {}
	for _, definition in NestCatalog.GetAll() do
		local status = VehicleDispatchService.GetNestStatus(definition.NestId)
		status.Name = definition.Name
		status.BaseIntervalSeconds = definition.BaseIntervalSeconds
		status.BaseDiamonds = definition.BaseDiamonds
		status.OwnVehicle = getOwnVehicle(player, definition.NestId)
		table.insert(nests, status)
	end
	return { Nests = nests }
end

local function response(
	player: Player,
	succeeded: boolean,
	reason: string?,
	action
)
	return {
		Succeeded = succeeded,
		Reason = reason,
		Action = action,
		State = getState(player),
	}
end

local function onRequest(player: Player, requestKind, value1, value2)
	assertPlayer(player)
	if player.Parent ~= Players then
		return { Succeeded = false, Reason = "PlayerUnavailable", State = nil }
	end

	local ready, readyReason = isReady(player)
	if not ready then
		return { Succeeded = false, Reason = readyReason, State = nil }
	end
	if requestKind == NestMapProtocol.RequestKinds.GetState then
		return response(player, true, nil, nil)
	end
	if requestKind ~= NestMapProtocol.RequestKinds.Dispatch
		and requestKind ~= NestMapProtocol.RequestKinds.Recall
	then
		return response(player, false, "InvalidRequestKind", nil)
	end
	if type(value1) ~= "string" or value1 == "" then
		return response(player, false, "InvalidVehicleInstanceId", nil)
	end
	if requestKind == NestMapProtocol.RequestKinds.Dispatch
		and (type(value2) ~= "string" or value2 == "")
	then
		return response(player, false, "InvalidNestId", nil)
	end
	if actionBusy[player] then
		return response(player, false, "ActionBusy", nil)
	end
	actionBusy[player] = true

	local succeeded, actionOrError = xpcall(function()
		if requestKind == NestMapProtocol.RequestKinds.Dispatch then
			return VehicleDispatchService.Dispatch(player, value1, value2)
		end
		return VehicleDispatchService.Recall(player, value1)
	end, debug.traceback)
	actionBusy[player] = nil

	if not succeeded then
		warn(string.format(
			"巢穴 Map 请求异常：%s/%s (%s)",
			player.Name,
			tostring(requestKind),
			tostring(actionOrError)
		))
		return response(player, false, "ServerError", nil)
	end
	return response(player, actionOrError.Succeeded, actionOrError.Reason, actionOrError)
end

function NestMapRemoteService.Start()
	if started then
		return
	end
	started = true

	local remote = ServerRemoteAccess.EnsureFunction(NestMapProtocol.RemoteName)
	remote.OnServerInvoke = onRequest
	Players.PlayerRemoving:Connect(function(player)
		actionBusy[player] = nil
	end)
end

return NestMapRemoteService
