--[[
	职责：为所有玩家的出征/守城怪兽和正在被攻击的房屋维护本地战斗血条。
	输入：Start；只读运行时 Model 上的服务器复制 Attributes。
	输出：符合显示规则的 Model 各有一个本地 blood Attachment。
	内部算法：观察 PlayerPlots 全部运行时 Model，按身份绑定并仅在相关 Attribute 变化时刷新。
	不负责：伤害、攻击目标所有权、房屋生命周期或修改模板。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatHealthBarPresentationRules = require(
	ReplicatedStorage.Shared.UI.CombatHealthBarPresentationRules
)
local CombatHealthBarProtocol = require(
	ReplicatedStorage.Shared.UI.CombatHealthBarProtocol
)
local IncomeHouseWorldUIProtocol = require(
	ReplicatedStorage.Shared.Building.IncomeHouseWorldUIProtocol
)
local LocalCombatHealthBarUI = require(script.Parent.LocalCombatHealthBarUI)

local CombatHealthBarController = {}

local activeHandles: { [Model]: any } = setmetatable({}, { __mode = "k" })
local pendingBindings: { [Model]: { RBXScriptConnection } } = setmetatable({}, { __mode = "k" })
local started = false

local function hasBasePart(model: Model): boolean
	if model.PrimaryPart then
		return true
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			return true
		end
	end
	return false
end

local function resolveKind(model: Model): "Monster" | "House" | nil
	if type(model:GetAttribute("MonsterOwnerUserId")) == "number"
		and type(model:GetAttribute("MonsterSpawnPointId")) == "string"
	then
		return "Monster"
	end
	if type(model:GetAttribute("BuildingOwnerUserId")) == "number"
		and type(model:GetAttribute("BuildingHouseId")) == "string"
	then
		return "House"
	end
	return nil
end

local function unbind(model: Model)
	local pending = pendingBindings[model]
	pendingBindings[model] = nil
	if pending then
		for _, connection in pending do
			connection:Disconnect()
		end
	end
	local binding = activeHandles[model]
	activeHandles[model] = nil
	if binding then
		binding:Destroy()
	end
end

local function bind(model: Model)
	if activeHandles[model] or not model.Parent then
		return
	end
	local kind = resolveKind(model)
	if not kind or not hasBasePart(model) then
		return
	end
	local pending = pendingBindings[model]
	pendingBindings[model] = nil
	if pending then
		for _, connection in pending do
			connection:Disconnect()
		end
	end

	local worldUI = LocalCombatHealthBarUI.Create(
		model,
		CombatHealthBarProtocol.LocalAttachmentName
	)
	local connections = {}
	local destroyed = false

	local function refresh()
		if destroyed or not model.Parent then
			return
		end
		if kind == "Monster" then
			worldUI:Apply(CombatHealthBarPresentationRules.ResolveMonster({
				State = model:GetAttribute(CombatHealthBarProtocol.MonsterStateAttributeName),
				CurrentHealth = model:GetAttribute(CombatHealthBarProtocol.MonsterCurrentHealthAttributeName),
				MaxHealth = model:GetAttribute(CombatHealthBarProtocol.MonsterMaxHealthAttributeName),
			}))
		else
			worldUI:Apply(CombatHealthBarPresentationRules.ResolveHouse({
				LifeState = model:GetAttribute(IncomeHouseWorldUIProtocol.LifeStateAttributeName),
				ActiveAttackCount = model:GetAttribute(
					CombatHealthBarProtocol.HouseActiveAttackCountAttributeName
				),
				CurrentHealth = model:GetAttribute(IncomeHouseWorldUIProtocol.CurrentHealthAttributeName),
				MaxHealth = model:GetAttribute(IncomeHouseWorldUIProtocol.MaxHealthAttributeName),
			}))
		end
	end

	local handle = {} :: any
	function handle:Destroy()
		if destroyed then
			return
		end
		destroyed = true
		for _, connection in connections do
			connection:Disconnect()
		end
		worldUI:Destroy()
	end
	activeHandles[model] = handle

	local observedAttributes = if kind == "Monster"
		then {
			CombatHealthBarProtocol.MonsterStateAttributeName,
			CombatHealthBarProtocol.MonsterCurrentHealthAttributeName,
			CombatHealthBarProtocol.MonsterMaxHealthAttributeName,
		}
		else {
			IncomeHouseWorldUIProtocol.LifeStateAttributeName,
			CombatHealthBarProtocol.HouseActiveAttackCountAttributeName,
			IncomeHouseWorldUIProtocol.CurrentHealthAttributeName,
			IncomeHouseWorldUIProtocol.MaxHealthAttributeName,
		}
	for _, attributeName in observedAttributes do
		table.insert(connections, model:GetAttributeChangedSignal(attributeName):Connect(refresh))
	end
	table.insert(connections, model.Destroying:Connect(function()
		unbind(model)
	end))
	refresh()
end

local function scheduleBind(instance: Instance)
	if not instance:IsA("Model") or activeHandles[instance] or pendingBindings[instance] then
		return
	end
	local connections = {}
	pendingBindings[instance] = connections
	local function tryBind()
		if not instance.Parent then
			unbind(instance)
			return
		end
		bind(instance)
	end
	table.insert(connections, instance.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			tryBind()
		end
	end))
	table.insert(connections, instance.AttributeChanged:Connect(tryBind))
	table.insert(connections, instance.Destroying:Connect(function()
		unbind(instance)
	end))
	task.defer(function()
		tryBind()
	end)
end

function CombatHealthBarController.Start()
	if started then
		return
	end
	started = true

	local playerPlots = workspace:WaitForChild("PlayerPlots")
	for _, descendant in playerPlots:GetDescendants() do
		scheduleBind(descendant)
	end
	playerPlots.DescendantAdded:Connect(scheduleBind)
	playerPlots.DescendantRemoving:Connect(function(descendant)
		if descendant:IsA("Model") then
			unbind(descendant)
		end
	end)
end

return CombatHealthBarController
