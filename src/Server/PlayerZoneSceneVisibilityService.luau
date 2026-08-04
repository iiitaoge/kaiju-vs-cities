--[[
	职责：按玩家权威 Zone 解锁状态控制其 Plot 的 Decoration 和实体按钮可见性。

	输入：Apply 接收 Player、ZoneId；ApplyAll 接收 Player；Start 注册玩家加载生命周期。
	输出：Apply 返回是否成功、Reason，以及 Decoration/按钮处理数量。
	内部算法：前置满足的锁定 Zone 只显示 <ZoneId>-Unlock-Button；未满足前置时全部隐藏；
		解锁后显示 Decoration 和其他按钮，同时隐藏 Unlock。属性恢复委托 ZoneSceneVisibility。

	不负责：扣款、修改 Unlocked/Level、创建房屋、创建或复制场景内容。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataReadyService = require(script.Parent.PlayerDataReadyService)
local PlayerPlotAssignmentService = require(script.Parent.PlayerPlotAssignmentService)
local ZoneSceneVisibility = require(script.Parent.ZoneSceneVisibility)
local ZoneStateService = require(script.Parent.ZoneStateService)
local ZoneCatalog = require(ReplicatedStorage.Shared.World.ZoneCatalog)

local PlayerZoneSceneVisibilityService = {}

local started = false

local function isContainer(instance: Instance?): boolean
	return instance ~= nil and (instance:IsA("Model") or instance:IsA("Folder"))
end

function PlayerZoneSceneVisibilityService.Apply(player: Player, zoneId: string)
	assert(
		typeof(player) == "Instance" and player:IsA("Player"),
		"player 必须是 Player"
	)
	assert(type(zoneId) == "string" and zoneId ~= "", "zoneId 必须是非空字符串")
	if player.Parent ~= Players then
		return { Succeeded = false, Reason = "PlayerUnavailable", DecorationCount = 0, ButtonCount = 0 }
	end
	local definition = ZoneCatalog.Get(zoneId)
	if not definition then
		return { Succeeded = false, Reason = "UnknownZone", DecorationCount = 0, ButtonCount = 0 }
	end

	local plot, plotReason = PlayerPlotAssignmentService.GetPlot(player)
	if not plot then
		return {
			Succeeded = false,
			Reason = plotReason or "PlayerPlotUnavailable",
			DecorationCount = 0,
			ButtonCount = 0,
		}
	end
	local zones = plot:FindFirstChild("Zones")
	local zone = zones and zones:FindFirstChild(zoneId)
	if not isContainer(zone) then
		return { Succeeded = false, Reason = "ZoneSceneUnavailable", DecorationCount = 0, ButtonCount = 0 }
	end

	local unlocked = ZoneStateService.GetUnlocked(player, zoneId)
	local prerequisiteZoneId = definition.UnlockPrerequisiteZoneId
	local prerequisiteLevel = definition.UnlockPrerequisiteLevel
	local prerequisiteMet = prerequisiteZoneId == nil
		or (ZoneStateService.GetUnlocked(player, prerequisiteZoneId)
			and ZoneStateService.GetLevel(player, prerequisiteZoneId)
				>= assert(prerequisiteLevel))
	local decorationCount = 0
	local decoration = zone:FindFirstChild("Decoration")
	if isContainer(decoration) then
		ZoneSceneVisibility.SetVisible(decoration, unlocked)
		decorationCount = 1
	end

	local buttonCount = 0
	local buttons = zone:FindFirstChild("Buttons")
	if buttons and buttons:IsA("Folder") then
		local unlockButtonName = zoneId .. "-Unlock-Button"
		for _, child in buttons:GetChildren() do
			if not child:IsA("Model") then
				continue
			end
			local isUnlockButton = child.Name == unlockButtonName
			local visible = if unlocked
				then not isUnlockButton
				else isUnlockButton and prerequisiteMet
			ZoneSceneVisibility.SetVisible(child, visible)
			buttonCount += 1
		end
	end

	return {
		Succeeded = true,
		Reason = nil,
		DecorationCount = decorationCount,
		ButtonCount = buttonCount,
	}
end

function PlayerZoneSceneVisibilityService.ApplyAll(player: Player)
	local appliedCount = 0
	for _, definition in ZoneCatalog.GetAll() do
		local result = PlayerZoneSceneVisibilityService.Apply(player, definition.ZoneId)
		if result.Succeeded then
			appliedCount += 1
		elseif result.Reason ~= "ZoneSceneUnavailable" then
			return { Succeeded = false, Reason = result.Reason, AppliedCount = appliedCount }
		end
	end
	return { Succeeded = true, Reason = nil, AppliedCount = appliedCount }
end

local function applyWhenReady(player: Player)
	local ready, readyReason = PlayerDataReadyService.Wait(player)
	if not ready or player.Parent ~= Players then
		return
	end
	local result = PlayerZoneSceneVisibilityService.ApplyAll(player)
	if not result.Succeeded then
		warn(string.format(
			"应用玩家 Zone 场景可见性失败：%s (%s)",
			player.Name,
			result.Reason or readyReason or "Unknown"
		))
	end
end

function PlayerZoneSceneVisibilityService.Start()
	if started then
		return
	end
	started = true
	Players.PlayerAdded:Connect(function(player)
		task.defer(applyWhenReady, player)
	end)
	for _, player in Players:GetPlayers() do
		task.defer(applyWhenReady, player)
	end
end

return PlayerZoneSceneVisibilityService
