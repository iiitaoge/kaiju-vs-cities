--[[
	职责：查询当前攻击者可以浏览的在线玩家城市，或没有其他玩家时的展示空 Plot。

	输入：发起攻击的 Player。
	输出：Succeeded、Reason、玩家目标数组，以及可选的 SoloTarget 快照。
	内部算法：排除自己，读取每名在线玩家的总 AttackView 和已解锁 Territory；
	缺少 Plot、总视野或有效领地的玩家不会进入结果；只有服务器中确实没有其他玩家时，
	才读取唯一展示空 Plot 的 AttackViewBounds 作为视野和可点击范围。

	不负责：选择当前目标、校验最终落点、执行攻击或改变怪兽状态。
]]

local Players = game:GetService("Players")

local WorkspacePlayerWorldAccess = require(script.Parent.WorkspacePlayerWorldAccess)
local WorkspaceSoloAttackAreaAccess = require(script.Parent.WorkspaceSoloAttackAreaAccess)

local PlayerAttackTargetQuery = {}

export type TargetSnapshot = {
	TargetPlayerId: number,
	Name: string,
	DisplayName: string,
	AttackView: {
		CFrame: CFrame,
		Size: Vector3,
	},
	UnlockedTerritories: {
		{
			ZoneId: string,
			BoundsId: string,
			CFrame: CFrame,
			Size: Vector3,
		}
	},
}

export type SoloTargetSnapshot = {
	AttackView: {
		CFrame: CFrame,
		Size: Vector3,
	},
	Bounds: {
		CFrame: CFrame,
		Size: Vector3,
	},
}

function PlayerAttackTargetQuery.Query(attacker: Player)
	if typeof(attacker) ~= "Instance"
		or not attacker:IsA("Player")
		or attacker.Parent ~= Players then
		return {
			Succeeded = false,
			Reason = "AttackerUnavailable",
			Targets = {},
			SoloTarget = nil,
			SoloReason = nil,
		}
	end

	local targets: { TargetSnapshot } = {}
	local hasOtherPlayer = false
	for _, targetPlayer in Players:GetPlayers() do
		if targetPlayer == attacker then
			continue
		end
		hasOtherPlayer = true

		local attackView = WorkspacePlayerWorldAccess.AttackView.GetAttackView(targetPlayer)
		local territories = WorkspacePlayerWorldAccess.Territory.ListUnlockedTerritories(
			targetPlayer
		)
		if not attackView or #territories == 0 then
			continue
		end

		table.insert(targets, {
			TargetPlayerId = targetPlayer.UserId,
			Name = targetPlayer.Name,
			DisplayName = targetPlayer.DisplayName,
			AttackView = attackView,
			UnlockedTerritories = territories,
		})
	end

	table.sort(targets, function(a, b)
		return a.TargetPlayerId < b.TargetPlayerId
	end)
	local soloTarget: SoloTargetSnapshot? = nil
	local soloReason: string? = nil
	if not hasOtherPlayer then
		local area
		area, soloReason = WorkspaceSoloAttackAreaAccess.Resolve()
		if area then
			soloTarget = {
				AttackView = {
					CFrame = area.CFrame,
					Size = area.Size,
				},
				Bounds = {
					CFrame = area.CFrame,
					Size = area.Size,
				},
			}
		end
	end
	return {
		Succeeded = true,
		Reason = nil,
		Targets = targets,
		SoloTarget = soloTarget,
		SoloReason = soloReason,
	}
end

return PlayerAttackTargetQuery
