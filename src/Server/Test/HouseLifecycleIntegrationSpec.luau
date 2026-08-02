--[[
	职责：验收正式房屋状态、收入、攻击访问、运行时模型和自动重建的服务器组装。
	输入：已经加入测试服务器并分配 Plot 的 Player。
	输出：最新 Zone 等级重建与完整约束均通过时返回 true。
	内部算法：准备一栋正式房屋，走正式攻击访问摧毁，等待定时重建后验证状态和 Model。
	不负责：不执行怪兽移动、不发奖励、不验证客户端动画像素效果。
]]

local Players = game:GetService("Players")

local HouseIncomeService = require(script.Parent.Parent.HouseIncomeService)
local HouseStateService = require(script.Parent.Parent.HouseStateService)
local PlayerCityRuntimeCoordinator = require(
	script.Parent.Parent.PlayerCityRuntimeCoordinator
)
local PlayerPlotAssignmentService = require(
	script.Parent.Parent.PlayerPlotAssignmentService
)
local PlayerRuntimeHouseAttackAccess = require(
	script.Parent.Parent.PlayerRuntimeHouseAttackAccess
)
local ZoneStateService = require(script.Parent.Parent.ZoneStateService)

local HouseLifecycleIntegrationSpec = {}

local function expect(condition: boolean, message: string)
	assert(condition, "HouseLifecycleIntegrationSpec: " .. message)
end

local function waitFor(predicate: () -> boolean, timeout: number, message: string)
	local deadline = os.clock() + timeout
	repeat
		if predicate() then
			return
		end
		task.wait(0.05)
	until os.clock() >= deadline
	error("HouseLifecycleIntegrationSpec: 等待超时：" .. message)
end

function HouseLifecycleIntegrationSpec.Run(player: Player): boolean
	expect(player.Parent == Players, "player 必须在线")
	local houseId = "R1-H1"
	local zoneId = "R1"

	waitFor(function()
		return PlayerPlotAssignmentService.GetPlot(player) ~= nil
	end, 5, "玩家 Plot 分配")
	ZoneStateService.SetUnlocked(player, zoneId, true)
	ZoneStateService.SetLevel(player, zoneId, 1)
	local state = HouseStateService.Get(player, houseId)
	if state.LifeState == "Unbuilt" then
		local _, built = HouseStateService.Build(player, houseId, os.time())
		expect(built, "正式房屋无法进入 Alive")
	else
		expect(state.LifeState == "Alive", "测试开始时房屋状态不是 Alive")
	end

	local refreshed = PlayerCityRuntimeCoordinator.RefreshZone(player, zoneId)
	expect(refreshed.Succeeded, refreshed.Reason or "无法创建正式运行时建筑")
	local initialModel = PlayerCityRuntimeCoordinator.ResolveBuilding(player, houseId)
	expect(initialModel ~= nil, "找不到初始运行时建筑")
	expect(initialModel:GetAttribute("BuildingLevel") == 1, "初始建筑等级不是 1")
	expect(HouseIncomeService.GetHouseRate(player, houseId).Accepted, "Alive 房屋没有产钱")

	local prepared, prepareReason = PlayerRuntimeHouseAttackAccess.PrepareDestroy(player, houseId)
	expect(prepared, prepareReason or "摧毁前收入结算失败")
	local destroyed, destroyReason = PlayerRuntimeHouseAttackAccess.Destroy(player, houseId)
	expect(destroyed, destroyReason or "正式攻击访问未能摧毁房屋")
	local destroyedState = HouseStateService.Get(player, houseId)
	expect(destroyedState.LifeState == "Destroyed", "摧毁后状态不是 Destroyed")
	expect(type(destroyedState.RespawnAt) == "number", "摧毁后没有 RespawnAt")
	expect(PlayerCityRuntimeCoordinator.ResolveBuilding(player, houseId) == nil, "摧毁后 Model 仍存在")
	expect(not HouseIncomeService.GetHouseRate(player, houseId).Accepted, "Destroyed 房屋仍在产钱")
	local target, targetReason = PlayerRuntimeHouseAttackAccess.ResolveAliveTarget(player, houseId)
	expect(target == nil and targetReason == "HouseNotAlive", "Destroyed 房屋仍可成为攻击目标")

	-- 模拟摧毁等待期间升级 Zone；自动重建必须读取这里的最新等级。
	ZoneStateService.SetLevel(player, zoneId, 2)
	waitFor(function()
		return HouseStateService.Get(player, houseId).LifeState == "Rebuilding"
	end, 15, "进入 Rebuilding")

	-- 模拟重建动画期间发生 Zone 权威刷新；正在重建的 Model 会被清除，
	-- 生命周期必须回退到 Destroyed 并按最新等级重试，不能卡死。
	local interruptedRefresh = PlayerCityRuntimeCoordinator.RefreshZone(player, zoneId)
	expect(interruptedRefresh.Succeeded, interruptedRefresh.Reason or "重建期间 Zone 刷新失败")
	expect(PlayerCityRuntimeCoordinator.ResolveBuilding(player, houseId) == nil, "Zone 刷新没有中断重建 Model")
	waitFor(function()
		return HouseStateService.Get(player, houseId).LifeState == "Alive"
	end, 10, "中断后的自动重建完成")

	local rebuiltModel = PlayerCityRuntimeCoordinator.ResolveBuilding(player, houseId)
	expect(rebuiltModel ~= nil and rebuiltModel.Parent ~= nil, "重建后权威 Model 不存在")
	expect(rebuiltModel ~= initialModel, "重建后仍使用旧 Model")
	expect(rebuiltModel:GetAttribute("BuildingLevel") == 2, "没有使用 Zone 最新等级重建")
	expect(HouseIncomeService.GetHouseRate(player, houseId).Accepted, "重建完成后没有恢复产钱")
	expect(PlayerRuntimeHouseAttackAccess.ResolveAliveTarget(player, houseId) ~= nil, "重建完成后不可攻击")
	return true
end

return HouseLifecycleIntegrationSpec
