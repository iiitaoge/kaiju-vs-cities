--[[
	职责：创建一次重生提交使用的全新业务存档。
	输入：当前重生次数、提交时间，以及可选的账号级持久字段。
	输出：重生次数加一、本轮收入归零；钱和城市重置，钻石、七日奖励和群组奖励领取记录保留。
	内部算法：PlayerSaveSchema.Default → 复制账号级持久字段 → 写入永久次数和 SavedAt。
	不负责：资格判断、DataStore、运行时重载、玩家或 UI。
]]

local PlayerSaveSchema = require(script.Parent.Parent.Persistence.PlayerSaveSchema)

local RebirthResetRules = {}

local function isFiniteNonNegativeInteger(value): boolean
	return type(value) == "number"
		and value == value
		and value < math.huge
		and value >= 0
		and value % 1 == 0
end

local function copyGroupRewardClaims(values)
	local result = {}
	if type(values) ~= "table" then
		return result
	end
	for rewardId, claimed in values do
		if type(rewardId) == "string"
			and rewardId ~= ""
			and string.match(rewardId, "^[A-Za-z0-9_.%-]+$") ~= nil
			and claimed == true
		then
			result[rewardId] = true
		end
	end
	return result
end

function RebirthResetRules.Create(currentCount: number, savedAt: number, preserved)
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
	if type(preserved) == "table" then
		if type(preserved.Diamond) == "number"
			and preserved.Diamond == preserved.Diamond
			and preserved.Diamond < math.huge
			and preserved.Diamond >= 0
		then
			data.Economy.Diamond = preserved.Diamond
		end

		local dailyReward = preserved.DailyReward
		if type(dailyReward) == "table"
			and isFiniteNonNegativeInteger(dailyReward.Day)
			and dailyReward.Day >= 1
			and dailyReward.Day <= 8
			and isFiniteNonNegativeInteger(dailyReward.NextClaimAt)
		then
			data.DailyReward = {
				Day = dailyReward.Day,
				NextClaimAt = if dailyReward.Day == 8
					then 0
					else dailyReward.NextClaimAt,
			}
		end
		data.GroupRewardClaims = copyGroupRewardClaims(preserved.GroupRewardClaims)
	end
	data.SavedAt = savedAt
	data.Rebirth.Count = currentCount + 1
	data.Rebirth.RunEarnings = 0
	return data
end

return table.freeze(RebirthResetRules)
