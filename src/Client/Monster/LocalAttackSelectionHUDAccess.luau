--[[
	职责：按固定场景合同解析或等待本地攻击选择 HUD。
	输入：本地 PlayerGui。
	输出：HUD 根节点、目标浏览区、目标标题、左右切换按钮和退出按钮；失败时返回具体节点原因。
	内部算法：Resolve 立即检查直接子节点；Wait 由 DescendantAdded 驱动重试，吸收 UI 复制时序差异。
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

local function childOfClass(
	parent: Instance,
	name: string,
	className: string,
	path: string
): (Instance?, string?)
	local child = parent:FindFirstChild(name)
	if not child then
		return nil, "InvalidAttackSelectionHUDHierarchy:Missing:" .. path
	end
	if child.ClassName ~= className then
		return nil, string.format(
			"InvalidAttackSelectionHUDHierarchy:WrongClass:%s:Expected=%s:Actual=%s",
			path,
			className,
			child.ClassName
		)
	end
	return child, nil
end

function LocalAttackSelectionHUDAccess.Resolve(
	playerGui: PlayerGui
): (References?, string?)
	assert(playerGui:IsA("PlayerGui"), "playerGui 必须是 PlayerGui")

	local gui, reason = childOfClass(playerGui, "HUD", "ScreenGui", "HUD")
	if not gui then
		return nil, reason
	end
	local root
	root, reason = childOfClass(gui, "Launching", "Frame", "HUD.Launching")
	if not root then
		return nil, reason
	end
	local top
	top, reason = childOfClass(root, "Top", "Frame", "HUD.Launching.Top")
	if not top then
		return nil, reason
	end
	local panel
	panel, reason = childOfClass(top, "Panel", "Frame", "HUD.Launching.Top.Panel")
	if not panel then
		return nil, reason
	end
	local title
	title, reason = childOfClass(
		panel,
		"Title",
		"TextLabel",
		"HUD.Launching.Top.Panel.Title"
	)
	if not title then
		return nil, reason
	end
	local previousButton
	previousButton, reason = childOfClass(
		panel,
		"Left",
		"ImageButton",
		"HUD.Launching.Top.Panel.Left"
	)
	if not previousButton then
		return nil, reason
	end
	local nextButton
	nextButton, reason = childOfClass(
		panel,
		"Right",
		"ImageButton",
		"HUD.Launching.Top.Panel.Right"
	)
	if not nextButton then
		return nil, reason
	end
	local down
	down, reason = childOfClass(root, "Down", "Frame", "HUD.Launching.Down")
	if not down then
		return nil, reason
	end
	local exit
	exit, reason = childOfClass(down, "Exit", "Frame", "HUD.Launching.Down.Exit")
	if not exit then
		return nil, reason
	end
	local exitButton
	exitButton, reason = childOfClass(
		exit,
		"Button",
		"TextButton",
		"HUD.Launching.Down.Exit.Button"
	)
	if not exitButton then
		return nil, reason
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

function LocalAttackSelectionHUDAccess.Wait(
	playerGui: PlayerGui
): (References?, string?)
	assert(playerGui:IsA("PlayerGui"), "playerGui 必须是 PlayerGui")

	while playerGui.Parent do
		local refs = LocalAttackSelectionHUDAccess.Resolve(playerGui)
		if refs then
			return refs, nil
		end
		playerGui.DescendantAdded:Wait()
	end

	return nil, "PlayerGuiRemoved"
end

return LocalAttackSelectionHUDAccess
