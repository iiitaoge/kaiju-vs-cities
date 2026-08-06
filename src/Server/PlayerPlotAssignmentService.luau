--[[
	职责：
	- 把在线玩家分配到 Workspace/PlayerPlots 下预先放置的固定 Plot。
	- 以 Plot 的 OwnerUserId Attribute 保存服务器权威占用关系。
	- 始终把一块未占用 Plot 留在 Workspace 展示，其余空 Plot 停放到 ServerStorage。
	- 分配时优先使用 ServerStorage 中的空 Plot，容量将满时才分配展示 Plot。

	场景合同：
	- PlayerPlots (Folder)
		- <PlotId> (Model)
			- Origin (BasePart)
			- AttackViewBounds (BasePart)
			- Zones (Folder)
			- Runtime (Folder；内部全部可由服务器清空重建)

	输入：
	- Assign/GetPlot/Release：Player。

	输出：
	- Assign/GetPlot：Plot Model，失败时附原因。
	- Release：是否释放成功。
	- GetDisplayedAvailablePlot：当前留在 Workspace 的唯一空 Plot。

	内部算法：
	- 合并 Workspace 活跃 Plot 与 ServerStorage 空闲池，按 PlotId 稳定排序。
	- 选择空 Plot 时先取空闲池，池耗尽后才取 Workspace 展示 Plot。
	- 分配或释放后重新维持“有剩余容量时恰好展示一块空 Plot”的不变量。
	- 分配和释放时清空 Runtime，永远不修改 Zones 等静态场景。
]]

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local PlayerRuntimeLoadReporter = require(
	script.Parent.Analytics.PlayerRuntimeLoadReporter
)

local PlayerPlotAssignmentService = {}

local ROOT_NAME = "PlayerPlots"
local AVAILABLE_POOL_NAME = "AvailablePlayerPlots"
local OWNER_ATTRIBUTE = "OwnerUserId"

local assignments: { [Player]: Model } = setmetatable({}, { __mode = "k" })
local started = false

local function assertPlayer(player: Player)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
end

local function getRoot(): Folder?
	local root = workspace:FindFirstChild(ROOT_NAME)
	return if root and root:IsA("Folder") then root else nil
end

local function getAvailablePool(): Folder
	local existing = ServerStorage:FindFirstChild(AVAILABLE_POOL_NAME)
	if existing then
		assert(
			existing:IsA("Folder"),
			"ServerStorage/" .. AVAILABLE_POOL_NAME .. " 必须是 Folder"
		)
		return existing
	end
	local pool = Instance.new("Folder")
	pool.Name = AVAILABLE_POOL_NAME
	pool.Parent = ServerStorage
	return pool
end

local function checkPlot(instance: Instance): (Model?, string?)
	if not instance:IsA("Model") then
		return nil, "PlotNotModel"
	end

	local origin = instance:FindFirstChild("Origin")
	local attackViewBounds = instance:FindFirstChild("AttackViewBounds")
	local zones = instance:FindFirstChild("Zones")
	local runtime = instance:FindFirstChild("Runtime")
	if not origin or not origin:IsA("BasePart") then
		return nil, "MissingOrigin"
	end
	if not attackViewBounds or not attackViewBounds:IsA("BasePart") then
		return nil, "MissingAttackViewBounds"
	end
	if not zones or not zones:IsA("Folder") then
		return nil, "MissingZones"
	end
	if not runtime or not runtime:IsA("Folder") then
		return nil, "MissingRuntime"
	end

	return instance, nil
end

local function listPlots(): { Model }
	local root = getRoot()
	local plots = {}
	local containers = { getAvailablePool() }
	if root then
		table.insert(containers, root)
	end
	for _, container in containers do
		for _, child in container:GetChildren() do
			local plot = checkPlot(child)
			if plot then
				table.insert(plots, plot)
			end
		end
	end
	table.sort(plots, function(a, b)
		return a.Name < b.Name
	end)
	return plots
end

local function activate(plot: Model): (boolean, string?)
	local root = getRoot()
	if not root then
		return false, "PlotRootUnavailable"
	end
	plot.Parent = root
	return true, nil
end

local function park(plot: Model)
	plot.Parent = getAvailablePool()
end

local function getOwnerUserId(plot: Model): number
	local value = plot:GetAttribute(OWNER_ATTRIBUTE)
	-- Studio 多客户端测试可能使用负 UserId；仅 0 表示未分配。
	return if type(value) == "number" and value % 1 == 0 and value ~= 0 then value else 0
end

local function clearRuntime(plot: Model)
	local runtime = plot:FindFirstChild("Runtime")
	if not runtime or not runtime:IsA("Folder") then
		return
	end
	for _, child in runtime:GetChildren() do
		child:Destroy()
	end
end

