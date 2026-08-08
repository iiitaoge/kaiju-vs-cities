local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalHouseDestructionPresenter = require(script.Parent.Parent.Building.LocalHouseDestructionPresenter)
local WorldPointSelectionController = require(script.Parent.Parent.Camera.WorldPointSelectionController)
local LocalMonsterAttackTestHouses = require(script.Parent.LocalMonsterAttackTestHouses)
local InstancePath = require(ReplicatedStorage.Shared.InstancePath)
local MonsterAttackTestConfig = require(ReplicatedStorage.Shared.Test.MonsterAttackTestConfig)

if not MonsterAttackTestConfig.Enabled then
	return
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("MonsterAttackTestGui")
local spawnButton = gui:WaitForChild("SpawnMonsterButton")
local attackButton = gui:WaitForChild("AttackButton")
assert(spawnButton:IsA("TextButton"), "SpawnMonsterButton 必须是 TextButton")
assert(attackButton:IsA("TextButton"), "AttackButton 必须是 TextButton")

local testRemotes = ReplicatedStorage
	:WaitForChild("Remotes")
	:WaitForChild("MonsterAttackTest")
local spawnMonster = testRemotes:WaitForChild("SpawnMonster")
local attackDestination = testRemotes:WaitForChild("AttackDestination")
local houseDestroyed = testRemotes:WaitForChild("HouseDestroyed")
assert(spawnMonster:IsA("RemoteFunction"), "SpawnMonster 必须是 RemoteFunction")
assert(attackDestination:IsA("RemoteEvent"), "AttackDestination 必须是 RemoteEvent")
assert(houseDestroyed:IsA("RemoteEvent"), "HouseDestroyed 必须是 RemoteEvent")

local cameraTarget = InstancePath.Wait(MonsterAttackTestConfig.Paths.CameraTarget)
assert(cameraTarget:IsA("BasePart"), "测试 CameraTarget 必须是 BasePart")

attackButton.Interactable = false
attackButton.Text = "Enter Attack"

local housesBuilt, buildResult = pcall(LocalMonsterAttackTestHouses.Build)
if not housesBuilt then
	warn("创建测试房屋失败：", buildResult)
	spawnButton.Interactable = false
	spawnButton.Text = "House Creation Failed"
	return
end

houseDestroyed.OnClientEvent:Connect(function(houseId)
	if type(houseId) == "string" then
		LocalHouseDestructionPresenter.Play(houseId, "Demolish")
	end
end)

local spawnBusy = false
spawnButton.Activated:Connect(function()
	if spawnBusy then
		return
	end
	spawnBusy = true
	spawnButton.Interactable = false
	spawnButton.Text = "Spawning..."

	local succeeded, result = pcall(function()
		return spawnMonster:InvokeServer()
	end)
	if succeeded and result and result.Succeeded then
		spawnButton.Text = "Monster Spawned"
		attackButton.Interactable = true
	else
		spawnButton.Text = "Spawn Failed. Retry"
		spawnButton.Interactable = true
		if not succeeded then
			warn("生成测试怪兽失败：", result)
		end
	end
	spawnBusy = false
end)

local selecting = false
attackButton.Activated:Connect(function()
	if selecting or not attackButton.Interactable then
		return
	end
	selecting = true
	attackButton.Interactable = false
	attackButton.Text = "Click the Map to Select a Target"

	task.spawn(function()
		local succeeded, resultOrError = pcall(
			WorldPointSelectionController.Run,
			cameraTarget,
			MonsterAttackTestConfig.Camera,
			function(position)
				-- FireServer 不等待服务端；攻击立即开始，相机随后同时平滑恢复。
				attackDestination:FireServer(position)
			end
		)
		if not succeeded then
			warn("测试选点失败：", resultOrError)
		end

		selecting = false
		attackButton.Text = "Enter Attack"
		attackButton.Interactable = true
	end)
end)
