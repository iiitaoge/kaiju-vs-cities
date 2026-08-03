--[[
	职责：验证所有预放置 Plot 的产钱区域场景是否符合代码合同。
	输入：ValidatePlot 接收 Plot Model；ValidateAll/AssertAll 读取 Workspace/PlayerPlots。
	输出：{ Valid, Errors, PlotCount }；AssertAll 在合同不合法时终止启动。
	内部算法：按 ZoneCatalog 遍历 Income Zone，逐一核对 Zone、Slot、Bounds 和主按钮。
	不负责：修改场景、分配 Plot、读取玩家状态或生成运行时建筑。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ButtonConfigs = require(ReplicatedStorage.Shared.Button.ButtonConfigs)
local ZoneCatalog = require(ReplicatedStorage.Shared.World.ZoneCatalog)

local IncomePlotContractValidator = {}

local function isContainer(instance: Instance?): boolean
	return instance ~= nil and (instance:IsA("Folder") or instance:IsA("Model"))
end

local function add(errors: { string }, condition: boolean, message: string)
	if not condition then
		table.insert(errors, message)
	end
end

local function hasDirectBasePart(container: Instance?): boolean
	if not container then
		return false
	end
	for _, child in container:GetChildren() do
		if child:IsA("BasePart") then
			return true
		end
	end
	return false
end

function IncomePlotContractValidator.ValidatePlot(plot: Model): { string }
	assert(plot:IsA("Model"), "plot 必须是 Model")
	local errors = {}
	local prefix = plot:GetFullName()
	local zones = plot:FindFirstChild("Zones")
	add(errors, zones ~= nil and zones:IsA("Folder"), prefix .. "/Zones 必须是 Folder")
	if not zones or not zones:IsA("Folder") then
		return errors
	end

	for _, definition in ZoneCatalog.GetAll() do
		if definition.Kind ~= "Income" then
			continue
		end

		local zonePrefix = string.format("%s/Zones/%s", prefix, definition.ZoneId)
		local zone = zones:FindFirstChild(definition.ZoneId)
		add(errors, isContainer(zone), zonePrefix .. " 必须是 Model 或 Folder")
		if not isContainer(zone) then
			continue
		end

		local slots = zone:FindFirstChild("Slots")
		local bounds = zone:FindFirstChild("Bounds")
		local buttons = zone:FindFirstChild("Buttons")
		add(errors, isContainer(slots), zonePrefix .. "/Slots 必须是 Model 或 Folder")
		add(errors, isContainer(bounds), zonePrefix .. "/Bounds 必须是 Model 或 Folder")
		add(
			errors,
			isContainer(bounds) and hasDirectBasePart(bounds),
			zonePrefix .. "/Bounds 至少需要一个直接 BasePart 子项"
		)
		add(errors, buttons ~= nil and buttons:IsA("Folder"), zonePrefix .. "/Buttons 必须是 Folder")

		if isContainer(slots) then
			for slotId, slotDefinition in definition.Slots do
				if slotDefinition.Kind ~= "IncomeBuilding" then
					continue
				end
				local point = slots:FindFirstChild(slotId)
				add(
					errors,
					point ~= nil and point:IsA("BasePart"),
					string.format("%s/Slots/%s 必须是 BasePart", zonePrefix, slotId)
				)
			end
		end

		local buttonName = definition.ZoneId .. "-Primary-Button"
		local buttonConfig = ButtonConfigs[buttonName]
		add(
			errors,
			buttonConfig ~= nil
				and buttonConfig.Scope == "PlayerPlot"
				and buttonConfig.ZoneId == definition.ZoneId,
			buttonName .. " 缺少同 Zone 的 PlayerPlot 配置"
		)
		if buttons and buttons:IsA("Folder") then
			local button = buttons:FindFirstChild(buttonName)
			add(errors, button ~= nil and button:IsA("Model"), zonePrefix .. "/Buttons/" .. buttonName .. " 必须是 Model")
			if button and button:IsA("Model") then
				local pull = button:FindFirstChild("Pull")
				local base = button:FindFirstChild("Part")
				add(errors, pull ~= nil and pull:IsA("BasePart"), button:GetFullName() .. "/Pull 必须是 BasePart")
				add(errors, base ~= nil and base:IsA("BasePart"), button:GetFullName() .. "/Part 必须是 BasePart")
			end
		end
	end

	return errors
end

function IncomePlotContractValidator.ValidateAll()
	local errors = {}
	local plotCount = 0
	local root = workspace:FindFirstChild("PlayerPlots")
	add(errors, root ~= nil and root:IsA("Folder"), "Workspace/PlayerPlots 必须是 Folder")
	if not root or not root:IsA("Folder") then
		return { Valid = false, Errors = errors, PlotCount = 0 }
	end

	for _, child in root:GetChildren() do
		if not child:IsA("Model") then
			table.insert(errors, child:GetFullName() .. " 必须是 Plot Model")
			continue
		end
		plotCount += 1
		for _, message in IncomePlotContractValidator.ValidatePlot(child) do
			table.insert(errors, message)
		end
	end
	add(errors, plotCount > 0, "Workspace/PlayerPlots 至少需要一个 Plot")

	return { Valid = #errors == 0, Errors = errors, PlotCount = plotCount }
end

function IncomePlotContractValidator.AssertAll(): boolean
	local result = IncomePlotContractValidator.ValidateAll()
	assert(result.Valid, "产钱 Plot 场景合同无效：\n" .. table.concat(result.Errors, "\n"))
	return true
end

return IncomePlotContractValidator
