--[[
	职责：可逆地隐藏或恢复一个静态 Zone 场景容器。

	输入：Model 或 Folder 容器，以及目标 visible。
	输出：是否改变了容器隐藏状态。
	内部算法：隐藏时保存 BasePart、Decal、Texture 和 SurfaceGui 的原属性；
		BasePart 同时关闭 CanCollide、CanTouch、CanQuery；恢复时逐项还原并清理临时 Attribute。

	不负责：解释 Zone 状态、选择 Decoration/按钮、玩家 Plot 或业务解锁。
]]

local ZoneSceneVisibility = {}

local HIDDEN_ATTRIBUTE = "ZoneSceneHidden"
local ORIGINAL_TRANSPARENCY_ATTRIBUTE = "ZoneSceneOriginalTransparency"
local ORIGINAL_CAN_COLLIDE_ATTRIBUTE = "ZoneSceneOriginalCanCollide"
local ORIGINAL_CAN_TOUCH_ATTRIBUTE = "ZoneSceneOriginalCanTouch"
local ORIGINAL_CAN_QUERY_ATTRIBUTE = "ZoneSceneOriginalCanQuery"
local ORIGINAL_ENABLED_ATTRIBUTE = "ZoneSceneOriginalEnabled"

local function assertContainer(container: Instance)
	assert(
		typeof(container) == "Instance"
			and (container:IsA("Model") or container:IsA("Folder")),
		"container 必须是 Model 或 Folder"
	)
end

local function hide(container: Instance): boolean
	if container:GetAttribute(HIDDEN_ATTRIBUTE) == true then
		return false
	end
	for _, descendant in container:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant:SetAttribute(
				ORIGINAL_TRANSPARENCY_ATTRIBUTE,
				descendant.Transparency
			)
			descendant:SetAttribute(
				ORIGINAL_CAN_COLLIDE_ATTRIBUTE,
				descendant.CanCollide
			)
			descendant:SetAttribute(ORIGINAL_CAN_TOUCH_ATTRIBUTE, descendant.CanTouch)
			descendant:SetAttribute(ORIGINAL_CAN_QUERY_ATTRIBUTE, descendant.CanQuery)
			descendant.Transparency = 1
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			descendant:SetAttribute(
				ORIGINAL_TRANSPARENCY_ATTRIBUTE,
				descendant.Transparency
			)
			descendant.Transparency = 1
		elseif descendant:IsA("SurfaceGui") then
			descendant:SetAttribute(ORIGINAL_ENABLED_ATTRIBUTE, descendant.Enabled)
			descendant.Enabled = false
		end
	end
	container:SetAttribute(HIDDEN_ATTRIBUTE, true)
	return true
end

local function restore(container: Instance): boolean
	if container:GetAttribute(HIDDEN_ATTRIBUTE) ~= true then
		return false
	end
	for _, descendant in container:GetDescendants() do
		if descendant:IsA("BasePart") then
			local transparency = descendant:GetAttribute(ORIGINAL_TRANSPARENCY_ATTRIBUTE)
			local canCollide = descendant:GetAttribute(ORIGINAL_CAN_COLLIDE_ATTRIBUTE)
			local canTouch = descendant:GetAttribute(ORIGINAL_CAN_TOUCH_ATTRIBUTE)
			local canQuery = descendant:GetAttribute(ORIGINAL_CAN_QUERY_ATTRIBUTE)
			if type(transparency) == "number" then
				descendant.Transparency = transparency
			end
			if type(canCollide) == "boolean" then
				descendant.CanCollide = canCollide
			end
			if type(canTouch) == "boolean" then
				descendant.CanTouch = canTouch
			end
			if type(canQuery) == "boolean" then
				descendant.CanQuery = canQuery
			end
			descendant:SetAttribute(ORIGINAL_TRANSPARENCY_ATTRIBUTE, nil)
			descendant:SetAttribute(ORIGINAL_CAN_COLLIDE_ATTRIBUTE, nil)
			descendant:SetAttribute(ORIGINAL_CAN_TOUCH_ATTRIBUTE, nil)
			descendant:SetAttribute(ORIGINAL_CAN_QUERY_ATTRIBUTE, nil)
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			local transparency = descendant:GetAttribute(ORIGINAL_TRANSPARENCY_ATTRIBUTE)
			if type(transparency) == "number" then
				descendant.Transparency = transparency
			end
			descendant:SetAttribute(ORIGINAL_TRANSPARENCY_ATTRIBUTE, nil)
		elseif descendant:IsA("SurfaceGui") then
			local enabled = descendant:GetAttribute(ORIGINAL_ENABLED_ATTRIBUTE)
			if type(enabled) == "boolean" then
				descendant.Enabled = enabled
			end
			descendant:SetAttribute(ORIGINAL_ENABLED_ATTRIBUTE, nil)
		end
	end
	container:SetAttribute(HIDDEN_ATTRIBUTE, nil)
	return true
end

function ZoneSceneVisibility.SetVisible(container: Instance, visible: boolean): boolean
	assertContainer(container)
	assert(type(visible) == "boolean", "visible 必须是 boolean")
	return if visible then restore(container) else hide(container)
end

function ZoneSceneVisibility.IsVisible(container: Instance): boolean
	assertContainer(container)
	return container:GetAttribute(HIDDEN_ATTRIBUTE) ~= true
end

return table.freeze(ZoneSceneVisibility)
