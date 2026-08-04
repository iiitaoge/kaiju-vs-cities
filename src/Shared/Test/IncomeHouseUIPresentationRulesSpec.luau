local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IncomeHouseUIPresentationRules = require(
	ReplicatedStorage.Shared.UI.IncomeHouseUIPresentationRules
)

local IncomeHouseUIPresentationRulesSpec = {}

local function input()
	return {
		LifeState = "Alive",
		AutoIncome = false,
		IncomePerSecond = 5,
		StoredMoney = 20,
		LastIncomeAt = 100,
		Now = 110,
		CurrentHealth = 80,
		MaxHealth = 100,
	}
end

function IncomeHouseUIPresentationRulesSpec.Run(): boolean
	local manual = IncomeHouseUIPresentationRules.Resolve(input())
	assert(manual.Enabled, "Alive 房屋 UI 未启用")
	assert(manual.Texts.Text1.Text == "HP 80/100", "HP 文本错误")
	assert(manual.Money.Text == "70", "累计待领取金额错误")
	assert(not manual.Texts.Text2.Visible and not manual.Texts.Text5.Visible, "无关文本没有隐藏")

	local autoInput = input()
	autoInput.AutoIncome = true
	local automatic = IncomeHouseUIPresentationRules.Resolve(autoInput)
	assert(automatic.Money.Text == "+5/s", "自动收入每秒产量错误")

	local destroyedInput = input()
	destroyedInput.LifeState = "Destroyed"
	assert(not IncomeHouseUIPresentationRules.Resolve(destroyedInput).Enabled, "摧毁房屋仍显示 UI")
	return true
end

return IncomeHouseUIPresentationRulesSpec
