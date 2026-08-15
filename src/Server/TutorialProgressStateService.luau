--[[
	职责：保存玩家新手引导版本和首次攻击中间进度，并向客户端提供只读 Attribute 镜像。
	输入：Get/GetAttackCompleted 接收 player；Restore 接收持久化版本和可选攻击进度；MarkAttackCompleted 接收成功攻击的 player；Complete 接收防守哥斯拉建造完成的 player。
	输出：当前非负整数版本或攻击是否完成。
	内部算法：权威值写入 PlayerStateService.Progression，镜像写入 Player Attribute；旧版 Version=1 存档自动恢复为攻击已完成。
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
local ATTACK_COMPLETED_ATTRIBUTE_NAME = "TutorialAttackCompleted"
local DEFAULT_VERSION = 0
local DEFAULT_ATTACK_COMPLETED = false

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
	if section:GetAttribute(ATTACK_COMPLETED_ATTRIBUTE_NAME) == nil then
		section:SetAttribute(ATTACK_COMPLETED_ATTRIBUTE_NAME, DEFAULT_ATTACK_COMPLETED)
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

function TutorialProgressStateService.GetAttackCompleted(player: Player): boolean
	local version = TutorialProgressStateService.Get(player)
	local section = getSection(player)
	return section:GetAttribute(ATTACK_COMPLETED_ATTRIBUTE_NAME) == true
		or version >= TutorialProgression.AttackCompletedVersion
end

function TutorialProgressStateService.Restore(
	player: Player,
	version: number,
	attackCompleted: boolean?
): number
	assertVersion(version)
	assert(
		attackCompleted == nil or type(attackCompleted) == "boolean",
		"attackCompleted 必须是 boolean 或 nil"
	)
	getSection(player):SetAttribute(
		ATTACK_COMPLETED_ATTRIBUTE_NAME,
		attackCompleted == true or version >= TutorialProgression.AttackCompletedVersion
	)
	return write(player, version)
end

function TutorialProgressStateService.MarkAttackCompleted(player: Player): number
	local version = TutorialProgressStateService.Get(player)
	getSection(player):SetAttribute(ATTACK_COMPLETED_ATTRIBUTE_NAME, true)
	return version
end

function TutorialProgressStateService.Complete(player: Player): number
	getSection(player):SetAttribute(ATTACK_COMPLETED_ATTRIBUTE_NAME, true)
	return write(
		player,
		math.max(TutorialProgressStateService.Get(player), TutorialProgression.CurrentVersion)
	)
end

function TutorialProgressStateService.CompleteAfterDefenseMonsterBuild(player: Player): number
	if not TutorialProgressStateService.GetAttackCompleted(player) then
		return TutorialProgressStateService.Get(player)
	end
	return TutorialProgressStateService.Complete(player)
end

return TutorialProgressStateService
