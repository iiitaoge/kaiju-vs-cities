--[[
	职责：解析 HUD.Panel 中供怪兽攻击与升级共用的管理面板。
	输入：本地 PlayerGui。
	输出：HUD.Panel、标题、发动攻击按钮、升级按钮及其显示文本；失败返回稳定原因。
	内部算法：按 HUD.Panel 的稳定层级解析控件；Money 数值兼容旧模板的 Frame 和新 HUD 的 Money 子节点。
	不负责：面板显隐、怪兽状态、攻击目标、升级请求或货币计算。
]]

local LocalMonsterManagementPanelAccess = {}

export type References = {
	Gui: ScreenGui,
	Panel: Frame,
	Title: TextLabel,
	StartButton: TextButton,
	StartValue: TextLabel,
	MoneyButton: TextButton,
	MoneyValue: TextLabel,
	Robux: Frame,
}

local function childOfClass(parent: Instance?, name: string, className: string): Instance?
	local child = parent and parent:FindFirstChild(name)
	return if child and child:IsA(className) then child else nil
end

local function missing(path: string): (nil, string)
	return nil, "InvalidMonsterManagementHUDHierarchy:Missing:" .. path
end

function LocalMonsterManagementPanelAccess.Resolve(
	playerGui: PlayerGui
): (References?, string?)
	assert(playerGui:IsA("PlayerGui"), "playerGui 必须是 PlayerGui")

	local gui = childOfClass(playerGui, "HUD", "ScreenGui")
	if not gui then
		return missing("HUD")
	end
	local panel = childOfClass(gui, "Panel", "Frame")
	if not panel then
		return missing("HUD.Panel")
	end

	local titleFrame = childOfClass(panel, "Title", "Frame")
	local title = childOfClass(titleFrame, "Title", "TextLabel")
	if not title then
		return missing("HUD.Panel.Title.Title")
	end

	local startFrame = childOfClass(panel, "Start", "Frame")
	local startButton = childOfClass(startFrame, "Button", "TextButton")
	local startValue = childOfClass(startButton, "Val", "TextLabel")
	if not startButton or not startValue then
		return missing("HUD.Panel.Start.Button.Val")
	end

	local moneyFrame = childOfClass(panel, "Money", "Frame")
	local moneyButton = childOfClass(moneyFrame, "Button", "TextButton")
	local moneyValueFrame = childOfClass(moneyButton, "Money", "Frame")
		or childOfClass(moneyButton, "Frame", "Frame")
	local moneyValue = childOfClass(moneyValueFrame, "Val", "TextLabel")
	if not moneyButton or not moneyValue then
		return missing("HUD.Panel.Money.Button.Money.Val")
	end

	local robux = childOfClass(panel, "Robux", "Frame")
	if not robux then
		return missing("HUD.Panel.Robux")
	end

	return {
		Gui = gui :: ScreenGui,
		Panel = panel :: Frame,
		Title = title :: TextLabel,
		StartButton = startButton :: TextButton,
		StartValue = startValue :: TextLabel,
		MoneyButton = moneyButton :: TextButton,
		MoneyValue = moneyValue :: TextLabel,
		Robux = robux :: Frame,
	}, nil
end

function LocalMonsterManagementPanelAccess.Wait(
	playerGui: PlayerGui
): (References?, string?)
	assert(playerGui:IsA("PlayerGui"), "playerGui 必须是 PlayerGui")

	while playerGui.Parent do
		local refs = LocalMonsterManagementPanelAccess.Resolve(playerGui)
		if refs then
			return refs, nil
		end
		playerGui.DescendantAdded:Wait()
	end

	return nil, "PlayerGuiRemoved"
end

return LocalMonsterManagementPanelAccess
