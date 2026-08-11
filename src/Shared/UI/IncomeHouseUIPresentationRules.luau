--[[
	职责：把单栋产钱房屋的只读收入状态映射为 WorldObjectUI 显示快照。
	输入：LifeState、自动收入、产速、累计基数、结算时间、当前时间和生命值。
	输出：Billboard 是否启用、Text1～Text5 与 Money.Val 的可见性和文本。
	内部算法：Alive 才显示；HP 未满时显示，满血时隐藏；非自动额外显示产速并按时间推算待领取，自动显示每秒产量。
	不负责：读取 Instance、结算收入、战斗血条或定位 UI。
]]

local CompactNumberFormatter = require(script.Parent.CompactNumberFormatter)

local IncomeHouseUIPresentationRules = {}

local function hiddenText()
	return { Visible = false, Text = "" }
end

local function visibleText(text: string)
	return { Visible = true, Text = text }
end

local function disabled()
	return {
		Enabled = false,
		Texts = {
			Text1 = hiddenText(),
			Text2 = hiddenText(),
			Text3 = hiddenText(),
			Text4 = hiddenText(),
			Text5 = hiddenText(),
		},
		Money = { Visible = false, Text = "" },
	}
end

local function finiteNonNegative(value): boolean
	return type(value) == "number"
		and value == value
		and value < math.huge
		and value >= 0
end

function IncomeHouseUIPresentationRules.Resolve(input)
	if type(input) ~= "table"
		or input.LifeState ~= "Alive"
		or type(input.AutoIncome) ~= "boolean"
		or not finiteNonNegative(input.IncomePerSecond)
		or not finiteNonNegative(input.StoredMoney)
		or not finiteNonNegative(input.Now)
		or (input.LastIncomeAt ~= nil and not finiteNonNegative(input.LastIncomeAt))
		or not finiteNonNegative(input.CurrentHealth)
		or not finiteNonNegative(input.MaxHealth)
		or input.MaxHealth <= 0
	then
		return disabled()
	end

	local moneyText
	local incomeText = hiddenText()
	local currentHealth = math.clamp(input.CurrentHealth, 0, input.MaxHealth)
	local healthText = if currentHealth < input.MaxHealth
		then visibleText(string.format(
			"%s/%s HP",
			CompactNumberFormatter.Format(currentHealth),
			CompactNumberFormatter.Format(input.MaxHealth)
		))
		else hiddenText()
	if input.AutoIncome then
		moneyText = "+" .. CompactNumberFormatter.Format(input.IncomePerSecond) .. "/s"
	else
		local elapsed = if input.LastIncomeAt == nil
			then 0
			else math.max(0, input.Now - input.LastIncomeAt)
		local accumulated = input.StoredMoney + input.IncomePerSecond * elapsed
		moneyText = CompactNumberFormatter.Format(accumulated)
		incomeText = visibleText(
			"+" .. CompactNumberFormatter.Format(input.IncomePerSecond) .. "/s"
		)
	end

	return {
		Enabled = true,
		Texts = {
			Text1 = hiddenText(),
			Text2 = incomeText,
			Text3 = healthText,
			Text4 = hiddenText(),
			Text5 = hiddenText(),
		},
		Money = { Visible = true, Text = moneyText },
	}
end

return table.freeze(IncomeHouseUIPresentationRules)
