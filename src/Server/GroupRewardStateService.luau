--[[
	职责：维护群组奖励 RewardId 的服务器运行时领取状态。
	输入：player、RewardId，以及可序列化的 claims 表。
	输出：单个 RewardId 是否已领取、全部领取记录，以及恢复后的状态。
	内部算法：在 RuntimePlayerStates/<UserId>/Rewards/GroupRewardClaims 下用 BoolValue
	按 RewardId 建立领取标记；Restore 先清理旧标记，再写入存档中的 true 项。
	不负责：群组 API、奖励配置、发奖、DataStore、Remote 或 UI。
]]

local PlayerStateService = require(script.Parent.PlayerStateService)

local GroupRewardStateService = {}

local ROOT_NAME = "GroupRewardClaims"

local function assertRewardId(rewardId: string)
	assert(
		type(rewardId) == "string"
			and rewardId ~= ""
			and string.match(rewardId, "^[A-Za-z0-9_.%-]+$") ~= nil,
		"rewardId 必须是非空安全标识符"
	)
end

local function getRoot(player: Player): Folder
	local rewards = PlayerStateService.GetSection(player, "Rewards")
	local existing = rewards:FindFirstChild(ROOT_NAME)
	if existing then
		assert(existing:IsA("Folder"), rewards:GetFullName() .. "." .. ROOT_NAME .. " 必须是 Folder")
		return existing
	end

	local root = Instance.new("Folder")
	root.Name = ROOT_NAME
	root.Parent = rewards
	return root
end

local function getClaim(root: Folder, rewardId: string, create: boolean): BoolValue?
	local existing = root:FindFirstChild(rewardId)
	if existing then
		assert(existing:IsA("BoolValue"), existing:GetFullName() .. " 必须是 BoolValue")
		return existing :: BoolValue
	end
	if not create then
		return nil
	end

	local claim = Instance.new("BoolValue")
	claim.Name = rewardId
	claim.Value = true
	claim.Parent = root
	return claim
end

function GroupRewardStateService.IsClaimed(player: Player, rewardId: string): boolean
	assertRewardId(rewardId)
	local claim = getClaim(getRoot(player), rewardId, false)
	return claim ~= nil and claim.Value == true
end

function GroupRewardStateService.SetClaimed(player: Player, rewardId: string, claimed: boolean)
	assertRewardId(rewardId)
	assert(type(claimed) == "boolean", "claimed 必须是 boolean")

	local root = getRoot(player)
	local claim = getClaim(root, rewardId, claimed)
	if claim then
		claim.Value = claimed
	end
	if not claimed and claim then
		claim:Destroy()
	end
	return claimed
end

function GroupRewardStateService.GetAll(player: Player): { [string]: boolean }
	local claims = {}
	for _, child in getRoot(player):GetChildren() do
		assert(child:IsA("BoolValue"), child:GetFullName() .. " 必须是 BoolValue")
		if child.Value then
			claims[child.Name] = true
		end
	end
	return claims
end

function GroupRewardStateService.Restore(
	player: Player,
	claims: { [string]: boolean }?
)
	local root = getRoot(player)
	for _, child in root:GetChildren() do
		child:Destroy()
	end

	if type(claims) ~= "table" then
		return GroupRewardStateService.GetAll(player)
	end

	for rewardId, claimed in claims do
		if claimed == true then
			GroupRewardStateService.SetClaimed(player, rewardId, true)
		end
	end
	return GroupRewardStateService.GetAll(player)
end

return GroupRewardStateService
