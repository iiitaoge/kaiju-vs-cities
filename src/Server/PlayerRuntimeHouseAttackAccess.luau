--[[
	职责：
	- 为正式攻击链提供按防守玩家隔离的房屋查询、最新边界和摧毁提交访问。

	输入：
	- defender Player；查询或提交额外接收 HouseId。

	输出：
	- 实现 HouseAttackTargetAccess：Alive 目标数组、单栋最新目标、摧毁准备和摧毁结果。

	内部算法：
	- 通过 Player + HouseId 查询当前服务器权威 Model。
	- 校验 Model 的 Owner/House/Zone/Slot 身份和 HouseState。
	- 直接读取当前 Model 实际边界；摧毁时同步移除该玩家的运行时 Model。

	不负责：
	- 不选择附近目标、不计算攻击站位、不播放摧毁动画、不发放攻击奖励。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HouseAttackTargetAccess = require(script.Parent.HouseAttackTargetAccess)
local HouseIncomeService = require(script.Parent.HouseIncomeService)
local HouseLifecycleCoordinator = require(script.Parent.HouseLifecycleCoordinator)
local HouseStateService = require(script.Parent.HouseStateService)
local PlayerCityRuntimeCoordinator = require(script.Parent.PlayerCityRuntimeCoordinator)
local HouseCatalog = require(ReplicatedStorage.Shared.Building.HouseCatalog)
local RuntimeBuildingBounds = require(ReplicatedStorage.Shared.Building.RuntimeBuildingBounds)
local RuntimeBuildingIdentity = require(ReplicatedStorage.Shared.Building.RuntimeBuildingIdentity)

local PlayerRuntimeHouseAttackAccess = {}

local function assertPlayer(player: Player)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
end

local function resolveRuntimeModel(
	player: Player,
	houseId: string
): (Model?, string?)
	local definition = HouseCatalog.Get(houseId)
	if not definition then
		return nil, "UnknownHouse"
	end

	local model = PlayerCityRuntimeCoordinator.ResolveBuilding(player, houseId)
	if not model then
		return nil, "RuntimeBuildingUnavailable"
	end
	local identity, identityReason = RuntimeBuildingIdentity.Read(model)
	if not identity then
		return nil, identityReason or "InvalidRuntimeBuildingIdentity"
	end
	if identity.OwnerUserId ~= player.UserId
		or identity.HouseId ~= houseId
		or identity.ZoneId ~= definition.RegionId
		or identity.SlotId ~= houseId
	then
		return nil, "RuntimeBuildingIdentityMismatch"
	end
	return model, nil
end

function PlayerRuntimeHouseAttackAccess.ResolveAliveTarget(
	player: Player,
	houseId: string
): (HouseAttackTargetAccess.HouseTarget?, string?)
	assertPlayer(player)
	if player.Parent ~= Players then
		return nil, "DefenderUnavailable"
	end
	if type(houseId) ~= "string" or houseId == "" then
		return nil, "InvalidHouseId"
	end
	if not HouseCatalog.Get(houseId) then
		return nil, "UnknownHouse"
	end
	if HouseStateService.Get(player, houseId).LifeState ~= "Alive" then
		return nil, "HouseNotAlive"
	end

	local model, modelReason = resolveRuntimeModel(player, houseId)
	if not model then
		return nil, modelReason or "RuntimeBuildingUnavailable"
	end
	local bounds, boundsReason = RuntimeBuildingBounds.Resolve(model)
	if not bounds then
		return nil, boundsReason or "RuntimeBuildingBoundsUnavailable"
	end
	return {
		HouseId = houseId,
		CFrame = bounds.CFrame,
		Size = bounds.Size,
	}, nil
end

function PlayerRuntimeHouseAttackAccess.ListAliveTargets(
	player: Player
): { HouseAttackTargetAccess.HouseTarget }
	assertPlayer(player)
	if player.Parent ~= Players then
		return {}
	end

	local targets = {}
	for _, definition in HouseCatalog.GetAll() do
		local target = PlayerRuntimeHouseAttackAccess.ResolveAliveTarget(
			player,
			definition.HouseId
		)
		if target then
			table.insert(targets, target)
		end
	end
	return targets
end

function PlayerRuntimeHouseAttackAccess.PrepareDestroy(
	player: Player,
	houseId: string
): (boolean, string?)
	assertPlayer(player)
	local target, targetReason = PlayerRuntimeHouseAttackAccess.ResolveAliveTarget(player, houseId)
	if not target then
		return false, targetReason or "HouseUnavailable"
	end

	local settlement = HouseIncomeService.SettleHouse(player, houseId, os.time())
	if not settlement.Accepted then
		return false, "IncomeSettlementFailed"
	end
	return true, nil
end

function PlayerRuntimeHouseAttackAccess.Destroy(
	player: Player,
	houseId: string
): (boolean, string?)
	assertPlayer(player)
	if HouseStateService.Get(player, houseId).LifeState ~= "Alive" then
		return false, "HouseNotAlive"
	end
	local lifecycle = HouseLifecycleCoordinator.Destroy(player, houseId)
	return lifecycle.Succeeded, lifecycle.Reason
end

return PlayerRuntimeHouseAttackAccess
