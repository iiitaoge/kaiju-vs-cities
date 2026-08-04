--[[
	职责：把每名在线玩家的角色放到其已分配 Plot 的专属出生点。

	场景合同：
	- PlayerPlots/<PlotId>/PlayerSpawn (BasePart)

	输入：PlaceCharacter 接收在线 Player 及其当前 Character；Start 注册玩家和角色生命周期。
	输出：PlaceCharacter 返回是否成功，以及稳定失败原因。
	内部算法：等待玩家 Plot、Humanoid 和 HumanoidRootPart 就绪；把角色脚底放在 PlayerSpawn
		顶面，并继承 PlayerSpawn 朝向；首次出生和之后每次 CharacterAdded 使用同一流程。

	不负责：不分配 Plot、不创建或复制 PlayerSpawn、不加载角色、不修改存档。
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
local READY_TIMEOUT_SECONDS = 5

local started = false
local boundPlayers: { [Player]: boolean } = setmetatable({}, { __mode = "k" })

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

local function placeAsync(player: Player, character: Model)
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
	end)
end

local function bindPlayer(player: Player)
	if boundPlayers[player] then
		return
	end
	boundPlayers[player] = true
	player.CharacterAdded:Connect(function(character)
		placeAsync(player, character)
	end)
	if player.Character then
		placeAsync(player, player.Character)
	end
end

function PlayerPlotSpawnService.Start()
	if started then
		return
	end
	started = true
	Players.PlayerAdded:Connect(bindPlayer)
	for _, player in Players:GetPlayers() do
		bindPlayer(player)
	end
end

return PlayerPlotSpawnService
