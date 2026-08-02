local GodzillaService = require(script.Parent.Parent.GodzillaService)

local MonsterAttackTestRuntime = {}

export type SpawnResult = {
	Succeeded: boolean,
	Reason: string?,
	Created: boolean,
	Model: Model?,
}

local modelsByPlayer: { [Player]: Model } = setmetatable({}, { __mode = "k" })

-- 输入：
--   player：本次测试怪兽所属玩家。
--   template：带 PrimaryPart 的怪兽模板。
--   spawnCFrame：怪兽初始位置与朝向。
--   monstersRoot：运行时怪兽父级。
-- 输出：
--   返回是否成功、是否新建以及当前玩家的测试怪兽模型。
-- 副作用：首次调用时克隆并稳定放置怪兽到 monstersRoot。
function MonsterAttackTestRuntime.Spawn(
	player: Player,
	template: Model,
	spawnCFrame: CFrame,
	monstersRoot: Instance
): SpawnResult
	assert(player:IsA("Player"), "player 必须是 Player")
	assert(template:IsA("Model"), "template 必须是 Model")
	assert(typeof(spawnCFrame) == "CFrame", "spawnCFrame 必须是 CFrame")

	local existing = modelsByPlayer[player]
	if existing and existing:IsDescendantOf(workspace) then
		return {
			Succeeded = true,
			Reason = "AlreadySpawned",
			Created = false,
			Model = existing,
		}
	end

	local model = GodzillaService.Create(template, spawnCFrame)
	model.Name = string.format("%s_%d", template.Name, player.UserId)
	model:SetAttribute("MonsterAttackTestOwnerUserId", player.UserId)
	model.Parent = monstersRoot
	modelsByPlayer[player] = model

	return {
		Succeeded = true,
		Reason = nil,
		Created = true,
		Model = model,
	}
end

-- 输入：player。
-- 输出：该玩家仍在 Workspace 的测试怪兽；不存在时返回 nil。
-- 副作用：发现失效记录时清理内存索引。
function MonsterAttackTestRuntime.Get(player: Player): Model?
	local model = modelsByPlayer[player]
	if model and model:IsDescendantOf(workspace) then
		return model
	end
	modelsByPlayer[player] = nil
	return nil
end

-- 输入：player。
-- 输出：是否销毁了该玩家的测试怪兽。
-- 副作用：销毁运行时模型并清理索引。
function MonsterAttackTestRuntime.Remove(player: Player): boolean
	local model = modelsByPlayer[player]
	modelsByPlayer[player] = nil
	if model and model.Parent then
		model:Destroy()
		return true
	end
	return false
end

return MonsterAttackTestRuntime
