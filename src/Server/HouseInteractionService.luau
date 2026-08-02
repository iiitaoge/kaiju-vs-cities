--[[
	职责：
	- 校验玩家与单栋房屋的 Enter / Exit 交互。
	- Enter 成功时只领取目标房屋自己的累计收入。

	输入：
	- player、"Enter" 或 "Exit"、houseId。

	输出：
	- Action、HouseId、Accepted、Reward、Balance、Reason。

	读取：
	- HouseCatalog、HouseStateService、RegionStateService 和房屋空间边界。

	写入：
	- 当前模块内部的进入状态与领取冷却。
	- 通过 HouseIncomeService 结算单栋收入并写入玩家余额。

	内部算法：
	- 客户端只上报 Enter / Exit 意图，服务端始终用房屋边界重新校验。
	- 角色由客户端持有网络所有权，RemoteEvent 可能先于角色位置到达服务端；
	  因此边界状态不匹配时，在一个很短的窗口内等待位置同步后再裁决。

	不负责：
	- 不计算区域收入公式。
	- 不领取区域内其他房屋。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HouseIncomeService = require(script.Parent.HouseIncomeService)
local HouseStateService = require(script.Parent.HouseStateService)
local RegionStateService = require(script.Parent.RegionStateService)
local HouseBoundsResolver = require(ReplicatedStorage.Shared.Building.HouseBoundsResolver)
local HouseCatalog = require(ReplicatedStorage.Shared.Building.HouseCatalog)

local HouseInteractionService = {}

local REWARD_COOLDOWN = 0.1
local POSITION_SYNC_GRACE_SECONDS = 0.35
local POSITION_SYNC_RETRY_SECONDS = 0.05

export type Action = "Enter" | "Exit"

export type Result = {
	Action: Action,
	HouseId: string,
	Accepted: boolean,
	Reward: number,
	Balance: number?,
	Reason: string?,
}

type PlayerInteractionState = {
	Character: Model?,
	Inside: { [string]: boolean },
	LastRewardAt: number?,
}

local statesByPlayer = setmetatable({}, { __mode = "k" })

local function makeResult(
	action: Action,
	houseId: string,
	accepted: boolean,
	reason: string?,
	reward: number?,
	balance: number?
): Result
	return {
		Action = action,
		HouseId = houseId,
		Accepted = accepted,
		Reward = reward or 0,
		Balance = balance,
		Reason = reason,
	}
end

local function getPlayerState(player: Player): PlayerInteractionState
	local character = player.Character
	local state = statesByPlayer[player]
	if not state then
		state = {
			Character = character,
			Inside = {},
			LastRewardAt = nil,
		}
		statesByPlayer[player] = state
	elseif state.Character ~= character then
		state.Character = character
		table.clear(state.Inside)
	end

	return state
end

local function isCharacterInside(
	player: Player,
	target: HouseBoundsResolver.HouseTarget
): boolean
	local character = player.Character
	if not character or not character.Parent then
		return false
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	overlapParams.FilterDescendantsInstances = { character }

	return #workspace:GetPartBoundsInBox(target.CFrame, target.Size, overlapParams) > 0
end

local function waitForBoundaryState(
	player: Player,
	target: HouseBoundsResolver.HouseTarget,
	expectedInside: boolean
): boolean
	local deadline = os.clock() + POSITION_SYNC_GRACE_SECONDS

	while isCharacterInside(player, target) ~= expectedInside do
		if os.clock() >= deadline then
			return false
		end
		task.wait(POSITION_SYNC_RETRY_SECONDS)
	end

	return true
end

function HouseInteractionService.Enter(player: Player, houseId: string): Result
	if type(houseId) ~= "string" or houseId == "" then
		return makeResult("Enter", tostring(houseId), false, "InvalidHouseId")
	end

	local definition = HouseCatalog.Get(houseId)
	if not definition then
		return makeResult("Enter", houseId, false, "UnknownHouse")
	end

	local houseState = HouseStateService.Get(player, houseId)
	if houseState.LifeState ~= "Alive" then
		return makeResult("Enter", houseId, false, "HouseNotAlive")
	end

	local level = RegionStateService.GetLevel(player, definition.RegionId)
	if level <= 0 then
		return makeResult("Enter", houseId, false, "RegionNotBuilt")
	end
	local target = HouseBoundsResolver.Resolve(definition, level)

	local playerState = getPlayerState(player)
	if playerState.Inside[houseId] then
		return makeResult("Enter", houseId, false, "AlreadyInside")
	end

	if not waitForBoundaryState(player, target, true) then
		playerState.Inside[houseId] = nil
		return makeResult("Enter", houseId, false, "OutsideHouse")
	end

	-- waitForBoundaryState 会让出当前线程；防止并发的重复 Enter 都通过。
	if playerState.Inside[houseId] then
		return makeResult("Enter", houseId, false, "AlreadyInside")
	end
	playerState.Inside[houseId] = true

	local now = os.clock()
	local lastRewardAt = playerState.LastRewardAt
	if lastRewardAt and now - lastRewardAt < REWARD_COOLDOWN then
		return makeResult("Enter", houseId, false, "Cooldown")
	end

	playerState.LastRewardAt = now
	local collection = HouseIncomeService.CollectHouse(player, houseId, os.time())
	if not collection.Accepted then
		return makeResult(
			"Enter",
			houseId,
			false,
			collection.Reason,
			0,
			collection.Balance
		)
	end

	return makeResult(
		"Enter",
		houseId,
		true,
		nil,
		collection.Collected,
		collection.Balance
	)
end

function HouseInteractionService.Exit(player: Player, houseId: string): Result
	if type(houseId) ~= "string" or houseId == "" then
		return makeResult("Exit", tostring(houseId), false, "InvalidHouseId")
	end

	local definition = HouseCatalog.Get(houseId)
	if not definition then
		return makeResult("Exit", houseId, false, "UnknownHouse")
	end

	local playerState = getPlayerState(player)
	local level = RegionStateService.GetLevel(player, definition.RegionId)
	if level > 0 then
		local target = HouseBoundsResolver.Resolve(definition, level)
		if not waitForBoundaryState(player, target, false) then
			return makeResult("Exit", houseId, false, "StillInside")
		end
	end

	playerState.Inside[houseId] = nil
	return makeResult("Exit", houseId, true, nil)
end

function HouseInteractionService.Handle(player: Player, action: string, houseId: string): Result
	if action == "Enter" then
		return HouseInteractionService.Enter(player, houseId)
	end
	if action == "Exit" then
		return HouseInteractionService.Exit(player, houseId)
	end

	return makeResult("Enter", tostring(houseId), false, "InvalidAction")
end

return HouseInteractionService