-- 输入：当前全部合法 Plot。
-- 输出：有剩余容量时，Workspace 中按名称最小的唯一空 Plot；满员时返回 nil。
-- 内部算法：优先保留已经展示的空 Plot，停放多余展示 Plot；若没有则激活第一个空 Plot。
local function ensureSingleDisplayedAvailablePlot(): Model?
	local root = getRoot()
	if not root then
		return nil
	end

	local availablePlots = {}
	local displayedPlots = {}
	for _, plot in listPlots() do
		if getOwnerUserId(plot) == 0 then
			table.insert(availablePlots, plot)
			if plot.Parent == root then
				table.insert(displayedPlots, plot)
			end
		end
	end
	if #availablePlots == 0 then
		return nil
	end

	local displayed = displayedPlots[1]
	if not displayed then
		displayed = availablePlots[1]
		local activated, reason = activate(displayed)
		assert(activated, reason)
	end
	for _, plot in displayedPlots do
		if plot ~= displayed then
			park(plot)
		end
	end
	return displayed
end

local function findOwnedPlot(player: Player): Model?
	local indexed = assignments[player]
	if indexed and indexed.Parent and getOwnerUserId(indexed) == player.UserId then
		return indexed
	end
	assignments[player] = nil

	for _, plot in listPlots() do
		if getOwnerUserId(plot) == player.UserId then
			assignments[player] = plot
			return plot
		end
	end
	return nil
end

function PlayerPlotAssignmentService.Assign(player: Player): (Model?, string?)
	assertPlayer(player)
	if player.Parent ~= Players then
		return nil, "PlayerUnavailable"
	end

	local owned = findOwnedPlot(player)
	if owned then
		return owned, nil
	end
	if not getRoot() then
		return nil, "PlotRootUnavailable"
	end

	local plots = listPlots()
	if #plots == 0 then
		return nil, "NoValidPlot"
	end
	local availablePool = getAvailablePool()
	local selected = nil
	for _, plot in plots do
		if getOwnerUserId(plot) == 0 and plot.Parent == availablePool then
			selected = plot
			break
		end
	end
	if not selected then
		for _, plot in plots do
			if getOwnerUserId(plot) == 0 then
				selected = plot
				break
			end
		end
	end
	if selected then
		clearRuntime(selected)
		selected:SetAttribute(OWNER_ATTRIBUTE, player.UserId)
		local activated, activateReason = activate(selected)
		if not activated then
			selected:SetAttribute(OWNER_ATTRIBUTE, 0)
			return nil, activateReason
		end
		assignments[player] = selected
		ensureSingleDisplayedAvailablePlot()
		return selected, nil
	end

	return nil, "NoAvailablePlot"
end

function PlayerPlotAssignmentService.GetPlot(player: Player): (Model?, string?)
	assertPlayer(player)
	local plot = findOwnedPlot(player)
	if plot then
		return plot, nil
	end
	return nil, "PlayerHasNoPlot"
end

function PlayerPlotAssignmentService.GetDisplayedAvailablePlot(): (Model?, string?)
	local root = getRoot()
	if not root then
		return nil, "PlotRootUnavailable"
	end
	for _, plot in listPlots() do
		if plot.Parent == root and getOwnerUserId(plot) == 0 then
			return plot, nil
		end
	end
	return nil, "NoDisplayedAvailablePlot"
end

function PlayerPlotAssignmentService.Release(player: Player): boolean
	assertPlayer(player)
	local plot = findOwnedPlot(player)
	assignments[player] = nil
	if not plot or getOwnerUserId(plot) ~= player.UserId then
		return false
	end

	clearRuntime(plot)
	plot:SetAttribute(OWNER_ATTRIBUTE, 0)
	park(plot)
	ensureSingleDisplayedAvailablePlot()
	return true
end

function PlayerPlotAssignmentService.Start()
	if started then
		return
	end
	started = true

	local claimedUserIds = {}
	for _, plot in listPlots() do
		local ownerUserId = getOwnerUserId(plot)
		local player = if ownerUserId ~= 0 then Players:GetPlayerByUserId(ownerUserId) else nil
		if not player or claimedUserIds[ownerUserId] then
			clearRuntime(plot)
			plot:SetAttribute(OWNER_ATTRIBUTE, 0)
			park(plot)
		else
			claimedUserIds[ownerUserId] = true
			local activated, reason = activate(plot)
			assert(activated, reason)
			assignments[player] = plot
		end
	end
	ensureSingleDisplayedAvailablePlot()

	Players.PlayerAdded:Connect(function(player)
		local plot, reason = PlayerPlotAssignmentService.Assign(player)
		PlayerRuntimeLoadReporter.Report(player, "Plot", plot ~= nil, reason)
		if reason and reason ~= "PlotRootUnavailable" then
			warn(string.format("玩家 %s 分配 Plot 失败：%s", player.Name, reason))
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		PlayerPlotAssignmentService.Release(player)
	end)

	for _, player in Players:GetPlayers() do
		local plot, reason = PlayerPlotAssignmentService.Assign(player)
		PlayerRuntimeLoadReporter.Report(player, "Plot", plot ~= nil, reason)
		if reason and reason ~= "PlotRootUnavailable" then
			warn(string.format("玩家 %s 分配 Plot 失败：%s", player.Name, reason))
		end
	end
end

return PlayerPlotAssignmentService
