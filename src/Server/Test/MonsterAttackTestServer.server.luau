local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterAttackCoordinator = require(script.Parent.Parent.MonsterAttackCoordinator)
local MonsterAttackTestHouseAccess = require(script.Parent.MonsterAttackTestHouseAccess)
local MonsterAttackTestRuntime = require(script.Parent.MonsterAttackTestRuntime)
local InstancePath = require(ReplicatedStorage.Shared.InstancePath)
local ModelAnimationConfigs = require(ReplicatedStorage.Shared.Animation.ModelAnimationConfigs)
local MonsterAttackConfigs = require(ReplicatedStorage.Shared.Monster.MonsterAttackConfigs)
local MonsterAttackTestConfig = require(ReplicatedStorage.Shared.Test.MonsterAttackTestConfig)

if not MonsterAttackTestConfig.Enabled then
	return
end

local function ensure(parent: Instance, className: string, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing then
		assert(existing.ClassName == className, existing:GetFullName() .. " 类型错误")
		return existing
	end

	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = parent
	return instance
end

local remotesRoot = ensure(ReplicatedStorage, "Folder", "Remotes")
local testRemotes = ensure(remotesRoot, "Folder", "MonsterAttackTest")
local spawnMonster = ensure(testRemotes, "RemoteFunction", "SpawnMonster") :: RemoteFunction
local attackDestination = ensure(testRemotes, "RemoteEvent", "AttackDestination") :: RemoteEvent
local houseDestroyed = ensure(testRemotes, "RemoteEvent", "HouseDestroyed") :: RemoteEvent

local runtimeRoot = InstancePath.Get(MonsterAttackTestConfig.Paths.Runtime)
local monstersRoot = ensure(runtimeRoot, "Folder", "Monsters")
local monsterTemplate = InstancePath.Get(MonsterAttackTestConfig.Paths.MonsterTemplate)
local monsterSpawnPoint = InstancePath.Get(MonsterAttackTestConfig.Paths.MonsterSpawnPoint)
assert(monsterTemplate:IsA("Model"), "测试怪兽模板必须是 Model")
assert(monsterSpawnPoint:IsA("BasePart"), "测试怪兽出生点必须是 BasePart")

local modelAnimationConfig = assert(
	ModelAnimationConfigs[MonsterAttackTestConfig.MonsterKey],
	"缺少测试怪兽动画配置"
)
local monsterAttackConfig = assert(
	MonsterAttackConfigs[MonsterAttackTestConfig.MonsterKey],
	"缺少测试怪兽攻击配置"
)

local function isFiniteVector3(value): boolean
	return typeof(value) == "Vector3"
		and value.X == value.X
		and value.Y == value.Y
		and value.Z == value.Z
		and math.abs(value.X) < math.huge
		and math.abs(value.Y) < math.huge
		and math.abs(value.Z) < math.huge
end

-- 输入：加入服务器的 player。
-- 输出：无。
-- 副作用：为该玩家建立 40 栋测试房屋的服务器 Alive 状态。
local function initializePlayer(player: Player)
	MonsterAttackTestHouseAccess.InitializePlayer(player)
end

Players.PlayerAdded:Connect(initializePlayer)
Players.PlayerRemoving:Connect(function(player)
	MonsterAttackTestRuntime.Remove(player)
end)
for _, player in Players:GetPlayers() do
	initializePlayer(player)
end

-- 输入：客户端调用者；无额外参数。
-- 输出：可序列化的 Succeeded、Reason、Created。
-- 副作用：首次调用时在 Runtime/Monsters 克隆并稳定放置 P4。
spawnMonster.OnServerInvoke = function(player)
	local result = MonsterAttackTestRuntime.Spawn(
		player,
		monsterTemplate,
		monsterSpawnPoint.CFrame,
		monstersRoot
	)
	return {
		Succeeded = result.Succeeded,
		Reason = result.Reason,
		Created = result.Created,
	}
end

-- 输入：客户端调用者和射线命中的世界 Vector3。
-- 输出：无；攻击结果通过怪兽状态和 HouseDestroyed 表现事件体现。
-- 副作用：异步执行“沿途逐栋攻击检测半径内房屋，然后继续目的地”的命令。
attackDestination.OnServerEvent:Connect(function(player, destination)
	if not isFiniteVector3(destination) then
		return
	end

	local monster = MonsterAttackTestRuntime.Get(player)
	if not monster then
		return
	end

	task.spawn(function()
		local succeeded, resultOrError = pcall(
			MonsterAttackCoordinator.Execute,
			player,
			monster,
			destination,
			{
				HouseAccess = MonsterAttackTestHouseAccess,
				ModelAnimationConfig = modelAnimationConfig,
				MonsterAttackConfig = monsterAttackConfig,
				MoveSpeed = MonsterAttackTestConfig.Movement.MoveSpeed,
				TurnDuration = MonsterAttackTestConfig.Movement.TurnDuration,
				RewardAmount = MonsterAttackTestConfig.RewardAmount,
				OnHouseDestroyed = function(houseId, commitResult)
					houseDestroyed:FireClient(player, houseId, commitResult.RewardGranted)
				end,
			}
		)
		if not succeeded then
			warn("测试怪兽攻击命令失败：", resultOrError)
		end
	end)
end)
