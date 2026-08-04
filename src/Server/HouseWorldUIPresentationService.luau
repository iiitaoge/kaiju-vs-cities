--[[
	职责：把单栋房屋的权威生命周期、收入、自动状态和 HP 镜像到运行时 Model。
	输入：Player、HouseId、对应运行时 Model。
	输出：是否成功和稳定失败原因；成功时写入共享协议 Attributes。
	内部算法：验证身份 → Ensure 当前耐久 → 查询收入速率/房屋状态 → 一次写全 UI 镜像。
	不负责：创建/销毁建筑、结算或领取收入、客户端 UI 和按钮。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HouseHealthStateService = require(script.Parent.HouseHealthStateService)
local HouseIncomeService = require(script.Parent.HouseIncomeService)
local HouseStateService = require(script.Parent.HouseStateService)
local PlayerStructureDurabilityResolver = require(
	script.Parent.PlayerStructureDurabilityResolver
)
local RegionStateService = require(script.Parent.RegionStateService)
local HouseCatalog = require(ReplicatedStorage.Shared.Building.HouseCatalog)
local IncomeHouseWorldUIProtocol = require(
	ReplicatedStorage.Shared.Building.IncomeHouseWorldUIProtocol
)
local RuntimeBuildingIdentity = require(
	ReplicatedStorage.Shared.Building.RuntimeBuildingIdentity
)

local HouseWorldUIPresentationService = {}

function HouseWorldUIPresentationService.Refresh(
	player: Player,
	houseId: string,
	model: Model
): (boolean, string?)
	local definition = HouseCatalog.Get(houseId)
	if not definition then
		return false, "UnknownHouse"
	end
	if not model:IsA("Model") or not model.Parent then
		return false, "RuntimeBuildingUnavailable"
	end

	local identity, identityReason = RuntimeBuildingIdentity.Read(model)
	if not identity then
		return false, identityReason or "InvalidRuntimeBuildingIdentity"
	end
	if identity.OwnerUserId ~= player.UserId
		or identity.HouseId ~= houseId
		or identity.ZoneId ~= definition.RegionId
	then
		return false, "RuntimeBuildingIdentityMismatch"
	end

	local durability, durabilityReason = PlayerStructureDurabilityResolver.Resolve(
		player,
		definition.RegionId,
		identity.Level
	)
	if not durability then
		return false, durabilityReason or "DurabilityUnavailable"
	end
	local health = HouseHealthStateService.Ensure(
		player,
		houseId,
		identity.Level,
		durability.MaxHealth
	)
	local state = HouseStateService.Get(player, houseId)
	local rate = HouseIncomeService.GetHouseRate(player, houseId)

	model:SetAttribute(
		IncomeHouseWorldUIProtocol.CurrentHealthAttributeName,
		health.CurrentHealth
	)
	model:SetAttribute(
		IncomeHouseWorldUIProtocol.MaxHealthAttributeName,
		health.MaxHealth
	)
	model:SetAttribute("BuildingHealthGeneration", health.Generation)
	model:SetAttribute(
		IncomeHouseWorldUIProtocol.LifeStateAttributeName,
		state.LifeState
	)
	model:SetAttribute(
		IncomeHouseWorldUIProtocol.AutoIncomeAttributeName,
		RegionStateService.GetAutoIncome(player, definition.RegionId)
	)
	model:SetAttribute(
		IncomeHouseWorldUIProtocol.IncomePerSecondAttributeName,
		if rate.Accepted then rate.IncomePerSecond else 0
	)
	model:SetAttribute(
		IncomeHouseWorldUIProtocol.StoredMoneyAttributeName,
		state.StoredMoney
	)
	model:SetAttribute(
		IncomeHouseWorldUIProtocol.LastIncomeAtAttributeName,
		state.LastIncomeAt
	)
	return true, nil
end

return HouseWorldUIPresentationService
