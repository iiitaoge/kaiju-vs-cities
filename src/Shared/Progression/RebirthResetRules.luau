--[[
	职责：创建一次重生提交使用的全新业务存档。
	输入：当前重生次数、提交时间。
	输出：重生次数加一、本轮收入归零，其余字段全部采用新玩家默认值的存档。
	内部算法：PlayerSaveSchema.Default → 写入永久次数和 SavedAt。
	不负责：资格判断、DataStore、运行时重载、玩家或 UI。
]]

local PlayerSaveSchema = require(script.Parent.Parent.Persistence.PlayerSaveSchema)

local RebirthResetRules = {}

function RebirthResetRules.Create(currentCount: number, savedAt: number)
	assert(
		type(currentCount) == "number"
			and currentCount == currentCount
			and currentCount < math.huge
			and currentCount >= 0
			and currentCount % 1 == 0,
		"currentCount 必须是非负整数"
	)
	assert(
		type(savedAt) == "number"
			and savedAt == savedAt
			and savedAt < math.huge
			and savedAt >= 0
			and savedAt % 1 == 0,
		"savedAt 必须是非负整数"
	)

	local data = PlayerSaveSchema.Default()
	data.SavedAt = savedAt
	data.Rebirth.Count = currentCount + 1
	data.Rebirth.RunEarnings = 0
	return data
end

return table.freeze(RebirthResetRules)
