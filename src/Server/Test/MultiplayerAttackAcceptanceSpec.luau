--[[
	职责：验收正式多人攻击 Remote 到房屋自动重建的完整服务器链路。
	输入：Run 接收三名在线 Studio 测试玩家；前两名为攻击者，第三名为防守者。
	输出：四个场景的状态轨迹摘要；全部约束满足时返回 Report。
	内部算法：准备一栋正式房屋和两只正式怪兽，通过客户端调用正式攻击 Remote，依次覆盖
		正常出征、同目标并发、摧毁等待期间正式区域升级、重建期间防守玩家离服。
	不负责：修改正式数值、伪造攻击提交、增加出生点、连接 UI 或验证动画像素效果。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HouseLifecycleConfigs = require(script.Parent.Parent.HouseLifecycleConfigs)
local HouseStateService = require(script.Parent.Parent.HouseStateService)
local HouseTargetReservationService = require(
	script.Parent.Parent.HouseTargetReservationService
)
local MoneyService = require(script.Parent.Parent.MoneyService)
local MonsterRosterCoordinator = require(script.Parent.Parent.MonsterRosterCoordinator)
local MonsterSpawnPointStateService = require(
	script.Parent.Parent.MonsterSpawnPointStateService
)
local PlayerCityRuntimeCoordinator = require(
	script.Parent.Parent.PlayerCityRuntimeCoordinator
)
local PlayerMonsterRuntimeCoordinator = require(
	script.Parent.Parent.PlayerMonsterRuntimeCoordinator
)
local PlayerPlotAssignmentService = require(
	script.Parent.Parent.PlayerPlotAssignmentService
)
local PlayerRuntimeHouseAttackAccess = require(
	script.Parent.Parent.PlayerRuntimeHouseAttackAccess
)
local RegionEconomyConfigs = require(script.Parent.Parent.RegionEconomyConfigs)
local RegionUpgradeCityCoordinator = require(
	script.Parent.Parent.RegionUpgradeCityCoordinator
)
local ZoneStateService = require(script.Parent.Parent.ZoneStateService)
local BuildingPresentationConfigs = require(
	ReplicatedStorage.Shared.Building.BuildingPresentationConfigs
)
local MultiplayerAttackAcceptanceProtocol = require(
	ReplicatedStorage.Shared.Test.MultiplayerAttackAcceptanceProtocol
)

local MultiplayerAttackAcceptanceSpec = {}

local PLAYER_COUNT = 3
local SPAWN_POINT_ID = "M1-S1"
local MONSTER_ZONE_ID = "M1"
local HOUSE_ID = "R1-H1"
local HOUSE_ZONE_ID = "R1"
local REQUEST_TIMEOUT = 15
local MOVEMENT_TIMEOUT = 90
local REBUILD_TIMEOUT = HouseLifecycleConfigs.Default.RebuildDelaySeconds + 15

local function expect(condition: boolean, message: string)
	assert(condition, "MultiplayerAttackAcceptanceSpec: " .. message)
end

local function waitFor(predicate: () -> boolean, timeout: number, message: string)
	local deadline = os.clock() + timeout
	repeat
		if predicate() then
			return
		end
		task.wait(0.05)
	until os.clock() >= deadline
	error("MultiplayerAttackAcceptanceSpec: 等待超时：" .. message)
end

local function sortedPlayers(players: { Player }): { Player }
	local result = table.clone(players)
	table.sort(result, function(a, b)
		return a.UserId < b.UserId
	end)
	return result
end

local function ensureControlRemote(): RemoteEvent
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage
	end
	expect(remotes:IsA("Folder"), "ReplicatedStorage.Remotes 必须是 Folder")
	local existing = remotes:FindFirstChild(MultiplayerAttackAcceptanceProtocol.RemoteName)
	if existing then
		expect(existing:IsA("RemoteEvent"), "验收控制通道类型错误")
		return existing
	end
	local remote = Instance.new("RemoteEvent")
	remote.Name = MultiplayerAttackAcceptanceProtocol.RemoteName
	remote.Parent = remotes
	return remote
end

local function runtimeIsEmpty(plot: Model): boolean
	local runtime = plot:FindFirstChild("Runtime")
	return runtime ~= nil and #runtime:GetChildren() == 0
end

function MultiplayerAttackAcceptanceSpec.Run(players: { Player })
	expect(type(players) == "table" and #players == PLAYER_COUNT, "必须传入三名测试玩家")
	local ordered = sortedPlayers(players)
	local attackerA = ordered[1]
	local attackerB = ordered[2]
	local defender = ordered[3]
	for _, player in ordered do
		expect(player.Parent == Players, "所有测试玩家必须在线")
	end

	local control = ensureControlRemote()
	local clientStates = {}
	for _, player in ordered do
		clientStates[player] = {
			Ready = false,
			ScenarioReady = nil,
			Responses = {},
			Observations = {},
		}
	end
	local activeScenarioId: string? = nil
	local nextRequestId = 0

	local connection = control.OnServerEvent:Connect(function(player, message)
		local state = clientStates[player]
		if not state or type(message) ~= "table" then
			return
		end
		if message.Kind == MultiplayerAttackAcceptanceProtocol.Kinds.ClientReady then
			state.Ready = true
			return
		end
		if message.Kind == MultiplayerAttackAcceptanceProtocol.Kinds.ScenarioReady
			and message.ScenarioId == activeScenarioId then
			state.ScenarioReady = message.ScenarioId
			return
		end
		if message.Kind == MultiplayerAttackAcceptanceProtocol.Kinds.AttackResponse
			and message.ScenarioId == activeScenarioId
			and type(message.RequestId) == "number" then
			state.Responses[message.RequestId] = message
			return
		end
		if message.Kind == MultiplayerAttackAcceptanceProtocol.Kinds.PresentationObserved
			and message.ScenarioId == activeScenarioId then
			local observations = state.Observations
			table.insert(observations, message)
		end
	end)

	local function allClients(predicate): boolean
		for _, player in ordered do
			if player.Parent == Players and not predicate(clientStates[player], player) then
				return false
			end
		end
		return true
	end

	local function beginScenario(scenarioId: string)
		activeScenarioId = scenarioId
		for _, player in ordered do
			local state = clientStates[player]
			state.ScenarioReady = nil
			table.clear(state.Responses)
			table.clear(state.Observations)
			if player.Parent == Players then
				control:FireClient(player, {
					Kind = MultiplayerAttackAcceptanceProtocol.Kinds.BeginScenario,
					ScenarioId = scenarioId,
				})
			end
		end
		waitFor(function()
			return allClients(function(state)
				return state.ScenarioReady == scenarioId
			end)
		end, REQUEST_TIMEOUT, scenarioId .. " 客户端场景确认")
	end

	local function sendAttack(attacker: Player, entryPoint: Vector3): number
		nextRequestId += 1
		local requestId = nextRequestId
		control:FireClient(attacker, {
			Kind = MultiplayerAttackAcceptanceProtocol.Kinds.RequestAttack,
			ScenarioId = activeScenarioId,
			RequestId = requestId,
			SpawnPointId = SPAWN_POINT_ID,
			TargetPlayerId = defender.UserId,
			EntryPoint = entryPoint,
		})
		return requestId
	end

	local function waitAttack(attacker: Player, requestId: number)
		local response = nil
		waitFor(function()
			response = clientStates[attacker].Responses[requestId]
			return response ~= nil
		end, REQUEST_TIMEOUT, tostring(activeScenarioId) .. " 攻击 Remote 响应")
		expect(response.QuerySucceeded, "正式目标查询失败：" .. tostring(response.Reason))
		expect(response.QuerySawTarget, "正式目标查询没有返回防守玩家")
		expect(response.Succeeded, "正式攻击 Remote 被拒绝：" .. tostring(response.Reason))
		expect(type(response.CommandId) == "number", "正式攻击响应缺少 CommandId")
		expect(response.HasMonster, "正式攻击响应缺少怪兽 Model")
		return response
	end

	local function countObserved(player: Player, commandKind: string): number
		local count = 0
		for _, observation in clientStates[player].Observations do
			if observation.CommandKind == commandKind
				and observation.OwnerUserId == defender.UserId
				and (observation.HouseId == nil or observation.HouseId == HOUSE_ID) then
				count += 1
			end
		end
		return count
	end

	local function waitPresentation(commandKind: string, count: number)
		waitFor(function()
			return allClients(function(_, player)
				return countObserved(player, commandKind) >= count
			end)
		end, REBUILD_TIMEOUT, tostring(activeScenarioId) .. " 全客户端 " .. commandKind)
	end

	local function assertPresentation(commandKind: string, count: number)
		for _, player in ordered do
			if player.Parent == Players then
				expect(
					countObserved(player, commandKind) == count,
					string.format(
						"%s 在 %s 收到 %s 次 %s，预期 %s 次",
						player.Name,
						tostring(activeScenarioId),
						tostring(countObserved(player, commandKind)),
						commandKind,
						tostring(count)
					)
				)
			end
		end
	end

	local function waitMonsterIdle(player: Player)
		waitFor(function()
			local record = MonsterRosterCoordinator.Get(player, SPAWN_POINT_ID)
			return record ~= nil and record.State == "IdleAtSpawn" and record.Model ~= nil
		end, MOVEMENT_TIMEOUT, player.Name .. " 怪兽回到 IdleAtSpawn")
	end

	local function positionMonsterNearTarget(
		player: Player,
		entryPoint: Vector3,
		horizontalOffset: Vector3
	)
		local record = MonsterRosterCoordinator.Get(player, SPAWN_POINT_ID)
		expect(record ~= nil and record.Model ~= nil, player.Name .. " 缺少并发测试怪兽")
		local currentPivot = record.Model:GetPivot()
		local position = Vector3.new(
			entryPoint.X + horizontalOffset.X,
			currentPivot.Position.Y,
			entryPoint.Z + horizontalOffset.Z
		)
		record.Model:PivotTo(CFrame.new(position) * currentPivot.Rotation)
	end

	local function waitHouseState(lifeState: string)
		local timeout = if lifeState == "Destroyed" then MOVEMENT_TIMEOUT else REBUILD_TIMEOUT
		waitFor(function()
			return HouseStateService.Get(defender, HOUSE_ID).LifeState == lifeState
		end, timeout, "房屋进入 " .. lifeState)
	end

	local function prepareAttacker(player: Player)
		ZoneStateService.SetUnlocked(player, MONSTER_ZONE_ID, true)
		waitFor(function()
			local permission = PlayerMonsterRuntimeCoordinator.CanBuild(player, SPAWN_POINT_ID)
			return permission.Reason ~= "MonsterRuntimeNotLoaded"
		end, REQUEST_TIMEOUT, player.Name .. " 怪兽运行时加载")
		local capacity = math.max(1, MonsterRosterCoordinator.GetCapacity(player))
		expect(MonsterRosterCoordinator.SetCapacity(player, capacity).Succeeded, "无法准备怪兽容量")

		local spawnState = MonsterSpawnPointStateService.Get(player, SPAWN_POINT_ID)
		if not spawnState.Built then
			local built = PlayerMonsterRuntimeCoordinator.Build(player, SPAWN_POINT_ID)
			expect(built.Succeeded, player.Name .. " 建造怪兽失败：" .. tostring(built.Reason))
		end
		waitMonsterIdle(player)
	end

	local report = {
		Players = {
			AttackerA = attackerA.UserId,
			AttackerB = attackerB.UserId,
			Defender = defender.UserId,
		},
		Scenarios = {},
	}

	local succeeded, resultOrError = xpcall(function()
		waitFor(function()
			return allClients(function(state)
				return state.Ready
			end)
		end, REQUEST_TIMEOUT, "三个客户端验收驱动就绪")
		for _, player in ordered do
			waitFor(function()
				return PlayerPlotAssignmentService.GetPlot(player) ~= nil
			end, REQUEST_TIMEOUT, player.Name .. " Plot 分配")
		end

		prepareAttacker(attackerA)
		prepareAttacker(attackerB)
		ZoneStateService.SetUnlocked(defender, HOUSE_ZONE_ID, true)
		ZoneStateService.SetLevel(defender, HOUSE_ZONE_ID, 1)
		local initialHouse = HouseStateService.Get(defender, HOUSE_ID)
		if initialHouse.LifeState == "Unbuilt" then
			local _, built = HouseStateService.Build(defender, HOUSE_ID, os.time())
			expect(built, "无法准备正式测试房屋")
		else
			expect(initialHouse.LifeState == "Alive", "测试房屋初始状态必须为 Alive")
		end
		local refreshed = PlayerCityRuntimeCoordinator.RefreshZone(defender, HOUSE_ZONE_ID)
		expect(refreshed.Succeeded, "刷新防守城市失败：" .. tostring(refreshed.Reason))
		local target = PlayerRuntimeHouseAttackAccess.ResolveAliveTarget(defender, HOUSE_ID)
		expect(target ~= nil, "无法解析正式房屋攻击目标")
		local entryPoint = target.CFrame.Position

		beginScenario("NormalFullFlow")
		local normalRequest = sendAttack(attackerA, entryPoint)
		local normalResponse = waitAttack(attackerA, normalRequest)
		waitHouseState("Destroyed")
		waitPresentation("HouseDestroyed", 1)
		waitHouseState("Alive")
		waitPresentation("HouseRebuilding", 1)
		waitMonsterIdle(attackerA)
		task.wait(0.2)
		assertPresentation("HouseDestroyed", 1)
		assertPresentation("HouseRebuilding", 1)
		table.insert(report.Scenarios, {
			Name = "NormalFullFlow",
			CommandId = normalResponse.CommandId,
			FinalMonsterState = "IdleAtSpawn",
			FinalHouseState = "Alive",
		})

		-- 并发验收要消除不同 Plot 到目标的路程差；否则第一栋已重建后第二只怪兽才到达，
		-- 那会是两次合法生命周期，而不是同一栋 Alive 房屋的预约竞争。
		positionMonsterNearTarget(attackerA, entryPoint, Vector3.new(8, 0, 0))
		positionMonsterNearTarget(attackerB, entryPoint, Vector3.new(-8, 0, 0))
		beginScenario("ConcurrentSameHouse")
		local balanceA = MoneyService.Get(attackerA)
		local balanceB = MoneyService.Get(attackerB)
		local concurrentA = sendAttack(attackerA, entryPoint)
		local concurrentB = sendAttack(attackerB, entryPoint)
		local concurrentResponseA = waitAttack(attackerA, concurrentA)
		local concurrentResponseB = waitAttack(attackerB, concurrentB)
		waitHouseState("Destroyed")
		waitPresentation("HouseDestroyed", 1)
		waitHouseState("Alive")
		waitPresentation("HouseRebuilding", 1)
		waitMonsterIdle(attackerA)
		waitMonsterIdle(attackerB)
		task.wait(0.2)
		assertPresentation("HouseDestroyed", 1)
		assertPresentation("HouseRebuilding", 1)
		expect(MoneyService.Get(attackerA) == balanceA, "零奖励配置下攻击者 A 余额变化")
		expect(MoneyService.Get(attackerB) == balanceB, "零奖励配置下攻击者 B 余额变化")
		table.insert(report.Scenarios, {
			Name = "ConcurrentSameHouse",
			CommandIds = { concurrentResponseA.CommandId, concurrentResponseB.CommandId },
			SuccessfulDestroyCount = 1,
			RewardDelta = 0,
			FinalMonsterStates = { "IdleAtSpawn", "IdleAtSpawn" },
		})

		beginScenario("FormalUpgradeDuringDestroyed")
		local upgradeRequest = sendAttack(attackerA, entryPoint)
		waitAttack(attackerA, upgradeRequest)
		waitHouseState("Destroyed")
		waitPresentation("HouseDestroyed", 1)
		MoneyService.Add(defender, RegionEconomyConfigs[HOUSE_ZONE_ID].UpgradeBaseCost)
		RegionUpgradeCityCoordinator.Upgrade(defender, HOUSE_ZONE_ID)
		expect(ZoneStateService.GetLevel(defender, HOUSE_ZONE_ID) == 2, "正式区域升级没有进入等级 2")
		waitPresentation("RegionUpgrade", 1)
		waitHouseState("Alive")
		waitPresentation("HouseRebuilding", 1)
		waitMonsterIdle(attackerA)
		local upgradedModel = PlayerCityRuntimeCoordinator.ResolveBuilding(defender, HOUSE_ID)
		expect(upgradedModel ~= nil, "升级后重建模型不存在")
		expect(upgradedModel:GetAttribute("BuildingLevel") == 2, "重建没有采用正式升级后的最新等级")
		task.wait(0.2)
		assertPresentation("HouseDestroyed", 1)
		assertPresentation("RegionUpgrade", 1)
		assertPresentation("HouseRebuilding", 1)
		table.insert(report.Scenarios, {
			Name = "FormalUpgradeDuringDestroyed",
			FinalHouseState = "Alive",
			FinalBuildingLevel = 2,
		})

		for _, player in ordered do
			control:FireClient(player, {
				Kind = MultiplayerAttackAcceptanceProtocol.Kinds.EvidenceAccepted,
				Checkpoint = "NormalConcurrentUpgrade",
			})
		end

		beginScenario("DefenderLeavesDuringRebuilding")
		local leaveRequest = sendAttack(attackerB, entryPoint)
		waitAttack(attackerB, leaveRequest)
		waitHouseState("Destroyed")
		waitPresentation("HouseDestroyed", 1)
		waitHouseState("Rebuilding")
		waitPresentation("HouseRebuilding", 1)
		assertPresentation("HouseDestroyed", 1)
		assertPresentation("HouseRebuilding", 1)

		local defenderPlot = assert(PlayerPlotAssignmentService.GetPlot(defender))
		defender:Kick("Codex multiplayer acceptance: expected defender departure")
		waitFor(function()
			return defender.Parent ~= Players
		end, REQUEST_TIMEOUT, "防守玩家离开服务器")
		waitFor(function()
			return defenderPlot:GetAttribute("OwnerUserId") == 0 and runtimeIsEmpty(defenderPlot)
		end, REQUEST_TIMEOUT, "离服后 Plot Runtime 清理")
		waitMonsterIdle(attackerB)

		expect(
			HouseTargetReservationService.GetActiveCount(defender, HOUSE_ID) == 0,
			"玩家离开后仍残留房屋攻击凭证"
		)

		local riseDuration = BuildingPresentationConfigs[
			HouseLifecycleConfigs.Default.PresentationId
		].Rise.TotalDuration
		task.wait(riseDuration + 0.25)
		expect(defenderPlot:GetAttribute("OwnerUserId") == 0, "异步任务重新占用了已释放 Plot")
		expect(runtimeIsEmpty(defenderPlot), "异步任务在已释放 Plot 留下孤儿 Model")
		table.insert(report.Scenarios, {
			Name = "DefenderLeavesDuringRebuilding",
			PlotReleased = true,
			RuntimeEmpty = true,
			ReservationReleased = true,
			AttackerFinalState = "IdleAtSpawn",
		})

		for _, player in { attackerA, attackerB } do
			if player.Parent == Players then
				control:FireClient(player, {
					Kind = MultiplayerAttackAcceptanceProtocol.Kinds.AcceptanceFinished,
				})
			end
		end
		return report
	end, debug.traceback)

	connection:Disconnect()
	if not succeeded then
		error(resultOrError, 0)
	end
	return resultOrError
end

return MultiplayerAttackAcceptanceSpec
