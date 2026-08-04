--[[
	职责：按玩家四个怪兽槽的建造顺序显示一个可用的实体建造按钮。
	输入：已分配给玩家的 Plot。
	输出：已建按钮和尚未轮到的按钮隐藏并禁用；当前下一个按钮恢复 Studio 原属性。
	内部算法：S1～S4 按 Catalog 前置关系读取状态，再从 BasePart 持久 Attribute 恢复可见/碰撞/触摸属性。
	不负责：执行购买、修改出生点状态、管理培养罐 UI 或真正销毁静态按钮。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterSpawnPointStateService = require(script.Parent.Parent.MonsterSpawnPointStateService)
local PlotButtonAccess = require(script.Parent.PlotButtonAccess)
local MonsterSpawnPointCatalog = require(
	ReplicatedStorage.Shared.Monster.MonsterSpawnPointCatalog
)

local MonsterBuildButtonPresentationService = {}

type PartDefaults = {
	Transparency: number,
	CanCollide: boolean,
	CanTouch: boolean,
	CanQuery: boolean,
}

type PartWithDefaults = {
	Part: BasePart,
	Defaults: PartDefaults,
}

local DEFAULT_TRANSPARENCY_ATTRIBUTE = "MonsterBuildDefaultTransparency"
local DEFAULT_CAN_COLLIDE_ATTRIBUTE = "MonsterBuildDefaultCanCollide"
local DEFAULT_CAN_TOUCH_ATTRIBUTE = "MonsterBuildDefaultCanTouch"
local DEFAULT_CAN_QUERY_ATTRIBUTE = "MonsterBuildDefaultCanQuery"

local function readDefaults(part: BasePart): (PartDefaults?, string?)
	local transparency = part:GetAttribute(DEFAULT_TRANSPARENCY_ATTRIBUTE)
	local canCollide = part:GetAttribute(DEFAULT_CAN_COLLIDE_ATTRIBUTE)
	local canTouch = part:GetAttribute(DEFAULT_CAN_TOUCH_ATTRIBUTE)
	local canQuery = part:GetAttribute(DEFAULT_CAN_QUERY_ATTRIBUTE)
	if type(transparency) ~= "number" or transparency < 0 or transparency > 1 then
		return nil, "InvalidDefaultTransparency:" .. part:GetFullName()
	end
	if type(canCollide) ~= "boolean" then
		return nil, "InvalidDefaultCanCollide:" .. part:GetFullName()
	end
	if type(canTouch) ~= "boolean" then
		return nil, "InvalidDefaultCanTouch:" .. part:GetFullName()
	end
	if type(canQuery) ~= "boolean" then
		return nil, "InvalidDefaultCanQuery:" .. part:GetFullName()
	end
	return {
		Transparency = transparency,
		CanCollide = canCollide,
		CanTouch = canTouch,
		CanQuery = canQuery,
	}, nil
end

local function setVisible(button: Model, visible: boolean): (boolean, string?)
	local parts: { PartWithDefaults } = {}
	for _, descendant in button:GetDescendants() do
		if not descendant:IsA("BasePart") then
			continue
		end
		local defaults, reason = readDefaults(descendant)
		if not defaults then
			return false, reason
		end
		table.insert(parts, {
			Part = descendant,
			Defaults = defaults,
		})
	end
	if #parts == 0 then
		return false, "ButtonHasNoBaseParts:" .. button:GetFullName()
	end

	button:SetAttribute("MonsterBuildButtonVisible", visible)
	for _, item in parts do
		local descendant = item.Part
		local defaults = item.Defaults
		if visible then
			descendant.Transparency = defaults.Transparency
			descendant.CanCollide = defaults.CanCollide
			descendant.CanTouch = defaults.CanTouch
			descendant.CanQuery = defaults.CanQuery
		else
			descendant.Transparency = 1
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end
	return true, nil
end

function MonsterBuildButtonPresentationService.RefreshAll(
	player: Player,
	plot: Model
): (boolean, string?)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	assert(typeof(plot) == "Instance" and plot:IsA("Model"), "plot 必须是 Model")

	for _, definition in MonsterSpawnPointCatalog.GetAll() do
		local buttonName = definition.SpawnPointId .. "-Button"
		local button, _, reason = PlotButtonAccess.Get(
			plot,
			definition.ZoneId,
			buttonName
		)
		if not button then
			return false, (reason or "ButtonUnavailable") .. ":" .. buttonName
		end

		local state = MonsterSpawnPointStateService.Get(player, definition.SpawnPointId)
		local prerequisiteBuilt = definition.RequiredBuiltSpawnPointId == nil
			or MonsterSpawnPointStateService.Get(
				player,
				definition.RequiredBuiltSpawnPointId
			).Built
		local updated, updateReason = setVisible(
			button,
			not state.Built and prerequisiteBuilt
		)
		if not updated then
			return false, updateReason or "ButtonPresentationUnavailable"
		end
	end
	return true, nil
end

return MonsterBuildButtonPresentationService
