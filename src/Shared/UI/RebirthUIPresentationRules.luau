--[[
	职责：把服务器重生状态快照映射为 Rebirth-Button BillboardGui 文本。
	输入：Count、NextCount、下一次怪兽等级上限、下一次展示配置、Status、资格门槛和剩余收入。
	输出：标题、操作文字、门槛、说明以及 CanExecute。
	内部算法：数字使用紧凑格式；只有 Ready 且激活距离有效时允许点击。
	不负责：查找 UI、触碰、Remote、资格计算、存档或重生执行。
]]

local CompactNumberFormatter = require(script.Parent.CompactNumberFormatter)

local RebirthUIPresentationRules = {}

local BONUS_FIELDS = {
	{ Key = "IncomeMultiplier", Label = "Income" },
	{ Key = "BuildSpeedMultiplier", Label = "Build" },
	{ Key = "MonsterDamageMultiplier", Label = "Damage" },
	{ Key = "MonsterHealthMultiplier", Label = "HP" },
	{ Key = "MonsterMoveSpeedMultiplier", Label = "Move" },
}

local function finite(value): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function validBonuses(value): boolean
	if type(value) ~= "table" then
		return false
	end
	for _, field in BONUS_FIELDS do
		if not finite(value[field.Key]) or value[field.Key] <= 0 then
			return false
		end
	end
	return true
end

local function formatMultiplier(value: number): string
	local text = string.format("%.2f", value)
	return (text:gsub("0+$", ""):gsub("%.$", ""))
end

local function formatNextBonuses(bonuses): string
	local parts = {}
	for _, field in BONUS_FIELDS do
		table.insert(parts, field.Label .. " x" .. formatMultiplier(bonuses[field.Key]))
	end
	return "Next rewards: " .. table.concat(parts, " · ")
end

local function formatRewardText(rewardText: string): string
	local formatted = rewardText:gsub("^Next rewards:%s*", "Next rewards:\n")
	return formatted:gsub("%s*·%s*", "\n")
end

local function validPresentation(value): boolean
	return type(value) == "table"
		and type(value.LevelText) == "string"
		and value.LevelText ~= ""
		and type(value.RewardText) == "string"
		and value.RewardText ~= ""
end

function RebirthUIPresentationRules.Resolve(snapshot)
	if type(snapshot) ~= "table"
		or type(snapshot.Status) ~= "string"
		or not finite(snapshot.Count)
		or not finite(snapshot.NextCount)
		or not finite(snapshot.CurrentMaxLevel)
		or not finite(snapshot.NextMaxLevel)
		or not finite(snapshot.TotalMaxLevel)
		or snapshot.CurrentMaxLevel < 1
		or snapshot.NextMaxLevel < snapshot.CurrentMaxLevel
		or snapshot.TotalMaxLevel < snapshot.NextMaxLevel
		or not validBonuses(snapshot.NextBonuses)
		or not finite(snapshot.RequiredRunEarnings)
		or not finite(snapshot.RemainingRunEarnings)
		or type(snapshot.ActivationAllowed) ~= "boolean"
	then
		return { Enabled = false, CanExecute = false }
	end

	local status = snapshot.Status
	local activationBlocked = status == "Ready" and not snapshot.ActivationAllowed
	local canExecute = status == "Ready" and snapshot.ActivationAllowed
	local actionText = if status == "Processing"
		then "Processing..."
		elseif activationBlocked then "Approach"
		elseif canExecute then "Rebirth" else "Locked"
	local infoTitle = if status == "Processing"
		then "Saving rebirth..."
	elseif status == "Failed"
	then "Rebirth unavailable"
		elseif activationBlocked
		then "Approach the rebirth button"
		elseif canExecute
		then "Ready to rebirth"
		else CompactNumberFormatter.Format(snapshot.RemainingRunEarnings)
	local levelText = if validPresentation(snapshot.NextPresentation)
		then snapshot.NextPresentation.LevelText
		elseif snapshot.CurrentMaxLevel < snapshot.NextMaxLevel
		then string.format(
			"Kaiju max Lv. %d → %d",
			snapshot.CurrentMaxLevel,
			snapshot.NextMaxLevel
		)
		else string.format("Kaiju max Lv. %d", snapshot.CurrentMaxLevel)
	local rewardText = if validPresentation(snapshot.NextPresentation)
		then snapshot.NextPresentation.RewardText
		else formatNextBonuses(snapshot.NextBonuses)

	return {
		Enabled = true,
		CanExecute = canExecute,
		TitleText = "Rebirth · " .. tostring(snapshot.Count),
		ActionText = actionText,
		TipText = if activationBlocked
			then "Move closer to confirm"
			elseif canExecute then "Click to confirm" else "Requirement",
		RequirementText = CompactNumberFormatter.Format(snapshot.RequiredRunEarnings),
		InfoTitleText = infoTitle,
		IntroductionText = string.format(
			"%s\n%s\nProgress resets · Rebirth count becomes %d",
			levelText,
			formatRewardText(rewardText),
			snapshot.NextCount
		),
	}
end

return table.freeze(RebirthUIPresentationRules)
