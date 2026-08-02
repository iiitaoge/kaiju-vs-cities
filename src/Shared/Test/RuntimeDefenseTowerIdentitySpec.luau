local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DefenseTowerConfigs = require(ReplicatedStorage.Shared.Monster.DefenseTowerConfigs)
local RuntimeDefenseTowerIdentity = require(
	ReplicatedStorage.Shared.Monster.RuntimeDefenseTowerIdentity
)

local RuntimeDefenseTowerIdentitySpec = {}

local function expect(condition: boolean, message: string)
	assert(condition, "RuntimeDefenseTowerIdentitySpec: " .. message)
end

function RuntimeDefenseTowerIdentitySpec.Run(): boolean
	local part = Instance.new("Part")
	part:SetAttribute("DefenseTowerOwnerUserId", 10)
	part:SetAttribute("DefenseTowerId", "D1-T1")
	part:SetAttribute("DefenseTowerZoneId", "D1")
	part:SetAttribute("DefenseTowerSlotId", "D1-T1")
	part:SetAttribute("DefenseTowerConfigId", "D1BasicL1")
	part:SetAttribute("DefenseTowerActive", true)
	local identity = RuntimeDefenseTowerIdentity.Read(part)
	expect(identity ~= nil and identity.TowerId == "D1-T1" and identity.Active, "合法身份读取失败")
	expect(DefenseTowerConfigs.Get(identity.ConfigId).Damage == 10, "塔配置读取失败")
	part:SetAttribute("DefenseTowerActive", nil)
	local invalid, reason = RuntimeDefenseTowerIdentity.Read(part)
	expect(invalid == nil and reason == "InvalidTowerActive", "缺失 Active 应拒绝")
	part:Destroy()
	return true
end

return RuntimeDefenseTowerIdentitySpec
