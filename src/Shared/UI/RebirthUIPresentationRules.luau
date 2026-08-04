--[[
	职责：把服务器重生状态快照映射为 Rebirth-Button BillboardGui 文本。
	输入：Count、NextCount、Status、资格门槛和剩余收入。
	输出：标题、操作文字、门槛、说明以及 CanExecute。
	内部算法：数字使用紧凑格式；只有 Ready 状态允许点击。
	不负责：查找 UI、触碰、Remote、资格计算、存档或重生执行。
]]

local CompactNumberFormatter = require(script.Parent.CompactNumberFormatter)

local RebirthUIPresentationRules = {}

local function finite(value): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

function RebirthUIPresentationRules.Resolve(snapshot)
	if type(snapshot) ~= "table"
		or type(snapshot.Status) ~= "string"
		or not finite(snapshot.Count)
		or not finite(snapshot.NextCount)
		or not finite(snapshot.RequiredRunEarnings)
		or not finite(snapshot.RemainingRunEarnings)
	then
		return { Enabled = false, CanExecute = false }
	end

	local status = snapshot.Status
	local canExecute = status == "Ready"
	local actionText = if status == "Processing"
		then "Processing..."
		elseif canExecute then "Rebirth" else "Locked"
	local infoTitle = if status == "Processing"
		then "Saving rebirth..."
		elseif status == "Failed"
		then "Rebirth unavailable"
		elseif canExecute
		then "Ready to rebirth"
		else CompactNumberFormatter.Format(snapshot.RemainingRunEarnings) .. " more required"

	return {
		Enabled = true,
		CanExecute = canExecute,
		TitleText = "Rebirth · " .. tostring(snapshot.Count),
		ActionText = actionText,
		TipText = if canExecute then "Click to confirm" else "Requirement",
		RequirementText = CompactNumberFormatter.Format(snapshot.RequiredRunEarnings),
		InfoTitleText = infoTitle,
		IntroductionText = string.format(
			"Progress resets · Rebirth count becomes %d",
			snapshot.NextCount
		),
	}
end

return table.freeze(RebirthUIPresentationRules)
