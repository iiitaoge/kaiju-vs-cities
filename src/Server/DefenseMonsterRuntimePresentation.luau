--[[
	职责：给防守怪兽运行时模型写入角色和区域身份。
	输入：Model、RegionId。
	输出：同一 Model。
	不负责：权限、距离 UI、模型生成或战斗。
]]

local DefenseMonsterRuntimePresentation = {}

function DefenseMonsterRuntimePresentation.Apply(model: Model, regionId: string): Model
	assert(model:IsA("Model"), "model 必须是 Model")
	assert(type(regionId) == "string" and regionId ~= "", "regionId 必须是非空字符串")
	local primaryPart = assert(model.PrimaryPart, "防守怪兽必须设置 PrimaryPart")
	model:SetAttribute("MonsterRole", "Defense")
	model:SetAttribute("DefenseRegionId", regionId)

	-- 旧版 UI 依赖难以点中的 RootPart；距离 UI 不再需要该实例。
	local clickDetector = primaryPart:FindFirstChild("DefenseMonsterClick")
	if clickDetector then
		clickDetector:Destroy()
	end
	return model
end

return DefenseMonsterRuntimePresentation
