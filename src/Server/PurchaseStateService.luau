--[[
	职责：维护付费收据幂等记录和怪兽定向购买意图。
	输入：Player；Restore/Capture 接收持久化 Purchases 数据；Pending 接收目标 SpawnPointId。
	输出：已处理 PurchaseId 查询、当前怪兽待处理目标和可序列化 Purchases 数据。
	内部算法：使用 ServerStorage 玩家状态树保存已处理收据；付费怪兽购买前先写入并持久化唯一目标。
	不负责：商品价格、收据回调、商品发放、随机抽取或 UI。
]]

local PlayerStateService = require(script.Parent.PlayerStateService)

local PurchaseStateService = {}

local SECTION_NAME = "Purchases"
local PROCESSED_FOLDER_NAME = "ProcessedPurchaseIds"
local PENDING_FOLDER_NAME = "PendingMonsterUpgrade"
local PENDING_PRODUCT_ID_ATTRIBUTE = "ProductId"
local PENDING_SPAWN_POINT_ID_ATTRIBUTE = "SpawnPointId"

local function assertPlayer(player: Player)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
end

local function assertPurchaseId(purchaseId: string)
	assert(type(purchaseId) == "string" and purchaseId ~= "", "purchaseId 必须是非空字符串")
	assert(
		#purchaseId <= 128 and string.match(purchaseId, "^[A-Za-z0-9_.%-]+$") ~= nil,
		"purchaseId 格式无效"
	)
end

local function getFolders(player: Player): (Folder, Folder, Folder)
	assertPlayer(player)
	local section = PlayerStateService.GetSection(player, SECTION_NAME)
	local processed = section:FindFirstChild(PROCESSED_FOLDER_NAME)
	if not processed then
		processed = Instance.new("Folder")
		processed.Name = PROCESSED_FOLDER_NAME
		processed.Parent = section
	end
	assert(processed:IsA("Folder"), "ProcessedPurchaseIds 必须是 Folder")

	local pending = section:FindFirstChild(PENDING_FOLDER_NAME)
	if not pending then
		pending = Instance.new("Folder")
		pending.Name = PENDING_FOLDER_NAME
		pending.Parent = section
	end
	assert(pending:IsA("Folder"), "PendingMonsterUpgrade 必须是 Folder")
	return section, processed, pending
end

local function clearPendingFolder(pending: Folder)
	pending:SetAttribute(PENDING_PRODUCT_ID_ATTRIBUTE, nil)
	pending:SetAttribute(PENDING_SPAWN_POINT_ID_ATTRIBUTE, nil)
end

function PurchaseStateService.Restore(player: Player, data)
	local _, processed, pending = getFolders(player)
	for _, child in processed:GetChildren() do
		child:Destroy()
	end
	clearPendingFolder(pending)

	if type(data) ~= "table" then
		return
	end
	if type(data.ProcessedPurchaseIds) == "table" then
		for purchaseId, handled in data.ProcessedPurchaseIds do
			if handled == true
				and type(purchaseId) == "string"
				and #purchaseId <= 128
				and string.match(purchaseId, "^[A-Za-z0-9_.%-]+$") ~= nil
			then
				local marker = Instance.new("BoolValue")
				marker.Name = purchaseId
				marker.Value = true
				marker.Parent = processed
			end
		end
	end

	local pendingData = data.PendingMonsterUpgrade
	if type(pendingData) == "table"
		and type(pendingData.ProductId) == "number"
		and pendingData.ProductId > 0
		and pendingData.ProductId % 1 == 0
		and type(pendingData.SpawnPointId) == "string"
		and pendingData.SpawnPointId ~= ""
	then
		pending:SetAttribute(PENDING_PRODUCT_ID_ATTRIBUTE, pendingData.ProductId)
		pending:SetAttribute(PENDING_SPAWN_POINT_ID_ATTRIBUTE, pendingData.SpawnPointId)
	end
end

function PurchaseStateService.Capture(player: Player)
	local _, processed, pending = getFolders(player)
	local processedPurchaseIds = {}
	for _, child in processed:GetChildren() do
		if child:IsA("BoolValue") and child.Value == true then
			processedPurchaseIds[child.Name] = true
		end
	end

	local productId = pending:GetAttribute(PENDING_PRODUCT_ID_ATTRIBUTE)
	local spawnPointId = pending:GetAttribute(PENDING_SPAWN_POINT_ID_ATTRIBUTE)
	local pendingMonsterUpgrade = nil
	if type(productId) == "number"
		and productId > 0
		and productId % 1 == 0
		and type(spawnPointId) == "string"
		and spawnPointId ~= ""
	then
		pendingMonsterUpgrade = {
			ProductId = productId,
			SpawnPointId = spawnPointId,
		}
	end

	return {
		ProcessedPurchaseIds = processedPurchaseIds,
		PendingMonsterUpgrade = pendingMonsterUpgrade,
	}
end

function PurchaseStateService.IsProcessed(player: Player, purchaseId: string): boolean
	assertPurchaseId(purchaseId)
	local _, processed = getFolders(player)
	local marker = processed:FindFirstChild(purchaseId)
	return marker ~= nil and marker:IsA("BoolValue") and marker.Value == true
end

function PurchaseStateService.MarkProcessed(player: Player, purchaseId: string)
	assertPurchaseId(purchaseId)
	local _, processed = getFolders(player)
	if PurchaseStateService.IsProcessed(player, purchaseId) then
		return
	end
	local marker = Instance.new("BoolValue")
	marker.Name = purchaseId
	marker.Value = true
	marker.Parent = processed
end

function PurchaseStateService.GetPendingMonsterUpgrade(player: Player)
	local _, _, pending = getFolders(player)
	local productId = pending:GetAttribute(PENDING_PRODUCT_ID_ATTRIBUTE)
	local spawnPointId = pending:GetAttribute(PENDING_SPAWN_POINT_ID_ATTRIBUTE)
	if type(productId) ~= "number"
		or productId <= 0
		or productId % 1 ~= 0
		or type(spawnPointId) ~= "string"
		or spawnPointId == ""
	then
		return nil
	end
	return {
		ProductId = productId,
		SpawnPointId = spawnPointId,
	}
end

function PurchaseStateService.SetPendingMonsterUpgrade(
	player: Player,
	spawnPointId: string,
	productId: number
)
	assert(type(spawnPointId) == "string" and spawnPointId ~= "", "spawnPointId 必须是非空字符串")
	assert(type(productId) == "number" and productId > 0 and productId % 1 == 0, "productId 无效")
	local _, _, pending = getFolders(player)
	pending:SetAttribute(PENDING_PRODUCT_ID_ATTRIBUTE, productId)
	pending:SetAttribute(PENDING_SPAWN_POINT_ID_ATTRIBUTE, spawnPointId)
end

function PurchaseStateService.ClearPendingMonsterUpgrade(player: Player)
	local _, _, pending = getFolders(player)
	clearPendingFolder(pending)
end

return PurchaseStateService
