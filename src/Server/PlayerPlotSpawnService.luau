--[[
	职责：把每名在线玩家的角色放到其已分配 Plot 的专属出生点。

	场景合同：
	- PlayerPlots/<PlotId>/PlayerSpawn (BasePart)
	- PlayerPlots/<PlotId>/Runtime (Folder；运行时出生点创建于此)

	输入：ReloadCharacter 接收在线 Player；PlaceCharacter 接收其当前 Character；Start 注册生命周期。
	输出：加载或放置是否成功，以及稳定失败原因。
	内部算法：先等待 Plot → 创建不可见运行时 SpawnLocation → 设置 RespawnLocation → LoadCharacter；
		角色创建后再精确把脚底对齐 PlayerSpawn 顶面；死亡等待 Players.RespawnTime 后走同一流程。

	不负责：不分配 Plot、不创建或复制静态 PlayerSpawn、不修改存档或玩家业务状态。
]]

local Players = game:GetService("Players")

local PlayerRuntimeLoadReporter = require(
	script.Parent.Analytics.PlayerRuntimeLoadReporter
)
local PlayerPlotAssignmentService = require(script.Parent.PlayerPlotAssignmentService)

local PlayerPlotSpawnService = {}

export type PlaceResult = {
	Succeeded: boolean,
	Reason: string?,
}

local SPAWN_NAME = "PlayerSpawn"
local RUNTIME_SPAWN_NAME = "PlayerRuntimeSpawn"
local READY_TIMEOUT_SECONDS = 5

local started = false
local boundPlayers: { [Player]: boolean } = setmetatable({}, { __mode = "k" })
local characterGenerations: { [Player]: number } = setmetatable({}, { __mode = "k" })
local loadingPlayers: { [Player]: boolean } = setmetatable({}, { __mode = "k" })

local function result(succeeded: boolean, reason: string?): PlaceResult
	return {
		Succeeded = succeeded,
		Reason = reason,
	}
end

local function waitForPlot(player: Player): Model?
	local deadline = os.clock() + READY_TIMEOUT_SECONDS
	repeat
		local plot = PlayerPlotAssignmentService.GetPlot(player)
		if plot then
			return plot
		end
		if player.Parent ~= Players then
			return nil
		end
		task.wait(0.05)
	until os.clock() >= deadline
	return nil
end

local function ensureRuntimeSpawn(plot: Model): (SpawnLocation?, string?)
	local source = plot:FindFirstChild(SPAWN_NAME)
	if not source or not source:IsA("BasePart") then
		return nil, "PlayerSpawnUnavailable"
	end
	local runtime = plot:FindFirstChild("Runtime")
	if not runtime or not runtime:IsA("Folder") then
		return nil, "PlayerRuntimeUnavailable"
	end

	local existing = runtime:FindFirstChild(RUNTIME_SPAWN_NAME)
	if existing and not existing:IsA("SpawnLocation") then
		return nil, "RuntimeSpawnInvalid"
	end
	local spawn = existing :: SpawnLocation?
	if not spawn then
		spawn = Instance.new("SpawnLocation")
		spawn.Name = RUNTIME_SPAWN_NAME
		spawn.Parent = runtime
	end

	spawn.Anchored = true
	spawn.CFrame = source.CFrame
	spawn.Size = source.Size
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.CanTouch = false
	spawn.CanQuery = false
	spawn.Neutral = true
	spawn.AllowTeamChangeOnTouch = false
	spawn.Duration = 0
	spawn.Enabled = true
	return spawn, nil
end

local function prepareRespawnLocation(player: Player): (SpawnLocation?, string?)
	local plot = waitForPlot(player)
	if not plot then
		return nil, "PlayerPlotUnavailable"
	end
	local spawn, reason = ensureRuntimeSpawn(plot)
	if not spawn then
		return nil, reason
	end
	player.RespawnLocation = spawn
	return spawn, nil
end

local function waitForCharacterPart(character: Model, name: string): BasePart?
	local existing = character:FindFirstChild(name)
	if existing and existing:IsA("BasePart") then
		return existing
	end
	local found = character:WaitForChild(name, READY_TIMEOUT_SECONDS)
	return if found and found:IsA("BasePart") then found else nil
end

local function waitForHumanoid(character: Model): Humanoid?
	local existing = character:FindFirstChildOfClass("Humanoid")
	if existing then
		return existing
	end
	local found = character:WaitForChild("Humanoid", READY_TIMEOUT_SECONDS)
	return if found and found:IsA("Humanoid") then found else nil
end

function PlayerPlotSpawnService.ReloadCharacter(player: Player): (boolean, string?)
	assert(
		typeof(player) == "Instance" and player:IsA("Player"),
		"player 必须是 Player"
	)
	if player.Parent ~= Players then
		return false, "PlayerUnavailable"
	end
	if loadingPlayers[player] then
		return false, "CharacterLoadBusy"
	end
	local spawn, spawnReason = prepareRespawnLocation(player)
	if not spawn then
		return false, spawnReason
	end

	loadingPlayers[player] = true
	local loaded, loadError = pcall(player.LoadCharacter, player)
	loadingPlayers[player] = nil
	if not loaded then
		warn(string.format(
			"加载玩家角色失败：%s (%s)",
			player.Name,
			tostring(loadError)
		))
		return false, "CharacterLoadFailed"
	end
	return true, nil
