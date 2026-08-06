local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CityBuildingPresentationProtocol = require(
	ReplicatedStorage.Shared.Building.CityBuildingPresentationProtocol
)
local EightPlayerCapacityAcceptanceProtocol = require(
	ReplicatedStorage.Shared.Test.EightPlayerCapacityAcceptanceProtocol
)
local IncomeHouseWorldUIProtocol = require(
	ReplicatedStorage.Shared.Building.IncomeHouseWorldUIProtocol
)
local MoneyProtocol = require(ReplicatedStorage.Shared.Economy.MoneyProtocol)
local IncomeGainPresentationProtocol = require(
	ReplicatedStorage.Shared.Economy.IncomeGainPresentationProtocol
)
local ModelMovementVisualProtocol = require(
	ReplicatedStorage.Shared.Movement.ModelMovementVisualProtocol
)
local MonsterAttackProtocol = require(
	ReplicatedStorage.Shared.Monster.MonsterAttackProtocol
)
local MonsterBuildPresentationProtocol = require(
	ReplicatedStorage.Shared.Monster.MonsterBuildPresentationProtocol
)
local MonsterManagementProtocol = require(
	ReplicatedStorage.Shared.Monster.MonsterManagementProtocol
)
local MultiplayerAttackAcceptanceProtocol = require(
	ReplicatedStorage.Shared.Test.MultiplayerAttackAcceptanceProtocol
)
local StudioSaveResetProtocol = require(
	ReplicatedStorage.Shared.Persistence.StudioSaveResetProtocol
)
local RebirthProtocol = require(ReplicatedStorage.Shared.Progression.RebirthProtocol)
local TutorialProtocol = require(ReplicatedStorage.Shared.Tutorial.TutorialProtocol)

local CrossBoundaryProtocolConstantsSpec = {}

local function expect(condition: boolean, message: string)
	assert(condition, "CrossBoundaryProtocolConstantsSpec: " .. message)
end

local function expectUniqueNonEmpty(values, kind: string)
	local seen = {}
	for label, value in values do
		expect(type(value) == "string" and value ~= "", label .. " 不是非空 " .. kind)
		expect(seen[value] == nil, string.format("%s 与 %s 的 %s 重名", label, seen[value] or "?", kind))
		seen[value] = label
	end
end

