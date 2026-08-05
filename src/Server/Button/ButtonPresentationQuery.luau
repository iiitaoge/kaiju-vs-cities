--[[
	职责：为一个已配置按钮动作生成服务器权威的世界 UI 显示快照。
	输入：Player、ButtonActions 中的一条 action。
	输出：只包含当前动作、现金成本和已实现效果的 UI 快照；未知 Kind 返回禁用快照。
	内部算法：复用现有业务 Query，再委托共享纯显示规则。
	不负责：执行动作、扣款、按钮颜色、场景查找或 Remote。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DefenseMonsterActionQuery = require(script.Parent.Parent.DefenseMonsterActionQuery)
local IncomeZoneActionQuery = require(script.Parent.Parent.IncomeZoneActionQuery)
local IncomeZoneBoostQuery = require(script.Parent.Parent.IncomeZoneBoostQuery)
local MonsterSpawnPointActionQuery = require(
	script.Parent.Parent.MonsterSpawnPointActionQuery
)
local ButtonWorldUIPresentationRules = require(
	ReplicatedStorage.Shared.UI.ButtonWorldUIPresentationRules
)

local ButtonPresentationQuery = {}

function ButtonPresentationQuery.Get(player: Player, action)
	if action.Kind == "IncomeZonePrimary" then
		local snapshot = IncomeZoneActionQuery.Get(player, action.RegionId)
		if not snapshot or not snapshot.Unlocked then
			return { Enabled = false }
		end
		return ButtonWorldUIPresentationRules.Resolve({
			Kind = "IncomePrimary",
			Action = snapshot.ConstructionAction,
			Cost = snapshot.Construction.Cost,
			TargetLevel = snapshot.Construction.TargetLevel,
			Reason = snapshot.Construction.Reason,
		})
	end

	if action.Kind == "IncomeZoneUnlock" then
		local snapshot = IncomeZoneActionQuery.Get(player, action.RegionId)
		if not snapshot or not snapshot.Unlock.Allowed then
			return { Enabled = false }
		end
		return ButtonWorldUIPresentationRules.Resolve({
			Kind = "IncomeUnlock",
			Cost = snapshot.Unlock.Cost,
			Unlocked = snapshot.Unlocked,
		})
	end

	if action.Kind == "IncomeZoneBoost" then
		local snapshot = IncomeZoneBoostQuery.Get(player, action.RegionId)
		if not snapshot or not snapshot.Unlocked then
			return { Enabled = false }
		end
		return ButtonWorldUIPresentationRules.Resolve({
			Kind = "IncomeBoost",
			Cost = snapshot.Permission.Cost,
			TransactionKind = snapshot.NextTransactionKind,
			Completed = snapshot.BoostCompleted,
			State = snapshot.BoostButtonState,
		})
	end

	if action.Kind == "MonsterSpawnPointBuild" then
		local snapshot = MonsterSpawnPointActionQuery.Get(player, action.SpawnPointId)
		if not snapshot or snapshot.Built
			or snapshot.Build.Reason == "RequiredSpawnPointNotBuilt"
		then
			return { Enabled = false }
		end
		return ButtonWorldUIPresentationRules.Resolve({
			Kind = "MonsterBuild",
			Cost = snapshot.Build.Cost,
			Reason = snapshot.Build.Reason,
		})
	end

	if action.Kind == "DefenseMonsterBuild" then
		local snapshot = DefenseMonsterActionQuery.Get(player, action.SpawnPointId)
		if not snapshot or snapshot.Built or not snapshot.Build.Allowed then
			return { Enabled = false }
		end
		return ButtonWorldUIPresentationRules.Resolve({
			Kind = "MonsterBuild",
			Cost = snapshot.Build.Cost,
			Reason = snapshot.Build.Reason,
		})
	end

	return { Enabled = false }
end

return ButtonPresentationQuery
