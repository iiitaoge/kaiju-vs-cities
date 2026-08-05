--[[
	职责：
	- 只为本地玩家自己 Plot 中的服务器权威建筑维护收入触碰交互。

	输入：
	- Start；场景输入来自 Workspace/PlayerPlots/<OwnPlot>/Runtime/Buildings。

	输出：
	- 每个合法自有建筑拥有一个本地触碰绑定；建筑替换或删除时自动解绑。

	内部算法：
	- 等待 OwnerUserId 与 LocalPlayer 一致的 Plot。
	- 监听 Buildings 子项增删，并用运行时身份 Attribute 二次确认归属。

	不负责：
	- 不给其他玩家建筑绑定触碰，不计算收入，不验证服务器位置。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RuntimeBuildingIdentity = require(ReplicatedStorage.Shared.Building.RuntimeBuildingIdentity)
local LocalBuildingInteractionController = require(script.Parent.LocalBuildingInteractionController)
local LocalPlayerCityRuntimeAccess = require(script.Parent.LocalPlayerCityRuntimeAccess)
local LocalRuntimeBuildingReadiness = require(script.Parent.LocalRuntimeBuildingReadiness)

local LocalPlayerBuildingInteractionCoordinator = {}

local activeHandles: { [Model]: any } = setmetatable({}, { __mode = "k" })
local pendingModels: { [Model]: boolean } = setmetatable({}, { __mode = "k" })
local started = false

local function unbind(model: Model)
	local handle = activeHandles[model]
	activeHandles[model] = nil
	if handle then
		handle:Destroy()
	end
end

local function bindReady(model: Model, identity: RuntimeBuildingIdentity.Identity)
	if activeHandles[model] then
		return
	end
	activeHandles[model] = LocalBuildingInteractionController.Bind(identity.HouseId, model)
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
					"运行时房屋触碰绑定等待失败：%s (%s)",
					model:GetFullName(),
					reason or "Unknown"
				))
			end
			return
		end
		bindReady(model, ready.Identity)
	end)
end

local function waitForOwnPlot(): Model?
	while Players.LocalPlayer.Parent do
		local plot = LocalPlayerCityRuntimeAccess.FindPlot(Players.LocalPlayer.UserId)
		if plot then
			return plot
		end
		task.wait()
	end
	return nil
end

local function attach()
	local plot = waitForOwnPlot()
	if not plot then
		return
	end
	local runtime = plot:WaitForChild("Runtime")
	assert(runtime:IsA("Folder"), "Own Plot Runtime 必须是 Folder")
	local buildings = runtime:WaitForChild("Buildings")
	assert(buildings:IsA("Folder"), "Own Plot Runtime/Buildings 必须是 Folder")

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

function LocalPlayerBuildingInteractionCoordinator.Start()
	if started then
		return
	end
	started = true
	task.spawn(attach)
end

return LocalPlayerBuildingInteractionCoordinator