-- 输入：服务端与客户端共同使用的 Remote/Attribute 协议模块。
-- 输出：名称、互异性和纯常量模块只读约束稳定时返回 true。
-- 内部算法：核对精确字符串并拒绝对冻结配置表的运行时改写。
function CrossBoundaryProtocolConstantsSpec.Run(): boolean
	expect(
		CityBuildingPresentationProtocol.RemoteName == "CityBuildingPresentation",
		"城市建筑表现 Remote 名称漂移"
	)
	expect(MonsterAttackProtocol.TargetQueryRemoteName == "MonsterAttackTargets", "怪兽目标查询 Remote 名称漂移")
	expect(MonsterAttackProtocol.CommandRemoteName == "MonsterAttackCommand", "怪兽攻击 Remote 名称漂移")
	expect(MonsterManagementProtocol.RemoteName == "MonsterManagementRequest", "怪兽管理 Remote 名称漂移")
	expect(RebirthProtocol.RemoteName == "RebirthRequest", "重生 Remote 名称漂移")
	expect(TutorialProtocol.SnapshotRemoteName == "TutorialSnapshot", "新手引导 Remote 名称漂移")
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
		IncomeGainPresentationProtocol.RemoteName == "IncomeGainPresentation",
		"房屋收入表现 Remote 名称漂移"
	)
	expect(
		IncomeGainPresentationProtocol.Kinds.Automatic == "Automatic"
			and IncomeGainPresentationProtocol.Kinds.Touch == "Touch",
		"房屋收入表现 Kind 漂移"
	)
	expect(
		ModelMovementVisualProtocol.RemoteName == "ModelMovementVisual",
		"模型移动表现 Remote 名称漂移"
	)
	expect(ModelMovementVisualProtocol.Kinds.Move == "Move", "模型移动 Move Kind 漂移")
	expect(ModelMovementVisualProtocol.Kinds.Cancel == "Cancel", "模型移动 Cancel Kind 漂移")
	expect(ModelMovementVisualProtocol.Kinds.Snap == "Snap", "模型移动 Snap Kind 漂移")
	for _, item in {
		{ "房屋生命周期", IncomeHouseWorldUIProtocol.LifeStateAttributeName, "BuildingUILifeState" },
		{ "房屋自动收入", IncomeHouseWorldUIProtocol.AutoIncomeAttributeName, "BuildingUIAutoIncome" },
		{ "房屋每秒收入", IncomeHouseWorldUIProtocol.IncomePerSecondAttributeName, "BuildingUIIncomePerSecond" },
		{ "房屋存款", IncomeHouseWorldUIProtocol.StoredMoneyAttributeName, "BuildingUIStoredMoney" },
		{ "房屋结算时间", IncomeHouseWorldUIProtocol.LastIncomeAtAttributeName, "BuildingUILastIncomeAt" },
		{ "房屋当前生命", IncomeHouseWorldUIProtocol.CurrentHealthAttributeName, "BuildingCurrentHealth" },
		{ "房屋最大生命", IncomeHouseWorldUIProtocol.MaxHealthAttributeName, "BuildingMaxHealth" },
	} do
		local label, actual, expected = table.unpack(item)
		expect(actual == expected, label .. " Attribute 名称漂移")
	end
	expect(MonsterManagementProtocol.GetSnapshot == "GetSnapshot", "怪兽管理快照请求名称漂移")
	expect(MonsterManagementProtocol.Upgrade == "Upgrade", "怪兽管理升级请求名称漂移")
	expect(TutorialProtocol.CompletedVersionAttributeName == "TutorialCompletedVersion", "新手引导完成版本 Attribute 名称漂移")
	expect(
		MultiplayerAttackAcceptanceProtocol.RemoteName
			== "CodexMultiplayerAttackAcceptance",
		"多人攻击验收 Remote 名称漂移"
	)
	expectUniqueNonEmpty({
		CityBuildingPresentation = CityBuildingPresentationProtocol.RemoteName,
		IncomeGainPresentation = IncomeGainPresentationProtocol.RemoteName,
		MonsterBuildPresentation = MonsterBuildPresentationProtocol.RemoteName,
		MonsterAttackTargets = MonsterAttackProtocol.TargetQueryRemoteName,
		MonsterAttackCommand = MonsterAttackProtocol.CommandRemoteName,
		MonsterManagement = MonsterManagementProtocol.RemoteName,
		Rebirth = RebirthProtocol.RemoteName,
		Tutorial = TutorialProtocol.SnapshotRemoteName,
		StudioSaveReset = StudioSaveResetProtocol.RemoteName,
		ModelMovementVisual = ModelMovementVisualProtocol.RemoteName,
		MultiplayerAcceptance = MultiplayerAttackAcceptanceProtocol.RemoteName,
	}, "Remote 名称")
	expectUniqueNonEmpty({
		Money = MoneyProtocol.BalanceAttributeName,
		LifeState = IncomeHouseWorldUIProtocol.LifeStateAttributeName,
		AutoIncome = IncomeHouseWorldUIProtocol.AutoIncomeAttributeName,
		IncomePerSecond = IncomeHouseWorldUIProtocol.IncomePerSecondAttributeName,
		StoredMoney = IncomeHouseWorldUIProtocol.StoredMoneyAttributeName,
		LastIncomeAt = IncomeHouseWorldUIProtocol.LastIncomeAtAttributeName,
		CurrentHealth = IncomeHouseWorldUIProtocol.CurrentHealthAttributeName,
		MaxHealth = IncomeHouseWorldUIProtocol.MaxHealthAttributeName,
		TutorialCompletedVersion = TutorialProtocol.CompletedVersionAttributeName,
	}, "Attribute 名称")
	for label, protocol in {
		CityBuildingPresentation = CityBuildingPresentationProtocol,
		MonsterBuildPresentation = MonsterBuildPresentationProtocol,
		IncomeHouseWorldUI = IncomeHouseWorldUIProtocol,
		IncomeGainPresentation = IncomeGainPresentationProtocol,
		MonsterAttack = MonsterAttackProtocol,
		MonsterManagement = MonsterManagementProtocol,
		ModelMovementVisual = ModelMovementVisualProtocol,
		Rebirth = RebirthProtocol,
		Tutorial = TutorialProtocol,
	} do
		expect(table.isfrozen(protocol), label .. " 协议必须只读")
	end
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
		MultiplayerAttackAcceptanceProtocol.Kinds.RequestMonsterVisualSnapshot
			== "RequestMonsterVisualSnapshot"
			and MultiplayerAttackAcceptanceProtocol.Kinds.MonsterVisualSnapshot
				== "MonsterVisualSnapshot",
		"多人攻击视觉快照 Kind 漂移"
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
	expect(table.isfrozen(IncomeGainPresentationProtocol.Kinds), "房屋收入表现 Kind 表必须只读")
	expect(table.isfrozen(ModelMovementVisualProtocol.Kinds), "模型移动 Kind 表必须只读")
	expect(
		table.isfrozen(MultiplayerAttackAcceptanceProtocol),
		"多人攻击验收协议必须只读"
	)
	expect(
		table.isfrozen(MultiplayerAttackAcceptanceProtocol.Kinds),
		"多人攻击验收 Kind 表必须只读"
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
