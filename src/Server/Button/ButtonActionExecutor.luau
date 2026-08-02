--[[
	职责：
	- 根据按钮 action.Kind 把输入分发给对应业务模块。

	输入：
	- player。
	- ButtonActions 中的一条 action 配置。

	输出：
	- 对应业务模块返回的 clientAction 和按钮状态。

	读取：
	- action.Kind 及该 Kind 需要的字段。

	写入：
	- 本模块不直接写状态；通过业务模块完成。

	支持的 Kind：
	- UnlockRegion：需要 RegionId。
	- UpgradeRegion：需要 RegionId。
	- SetIncomeMultiplier：需要 RegionId、Value。
	- MonsterSpawnPointPrimary：需要 SpawnPointId。
]]

local HouseIncomeService = require(script.Parent.Parent.HouseIncomeService)
local MonsterSpawnPointActionQuery = require(script.Parent.Parent.MonsterSpawnPointActionQuery)
local MonsterSpawnPointPurchaseCoordinator = require(
	script.Parent.Parent.MonsterSpawnPointPurchaseCoordinator
)
local RegionStateService = require(script.Parent.Parent.RegionStateService)
local RegionUpgradeCityCoordinator = require(script.Parent.Parent.RegionUpgradeCityCoordinator)
local RegionUpgradeService = require(script.Parent.Parent.RegionUpgradeService)

local handlers = {
	UnlockRegion = function(player, action)
		return RegionUpgradeService.Unlock(player, action.RegionId)
	end,

	UpgradeRegion = function(player, action)
		return RegionUpgradeCityCoordinator.Upgrade(player, action.RegionId)
	end,

	SetIncomeMultiplier = function(player, action)
		local settlement = HouseIncomeService.SettleRegionHouses(
			player,
			action.RegionId,
			os.time()
		)
		if not settlement.Accepted then
			return nil, "Locked"
		end

		RegionStateService.SetIncomeMultiplier(player, action.RegionId, action.Value)
	end,

	MonsterSpawnPointPrimary = function(player, action)
		local outcome = MonsterSpawnPointPurchaseCoordinator.ExecutePrimary(
			player,
			action.SpawnPointId
		)
		return nil, outcome.NextButtonState
	end,
}

local stateHandlers = {
	MonsterSpawnPointPrimary = function(player, action)
		return MonsterSpawnPointActionQuery.GetPrimaryButtonState(player, action.SpawnPointId)
	end,
}

local ButtonActionExecutor = {}

function ButtonActionExecutor.Run(player, action)
	local handler = assert(
		handlers[action.Kind],
		string.format("未知的服务端按钮 Action Kind：%s", tostring(action.Kind))
	)
	return handler(player, action)
end

function ButtonActionExecutor.GetState(player, action): string?
	local handler = stateHandlers[action.Kind]
	return if handler then handler(player, action) else nil
end

return ButtonActionExecutor
