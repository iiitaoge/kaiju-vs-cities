--[[
	职责：把服务器权威按钮操作快照映射为 WorldObjectUI 文本。
	输入：IncomeUnlock、IncomePrimary、IncomeBoost 或 MonsterBuild 的规范化快照。
	输出：Text1～Text5 与 Money.Val 的完整显示快照。
	内部算法：Unlock/建造动作显示语义与现金；Boost 只显示下一笔顺序事务；付费占位永远隐藏。
	不负责：查询玩家状态、扣款、按钮颜色、Remote 或 UI 定位。
]]

local CompactNumberFormatter = require(script.Parent.CompactNumberFormatter)

local ButtonWorldUIPresentationRules = {}

local function row(visible: boolean, text: string): { Visible: boolean, Text: string }
	return { Visible = visible, Text = if visible then text else "" }
end

local function output(
	text1: string,
	text2: string?,
	text3: string?,
	text4: string?,
	moneyVisible: boolean,
	cost: number?
)
	return {
		Enabled = true,
		Texts = {
			Text1 = row(true, text1),
			Text2 = row(text2 ~= nil, text2 or ""),
			Text3 = row(text3 ~= nil, text3 or ""),
			Text4 = row(text4 ~= nil, text4 or ""),
			-- Text5 是原附件的 Robux 占位；当前阶段始终隐藏。
			Text5 = row(false, ""),
		},
		Money = row(
			moneyVisible,
			if cost ~= nil then CompactNumberFormatter.Format(cost) else ""
		),
	}
end

local function validCost(cost): boolean
	return type(cost) == "number" and cost == cost and cost < math.huge and cost >= 0
end

function ButtonWorldUIPresentationRules.Resolve(snapshot)
	if type(snapshot) ~= "table" or type(snapshot.Kind) ~= "string" then
		return { Enabled = false }
	end

	if snapshot.Kind == "IncomePrimary" then
		if snapshot.Reason == "MaxLevel" or snapshot.Action == "None" then
			return output("MAX", nil, nil, nil, false, nil)
	end
		if not validCost(snapshot.Cost) then
			return { Enabled = false }
		end
		local labelByAction = {
			Build = "Build",
			Upgrade = if type(snapshot.TargetLevel) == "number"
				then "Upgrade Lv." .. tostring(snapshot.TargetLevel)
				else "Upgrade",
		}
		local label = labelByAction[snapshot.Action]
		return if label
			then output(label, nil, nil, nil, true, snapshot.Cost)
			else { Enabled = false }
	end

	if snapshot.Kind == "IncomeUnlock" then
		if snapshot.Unlocked == true then
			return { Enabled = false }
		end
		if snapshot.Unlocked ~= false or not validCost(snapshot.Cost) then
			return { Enabled = false }
		end
		return output("Unlock", nil, nil, nil, true, snapshot.Cost)
	end

	if snapshot.Kind == "IncomeBoost" then
		if not validCost(snapshot.Cost)
			or type(snapshot.Completed) ~= "boolean"
			or type(snapshot.State) ~= "string"
		then
			return { Enabled = false }
		end
		if snapshot.State == "Locked" then
			return output("Locked", nil, nil, nil, false, nil)
		end
		if snapshot.Completed or snapshot.State == "Special" then
			return output("MAX", nil, nil, nil, false, nil)
		end
		if snapshot.State ~= "Ready" and snapshot.State ~= "Insufficient" then
			return { Enabled = false }
		end
		if snapshot.TransactionKind == "Income" then
			return output("Boost", "2x Cash", nil, nil, true, snapshot.Cost)
		end
		if snapshot.TransactionKind == "Health" then
			return output("Boost", nil, "2x HP", nil, true, snapshot.Cost)
		end
		if snapshot.TransactionKind == "AutoIncome" then
			return output("Boost", nil, nil, "Auto Collect", true, snapshot.Cost)
		end
		return { Enabled = false }
	end

	if snapshot.Kind == "MonsterBuild" then
		if not validCost(snapshot.Cost) then
			return { Enabled = false }
		end
		return output("Build Monster", nil, nil, nil, true, snapshot.Cost)
	end

	return { Enabled = false }
end

return table.freeze(ButtonWorldUIPresentationRules)
