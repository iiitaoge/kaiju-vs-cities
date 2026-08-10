--[[
	职责：提供攻击选择期间给新手引导读取的只读交互状态。
	输入：攻击面板控制器写入当前目标领地边界和移动端是否已经瞄准。
	输出：教程可读取的攻击面板打开、目标边界与移动端瞄准状态。
	内部算法：只保存当前本地攻击选择会话的瞬时状态；会话结束时恢复为空状态。
	不负责：选择目标、校验落点、提交攻击、创建 UI 或判断教程进度。
]]

local LocalAttackSelectionTutorialState = {}

export type Snapshot = {
	IsOpen: boolean,
	MobileAimReady: boolean,
	WorldGuideCFrame: CFrame?,
	WorldGuideSize: Vector3?,
}

local state: Snapshot = {
	IsOpen = false,
	MobileAimReady = false,
	WorldGuideCFrame = nil,
	WorldGuideSize = nil,
}

local function clear()
	state = {
		IsOpen = false,
		MobileAimReady = false,
		WorldGuideCFrame = nil,
		WorldGuideSize = nil,
	}
end

function LocalAttackSelectionTutorialState.Begin()
	state = {
		IsOpen = true,
		MobileAimReady = false,
		WorldGuideCFrame = nil,
		WorldGuideSize = nil,
	}
end

function LocalAttackSelectionTutorialState.SetWorldGuideBounds(
	worldCFrame: CFrame?,
	worldSize: Vector3?
)
	if not state.IsOpen then
		return
	end
	if worldCFrame == nil or worldSize == nil then
		state.WorldGuideCFrame = nil
		state.WorldGuideSize = nil
		return
	end
	if typeof(worldCFrame) ~= "CFrame"
		or typeof(worldSize) ~= "Vector3"
		or worldSize.X <= 0
		or worldSize.Y <= 0
		or worldSize.Z <= 0
	then
		state.WorldGuideCFrame = nil
		state.WorldGuideSize = nil
		return
	end
	state.WorldGuideCFrame = worldCFrame
	state.WorldGuideSize = worldSize
end

function LocalAttackSelectionTutorialState.SetMobileAimReady(ready: boolean)
	if not state.IsOpen then
		return
	end
	state.MobileAimReady = ready == true
end

function LocalAttackSelectionTutorialState.End()
	clear()
end

function LocalAttackSelectionTutorialState.Get(): Snapshot
	return {
		IsOpen = state.IsOpen,
		MobileAimReady = state.MobileAimReady,
		WorldGuideCFrame = state.WorldGuideCFrame,
		WorldGuideSize = state.WorldGuideSize,
	}
end

return table.freeze(LocalAttackSelectionTutorialState)
