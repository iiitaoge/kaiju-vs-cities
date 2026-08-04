--[[
	职责：按固定场景合同解析本地攻击选择 HUD。
	输入：本地 PlayerGui。
	输出：HUD 根节点、目标浏览区、目标标题、左右切换按钮和退出按钮；层级无效时返回稳定原因。
	内部算法：只检查直接子节点名称与 ClassName。
	不负责：显示状态、目标玩家、相机、按钮监听或攻击请求。
]]

local LocalAttackSelectionHUDAccess = {}

export type References = {
	Gui: ScreenGui,
	Root: Frame,
	BrowseControls: Frame,
	Title: TextLabel,
	PreviousButton: ImageButton,
	NextButton: ImageButton,
	ExitButton: TextButton,
}

local function childOfClass(parent: Instance?, name: string, className: string): Instance?
	local child = parent and parent:FindFirstChild(name)
	return if child and child.ClassName == className then child else nil
end

function LocalAttackSelectionHUDAccess.Resolve(
	playerGui: PlayerGui
): (References?, string?)
	assert(playerGui:IsA("PlayerGui"), "playerGui 必须是 PlayerGui")

	local gui = childOfClass(playerGui, "HUD", "ScreenGui")
	local root = childOfClass(gui, "Launching", "Frame")
	local top = childOfClass(root, "Top", "Frame")
	local panel = childOfClass(top, "Panel", "Frame")
	local title = childOfClass(panel, "Title", "TextLabel")
	local previousButton = childOfClass(panel, "Left", "ImageButton")
	local nextButton = childOfClass(panel, "Right", "ImageButton")
	local down = childOfClass(root, "Down", "Frame")
	local exit = childOfClass(down, "Exit", "Frame")
	local exitButton = childOfClass(exit, "Button", "TextButton")

	if not gui or not root or not title or not previousButton
		or not nextButton or not exitButton then
		return nil, "InvalidAttackSelectionHUDHierarchy"
	end

	return {
		Gui = gui :: ScreenGui,
		Root = root :: Frame,
		BrowseControls = top :: Frame,
		Title = title :: TextLabel,
		PreviousButton = previousButton :: ImageButton,
		NextButton = nextButton :: ImageButton,
		ExitButton = exitButton :: TextButton,
	}, nil
end

return LocalAttackSelectionHUDAccess
