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
	- IncomeZonePrimary：需要 RegionId。
	- IncomeZoneBoost：需要 RegionId。
	- MonsterSpawnPointPrimary：需要 SpawnPointId。
]]

local IncomeZoneActionQuery = require(script.Parent.Parent.IncomeZoneActionQuery)
local IncomeZoneBoostCoordinator = require(script.Parent.Parent.IncomeZoneBoostCoordinator)
local IncomeZoneBoostQuery = require(script.Parent.Parent.IncomeZoneBoostQuery)
local IncomeZonePrimaryCoordinator = require(script.Parent.Parent.IncomeZonePrimaryCoordinator)
local MonsterSpawnPointActionQuery = require(script.Parent.Parent.MonsterSpawnPointActionQuery)
local MonsterSpawnPointPurchaseCoordinator = require(
	script.Parent.Parent.MonsterSpawnPointPurchaseCoordinator
)
local handlers = {
	IncomeZonePrimary = function(player, action)
		local outcome = IncomeZonePrimaryCoordinator.Execute(player, action.RegionId)
		return nil, outcome.NextButtonState
	end,

	IncomeZoneBoost = function(player, action)
		local outcome = IncomeZoneBoostCoordinator.Execute(player, action.RegionId)
		return nil, outcome.NextButtonState
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
	IncomeZonePrimary = function(player, action)
		return IncomeZoneActionQuery.GetPrimaryButtonState(player, action.RegionId)
	end,

	IncomeZoneBoost = function(player, action)
		return IncomeZoneBoostQuery.GetButtonState(player, action.RegionId)
	end,

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
