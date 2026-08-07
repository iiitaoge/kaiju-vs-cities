--[[
	职责：服务器启动时以 Plot01 为模板生成并布局 Plot01-Plot08。

	场景合同：
	- Workspace/PlayerPlots (Folder)
	- Workspace/PlayerPlots/Plot01 (Model；已摆放在目标圆周位置；场景中也兼容 Plot1)

	输入：Start 无参数；布局中心固定为世界原点，数量为 8，角度步长为 45 度。
	输出：Workspace/PlayerPlots 中存在按 Plot01/Origin 绕世界 Y 轴旋转得到的 Plot01-Plot08。
	内部算法：读取 Plot01/Origin CFrame 以及 Origin 到 Model Pivot 的相对变换；对每个序号
	计算世界原点绕 Y 轴的旋转 CFrame，并将相对 Pivot 变换带到目标 Plot；已有目标 Model
	只重定位，缺失目标则由 Plot01 Clone。

	不负责：玩家分配、区域解锁、Runtime 清理或玩家状态。
]]

local PlayerPlotLayoutService = {}

local ROOT_NAME = "PlayerPlots"
local TEMPLATE_NAME = "Plot01"
local LEGACY_TEMPLATE_NAME = "Plot1"
local PLOT_COUNT = 8
local ANGLE_STEP = math.rad(45)

local started = false

local function getRoot(): Folder
	local root = workspace:FindFirstChild(ROOT_NAME)
	assert(root and root:IsA("Folder"), "Workspace/PlayerPlots 必须是 Folder")
	return root
end

local function plotName(index: number): string
	return string.format("Plot%02d", index)
end

local function getOrigin(model: Model): BasePart
	local origin = model:FindFirstChild("Origin")
	assert(origin and origin:IsA("BasePart"), model:GetFullName() .. "/Origin 必须是 BasePart")
	return origin
end

local function getOrClonePlot(root: Folder, template: Model, index: number): Model
	local name = plotName(index)
	local existing = root:FindFirstChild(name)
	if existing then
		assert(existing:IsA("Model"), root:GetFullName() .. "/" .. name .. " 必须是 Model")
		return existing
	end

	local clone = template:Clone()
	clone.Name = name
	return clone
end

function PlayerPlotLayoutService.Start()
	if started then
		return
	end
	started = true

	local root = getRoot()
	local template = root:FindFirstChild(TEMPLATE_NAME)
	if not template then
		template = root:FindFirstChild(LEGACY_TEMPLATE_NAME)
		if template then
			template.Name = TEMPLATE_NAME
		end
	end
	assert(template and template:IsA("Model"), root:GetFullName() .. "/" .. TEMPLATE_NAME .. " 必须是 Model")
	local templateOrigin = getOrigin(template)
	local originToPivot = templateOrigin.CFrame:ToObjectSpace(template:GetPivot())

	for index = 2, PLOT_COUNT do
		local plot = getOrClonePlot(root, template, index)
		local rotation = CFrame.Angles(0, ANGLE_STEP * (index - 1), 0)
		local targetOrigin = rotation * templateOrigin.CFrame
		local targetPivot = targetOrigin * originToPivot
		plot:PivotTo(targetPivot)
		if plot.Parent ~= root then
			plot.Parent = root
		end
	end
end

return PlayerPlotLayoutService
