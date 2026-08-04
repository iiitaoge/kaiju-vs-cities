--[[
	职责：保存玩家已完成的新手引导版本，并向客户端提供只读 Attribute 镜像。
	输入：Get 接收 player；Restore 接收持久化版本；Complete 接收成功发起攻击的 player。
	输出：当前非负整数版本。
	内部算法：权威值写入 PlayerStateService.Progression，镜像写入 Player Attribute。
	不负责：步骤解析、条件查询、攻击校验、Remote 或 DataStore。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerStateService = require(script.Parent.PlayerStateService)
local TutorialProgression = require(
	ReplicatedStorage.Shared.Tutorial.TutorialProgression
)
local TutorialProtocol = require(ReplicatedStorage.Shared.Tutorial.TutorialProtocol)

local TutorialProgressStateService = {}

local STATE_ATTRIBUTE_NAME = "TutorialCompletedVersion"
local DEFAULT_VERSION = 0

local function assertVersion(version: number)
	assert(
		type(version) == "number"
			and version == version
			and version < math.huge
			and version >= 0
			and version % 1 == 0,
		"version 必须是有限非负整数"
	)
end

local function getSection(player: Player): Folder
	local section = PlayerStateService.GetSection(player, "Progression")
	if section:GetAttribute(STATE_ATTRIBUTE_NAME) == nil then
		section:SetAttribute(STATE_ATTRIBUTE_NAME, DEFAULT_VERSION)
	end
	return section
end

local function write(player: Player, version: number): number
	getSection(player):SetAttribute(STATE_ATTRIBUTE_NAME, version)
	player:SetAttribute(TutorialProtocol.CompletedVersionAttributeName, version)
	return version
end

function TutorialProgressStateService.Get(player: Player): number
	local version = getSection(player):GetAttribute(STATE_ATTRIBUTE_NAME) or DEFAULT_VERSION
	if player:GetAttribute(TutorialProtocol.CompletedVersionAttributeName) ~= version then
		player:SetAttribute(TutorialProtocol.CompletedVersionAttributeName, version)
	end
	return version
end

function TutorialProgressStateService.Restore(player: Player, version: number): number
	assertVersion(version)
	return write(player, version)
end

function TutorialProgressStateService.Complete(player: Player): number
	return write(
		player,
		math.max(TutorialProgressStateService.Get(player), TutorialProgression.CurrentVersion)
	)
end

return TutorialProgressStateService
