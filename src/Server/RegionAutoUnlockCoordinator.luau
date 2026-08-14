--[[
	职责：在区域升级达到配置门槛后，提交所有配置为自动解锁的后继区域。
	输入：Player、刚升级的前置 ZoneId 和新等级。
	输出：本次实际自动解锁的 ZoneId 数组。
	内部算法：扫描 ZoneCatalog 的直接后继 → 校验 AutoUnlockWhenPrerequisiteMet →
	复用 RegionUpgradeService.Unlock 提交权威状态和任务事件 → 发布区域扩展提示。
	不负责：升级区域、刷新 Plot 可见性、创建房屋或保存玩家数据。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ExpandedPresentationPublisher = require(script.Parent.ExpandedPresentationPublisher)
local RegionStateService = require(script.Parent.RegionStateService)
local RegionUpgradeService = require(script.Parent.RegionUpgradeService)
local ZoneCatalog = require(ReplicatedStorage.Shared.World.ZoneCatalog)

local RegionAutoUnlockCoordinator = {}

function RegionAutoUnlockCoordinator.UnlockEligibleDependents(
	player: Player,
	prerequisiteZoneId: string,
	prerequisiteLevel: number
): { string }
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	assert(type(prerequisiteZoneId) == "string" and prerequisiteZoneId ~= "", "前置 ZoneId 无效")
	assert(type(prerequisiteLevel) == "number" and prerequisiteLevel >= 0, "前置等级无效")

	local unlockedZoneIds = {}
	for _, definition in ZoneCatalog.GetAll() do
		if definition.AutoUnlockWhenPrerequisiteMet ~= true
			or definition.UnlockPrerequisiteZoneId ~= prerequisiteZoneId
			or prerequisiteLevel < assert(definition.UnlockPrerequisiteLevel)
			or RegionStateService.GetUnlocked(player, definition.ZoneId)
		then
			continue
		end

		RegionUpgradeService.Unlock(player, definition.ZoneId)
		if not RegionStateService.GetUnlocked(player, definition.ZoneId) then
			warn(string.format(
				"自动解锁区域失败：%s/%s",
				player.Name,
				definition.ZoneId
			))
			continue
		end

		table.insert(unlockedZoneIds, definition.ZoneId)
		local published = ExpandedPresentationPublisher.PublishRegionExpanded(
			player,
			definition.ZoneId
		)
		if not published.Succeeded then
			warn(string.format(
				"自动解锁区域提示发布失败：%s/%s (%s)",
				player.Name,
				definition.ZoneId,
				published.Reason or "Unknown"
			))
		end
	end
	return unlockedZoneIds
end

return table.freeze(RegionAutoUnlockCoordinator)
