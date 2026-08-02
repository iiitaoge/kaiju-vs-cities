local AttackAnimationSelector = {}

export type SelectionMode = "Sequence" | "Random"

export type SelectOptions = {
	-- Sequence 按配置顺序循环；Random 每次独立随机选择。
	Mode: SelectionMode,
}

export type AttackChoice = {
	Name: string,
	AssetId: number,
}

local sequenceIndexes = setmetatable({}, { __mode = "k" })

-- 输入：
--   model：用于隔离顺序游标的怪兽模型。
--   animationIds：动画名称到资源 ID 的映射。
--   sequence：允许选择的攻击动画名称数组。
--   options.Mode：Sequence 或 Random。
-- 输出：
--   本次选择的动画名称和资源 ID。
-- 副作用：Sequence 模式成功选择后推进该怪兽自己的顺序游标。
function AttackAnimationSelector.Next(
	model: Model,
	animationIds: { [string]: number },
	sequence: { string },
	options: SelectOptions
): AttackChoice
	assert(model:IsA("Model"), "model 必须是 Model")
	assert(type(animationIds) == "table", "animationIds 必须是 table")
	assert(type(sequence) == "table" and #sequence > 0, "sequence 必须是非空数组")
	assert(type(options) == "table", "options 必须是 table")
	assert(options.Mode == "Sequence" or options.Mode == "Random", "Mode 必须是 Sequence 或 Random")

	local index
	if options.Mode == "Sequence" then
		index = (sequenceIndexes[model] or 0) % #sequence + 1
	else
		index = math.random(1, #sequence)
	end

	local animationName = sequence[index]
	local assetId = animationIds[animationName]
	assert(
		type(assetId) == "number" and assetId > 0,
		string.format("未知或无效的攻击动画：%s", tostring(animationName))
	)

	if options.Mode == "Sequence" then
		sequenceIndexes[model] = index
	end

	return {
		Name = animationName,
		AssetId = assetId,
	}
end

-- 输入：
--   model：需要清除攻击动画顺序游标的怪兽模型。
-- 输出：无。
-- 副作用：该怪兽下一次 Sequence 选择会重新从第一项开始。
function AttackAnimationSelector.Reset(model: Model)
	assert(model:IsA("Model"), "model 必须是 Model")
	sequenceIndexes[model] = nil
end

return AttackAnimationSelector
