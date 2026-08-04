--[[
	职责：验收八名在线玩家能同时获得独占 Plot，并能彼此作为攻击目标。
	输入：恰好八名仍在 Players 中的测试玩家。
	输出：玩家数、Plot 名称和每名玩家可见目标数报告；失败时抛出具体合同错误。
	内部算法：等待存档 Ready 与 Plot 分配，验证 Plot/罐体场景合同，临时解锁 R1，
		再用正式 PlayerAttackTargetQuery 检查每人恰好看到另外七人。
	不负责：建造怪兽、执行攻击、保存测试状态或创建多人测试会话。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Protocol = require(
	ReplicatedStorage.Shared.Test.EightPlayerCapacityAcceptanceProtocol
)
local IncomePlotContractValidator = require(script.Parent.Parent.IncomePlotContractValidator)
local PlayerAttackTargetQuery = require(script.Parent.Parent.PlayerAttackTargetQuery)
local PlayerDataReadyService = require(script.Parent.Parent.PlayerDataReadyService)
local PlayerPlotAssignmentService = require(script.Parent.Parent.PlayerPlotAssignmentService)
local WorkspaceMonsterIncubatorSlotAccess = require(
	script.Parent.Parent.WorkspaceMonsterIncubatorSlotAccess
)
local ZoneStateService = require(script.Parent.Parent.ZoneStateService)

local EightPlayerCapacityAcceptanceSpec = {}

local SETTLE_TIMEOUT_SECONDS = 60

local function expect(condition: boolean, message: string)
	assert(condition, "EightPlayerCapacityAcceptanceSpec: " .. message)
end

local function waitForReadyPlot(player: Player): Model
	local deadline = os.clock() + SETTLE_TIMEOUT_SECONDS
	repeat
		local readiness = PlayerDataReadyService.Get(player)
		local plot = PlayerPlotAssignmentService.GetPlot(player)
		if readiness.Status == "Ready" and plot then
			return plot
		end
		if readiness.Status == "Cancelled" then
			error(string.format(
				"玩家 %s 的存档载入被取消：%s",
				player.Name,
				tostring(readiness.Reason)
			))
		end
		task.wait(0.1)
	until os.clock() >= deadline
	error(string.format("等待玩家 %s Ready 和 Plot 分配超时", player.Name))
end

local function waitForCharacterAtPlot(player: Player, plot: Model): number
	local spawn = plot:FindFirstChild("PlayerSpawn")
	expect(spawn ~= nil and spawn:IsA("BasePart"), plot.Name .. " 缺少 PlayerSpawn")
	local deadline = os.clock() + SETTLE_TIMEOUT_SECONDS
	repeat
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local respawnLocation = player.RespawnLocation
		if root and root:IsA("BasePart")
			and humanoid and humanoid.Health > 0
			and respawnLocation
			and respawnLocation:IsA("SpawnLocation")
			and respawnLocation:IsDescendantOf(plot) then
			local distance = (root.Position - (spawn :: BasePart).Position).Magnitude
			if distance <= 10 then
				return distance
			end
		end
		task.wait(0.1)
	until os.clock() >= deadline
	error(string.format("玩家 %s 没有在 %s 的出生点生成", player.Name, plot.Name))
end

local function validateTargetSet(attacker: Player, players: { Player }): number
	local result = PlayerAttackTargetQuery.Query(attacker)
	expect(result.Succeeded, string.format(
		"玩家 %s 查询攻击目标失败：%s",
		attacker.Name,
		tostring(result.Reason)
	))
	expect(
		#result.Targets == Protocol.RequiredPlayerCount - 1,
		string.format(
			"玩家 %s 应看到 %d 个目标，实际为 %d",
			attacker.Name,
			Protocol.RequiredPlayerCount - 1,
			#result.Targets
		)
	)

	local expectedUserIds = {}
	for _, player in ipairs(players) do
		if player ~= attacker then
			expectedUserIds[player.UserId] = true
		end
	end
	for _, target in ipairs(result.Targets) do
		expect(
			expectedUserIds[target.TargetPlayerId] == true,
			string.format(
				"玩家 %s 收到未知或重复目标 UserId %s",
				attacker.Name,
				tostring(target.TargetPlayerId)
			)
		)
		expectedUserIds[target.TargetPlayerId] = nil
	end
	expect(next(expectedUserIds) == nil, "攻击目标集合不完整")
	return #result.Targets
end

function EightPlayerCapacityAcceptanceSpec.Run(players: { Player })
	expect(type(players) == "table", "players 必须是数组")
	expect(
		#players == Protocol.RequiredPlayerCount,
		string.format(
			"需要 %d 名玩家，实际为 %d",
			Protocol.RequiredPlayerCount,
			#players
		)
	)

	local seenPlayers = {}
	local seenUserIds = {}
	for _, player in ipairs(players) do
		expect(
			typeof(player) == "Instance"
				and player:IsA("Player")
				and player.Parent == Players,
			"players 包含离线或非 Player 项"
		)
		expect(not seenPlayers[player], "players 包含重复 Player")
		expect(not seenUserIds[player.UserId], "players 包含重复 UserId")
		seenPlayers[player] = true
		seenUserIds[player.UserId] = true
	end

	local plotNames = {}
	local seenPlots = {}
	local spawnDistances = {}
	for _, player in ipairs(players) do
		local plot = waitForReadyPlot(player)
		expect(not seenPlots[plot], "两名玩家被分配到同一个 Plot")
		seenPlots[plot] = true
		table.insert(plotNames, plot.Name)
		expect(
			plot:GetAttribute("OwnerUserId") == player.UserId,
			plot.Name .. " 的 OwnerUserId 与玩家不一致"
		)
		spawnDistances[tostring(player.UserId)] = waitForCharacterAtPlot(player, plot)

		local plotErrors = IncomePlotContractValidator.ValidatePlot(plot)
		expect(#plotErrors == 0, table.concat(plotErrors, "\n"))
		local slot, slotReason = WorkspaceMonsterIncubatorSlotAccess.Resolve(
			plot,
			"M1",
			"M1-S1"
		)
		expect(
			slot ~= nil,
			string.format("%s 的 M1-S1 无效：%s", plot.Name, tostring(slotReason))
		)
	end
	table.sort(plotNames)
	for index = 1, Protocol.RequiredPlayerCount do
		expect(
			plotNames[index] == string.format("Plot%02d", index),
			"八名玩家没有完整占用 Plot01–Plot08"
		)
	end
	local availablePool = ServerStorage:FindFirstChild("AvailablePlayerPlots")
	expect(availablePool ~= nil and availablePool:IsA("Folder"), "缺少空闲 Plot 池")
	expect(
		#workspace.PlayerPlots:GetChildren() == Protocol.RequiredPlayerCount,
		"八名玩家在线时 Workspace 必须显示八个 Plot"
	)
	expect(#availablePool:GetChildren() == 0, "八名玩家在线时空闲池必须为空")

	local previousR1Unlocked = {}
	for _, player in ipairs(players) do
		previousR1Unlocked[player] = ZoneStateService.GetUnlocked(player, "R1")
		ZoneStateService.SetUnlocked(player, "R1", true)
	end

	local targetCounts = {}
	for _, player in ipairs(players) do
		targetCounts[tostring(player.UserId)] = validateTargetSet(player, players)
	end

	for _, player in ipairs(players) do
		ZoneStateService.SetUnlocked(player, "R1", previousR1Unlocked[player])
	end

	return {
		PlayerCount = #players,
		PlotNames = plotNames,
		TargetCounts = targetCounts,
		SpawnDistances = spawnDistances,
		ActivePlotCount = #workspace.PlayerPlots:GetChildren(),
		PooledPlotCount = #availablePool:GetChildren(),
	}
end

return EightPlayerCapacityAcceptanceSpec
