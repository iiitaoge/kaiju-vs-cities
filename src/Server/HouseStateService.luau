--[[
	职责：
	- 保存每栋房屋独立的运行时状态。

	输入：
	- player、houseId。
	- Build / CompleteRebuild / RollbackDestroy 可选 now。
	- Destroy 可选 respawnAt。
	- BeginRebuild 接收本次计划对应的 expectedRespawnAt。
	- AbortRebuild 接收下一次 respawnAt。
	- CreditStoredMoney 接收已由收入模块算好的 amount 和 settledAt。

	输出：
	- Get / 生命周期操作：房屋状态快照。
	- 状态转换同时返回 changed。
	- TakeStoredMoney 返回取出的金额和清空后的快照。

	读取：
	- PlayerStateService 的 Houses/<HouseId> Attributes。

	写入：
	- PlayerStateService 的房屋 LifeState、StoredMoney、LastIncomeAt、RespawnAt。

	不负责：
	- 不计算收入速率。
	- 不发放玩家余额。
	- Destroy 保留已经产生的 StoredMoney，只停止后续累计。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerStateService = require(script.Parent.PlayerStateService)
local HouseLifecycleRules = require(
	ReplicatedStorage.Shared.Building.HouseLifecycleRules
)

local HouseStateService = {}

local function snapshot(state: Folder)
	return {
		LifeState = state:GetAttribute("LifeState"),
		StoredMoney = state:GetAttribute("StoredMoney"),
		LastIncomeAt = state:GetAttribute("LastIncomeAt"),
		RespawnAt = state:GetAttribute("RespawnAt"),
	}
end

local function getState(player: Player, houseId: string): Folder
	local state = PlayerStateService.GetEntity(player, "Houses", houseId)
	if state:GetAttribute("LifeState") == nil then
		state:SetAttribute("LifeState", "Unbuilt")
	end
	if state:GetAttribute("StoredMoney") == nil then
		state:SetAttribute("StoredMoney", 0)
	end

	return state
end

function HouseStateService.Get(player: Player, houseId: string)
	return snapshot(getState(player, houseId))
end

local function applyTransition(state: Folder, eventKind: string): boolean
	local transition = HouseLifecycleRules.Apply(
		state:GetAttribute("LifeState"),
		eventKind
	)
	if not transition.Accepted then
		return false
	end
	state:SetAttribute("LifeState", transition.NewState)
	return true
end

function HouseStateService.Build(player: Player, houseId: string, now: number?)
	local state = getState(player, houseId)
	if not applyTransition(state, "Build") then
		return snapshot(state), false
	end

	state:SetAttribute("LastIncomeAt", now or os.time())
	state:SetAttribute("RespawnAt", nil)
	return snapshot(state), true
end

function HouseStateService.Destroy(player: Player, houseId: string, respawnAt: number?)
	local state = getState(player, houseId)
	if not applyTransition(state, "Destroy") then
		return snapshot(state), false
	end

	state:SetAttribute("LastIncomeAt", nil)
	state:SetAttribute("RespawnAt", respawnAt)
	return snapshot(state), true
end

-- 输入：摧毁事务失败后的 player、houseId 和恢复计时起点。
-- 输出：仅允许 Destroyed -> Alive；恢复收入但不改变 StoredMoney。
function HouseStateService.RollbackDestroy(player: Player, houseId: string, now: number?)
	local state = getState(player, houseId)
	if not applyTransition(state, "RollbackDestroy") then
		return snapshot(state), false
	end

	state:SetAttribute("LastIncomeAt", now or os.time())
	state:SetAttribute("RespawnAt", nil)
	return snapshot(state), true
end

-- 输入：player、houseId，以及发起本次任务时记录的 RespawnAt。
-- 输出：仅在当前 Destroyed 且计划未被替换时进入 Rebuilding。
function HouseStateService.BeginRebuild(
	player: Player,
	houseId: string,
	expectedRespawnAt: number
)
	local state = getState(player, houseId)
	if state:GetAttribute("RespawnAt") ~= expectedRespawnAt then
		return snapshot(state), false
	end
	if not applyTransition(state, "BeginRebuild") then
		return snapshot(state), false
	end

	state:SetAttribute("RespawnAt", nil)
	return snapshot(state), true
end

-- 输入：重建失败的 player、houseId 和下一次重试时间。
-- 输出：Rebuilding -> Destroyed，并保存新 RespawnAt。
function HouseStateService.AbortRebuild(
	player: Player,
	houseId: string,
	respawnAt: number
)
	local state = getState(player, houseId)
	if not applyTransition(state, "AbortRebuild") then
		return snapshot(state), false
	end

	state:SetAttribute("LastIncomeAt", nil)
	state:SetAttribute("RespawnAt", respawnAt)
	return snapshot(state), true
end

-- 输入：完成重建的 player、houseId 和恢复计时起点。
-- 输出：Rebuilding -> Alive；从完成时重新开始产钱。
function HouseStateService.CompleteRebuild(player: Player, houseId: string, now: number?)
	local state = getState(player, houseId)
	if not applyTransition(state, "CompleteRebuild") then
		return snapshot(state), false
	end

	state:SetAttribute("LastIncomeAt", now or os.time())
	state:SetAttribute("RespawnAt", nil)
	return snapshot(state), true
end

-- 输入：已由 HouseIncomeService 计算完成的非负收入和本次结算时间。
-- 输出：更新后的快照，以及房屋是否处于 Alive 并接受了结算。
function HouseStateService.CreditStoredMoney(
	player: Player,
	houseId: string,
	amount: number,
	settledAt: number
)
	assert(
		type(amount) == "number" and amount == amount and amount < math.huge and amount >= 0,
		"amount 必须是有限非负数"
	)
	assert(
		type(settledAt) == "number"
			and settledAt == settledAt
			and settledAt < math.huge
			and settledAt >= 0,
		"settledAt 必须是有限非负数"
	)

	local state = getState(player, houseId)
	if state:GetAttribute("LifeState") ~= "Alive" then
		return snapshot(state), false
	end

	local storedMoney = state:GetAttribute("StoredMoney") or 0
	state:SetAttribute("StoredMoney", storedMoney + amount)
	state:SetAttribute("LastIncomeAt", settledAt)
	return snapshot(state), true
end

-- 输入：player、houseId。
-- 输出：取出的未领取收入，以及 StoredMoney 清零后的状态快照。
function HouseStateService.TakeStoredMoney(player: Player, houseId: string)
	local state = getState(player, houseId)
	local amount = state:GetAttribute("StoredMoney") or 0
	state:SetAttribute("StoredMoney", 0)
	return amount, snapshot(state)
end

return HouseStateService
