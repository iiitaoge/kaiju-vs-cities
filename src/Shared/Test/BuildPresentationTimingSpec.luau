local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildPresentationTiming = require(
	ReplicatedStorage.Shared.Building.BuildPresentationTiming
)

local BuildPresentationTimingSpec = {}

function BuildPresentationTimingSpec.Run(): boolean
	assert(BuildPresentationTiming.ScaleDuration(2, 2) == 1, "时长没有除以速度倍率")
	local original = {
		MoveDistance = 8,
		TotalDuration = 2,
		MoveDuration = 0.5,
	}
	local scaled = BuildPresentationTiming.ScaleMotion(original, 1.25)
	assert(scaled.MoveDistance == 8, "空间位移不应被缩放")
	assert(math.abs(scaled.TotalDuration - 1.6) < 1e-9, "总时长缩放错误")
	assert(math.abs(scaled.MoveDuration - 0.4) < 1e-9, "移动时长缩放错误")
	assert(original.TotalDuration == 2, "输入配置被修改")
	assert(table.isfrozen(scaled), "缩放结果必须只读")
	assert(table.isfrozen(BuildPresentationTiming), "时间规则模块必须只读")
	for _, multiplier in { 0, -1, math.huge, 0 / 0 } do
		assert(
			not pcall(BuildPresentationTiming.ScaleDuration, 1, multiplier),
			"非法倍率未断言"
		)
	end
	return true
end

return BuildPresentationTimingSpec
