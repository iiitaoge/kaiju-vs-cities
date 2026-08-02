--[[
	职责：
	- 保存每栋房屋独立的运行时状态。

	输入：
	- player、houseId。
	- Build / Revive 可选 now。
	- Destroy 可选 respawnAt。
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

local PlayerStateService = require(script.Parent.PlayerStateService)

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

-- 三种状态切换 Build	Destroy		Revive
function HouseStateService.Build(player: Player, houseId: string, now: number?)
	local state = getState(player, houseId)
	if state:GetAttribute("LifeState") ~= "Unbuilt" then
		return snapshot(state), false
	end

	state:SetAttribute("LifeState", "Alive")
	state:SetAttribute("LastIncomeAt", now or os.time())
	return snapshot(state), true
end

function HouseStateService.Destroy(player: Player, houseId: string, respawnAt: number?)
	local state = getState(player, houseId)
	if state:GetAttribute("LifeState") ~= "Alive" then
		return snapshot(state), false
	end

	state:SetAttribute("LifeState", "Destroyed")
	state:SetAttribute("LastIncomeAt", nil)
	state:SetAttribute("RespawnAt", respawnAt)
	return snapshot(state), true
end

function HouseStateService.Revive(player: Player, houseId: string, now: number?)
	local state = getState(player, houseId)
	if state:GetAttribute("LifeState") ~= "Destroyed" then
		return snapshot(state), false
	end

	state:SetAttribute("LifeState", "Alive")
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
