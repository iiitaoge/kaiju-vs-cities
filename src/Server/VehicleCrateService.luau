--[[
	职责：提供载具箱子的服务器权威查询和钻石购买。
	输入：RemoteFunction 接收 GetState，或接收 crateId 与抽取次数 1/5 的 PurchaseDiamond。
	输出：公开箱子/概率/载具配置；购买返回抽中的载具实例和最新钻石余额。
	内部算法：校验准备状态与 R3 解锁 → 校验箱子和价格 → 扣钻石 → 服务端随机抽取
	→ 将每个结果登记为一个未部署的 Fleet 实例 → 排入立即存档；失败时回滚本次购买。
	不负责：模型生成、部署数量限制、Nest、战斗、UI 或 Robux 收据处理。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DiamondService = require(script.Parent.DiamondService)
local PlayerDataReadyService = require(script.Parent.PlayerDataReadyService)
local PlayerPersistenceCoordinator = require(script.Parent.PlayerPersistenceCoordinator)
local ServerRemoteAccess = require(script.Parent.ServerRemoteAccess)
local VehicleFleetService = require(script.Parent.VehicleFleetService)
local ZoneStateService = require(script.Parent.ZoneStateService)
local VehicleCatalog = require(ReplicatedStorage.Shared.Vehicle.VehicleCatalog)
local VehicleCrateConfigs = require(ReplicatedStorage.Shared.Vehicle.VehicleCrateConfigs)
local VehicleCrateProtocol = require(ReplicatedStorage.Shared.Vehicle.VehicleCrateProtocol)
local VehicleCrateRules = require(ReplicatedStorage.Shared.Vehicle.VehicleCrateRules)

local VehicleCrateService = {}

local actionBusy: { [Player]: boolean } = setmetatable({}, { __mode = "k" })
local random = Random.new()
local started = false

local function assertPlayer(player: Player)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
end

local function isReady(player: Player): (boolean, string?)
	local readiness = PlayerDataReadyService.Get(player)
	if readiness.Status == "Unmanaged" then
		return true, nil
	end
	if readiness.Status ~= "Ready" or not readiness.CanSave then
		return false, "PlayerDataNotReady"
	end
	return true, nil
end

local function isFeatureUnlocked(player: Player): boolean
	return ZoneStateService.GetUnlocked(player, VehicleCatalog.UnlockRegionId)
end

local function syncFeatureUnlocked(player: Player)
	if player.Parent ~= Players then
		return
	end
	player:SetAttribute(
		VehicleCrateProtocol.FeatureUnlockedAttributeName,
		isFeatureUnlocked(player)
	)
end

local function copyRates(rates)
	local result = {}
	for _, rarity in VehicleCrateConfigs.RarityOrder do
		result[rarity] = rates[rarity]
	end
	return result
end

local function serializeCrate(crate)
	local serialized = {
		CrateId = crate.CrateId,
		Name = crate.Name,
		DiamondPrice = crate.DiamondPrice,
		FiveDrawDiamondPrice = crate.FiveDrawDiamondPrice,
		RarityRates = copyRates(crate.RarityRates),
	}
	if type(crate.RobuxProductId) == "number" and crate.RobuxProductId > 0 then
		serialized.RobuxProductId = crate.RobuxProductId
	end
	return serialized
end

local function serializeCatalogVehicle(definition)
	return {
		VehicleId = definition.VehicleId,
		Name = definition.Name,
		Rarity = definition.Rarity,
		IconName = definition.VehicleId,
	}
end

local function getState(player: Player)
	syncFeatureUnlocked(player)
	local crates = {}
	for _, crate in VehicleCrateConfigs.GetAll() do
		table.insert(crates, serializeCrate(crate))
	end

	local vehicles = {}
	for _, definition in VehicleCatalog.GetAll() do
		table.insert(vehicles, serializeCatalogVehicle(definition))
	end

	return {
		FeatureUnlocked = isFeatureUnlocked(player),
		RarityOrder = table.clone(VehicleCrateConfigs.RarityOrder),
		Crates = crates,
		Vehicles = vehicles,
	}
end

local function response(player: Player, succeeded: boolean, reason: string?)
	return {
		Succeeded = succeeded,
		Reason = reason,
		State = getState(player),
		Balances = {
			Diamond = DiamondService.Get(player),
		},
	}
end

local function queueSave(player: Player)
	local queued, reason = PlayerPersistenceCoordinator.SavePlayer(player)
	if not queued then
		warn(string.format(
			"载具箱子购买已应用但立即存档未入队：%s (%s)",
			player.Name,
			tostring(reason)
		))
	end
end

local function rollbackPurchase(player: Player, instanceIds, diamondCost: number)
	for _, instanceId in instanceIds do
		local removed, reason = VehicleFleetService.Remove(player, instanceId)
		if not removed then
			warn(string.format(
				"载具箱子回滚失败：%s (%s)",
				instanceId,
				reason or "Unknown"
			))
		end
	end
	DiamondService.Add(player, diamondCost)
end

local function purchaseDiamond(player: Player, crateId: string, drawCount: number)
	if not isFeatureUnlocked(player) then
		return response(player, false, "R3Locked")
	end

	local crate = VehicleCrateConfigs.Get(crateId)
	if not crate then
		return response(player, false, "UnknownCrate")
	end

	local diamondCost = VehicleCrateRules.GetDiamondPrice(crate, drawCount)
	if not diamondCost then
		return response(player, false, "InvalidDrawCount")
	end

	local spent = DiamondService.TrySpend(player, diamondCost)
	if not spent.Succeeded then
		return response(player, false, spent.Reason or "InsufficientDiamonds")
	end

	local rewards = {}
	local registeredInstanceIds = {}
	for _ = 1, drawCount do
		local draw, drawReason = VehicleCrateRules.ResolveDraw(
			crate,
			VehicleCrateConfigs.RarityOrder,
			VehicleCatalog.GetAll(),
			random:NextNumber(0, 1),
			random:NextNumber(0, 1)
		)
		if not draw or not draw.Vehicle then
			rollbackPurchase(player, registeredInstanceIds, diamondCost)
			return response(player, false, drawReason or "CrateConfigurationInvalid")
		end

		local registered = VehicleFleetService.Register(player, draw.Vehicle.VehicleId)
		if not registered.Succeeded or not registered.Vehicle then
			rollbackPurchase(player, registeredInstanceIds, diamondCost)
			return response(player, false, registered.Reason or "VehicleGrantFailed")
		end

		table.insert(registeredInstanceIds, registered.Vehicle.InstanceId)
		table.insert(rewards, {
			InstanceId = registered.Vehicle.InstanceId,
			VehicleId = draw.Vehicle.VehicleId,
			Name = draw.Vehicle.Name,
			Rarity = draw.Rarity,
			Level = registered.Vehicle.Level,
		})
	end

	queueSave(player)
	local result = response(player, true, nil)
	result.Purchase = {
		CrateId = crate.CrateId,
		DrawCount = drawCount,
		DiamondCost = diamondCost,
	}
	result.Rewards = rewards
	return result
end

local function validateRequestValue(value, valueName: string): (boolean, string?)
	if type(value) ~= "string" or value == "" then
		return false, "Invalid" .. valueName
	end
	return true, nil
end

local function onRequest(player: Player, requestKind, crateId, drawCount)
	assertPlayer(player)
	local ready, readyReason = isReady(player)
	if not ready then
		return {
			Succeeded = false,
			Reason = readyReason,
			State = nil,
			Balances = nil,
		}
	end

	if requestKind == VehicleCrateProtocol.RequestKinds.GetState then
		return response(player, true, nil)
	end
	if requestKind ~= VehicleCrateProtocol.RequestKinds.PurchaseDiamond then
		return response(player, false, "InvalidRequestKind")
	end

	local validCrateId, crateReason = validateRequestValue(crateId, "CrateId")
	if not validCrateId then
		return response(player, false, crateReason)
	end
	if type(drawCount) ~= "number" or drawCount % 1 ~= 0 then
		return response(player, false, "InvalidDrawCount")
	end
	if actionBusy[player] then
		return response(player, false, "ActionBusy")
	end
	actionBusy[player] = true

	local succeeded, resultOrError = xpcall(function()
		return purchaseDiamond(player, crateId, drawCount)
	end, debug.traceback)
	actionBusy[player] = nil
	if not succeeded then
		warn(string.format(
			"载具箱子请求异常：%s/%s (%s)",
			player.Name,
			tostring(crateId),
			tostring(resultOrError)
		))
		return response(player, false, "ServerError")
	end
	return resultOrError
end

function VehicleCrateService.Start()
	if started then
		return
	end
	started = true

	for _, crate in VehicleCrateConfigs.GetAll() do
		local valid, reason = VehicleCrateRules.Validate(
			crate,
			VehicleCrateConfigs.RarityOrder,
			VehicleCatalog.GetAll()
		)
		assert(valid, string.format("载具箱子配置无效：%s (%s)", crate.CrateId, reason or "Unknown"))
	end

	local remote = ServerRemoteAccess.EnsureFunction(VehicleCrateProtocol.RemoteName)
	remote.OnServerInvoke = onRequest
	Players.PlayerAdded:Connect(function(player)
		task.defer(syncFeatureUnlocked, player)
	end)
	for _, player in Players:GetPlayers() do
		syncFeatureUnlocked(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		actionBusy[player] = nil
	end)
end

function VehicleCrateService.RefreshFeatureUnlocked(player: Player)
	syncFeatureUnlocked(player)
end

return VehicleCrateService
