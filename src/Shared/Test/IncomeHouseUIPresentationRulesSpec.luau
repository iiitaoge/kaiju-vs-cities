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
		CurrentHealth = 750,
		MaxHealth = 1_000,
	}
end

function IncomeHouseUIPresentationRulesSpec.Run(): boolean
	local manual = IncomeHouseUIPresentationRules.Resolve(input())
	assert(manual.Enabled, "Alive 房屋 UI 未启用")
	assert(manual.Texts.Text2.Text == "+5/s", "手动领取房屋产速错误")
	assert(manual.Texts.Text3.Text == "750/1K HP", "手动领取房屋生命值错误")
	assert(manual.Money.Text == "70", "累计待领取金额错误")
	assert(not manual.Texts.Text1.Visible and not manual.Texts.Text5.Visible, "无关文本没有隐藏")

	local autoInput = input()
	autoInput.AutoIncome = true
	local automatic = IncomeHouseUIPresentationRules.Resolve(autoInput)
	assert(automatic.Money.Text == "+5/s", "自动收入每秒产量错误")
	assert(
		not automatic.Texts.Text2.Visible,
		"自动收入房屋重复显示产速"
	)
	assert(
		automatic.Texts.Text3.Visible and automatic.Texts.Text3.Text == "750/1K HP",
		"自动收入房屋未显示生命值"
	)

	local destroyedInput = input()
	destroyedInput.LifeState = "Destroyed"
	assert(not IncomeHouseUIPresentationRules.Resolve(destroyedInput).Enabled, "摧毁房屋仍显示 UI")
	return true
end

return IncomeHouseUIPresentationRulesSpec
