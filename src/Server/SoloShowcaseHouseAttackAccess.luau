--[[
	职责：把固定单人演示房屋适配为正式 HouseAttackTargetAccess 接口。
	输入：多人攻击通用接口传入的 Player、HouseId、血量代次和伤害。
	输出：与正式房屋攻击一致的目标快照、扣血、回滚和摧毁结果。
	内部算法：把 Player 仅作为当前攻击会话身份传递，实际房屋状态由
	SoloShowcaseRuntimeService 保存；不创建假 Player，不读取玩家存档。
	不负责：目标筛选、攻击动画、相机、奖励或玩家 Plot。
]]

local HouseAttackTargetAccess = require(script.Parent.HouseAttackTargetAccess)
local SoloShowcaseRuntimeService = require(script.Parent.SoloShowcaseRuntimeService)

local SoloShowcaseHouseAttackAccess: HouseAttackTargetAccess.Access = {
	ListAliveTargets = function(_player: Player)
		return SoloShowcaseRuntimeService.ListAliveTargets()
	end,
	ResolveAliveTarget = function(_player: Player, houseId: string)
		return SoloShowcaseRuntimeService.ResolveAliveTarget(houseId)
	end,
	ApplyDamage = function(
		_player: Player,
		houseId: string,
		expectedGeneration: number,
		damage: number
	)
		return SoloShowcaseRuntimeService.ApplyDamage(
			houseId,
			expectedGeneration,
			damage
		)
	end,
	RollbackDamage = function(
		_player: Player,
		houseId: string,
		expectedGeneration: number,
		previousHealth: number
	)
		return SoloShowcaseRuntimeService.RollbackDamage(
			houseId,
			expectedGeneration,
		previousHealth
		)
	end,
	PrepareDestroy = function(_player: Player, houseId: string)
		return SoloShowcaseRuntimeService.PrepareDestroy(houseId)
	end,
	Destroy = function(_player: Player, houseId: string)
		return SoloShowcaseRuntimeService.Destroy(houseId)
	end,
}

return SoloShowcaseHouseAttackAccess
