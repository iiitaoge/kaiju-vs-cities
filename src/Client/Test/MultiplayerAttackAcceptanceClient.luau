--[[
	职责：在 Studio 多客户端验收中调用正式攻击 Remote，并上报本客户端看到的建筑表现命令。
	输入：Run 接收测试服务器创建的控制 RemoteEvent。
	输出：通过控制通道返回目标查询证据、攻击响应和表现观察；返回可断开 Session。
	内部算法：按服务器场景令牌隔离观察记录；攻击前先走正式目标查询，再走正式攻击命令。
	不负责：准备玩家数据、直接调用服务器业务、修改怪兽/房屋状态或替代正式表现控制器。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterAttackRemoteClient = require(
	script.Parent.Parent.Monster.MonsterAttackRemoteClient
)
local MultiplayerAttackAcceptanceProtocol = require(
	ReplicatedStorage.Shared.Test.MultiplayerAttackAcceptanceProtocol
)

local MultiplayerAttackAcceptanceClient = {}

local function findTargetSnapshot(values, targetPlayerId: number)
	for _, value in values do
		if type(value) == "table" and value.TargetPlayerId == targetPlayerId then
			return value
		end
	end
	return nil
end

function MultiplayerAttackAcceptanceClient.Run(control: RemoteEvent)
	assert(control:IsA("RemoteEvent"), "control 必须是 RemoteEvent")
	local localPlayer = Players.LocalPlayer
	local activeScenarioId: string? = nil
	local connections = {}

	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
	assert(remotes and remotes:IsA("Folder"), "找不到 ReplicatedStorage/Remotes")
	local presentationRemote = remotes:WaitForChild("CityBuildingPresentation", 10)
	assert(
		presentationRemote and presentationRemote:IsA("RemoteEvent"),
		"找不到 CityBuildingPresentation"
	)

	table.insert(connections, presentationRemote.OnClientEvent:Connect(function(command)
		if not activeScenarioId or type(command) ~= "table" then
			return
		end
		control:FireServer({
			Kind = MultiplayerAttackAcceptanceProtocol.Kinds.PresentationObserved,
			ScenarioId = activeScenarioId,
			CommandKind = command.Kind,
			OwnerUserId = command.OwnerUserId,
			RegionId = command.RegionId,
			HouseId = command.HouseId,
			Level = command.Level,
		})
	end))

	table.insert(connections, control.OnClientEvent:Connect(function(message)
		if type(message) ~= "table" then
			return
		end

		if message.Kind == MultiplayerAttackAcceptanceProtocol.Kinds.BeginScenario then
			activeScenarioId = message.ScenarioId
			control:FireServer({
				Kind = MultiplayerAttackAcceptanceProtocol.Kinds.ScenarioReady,
				ScenarioId = activeScenarioId,
			})
			return
		end

		if message.Kind == MultiplayerAttackAcceptanceProtocol.Kinds.RequestAttack then
			local targetPlayer = Players:GetPlayerByUserId(message.TargetPlayerId)
			local query = MonsterAttackRemoteClient.QueryTargets()
			local targetSnapshot = if query.Succeeded
				then findTargetSnapshot(query.Targets, message.TargetPlayerId)
				else nil
			local response = if targetPlayer and targetSnapshot
				then MonsterAttackRemoteClient.RequestAttack(
					message.SpawnPointId,
					targetPlayer,
					message.EntryPoint
				)
				else {
					Succeeded = false,
					Reason = if not targetPlayer then "TargetPlayerUnavailable" else "TargetMissingFromQuery",
					CommandId = nil,
					Monster = nil,
				}

			control:FireServer({
				Kind = MultiplayerAttackAcceptanceProtocol.Kinds.AttackResponse,
				ScenarioId = message.ScenarioId,
				RequestId = message.RequestId,
				QuerySucceeded = query.Succeeded,
				QuerySawTarget = targetSnapshot ~= nil,
				Succeeded = response.Succeeded,
				Reason = response.Reason,
				CommandId = response.CommandId,
				HasMonster = response.Monster ~= nil,
			})
			return
		end

		if message.Kind == MultiplayerAttackAcceptanceProtocol.Kinds.EvidenceAccepted then
			print(string.format(
				"CODEX_MULTIPLAYER_ATTACK_CLIENT_PRESENTATION_OK %s %s",
				localPlayer.Name,
				tostring(message.Checkpoint)
			))
			return
		end

		if message.Kind == MultiplayerAttackAcceptanceProtocol.Kinds.AcceptanceFinished then
			print("CODEX_MULTIPLAYER_ATTACK_CLIENT_E2E_OK " .. localPlayer.Name)
		end
	end))

	control:FireServer({
		Kind = MultiplayerAttackAcceptanceProtocol.Kinds.ClientReady,
	})

	return {
		Disconnect = function()
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
		end,
	}
end

return MultiplayerAttackAcceptanceClient
