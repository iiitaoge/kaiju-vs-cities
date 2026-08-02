local CurrentBuildings = require(script.Parent.CurrentBuildings)
local LocalModelDemolisher = require(script.Parent.LocalModelDemolisher)

local LocalHouseDestructionPresenter = {}

export type EffectMode = "Demolish" | "ReplaceWithRuin"

export type PresentResult = {
	-- CurrentBuildings 是否存在该 HouseId 的记录。
	ModelFound: boolean,
	-- 是否成功安排了本地拆除表现。
	EffectStarted: boolean,
	-- 实际选择的房屋摧毁效果；找不到模型时为 nil。
	EffectMode: EffectMode?,
	-- 未开始效果时的明确原因。
	Reason: string?,
}

type EffectHandler = (string, Model) -> ()

local handlers: { [string]: EffectHandler } = {
	Demolish = function(_houseId: string, model: Model)
		LocalModelDemolisher.Demolish(model)
	end,
}

-- 输入：
--   houseId：服务器确认已摧毁的稳定房屋 ID。
--   effectMode：调用方为本次摧毁显式选择的有限效果模式。
-- 输出：
--   返回是否找到本地模型、选择的效果模式、是否开始表现和失败原因。
-- 内部算法：
--   通过 HouseId 查找当前模型，再按显式模式选择处理器并异步执行。
--   第一版 Demolish 调用 LocalModelDemolisher；未实现模式明确返回失败。
-- 副作用：
--   效果成功安排后，从 CurrentBuildings 的 Point/HouseId 双索引移除 Alive 模型。
--   不修改任何服务器房屋状态。
function LocalHouseDestructionPresenter.Play(
	houseId: string,
	effectMode: EffectMode
): PresentResult
	assert(type(houseId) == "string" and houseId ~= "", "houseId 必须是非空字符串")
	assert(
		effectMode == "Demolish" or effectMode == "ReplaceWithRuin",
		"effectMode 必须是 Demolish 或 ReplaceWithRuin"
	)

	local model = CurrentBuildings.GetByHouseId(houseId)
	if not model then
		return {
			ModelFound = false,
			EffectStarted = false,
			EffectMode = nil,
			Reason = "ModelNotFound",
		}
	end
	if not model.Parent then
		CurrentBuildings.TakeByHouseId(houseId)
		return {
			ModelFound = true,
			EffectStarted = false,
			EffectMode = nil,
			Reason = "ModelNotParented",
		}
	end

	local handler = handlers[effectMode]
	if not handler then
		return {
			ModelFound = true,
			EffectStarted = false,
			EffectMode = effectMode,
			Reason = "UnsupportedEffectMode",
		}
	end

	CurrentBuildings.TakeByHouseId(houseId)
	task.defer(function()
		if not model.Parent then
			return
		end

		local succeeded, message = pcall(handler, houseId, model)
		if not succeeded then
			warn(
				string.format(
					"房屋 %s 的 %s 摧毁效果播放失败：%s",
					houseId,
					effectMode,
					tostring(message)
				)
			)
		end
	end)

	return {
		ModelFound = true,
		EffectStarted = true,
		EffectMode = effectMode,
		Reason = nil,
	}
end

return LocalHouseDestructionPresenter
