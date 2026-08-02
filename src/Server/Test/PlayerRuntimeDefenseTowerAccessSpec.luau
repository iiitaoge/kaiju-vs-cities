local PlayerPlotAssignmentService = require(script.Parent.Parent.PlayerPlotAssignmentService)
local PlayerRuntimeDefenseTowerAccess = require(
	script.Parent.Parent.PlayerRuntimeDefenseTowerAccess
)
local ZoneStateService = require(script.Parent.Parent.ZoneStateService)

local PlayerRuntimeDefenseTowerAccessSpec = {}

local function expect(condition: boolean, message: string)
	assert(condition, "PlayerRuntimeDefenseTowerAccessSpec: " .. message)
end

local function writeIdentity(instance: Instance, player: Player, towerId: string)
	instance:SetAttribute("DefenseTowerOwnerUserId", player.UserId)
	instance:SetAttribute("DefenseTowerId", towerId)
	instance:SetAttribute("DefenseTowerZoneId", "D1")
	instance:SetAttribute("DefenseTowerSlotId", "D1-T1")
	instance:SetAttribute("DefenseTowerConfigId", "D1BasicL1")
	instance:SetAttribute("DefenseTowerActive", true)
end

-- 输入：已分配 Plot 的在线 Player。
-- 输出：正式适配器能过滤归属/锁区并解析配置和世界位置时返回 true。
-- 内部算法：在 Runtime 下临时注入一座合同塔，逐项切换非法状态并查询。
function PlayerRuntimeDefenseTowerAccessSpec.Run(player: Player): boolean
	local plot = assert(PlayerPlotAssignmentService.GetPlot(player))
	local runtime = assert(plot:FindFirstChild("Runtime"))
	local towersRoot = runtime:FindFirstChild("DefenseTowers")
	local createdRoot = false
	if not towersRoot then
		towersRoot = Instance.new("Folder")
		towersRoot.Name = "DefenseTowers"
		towersRoot.Parent = runtime
		createdRoot = true
	end
	expect(towersRoot:IsA("Folder"), "Runtime/DefenseTowers 必须是 Folder")

	local tower = Instance.new("Model")
	tower.Name = "CodexTowerAccessSpec"
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Anchored = true
	root.CFrame = CFrame.new(12, 3, 8)
	root.Parent = tower
	tower.PrimaryPart = root
	writeIdentity(tower, player, "Codex-D1-T1")
	tower.Parent = towersRoot
	local previousUnlocked = ZoneStateService.GetUnlocked(player, "D1")

	local succeeded, errorMessage = xpcall(function()
		ZoneStateService.SetUnlocked(player, "D1", true)
		local found = nil
		for _, candidate in PlayerRuntimeDefenseTowerAccess.ListAliveTowers(player) do
			if candidate.TowerId == "Codex-D1-T1" then
				found = candidate
				break
			end
		end
		expect(found ~= nil, "合同塔未被解析")
		expect(found.Position == root.Position, "塔世界位置错误")
		expect(found.Range == 45 and found.Damage == 10 and found.AttackInterval == 1, "塔配置错误")

		tower:SetAttribute("DefenseTowerOwnerUserId", player.UserId + 1)
		for _, candidate in PlayerRuntimeDefenseTowerAccess.ListAliveTowers(player) do
			expect(candidate.TowerId ~= "Codex-D1-T1", "错误归属的塔未被过滤")
		end
		tower:SetAttribute("DefenseTowerOwnerUserId", player.UserId)
		ZoneStateService.SetUnlocked(player, "D1", false)
		for _, candidate in PlayerRuntimeDefenseTowerAccess.ListAliveTowers(player) do
			expect(candidate.TowerId ~= "Codex-D1-T1", "锁定 Zone 的塔未被过滤")
		end
	end, debug.traceback)

	ZoneStateService.SetUnlocked(player, "D1", previousUnlocked)
	tower:Destroy()
	if createdRoot and #towersRoot:GetChildren() == 0 then
		towersRoot:Destroy()
	end
	if not succeeded then
		error(errorMessage, 0)
	end
	return true
end

return PlayerRuntimeDefenseTowerAccessSpec
