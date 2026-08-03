--[[
	职责：在客户端按稳定身份查找怪兽 Plot、定位点和 Runtime 权威模型。
	输入：OwnerUserId、SpawnPointId、ZoneId、SlotId 和等待时长。
	输出：Plot、定位 Part、培养罐或怪兽 Model；找不到返回 nil。
	内部算法：委托 LocalPlayerPlotAccess 定位 Plot，再验证 Zones/Runtime 路径和身份 Attribute。
	不负责：读取配置/模板、隐藏模型、播放动画或修改服务器状态。
]]

local LocalPlayerPlotAccess = require(script.Parent.Parent.LocalPlayerPlotAccess)

local LocalMonsterBuildPresentationAccess = {}

function LocalMonsterBuildPresentationAccess.FindPlot(ownerUserId: number): Model?
	return LocalPlayerPlotAccess.Find(ownerUserId)
end

local function waitFor(resolve: () -> Instance?, timeout: number): Instance?
	assert(type(timeout) == "number" and timeout >= 0, "timeout 必须是非负数")
	local deadline = os.clock() + timeout
	repeat
		local instance = resolve()
		if instance then
			return instance
		end
		task.wait()
	until os.clock() >= deadline
	return resolve()
end

function LocalMonsterBuildPresentationAccess.WaitForPlot(
	ownerUserId: number,
	timeout: number
): Model?
	return LocalPlayerPlotAccess.Wait(ownerUserId, timeout)
end

function LocalMonsterBuildPresentationAccess.FindSlot(
	plot: Model,
	zoneId: string,
	slotFolderName: string,
	slotId: string
): BasePart?
	if not plot:IsA("Model") then
		return nil
	end
	local zones = plot:FindFirstChild("Zones")
	local zone = zones and zones:FindFirstChild(zoneId)
	local slots = zone and zone:FindFirstChild(slotFolderName)
	local slot = slots and slots:FindFirstChild(slotId)
	return if slot and slot:IsA("BasePart") then slot else nil
end

function LocalMonsterBuildPresentationAccess.FindIncubator(
	plot: Model,
	spawnPointId: string,
	ownerUserId: number
): Model?
	local runtime = plot:FindFirstChild("Runtime")
	local root = runtime and runtime:FindFirstChild("MonsterIncubators")
	local model = root and root:FindFirstChild(spawnPointId)
	if not model or not model:IsA("Model") then
		return nil
	end
	if model:GetAttribute("IncubatorSpawnPointId") ~= spawnPointId
		or model:GetAttribute("IncubatorOwnerUserId") ~= ownerUserId
	then
		return nil
	end
	return model
end

function LocalMonsterBuildPresentationAccess.WaitForIncubator(
	plot: Model,
	spawnPointId: string,
	ownerUserId: number,
	timeout: number
): Model?
	return waitFor(function()
		return LocalMonsterBuildPresentationAccess.FindIncubator(
			plot,
			spawnPointId,
			ownerUserId
		)
	end, timeout) :: Model?
end

function LocalMonsterBuildPresentationAccess.FindMonster(
	plot: Model,
	spawnPointId: string,
	ownerUserId: number,
	monsterKey: string
): Model?
	local runtime = plot:FindFirstChild("Runtime")
	local root = runtime and runtime:FindFirstChild("Monsters")
	if not root or not root:IsA("Folder") then
		return nil
	end
	for _, model in root:GetChildren() do
		if model:IsA("Model")
			and model:GetAttribute("MonsterSpawnPointId") == spawnPointId
			and model:GetAttribute("MonsterOwnerUserId") == ownerUserId
			and model:GetAttribute("MonsterKey") == monsterKey
		then
			return model
		end
	end
	return nil
end

function LocalMonsterBuildPresentationAccess.FindMonsterForSpawnPoint(
	plot: Model,
	spawnPointId: string,
	ownerUserId: number
): Model?
	local runtime = plot:FindFirstChild("Runtime")
	local root = runtime and runtime:FindFirstChild("Monsters")
	if not root or not root:IsA("Folder") then
		return nil
	end
	for _, model in root:GetChildren() do
		if model:IsA("Model")
			and model:GetAttribute("MonsterSpawnPointId") == spawnPointId
			and model:GetAttribute("MonsterOwnerUserId") == ownerUserId
		then
			return model
		end
	end
	return nil
end

function LocalMonsterBuildPresentationAccess.WaitForMonster(
	plot: Model,
	spawnPointId: string,
	ownerUserId: number,
	monsterKey: string,
	timeout: number
): Model?
	return waitFor(function()
		return LocalMonsterBuildPresentationAccess.FindMonster(
			plot,
			spawnPointId,
			ownerUserId,
			monsterKey
		)
	end, timeout) :: Model?
end

return LocalMonsterBuildPresentationAccess
