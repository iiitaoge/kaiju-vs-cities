local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ButtonWorldUIPresentationRules = require(
	ReplicatedStorage.Shared.UI.ButtonWorldUIPresentationRules
)

local ButtonWorldUIPresentationRulesSpec = {}

function ButtonWorldUIPresentationRulesSpec.Run(): boolean
	local income = ButtonWorldUIPresentationRules.Resolve({
		Kind = "IncomePrimary",
		Action = "Upgrade",
		Cost = 1_250,
		TargetLevel = 2,
	})
	assert(income.Enabled and income.Texts.Text1.Text == "Upgrade Lv.2", "区域升级动作文本错误")
	assert(income.Money.Text == "1.25K", "区域升级现金价格错误")
	assert(not income.Texts.Text5.Visible, "Robux 占位没有隐藏")

	local unlock = ButtonWorldUIPresentationRules.Resolve({
		Kind = "IncomeUnlock",
		Cost = 500,
		Unlocked = false,
	})
	assert(unlock.Enabled and unlock.Texts.Text1.Text == "Unlock", "区域解锁文本错误")
	assert(unlock.Money.Text == "500", "区域解锁现金价格错误")

	local unlocked = ButtonWorldUIPresentationRules.Resolve({
		Kind = "IncomeUnlock",
		Cost = 500,
		Unlocked = true,
	})
	assert(not unlocked.Enabled, "已解锁区域不得继续显示 Unlock UI")

	local oldPrimaryUnlock = ButtonWorldUIPresentationRules.Resolve({
		Kind = "IncomePrimary",
		Action = "Unlock",
		Cost = 500,
	})
	assert(not oldPrimaryUnlock.Enabled, "升级入口不得继续暴露 Unlock 语义")

	local boost = ButtonWorldUIPresentationRules.Resolve({
		Kind = "IncomeBoost",
		Cost = 100,
		TransactionKind = "Income",
		Completed = false,
		State = "Ready",
	})
	assert(boost.Texts.Text1.Text == "Boost", "可购买 Boost 主文本错误")
	assert(boost.Texts.Text2.Text == "2x Cash", "Boost 收入文本错误")
	assert(not boost.Texts.Text3.Visible, "收入事务不应显示 HP")
	assert(not boost.Texts.Text4.Visible, "收入事务不应显示自动领取")
	assert(boost.Money.Visible, "Boost 游戏现金价格被隐藏")

	local healthBoost = ButtonWorldUIPresentationRules.Resolve({
		Kind = "IncomeBoost",
		Cost = 200,
		TransactionKind = "Health",
		Completed = false,
		State = "Ready",
	})
	assert(not healthBoost.Texts.Text2.Visible, "生命事务不应显示收入")
	assert(healthBoost.Texts.Text3.Text == "2x HP", "Boost HP 文本错误")
	assert(not healthBoost.Texts.Text4.Visible, "生命事务不应显示自动领取")

	local autoBoost = ButtonWorldUIPresentationRules.Resolve({
		Kind = "IncomeBoost",
		Cost = 300,
		TransactionKind = "AutoIncome",
		Completed = false,
		State = "Ready",
	})
	assert(autoBoost.Texts.Text4.Text == "Auto Collect", "Boost 自动领取文本错误")
	assert(not autoBoost.Texts.Text2.Visible and not autoBoost.Texts.Text3.Visible, "自动事务显示了其他效果")

	local lockedBoost = ButtonWorldUIPresentationRules.Resolve({
		Kind = "IncomeBoost",
		Cost = 100,
		TransactionKind = "Income",
		Completed = false,
		State = "Locked",
	})
	assert(lockedBoost.Texts.Text1.Text == "Locked", "未解锁 Boost 主文本错误")
	assert(not lockedBoost.Texts.Text2.Visible, "未解锁 Boost 不应显示收入效果")
	assert(not lockedBoost.Texts.Text3.Visible, "未解锁 Boost 不应显示 HP 效果")
	assert(not lockedBoost.Texts.Text4.Visible, "未解锁 Boost 不应显示自动领取效果")
	assert(not lockedBoost.Money.Visible, "未解锁 Boost 不应显示价格")

	local purchasedBoost = ButtonWorldUIPresentationRules.Resolve({
		Kind = "IncomeBoost",
		Cost = 0,
		TransactionKind = nil,
		Completed = true,
		State = "Special",
	})
	assert(purchasedBoost.Texts.Text1.Text == "MAX", "已购买 Boost 主文本错误")
	assert(not purchasedBoost.Texts.Text2.Visible, "已购买 Boost 不应继续显示收入效果")
	assert(not purchasedBoost.Texts.Text3.Visible, "已购买 Boost 不应继续显示 HP 效果")
	assert(not purchasedBoost.Texts.Text4.Visible, "已购买 Boost 不应继续显示自动领取效果")
	assert(not purchasedBoost.Money.Visible, "已购买 Boost 不应显示价格")

	local monster = ButtonWorldUIPresentationRules.Resolve({
		Kind = "MonsterBuild",
		Cost = 500,
	})
	assert(monster.Texts.Text1.Text == "Build Monster", "怪兽孵化建造文本错误")
	assert(monster.Money.Text == "500", "怪兽孵化价格错误")

	local oldMonsterPrimary = ButtonWorldUIPresentationRules.Resolve({
		Kind = "MonsterPrimary",
		Cost = 500,
	})
	assert(not oldMonsterPrimary.Enabled, "实体怪兽按钮不得继续暴露升级入口")
	return true
end

return ButtonWorldUIPresentationRulesSpec