end

-- 输入：已进入 Players 的玩家及其当前 Character。
-- 输出：角色是否放置成功；失败时不移动角色。
-- 内部算法：目标 Root 高度 = Part 半高 + Humanoid.HipHeight + Root 半高；
-- 	通过 Root 到 Model Pivot 的偏移换算最终 Pivot，避免依赖 Character.PrimaryPart。
function PlayerPlotSpawnService.PlaceCharacter(
	player: Player,
	character: Model
): PlaceResult
	assert(
		typeof(player) == "Instance" and player:IsA("Player"),
		"player 必须是 Player"
	)
	assert(
		typeof(character) == "Instance" and character:IsA("Model"),
		"character 必须是 Model"
	)
	if player.Parent ~= Players then
		return result(false, "PlayerUnavailable")
	end
	if player.Character ~= character then
		return result(false, "CharacterChanged")
	end

	local plot = waitForPlot(player)
	if not plot then
		return result(false, "PlayerPlotUnavailable")
	end
	local spawnPart = plot:FindFirstChild(SPAWN_NAME)
	if not spawnPart or not spawnPart:IsA("BasePart") then
		return result(false, "PlayerSpawnUnavailable")
	end

	local humanoid = waitForHumanoid(character)
	local root = waitForCharacterPart(character, "HumanoidRootPart")
	if player.Character ~= character or not character.Parent then
		return result(false, "CharacterChanged")
	end
	if not humanoid then
		return result(false, "HumanoidUnavailable")
	end
	if not root then
		return result(false, "HumanoidRootPartUnavailable")
	end

	local rootHeight = spawnPart.Size.Y * 0.5
		+ humanoid.HipHeight
		+ root.Size.Y * 0.5
	local targetRootCFrame = spawnPart.CFrame * CFrame.new(0, rootHeight, 0)
	local rootToPivot = root.CFrame:ToObjectSpace(character:GetPivot())
	character:PivotTo(targetRootCFrame * rootToPivot)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	return result(true, nil)
end

local function scheduleRespawn(player: Player, character: Model, generation: number)
	task.delay(Players.RespawnTime, function()
		if player.Parent ~= Players
			or player.Character ~= character
			or characterGenerations[player] ~= generation then
			return
		end
		local loaded, reason = PlayerPlotSpawnService.ReloadCharacter(player)
		if not loaded and reason ~= "PlayerUnavailable" then
			warn(string.format(
				"玩家死亡后重新生成失败：%s (%s)",
				player.Name,
				reason or "Unknown"
			))
		end
	end)
end

local function placeAndBindDeathAsync(player: Player, character: Model)
	local generation = (characterGenerations[player] or 0) + 1
	characterGenerations[player] = generation
	task.spawn(function()
		local placement = PlayerPlotSpawnService.PlaceCharacter(player, character)
		PlayerRuntimeLoadReporter.Report(
			player,
			"Character",
			placement.Succeeded,
			placement.Reason
		)
		if not placement.Succeeded
			and placement.Reason ~= "PlayerUnavailable"
			and placement.Reason ~= "CharacterChanged" then
			warn(string.format(
				"玩家角色放置到 Plot 出生点失败：%s (%s)",
				player.Name,
				placement.Reason or "Unknown"
			))
		end
		if not placement.Succeeded then
			return
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end
		humanoid.Died:Once(function()
			scheduleRespawn(player, character, generation)
		end)
	end)
end

local function bindPlayer(player: Player)
	if boundPlayers[player] then
		return
	end
	boundPlayers[player] = true
	player.CharacterAdded:Connect(function(character)
		placeAndBindDeathAsync(player, character)
	end)
	task.spawn(function()
		local loaded, reason = PlayerPlotSpawnService.ReloadCharacter(player)
		if loaded then
			return
		end
		PlayerRuntimeLoadReporter.Report(player, "Character", false, reason)
		if reason ~= "PlayerUnavailable" then
			warn(string.format(
				"玩家首次角色生成失败：%s (%s)",
				player.Name,
				reason or "Unknown"
			))
		end
	end)
end

function PlayerPlotSpawnService.Start()
	if started then
		return
	end
	started = true
	assert(not Players.CharacterAutoLoads, "必须先关闭 Players.CharacterAutoLoads")
	Players.PlayerAdded:Connect(bindPlayer)
	Players.PlayerRemoving:Connect(function(player)
		boundPlayers[player] = nil
		characterGenerations[player] = nil
		loadingPlayers[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		bindPlayer(player)
	end
end

return PlayerPlotSpawnService
