--[[
	职责：验证并返回培养罐内 MonsterUI 的稳定控件引用。
	输入：一个运行时培养罐 Model。
	输出：控件引用表，或 nil 与稳定失败原因。
	不负责：查找玩家 Plot、绑定按钮、请求服务器或渲染文案。
]]

local LocalMonsterIncubatorUIAccess = {}

export type References = {
	Glass: BasePart,
	Attachment: Attachment,
	Gui: BillboardGui,
	Panel: Frame,
	Title: TextLabel,
	StartButton: TextButton,
	StartValue: TextLabel,
	MoneyButton: TextButton,
	MoneyValue: TextLabel,
	Robux: Frame,
}

export type WorldReferences = {
	Glass: BasePart,
	Attachment: Attachment?,
	Gui: BillboardGui?,
}

local function childOfClass(parent: Instance, name: string, className: string): Instance?
	local child = parent:FindFirstChild(name)
	return if child and child:IsA(className) then child else nil
end

function LocalMonsterIncubatorUIAccess.ResolveWorld(
	incubator: Model
): (WorldReferences?, string?)
	if typeof(incubator) ~= "Instance" or not incubator:IsA("Model") then
		return nil, "InvalidIncubator"
	end
	local glass = childOfClass(incubator, "Glass", "BasePart")
	local attachment = glass and childOfClass(glass, "MonsterUIAttachment", "Attachment")
	local gui = attachment and childOfClass(attachment, "MonsterUI", "BillboardGui")
	if not glass then
		return nil, "InvalidMonsterIncubatorWorldHierarchy:Missing:Glass"
	end
	return {
		Glass = glass :: BasePart,
		Attachment = if attachment then attachment :: Attachment else nil,
		Gui = if gui then gui :: BillboardGui else nil,
	}, nil
end

function LocalMonsterIncubatorUIAccess.Resolve(incubator: Model): (References?, string?)
	local world, worldReason = LocalMonsterIncubatorUIAccess.ResolveWorld(incubator)
	if not world then
		return nil, worldReason
	end
	local glass = world.Glass
	local attachment = world.Attachment
	local gui = world.Gui
	local panel = gui and childOfClass(gui, "Panel", "Frame")
	local titleFrame = panel and childOfClass(panel, "Title", "Frame")
	local title = titleFrame and childOfClass(titleFrame, "Title", "TextLabel")
	local startFrame = panel and childOfClass(panel, "Start", "Frame")
	local startButton = startFrame and childOfClass(startFrame, "Button", "TextButton")
	local startValue = startButton and childOfClass(startButton, "Val", "TextLabel")
	local moneyFrame = panel and childOfClass(panel, "Money", "Frame")
	local moneyButton = moneyFrame and childOfClass(moneyFrame, "Button", "TextButton")
	local moneyValueFrame = moneyButton and childOfClass(moneyButton, "Frame", "Frame")
	local moneyValue = moneyValueFrame and childOfClass(moneyValueFrame, "Val", "TextLabel")
	local robux = panel and childOfClass(panel, "Robux", "Frame")

	if not glass or not attachment or not gui or not panel or not title or not startButton or not startValue
		or not moneyButton or not moneyValue or not robux
	then
		return nil, "InvalidMonsterUIHierarchy"
	end
	return {
		Glass = glass,
		Attachment = attachment,
		Gui = gui,
		Panel = panel,
		Title = title,
		StartButton = startButton,
		StartValue = startValue,
		MoneyButton = moneyButton,
		MoneyValue = moneyValue,
		Robux = robux,
	}, nil
end

return LocalMonsterIncubatorUIAccess
