--[[
	职责：只为本地玩家自己的运行时产钱房屋维护 HP 与收入世界 UI。
	输入：Start；状态来自房屋 Model 的服务器镜像 Attributes。
	输出：每栋自有房屋一个本地 Attachment；其他玩家客户端不会创建。
	内部算法：监听自己的 Plot/Runtime/Buildings → 绑定合法身份 → Alive 时按规则刷新。
	不负责：服务器结算、房屋交互、攻击、按钮或其他玩家 UI。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IncomeHouseUIPresentationRules = require(
	ReplicatedStorage.Shared.UI.IncomeHouseUIPresentationRules
)
local IncomeHouseWorldUIProtocol = require(
	ReplicatedStorage.Shared.Building.IncomeHouseWorldUIProtocol
)
local WorldObjectUIPlacement = require(
	ReplicatedStorage.Shared.UI.WorldObjectUIPlacement
)
local LocalPlayerCityRuntimeAccess = require(script.Parent.LocalPlayerCityRuntimeAccess)
local LocalRuntimeBuildingReadiness = require(script.Parent.LocalRuntimeBuildingReadiness)
local LocalWorldObjectUI = require(script.Parent.Parent.UI.LocalWorldObjectUI)

local IncomeHouseWorldUIController = {}

local activeHandles: { [Model]: any } = setmetatable({}, { __mode = "k" })
local pendingModels: { [Model]: boolean } = setmetatable({}, { __mode = "k" })
local started = false

local observedAttributes = {
	IncomeHouseWorldUIProtocol.LifeStateAttributeName,
	IncomeHouseWorldUIProtocol.AutoIncomeAttributeName,
	IncomeHouseWorldUIProtocol.IncomePerSecondAttributeName,
	IncomeHouseWorldUIProtocol.StoredMoneyAttributeName,
	IncomeHouseWorldUIProtocol.LastIncomeAtAttributeName,
	IncomeHouseWorldUIProtocol.CurrentHealthAttributeName,
	IncomeHouseWorldUIProtocol.MaxHealthAttributeName,
}

local function unbind(model: Model)
	local handle = activeHandles[model]
	activeHandles[model] = nil
	if handle then
		handle:Destroy()
	end
end

local function bindReady(model: Model)
	if activeHandles[model] then
		return
	end

	local worldUI = LocalWorldObjectUI.CreateAboveModel(
		model,
		"LocalIncomeHouseWorldUI"
	)
	local connections = {}
	local destroyed = false
	local lastTimedRefresh = 0

	local function refresh()
		if destroyed or not model.Parent then
			return
		end
		worldUI:Apply(IncomeHouseUIPresentationRules.Resolve({
			LifeState = model:GetAttribute(IncomeHouseWorldUIProtocol.LifeStateAttributeName),
			AutoIncome = model:GetAttribute(IncomeHouseWorldUIProtocol.AutoIncomeAttributeName),
			IncomePerSecond = model:GetAttribute(IncomeHouseWorldUIProtocol.IncomePerSecondAttributeName),
			StoredMoney = model:GetAttribute(IncomeHouseWorldUIProtocol.StoredMoneyAttributeName),
			LastIncomeAt = model:GetAttribute(IncomeHouseWorldUIProtocol.LastIncomeAtAttributeName),
			CurrentHealth = model:GetAttribute(IncomeHouseWorldUIProtocol.CurrentHealthAttributeName),
			MaxHealth = model:GetAttribute(IncomeHouseWorldUIProtocol.MaxHealthAttributeName),
			-- 服务端收入用 os.time() 结算；向下取整后客户端显示与实际领取金额一致。
			Now = math.floor(workspace:GetServerTimeNow()),
		}))
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

	for _, attributeName in observedAttributes do
		table.insert(connections, model:GetAttributeChangedSignal(attributeName):Connect(refresh))
	end
	table.insert(connections, model.Destroying:Connect(function()
		unbind(model)
	end))
	table.insert(connections, RunService.Heartbeat:Connect(function()
		if model:GetAttribute(IncomeHouseWorldUIProtocol.AutoIncomeAttributeName) == false
			and os.clock() - lastTimedRefresh >= WorldObjectUIPlacement.AccumulatedMoneyRefreshSeconds
		then
			lastTimedRefresh = os.clock()
			refresh()
		end
	end))
	refresh()
end

local function scheduleBind(model: Model)
	if activeHandles[model] or pendingModels[model] then
		return
	end
	pendingModels[model] = true
	task.spawn(function()
		local ready, reason = LocalRuntimeBuildingReadiness.Wait(
			model,
			Players.LocalPlayer.UserId
		)
		pendingModels[model] = nil
		if not ready then
			if reason ~= "ModelRemoved" and reason ~= "OwnerMismatch" then
				warn(string.format(
					"房屋世界 UI 等待复制失败：%s (%s)",
					model:GetFullName(),
					reason or "Unknown"
				))
			end
			return
		end
		bindReady(model)
	end)
end

local function attach()
	local plot
	repeat
		plot = LocalPlayerCityRuntimeAccess.FindPlot(Players.LocalPlayer.UserId)
		if not plot then
			task.wait()
		end
	until plot or not Players.LocalPlayer.Parent
	if not plot then
		return
	end

	local runtime = plot:WaitForChild("Runtime")
	local buildings = runtime:WaitForChild("Buildings")
	assert(runtime:IsA("Folder") and buildings:IsA("Folder"), "自有 Plot 运行时建筑路径无效")

	for _, child in buildings:GetChildren() do
		if child:IsA("Model") then
			scheduleBind(child)
		end
	end
	buildings.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			scheduleBind(child)
		end
	end)
	buildings.ChildRemoved:Connect(function(child)
		if child:IsA("Model") then
			unbind(child)
		end
	end)
end

function IncomeHouseWorldUIController.Start()
	if started then
		return
	end
	started = true
	task.spawn(attach)
end

return IncomeHouseWorldUIController
