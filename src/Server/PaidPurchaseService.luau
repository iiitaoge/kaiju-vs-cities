--[[
	职责：统一处理 Developer Product 收据，并把收据映射为已确认的游戏权益。
	输入：ProcessReceipt 的 ReceiptInfo；PrepareMonsterUpgrade 接收指定 SpawnPointId。
	输出：Roblox PurchaseGranted/NotProcessedYet；向客户端发送已发放的奖励结果。
	内部算法：商品目录校验 → 收据幂等查询 → 发放运行时权益 → 标记 PurchaseId →
	使用独占替换同步提交完整存档；只有持久化成功后才确认收据。
	不负责：价格展示、购买提示、商品创建、钻石购买或 GUI。
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterManagementCoordinator = require(script.Parent.MonsterManagementCoordinator)
local MonsterSpawnPointPurchaseCoordinator = require(
	script.Parent.MonsterSpawnPointPurchaseCoordinator
)
local PlayerDataReadyService = require(script.Parent.PlayerDataReadyService)
local PlayerPersistenceCoordinator = require(script.Parent.PlayerPersistenceCoordinator)
local PlayerSaveStateAdapter = require(script.Parent.PlayerSaveStateAdapter)
local PurchaseStateService = require(script.Parent.PurchaseStateService)
local ServerRemoteAccess = require(script.Parent.ServerRemoteAccess)
local VehicleCrateService = require(script.Parent.VehicleCrateService)
local PaidProductCatalog = require(ReplicatedStorage.Shared.Monetization.PaidProductCatalog)
local PaidPurchaseProtocol = require(ReplicatedStorage.Shared.Monetization.PaidPurchaseProtocol)

local PaidPurchaseService = {}

local receiptBusy: { [Player]: boolean } = setmetatable({}, { __mode = "k" })
local pendingReceiptCommits: { [Player]: { [string]: boolean } } = setmetatable({}, { __mode = "k" })
local pendingReceiptPayloads: { [Player]: { [string]: any } } = setmetatable({}, { __mode = "k" })
local started = false
local resultRemote: RemoteEvent? = nil

local function isPurchaseId(value): boolean
	return type(value) == "string"
		and value ~= ""
		and #value <= 128
		and string.match(value, "^[A-Za-z0-9_.%-]+$") ~= nil
end

local function isReady(player: Player): boolean
	local readiness = PlayerDataReadyService.Get(player)
	return readiness.Status == "Ready" and readiness.CanSave
end

local function getPendingCommitTable(player: Player): { [string]: boolean }
	local pending = pendingReceiptCommits[player]
	if not pending then
		pending = {}
		pendingReceiptCommits[player] = pending
	end
	return pending
end

local function getPendingPayloadTable(player: Player): { [string]: any }
	local pending = pendingReceiptPayloads[player]
	if not pending then
		pending = {}
		pendingReceiptPayloads[player] = pending
	end
	return pending
end

local function commitCurrentState(player: Player): (boolean, string?)
	if not isReady(player) then
		return false, "PlayerDataNotReady"
	end
	if not PlayerPersistenceCoordinator.WaitUntilIdle(player, 5) then
		return false, "SaveSessionBusy"
	end

	local captured, captureOrError = pcall(function()
		return PlayerSaveStateAdapter.Capture(player, os.time())
	end)
	if not captured then
		warn(string.format("付费购买快照失败：%s (%s)", player.Name, tostring(captureOrError)))
		return false, "StateCaptureFailed"
	end

	local committed, commitOrError = pcall(function()
		return PlayerPersistenceCoordinator.CommitReplacement(player, captureOrError)
	end)
	if not committed then
		warn(string.format("付费购买提交异常：%s (%s)", player.Name, tostring(commitOrError)))
		return false, "SaveCommitFailed"
	end

	if type(commitOrError) ~= "table" then
		return false, "SaveCommitFailed"
	end
	if commitOrError.Succeeded then
		PlayerPersistenceCoordinator.FinishReplacement(player, false)
		return true, nil
	end
	if commitOrError.Uncertain
		and PlayerPersistenceCoordinator.WaitForReplacement(player, 10)
	then
		return true, nil
	end
	return false, commitOrError.Reason or "SaveCommitFailed"
end

local function getPolicyInfo(player: Player)
	local succeeded, info = pcall(function()
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)
	if not succeeded or type(info) ~= "table" then
		return nil
	end
	return info
end

local function paidRandomItemsAllowed(player: Player): boolean
	local info = getPolicyInfo(player)
	local allowed = info ~= nil and info.ArePaidRandomItemsRestricted ~= true
	player:SetAttribute(PaidPurchaseProtocol.PaidRandomItemsAllowedAttributeName, allowed)
	return allowed
end

local function notifyPurchaseGranted(player: Player, payload)
	if player.Parent == Players and resultRemote then
		resultRemote:FireClient(player, payload)
	end
end

local function prepareMonsterUpgrade(player: Player, spawnPointId: string)
	local productId = PaidProductCatalog.GetMonsterUpgradeToMaxProductId()
	if productId <= 0 then
		return { Succeeded = false, Reason = "ProductNotConfigured", ProductId = 0 }
	end
	if type(spawnPointId) ~= "string" or spawnPointId == "" then
		return { Succeeded = false, Reason = "InvalidSpawnPointId", ProductId = 0 }
	end
	if not isReady(player) then
		return { Succeeded = false, Reason = "PlayerDataNotReady", ProductId = 0 }
	end
	if receiptBusy[player] then
		return { Succeeded = false, Reason = "PurchaseBusy", ProductId = 0 }
	end

	local pending = PurchaseStateService.GetPendingMonsterUpgrade(player)
	if pending then
		if pending.ProductId == productId and pending.SpawnPointId == spawnPointId then
			local saved, saveReason = commitCurrentState(player)
			if not saved then
				return {
					Succeeded = false,
					Reason = saveReason or "PurchaseIntentNotSaved",
					ProductId = 0,
				}
			end
			local current = MonsterManagementCoordinator.Query(player, spawnPointId)
			local currentUpgrade = current.Snapshot and current.Snapshot.RobuxUpgrade
			return {
				Succeeded = true,
				ProductId = productId,
				TargetLevel = currentUpgrade and currentUpgrade.TargetLevel or "Max",
			}
		end
		return { Succeeded = false, Reason = "PurchasePending", ProductId = 0 }
	end

	local query = MonsterManagementCoordinator.Query(player, spawnPointId)
	if not query.Succeeded or not query.Snapshot then
		return { Succeeded = false, Reason = query.Reason or "MonsterUnavailable", ProductId = 0 }
	end
	local upgrade = query.Snapshot.RobuxUpgrade
	if type(upgrade) ~= "table" or not upgrade.Allowed then
		return { Succeeded = false, Reason = upgrade and upgrade.Reason or "UpgradeUnavailable", ProductId = 0 }
	end

	PurchaseStateService.SetPendingMonsterUpgrade(player, spawnPointId, productId)
	local saved, saveReason = commitCurrentState(player)
	if not saved then
		return { Succeeded = false, Reason = saveReason or "PurchaseIntentNotSaved", ProductId = 0 }
	end
	return {
		Succeeded = true,
		ProductId = productId,
		TargetLevel = upgrade.TargetLevel or "Max",
	}
end

local function cancelMonsterUpgrade(player: Player, spawnPointId: string, productId: number)
	if type(spawnPointId) ~= "string" or spawnPointId == "" then
		return { Succeeded = false, Reason = "InvalidSpawnPointId", ProductId = 0 }
	end
	if type(productId) ~= "number" or productId <= 0 or productId % 1 ~= 0 then
		return { Succeeded = false, Reason = "InvalidProductId", ProductId = 0 }
	end
	if not isReady(player) then
		return { Succeeded = false, Reason = "PlayerDataNotReady", ProductId = 0 }
	end
	if receiptBusy[player] then
		return { Succeeded = false, Reason = "PurchaseBusy", ProductId = 0 }
	end
	if not PlayerPersistenceCoordinator.WaitUntilIdle(player, 5) then
		return { Succeeded = false, Reason = "SaveSessionBusy", ProductId = 0 }
	end

	receiptBusy[player] = true
	local succeeded, resultOrError = xpcall(function()
		local pending = PurchaseStateService.GetPendingMonsterUpgrade(player)
		if not pending
			or pending.ProductId ~= productId
			or pending.SpawnPointId ~= spawnPointId
		then
			return { Succeeded = true, Reason = nil, ProductId = 0 }
		end

		PurchaseStateService.ClearPendingMonsterUpgrade(player)
		local saved, saveReason = commitCurrentState(player)
		if saved then
			return { Succeeded = true, Reason = nil, ProductId = 0 }
		end

		-- 清除意图未能持久化时恢复它，避免收据稍后到达却找不到指定怪兽。
		PurchaseStateService.SetPendingMonsterUpgrade(
			player,
			pending.SpawnPointId,
			pending.ProductId
		)
		local restored, restoreReason = commitCurrentState(player)
		if not restored then
			warn(string.format(
				"取消付费怪兽意图失败且恢复也失败：%s/%s (%s/%s)",
				player.Name,
				spawnPointId,
				tostring(saveReason),
				tostring(restoreReason)
			))
		end
		return {
			Succeeded = false,
			Reason = saveReason or "PurchaseIntentCancelNotSaved",
			ProductId = 0,
		}
	end, debug.traceback)
	receiptBusy[player] = nil
	if not succeeded then
		warn(string.format(
			"取消付费怪兽意图异常：%s/%s (%s)",
			player.Name,
			spawnPointId,
			tostring(resultOrError)
		))
		return { Succeeded = false, Reason = "PurchaseIntentCancelFailed", ProductId = 0 }
	end
	return resultOrError
end

local function refreshPaidRandomItemsPolicy(player: Player)
	local info = getPolicyInfo(player)
	local allowed = info ~= nil and info.ArePaidRandomItemsRestricted ~= true
	player:SetAttribute(PaidPurchaseProtocol.PaidRandomItemsAllowedAttributeName, allowed)
end

local function grantMonsterUpgrade(player: Player, definition)
	local pending = PurchaseStateService.GetPendingMonsterUpgrade(player)
	if not pending or pending.ProductId ~= definition.ProductId then
		return nil, "MonsterUpgradeTargetMissing"
	end

	local query = MonsterManagementCoordinator.Query(player, pending.SpawnPointId)
	if not query.Succeeded or not query.Snapshot then
		return nil, query.Reason or "MonsterUnavailable"
	end
	local upgrade = query.Snapshot.RobuxUpgrade
	if type(upgrade) ~= "table" then
		return nil, "UpgradeUnavailable"
	end
	local targetLevel = upgrade.TargetLevel
	if type(targetLevel) ~= "number" then
		return nil, "TargetLevelUnavailable"
	end
	if query.Snapshot.Level >= targetLevel then
		return {
			SpawnPointId = pending.SpawnPointId,
			TargetLevel = targetLevel,
		}, nil
	end

	local result = if targetLevel == query.Snapshot.DiamondUpgrade.TargetLevel
		then MonsterSpawnPointPurchaseCoordinator.GrantUpgradeToMax(
			player,
			pending.SpawnPointId
		)
		else MonsterSpawnPointPurchaseCoordinator.GrantUpgradeToLevel(
			player,
			pending.SpawnPointId,
			targetLevel
		)
	if not result.Succeeded then
		return nil, result.Reason or "MonsterUpgradeFailed"
	end
	return {
		SpawnPointId = pending.SpawnPointId,
		TargetLevel = (result.Record and result.Record.Level) or targetLevel,
	}, nil
end

local function grantVehicleCrate(player: Player, definition)
	if not paidRandomItemsAllowed(player) then
		return nil, "PaidRandomItemsRestricted"
	end
	local result = VehicleCrateService.GrantRobux(
		player,
		assert(definition.CrateId),
		assert(definition.DrawCount)
	)
	if not result.Succeeded then
		return nil, result.Reason or "VehicleGrantFailed"
	end
	return result, nil
end

local function processReceipt(receiptInfo)
	local productId = receiptInfo.ProductId
	local purchaseId = receiptInfo.PurchaseId
	if type(receiptInfo.PlayerId) ~= "number" then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local definition = PaidProductCatalog.Get(productId)
	if not definition or not isPurchaseId(purchaseId) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player or not isReady(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if receiptBusy[player] then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	receiptBusy[player] = true
	if not PlayerPersistenceCoordinator.WaitUntilIdle(player, 5) then
		receiptBusy[player] = nil
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local succeeded, decisionOrError = xpcall(function()
		local pendingCommits = getPendingCommitTable(player)
		local pendingPayloads = getPendingPayloadTable(player)
		if PurchaseStateService.IsProcessed(player, purchaseId) then
			if pendingCommits[purchaseId] then
				local committed = commitCurrentState(player)
				if not committed then
					return Enum.ProductPurchaseDecision.NotProcessedYet
				end
				pendingCommits[purchaseId] = nil
				if pendingPayloads[purchaseId] then
					notifyPurchaseGranted(player, pendingPayloads[purchaseId])
					pendingPayloads[purchaseId] = nil
				end
			end
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end

		local grant, grantReason
		if definition.Kind == "MonsterUpgradeToMax" then
			grant, grantReason = grantMonsterUpgrade(player, definition)
		else
			grant, grantReason = grantVehicleCrate(player, definition)
		end
		if not grant then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		PurchaseStateService.MarkProcessed(player, purchaseId)
		if definition.Kind == "MonsterUpgradeToMax" then
			PurchaseStateService.ClearPendingMonsterUpgrade(player)
		end
		local payload = {
			Kind = PaidPurchaseProtocol.ResultKinds.PurchaseGranted,
			ProductKind = definition.Kind,
			PurchaseId = purchaseId,
		}
		if definition.Kind == "MonsterUpgradeToMax" then
			payload.SpawnPointId = grant.SpawnPointId
			payload.TargetLevel = grant.TargetLevel
		else
			payload.CrateId = grant.Purchase.CrateId
			payload.DrawCount = grant.Purchase.DrawCount
			payload.Rewards = grant.Rewards
		end
		pendingPayloads[purchaseId] = payload
		pendingCommits[purchaseId] = true
		local committed, commitReason = commitCurrentState(player)
		if not committed then
			warn(string.format(
				"付费购买发放后等待存档：%s/%s (%s)",
				player.Name,
				purchaseId,
				tostring(commitReason or grantReason)
			))
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		pendingCommits[purchaseId] = nil
		pendingPayloads[purchaseId] = nil
		notifyPurchaseGranted(player, payload)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end, debug.traceback)

	receiptBusy[player] = nil
	if not succeeded then
		warn(string.format("ProcessReceipt 处理异常：%s (%s)", player.Name, tostring(decisionOrError)))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return decisionOrError
end

local function onRequest(player: Player, requestKind, spawnPointId, productId)
	if requestKind == PaidPurchaseProtocol.RequestKinds.CancelMonsterUpgrade then
		return cancelMonsterUpgrade(player, spawnPointId, productId)
	end
	if requestKind ~= PaidPurchaseProtocol.RequestKinds.PrepareMonsterUpgrade then
		return { Succeeded = false, Reason = "InvalidRequestKind", ProductId = 0 }
	end
	return prepareMonsterUpgrade(player, spawnPointId)
end

function PaidPurchaseService.Start()
	if started then
		return
	end
	started = true
	resultRemote = ServerRemoteAccess.EnsureEvent(PaidPurchaseProtocol.ResultRemoteName)
	local requestRemote = ServerRemoteAccess.EnsureFunction(PaidPurchaseProtocol.RequestRemoteName)
	requestRemote.OnServerInvoke = onRequest
	MarketplaceService.ProcessReceipt = processReceipt
	Players.PlayerRemoving:Connect(function(player)
		receiptBusy[player] = nil
		pendingReceiptCommits[player] = nil
		pendingReceiptPayloads[player] = nil
	end)
	Players.PlayerAdded:Connect(function(player)
		task.defer(refreshPaidRandomItemsPolicy, player)
	end)
	for _, player in Players:GetPlayers() do
		task.defer(refreshPaidRandomItemsPolicy, player)
	end
end

function PaidPurchaseService.IsBusy(player: Player): boolean
	return receiptBusy[player] == true
end

return PaidPurchaseService
