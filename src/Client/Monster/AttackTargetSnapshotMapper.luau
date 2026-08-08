--[[
	职责：把服务端可序列化的攻击目标快照转换为 AttackPanelCoordinator 目标。
	输入：未知快照数组，以及 TargetPlayerId -> Player? 解析回调。
	输出：字段完整且当前可解析为 Player 的目标数组。
	内部算法：逐项验证身份、总视野和每个 Territory；丢弃无效或离线项，按 UserId 排序。
	不负责：网络请求、目标切换、相机、落点校验或攻击提交。
]]

local AttackTargetSnapshotMapper = {}

local function isValidBounds(value): boolean
	return type(value) == "table"
		and typeof(value.CFrame) == "CFrame"
		and typeof(value.Size) == "Vector3"
		and value.Size.X > 0
		and value.Size.Y > 0
		and value.Size.Z > 0
end

function AttackTargetSnapshotMapper.Map(values, resolvePlayer: (number) -> Player?)
	assert(type(resolvePlayer) == "function", "resolvePlayer 必须是 function")
	if type(values) ~= "table" then
		return {}
	end

	local targets = {}
	local seenUserIds = {}
	for _, snapshot in values do
		if type(snapshot) ~= "table"
			or type(snapshot.TargetPlayerId) ~= "number"
			or snapshot.TargetPlayerId % 1 ~= 0
			or seenUserIds[snapshot.TargetPlayerId]
			or not isValidBounds(snapshot.AttackView)
			or type(snapshot.UnlockedTerritories) ~= "table" then
			continue
		end

		local territories = {}
		for _, territory in snapshot.UnlockedTerritories do
			if type(territory) == "table"
				and type(territory.ZoneId) == "string"
				and territory.ZoneId ~= ""
				and type(territory.BoundsId) == "string"
				and territory.BoundsId ~= ""
				and isValidBounds(territory) then
				table.insert(territories, {
					ZoneId = territory.ZoneId,
					BoundsId = territory.BoundsId,
					CFrame = territory.CFrame,
					Size = territory.Size,
					AttackInProgress = territory.AttackInProgress == true,
				})
			end
		end
		if #territories == 0 then
			continue
		end

		local player = resolvePlayer(snapshot.TargetPlayerId)
		if not player or not player:IsA("Player") then
			continue
		end
		seenUserIds[snapshot.TargetPlayerId] = true
		table.insert(targets, {
			Player = player,
			AttackView = {
				CFrame = snapshot.AttackView.CFrame,
				Size = snapshot.AttackView.Size,
			},
			UnlockedTerritories = territories,
		})
	end

	table.sort(targets, function(a, b)
		return a.Player.UserId < b.Player.UserId
	end)
	return targets
end

return AttackTargetSnapshotMapper
