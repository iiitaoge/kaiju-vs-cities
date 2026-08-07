--[[
	职责：解析玩家攻击列表 UI 的稳定场景合同。
	输入：本地 PlayerGui。
	输出：攻击入口、Destroy 面板、关闭按钮、列表容器和 Unit 模板引用。
	内部算法：按固定层级逐项校验 Instance 类型；Wait 通过 DescendantAdded 吸收 UI 复制时序。
	不负责：查询怪兽状态、克隆 Unit、设置等级或打开攻击选择。
]]

local LocalMonsterAttackRosterUIAccess = {}

export type References = {
	AttackButton: GuiButton,
	DestroyPanel: GuiObject,
	CloseButton: GuiButton,
	ScrollingFrame: ScrollingFrame,
	UnitTemplate: GuiObject,
}

local function childOfClass(
	parent: Instance,
	name: string,
	className: string,
	path: string
): (Instance?, string?)
	local child = parent:FindFirstChild(name)
	if not child then
		return nil, "InvalidMonsterAttackRosterUIHierarchy:Missing:" .. path
	end
	if not child:IsA(className) then
		return nil, string.format(
			"InvalidMonsterAttackRosterUIHierarchy:WrongClass:%s:Expected=%s:Actual=%s",
			path,
			className,
			child.ClassName
		)
	end
	return child, nil
end

function LocalMonsterAttackRosterUIAccess.Resolve(
	playerGui: PlayerGui
): (References?, string?)
	assert(playerGui:IsA("PlayerGui"), "playerGui 必须是 PlayerGui")

	local hud, reason = childOfClass(playerGui, "HUD", "ScreenGui", "HUD")
	if not hud then
		return nil, reason
	end
	local right
	right, reason = childOfClass(hud, "Right", "GuiObject", "HUD.Right")
	if not right then
		return nil, reason
	end
	local attackButton
	attackButton, reason = childOfClass(
		right,
		"Attack",
		"GuiButton",
		"HUD.Right.Attack"
	)
	if not attackButton then
		return nil, reason
	end

	local main, mainReason = childOfClass(playerGui, "Main", "ScreenGui", "Main")
	if not main then
		return nil, mainReason
	end
	local destroyPanel
	destroyPanel, reason = childOfClass(main, "Destroy", "GuiObject", "Main.Destroy")
	if not destroyPanel then
		return nil, reason
	end
	local mainAll
	mainAll, reason = childOfClass(
		destroyPanel,
		"MainAll",
		"GuiObject",
		"Main.Destroy.MainAll"
	)
	if not mainAll then
		return nil, reason
	end
	local title
	title, reason = childOfClass(
		mainAll,
		"Title",
		"GuiObject",
		"Main.Destroy.MainAll.Title"
	)
	if not title then
		return nil, reason
	end
	local closeButton
	closeButton, reason = childOfClass(
		title,
		"Close",
		"GuiButton",
		"Main.Destroy.MainAll.Title.Close"
	)
	if not closeButton then
		return nil, reason
	end

	local mainContent
	mainContent, reason = childOfClass(
		mainAll,
		"Main",
		"GuiObject",
		"Main.Destroy.MainAll.Main"
	)
	if not mainContent then
		return nil, reason
	end
	local scrollingFrame
	scrollingFrame, reason = childOfClass(
		mainContent,
		"ScrollingFrame",
		"ScrollingFrame",
		"Main.Destroy.MainAll.Main.ScrollingFrame"
	)
	if not scrollingFrame then
		return nil, reason
	end
	local unitTemplate
	unitTemplate, reason = childOfClass(
		scrollingFrame,
		"Unit",
		"GuiObject",
		"Main.Destroy.MainAll.Main.ScrollingFrame.Unit"
	)
	if not unitTemplate then
		return nil, reason
	end

	return {
		AttackButton = attackButton :: GuiButton,
		DestroyPanel = destroyPanel :: GuiObject,
		CloseButton = closeButton :: GuiButton,
		ScrollingFrame = scrollingFrame :: ScrollingFrame,
		UnitTemplate = unitTemplate :: GuiObject,
	}, nil
end

function LocalMonsterAttackRosterUIAccess.Wait(
	playerGui: PlayerGui
): (References?, string?)
	assert(playerGui:IsA("PlayerGui"), "playerGui 必须是 PlayerGui")

	while playerGui.Parent do
		local references = LocalMonsterAttackRosterUIAccess.Resolve(playerGui)
		if references then
			return references, nil
		end
		playerGui.DescendantAdded:Wait()
	end

	return nil, "PlayerGuiRemoved"
end

return LocalMonsterAttackRosterUIAccess
