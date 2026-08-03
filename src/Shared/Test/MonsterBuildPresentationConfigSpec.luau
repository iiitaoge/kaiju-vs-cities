local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildingPresentationConfigs = require(
	ReplicatedStorage.Shared.Building.BuildingPresentationConfigs
)
local MonsterCatalog = require(ReplicatedStorage.Shared.Monster.MonsterCatalog)
local MonsterIncubatorConfigs = require(
	ReplicatedStorage.Shared.Monster.MonsterIncubatorConfigs
)

local MonsterBuildPresentationConfigSpec = {}

local function expect(condition: boolean, message: string)
	assert(condition, "MonsterBuildPresentationConfigSpec: " .. message)
end

-- 输入：怪兽成长目录与培养罐表现配置。
-- 输出：专用时长和模板切换边界稳定时返回 true。
-- 内部算法：验证同外观连续等级不触发表现，并验证第一个换模等级触发表现。
function MonsterBuildPresentationConfigSpec.Run(): boolean
	local incubator = MonsterIncubatorConfigs["M1-S1"]
	expect(incubator ~= nil, "缺少 M1-S1 培养罐配置")
	expect(incubator.PresentationId == "MonsterStandard", "培养罐未使用怪兽专用表现")

	local presentation = BuildingPresentationConfigs[incubator.PresentationId]
	expect(presentation ~= nil, "缺少怪兽专用表现配置")
	expect(presentation.Demolish.TotalDuration == 1, "怪兽拆除总时长必须为 1 秒")
	expect(presentation.Rise.TotalDuration == 2, "怪兽建造总时长必须为 2 秒")

	expect(
		MonsterCatalog.HasTemplateChanged("Godzilla-L001", "Godzilla-L002") == false,
		"同一外观内升级不应触发拆除/建造"
	)
	expect(
		MonsterCatalog.HasTemplateChanged("Godzilla-L005", "Godzilla-L006") == true,
		"进入新外观等级必须触发拆除/建造"
	)
	expect(
		MonsterCatalog.HasTemplateChanged("Missing", "Godzilla-L001") == nil,
		"未知怪兽身份必须返回 nil"
	)
	return true
end

return MonsterBuildPresentationConfigSpec
