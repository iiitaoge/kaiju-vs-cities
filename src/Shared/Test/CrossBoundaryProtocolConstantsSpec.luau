local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CityBuildingPresentationProtocol = require(
	ReplicatedStorage.Shared.Building.CityBuildingPresentationProtocol
)
local EightPlayerCapacityAcceptanceProtocol = require(
	ReplicatedStorage.Shared.Test.EightPlayerCapacityAcceptanceProtocol
)
local MoneyProtocol = require(ReplicatedStorage.Shared.Economy.MoneyProtocol)
local MonsterBuildPresentationProtocol = require(
	ReplicatedStorage.Shared.Monster.MonsterBuildPresentationProtocol
)
local MultiplayerAttackAcceptanceProtocol = require(
	ReplicatedStorage.Shared.Test.MultiplayerAttackAcceptanceProtocol
)
local StudioSaveResetProtocol = require(
	ReplicatedStorage.Shared.Persistence.StudioSaveResetProtocol
)

local CrossBoundaryProtocolConstantsSpec = {}

local function expect(condition: boolean, message: string)
	assert(condition, "CrossBoundaryProtocolConstantsSpec: " .. message)
end

-- 输入：服务端与客户端共同使用的 Remote/Attribute 协议模块。
-- 输出：名称、互异性和纯常量模块只读约束稳定时返回 true。
-- 内部算法：核对精确字符串并拒绝对冻结配置表的运行时改写。
function CrossBoundaryProtocolConstantsSpec.Run(): boolean
	expect(
		CityBuildingPresentationProtocol.RemoteName == "CityBuildingPresentation",
		"城市建筑表现 Remote 名称漂移"
	)
	expect(
		MonsterBuildPresentationProtocol.RemoteName == "MonsterBuildPresentation",
		"怪兽建造表现 Remote 名称漂移"
	)
	expect(
		StudioSaveResetProtocol.RemoteName == "StudioSaveReset",
		"Studio 删档 Remote 名称漂移"
	)
	expect(MoneyProtocol.BalanceAttributeName == "MoneyBalance", "余额 Attribute 名称漂移")
	expect(
		MultiplayerAttackAcceptanceProtocol.RemoteName
			== "CodexMultiplayerAttackAcceptance",
		"多人攻击验收 Remote 名称漂移"
	)
	expect(
		MultiplayerAttackAcceptanceProtocol.TestArgument
			== "MultiplayerAttackAcceptance",
		"多人攻击验收启动参数漂移"
	)
	expect(
		MultiplayerAttackAcceptanceProtocol.RequiredPlayerCount == 3,
		"多人攻击验收所需玩家数漂移"
	)
	expect(
		EightPlayerCapacityAcceptanceProtocol.TestArgument
			== "EightPlayerCapacityAcceptance",
		"八人容量验收启动参数漂移"
	)
	expect(
		EightPlayerCapacityAcceptanceProtocol.RequiredPlayerCount == 8,
		"八人容量验收所需玩家数漂移"
	)
	expect(
		CityBuildingPresentationProtocol.RemoteName
			~= MonsterBuildPresentationProtocol.RemoteName,
		"城市与怪兽表现 Remote 不得重名"
	)
	expect(table.isfrozen(StudioSaveResetProtocol), "Studio 删档协议必须只读")
	expect(table.isfrozen(MoneyProtocol), "余额协议必须只读")
	expect(
		table.isfrozen(MultiplayerAttackAcceptanceProtocol),
		"多人攻击验收协议必须只读"
	)
	expect(
		table.isfrozen(EightPlayerCapacityAcceptanceProtocol),
		"八人容量验收协议必须只读"
	)
	expect(
		not pcall(function()
			StudioSaveResetProtocol.RemoteName = "Changed"
		end),
		"Studio 删档协议接受了运行时改写"
	)
	expect(
		not pcall(function()
			MoneyProtocol.BalanceAttributeName = "Changed"
		end),
		"余额协议接受了运行时改写"
	)
	expect(
		not pcall(function()
			EightPlayerCapacityAcceptanceProtocol.RequiredPlayerCount = 7
		end),
		"八人容量验收协议接受了运行时改写"
	)
	return true
end

return CrossBoundaryProtocolConstantsSpec
