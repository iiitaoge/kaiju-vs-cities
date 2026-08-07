local Players = game:GetService("Players")

-- Plot 必须先分配并激活，角色才能在其专属 SpawnLocation 上首次创建。
Players.CharacterAutoLoads = false

local AnalyticsIntentService = require(script.Parent.Analytics.AnalyticsIntentService)
local AutomaticIncomeRatePresentationService = require(
	script.Parent.AutomaticIncomeRatePresentationService
)
local GameAnalyticsEconomyAggregator = require(
	script.Parent.Analytics.GameAnalyticsEconomyAggregator
)
local GameAnalyticsGateway = require(script.Parent.Analytics.GameAnalyticsGateway)
local PlayerLoadAnalyticsCoordinator = require(
	script.Parent.Analytics.PlayerLoadAnalyticsCoordinator
)
local SecurityAnalyticsAggregator = require(
	script.Parent.Analytics.SecurityAnalyticsAggregator
)
local CityBuildingPresentationPublisher = require(script.Parent.CityBuildingPresentationPublisher)
local ContentContractValidator = require(script.Parent.ContentContractValidator)
local IncomeAutoCollectionService = require(script.Parent.IncomeAutoCollectionService)
local IncomeGainPresentationPublisher = require(
	script.Parent.IncomeGainPresentationPublisher
)
local DiamondService = require(script.Parent.DiamondService)
local MoneyService = require(script.Parent.MoneyService)
local DefenseMonsterSpawnPointStateService = require(
	script.Parent.DefenseMonsterSpawnPointStateService
)
local MonsterBuildPresentationPublisher = require(
	script.Parent.MonsterBuildPresentationPublisher
)
local MonsterSpawnPointStateService = require(script.Parent.MonsterSpawnPointStateService)
local PlayerCityRuntimeCoordinator = require(script.Parent.PlayerCityRuntimeCoordinator)
local PlayerCharacterMovementService = require(
	script.Parent.PlayerCharacterMovementService
)
local PlayerPersistenceCoordinator = require(script.Parent.PlayerPersistenceCoordinator)
local PlayerPlotContractValidator = require(script.Parent.PlayerPlotContractValidator)
local PlayerMonsterRuntimeCoordinator = require(script.Parent.PlayerMonsterRuntimeCoordinator)
local PlayerDefenseMonsterRuntimeCoordinator = require(
	script.Parent.PlayerDefenseMonsterRuntimeCoordinator
)
local PlayerPlotAssignmentService = require(script.Parent.PlayerPlotAssignmentService)
local PlayerPlotSpawnService = require(script.Parent.PlayerPlotSpawnService)
local PlayerStateService = require(script.Parent.PlayerStateService)
local PlayerZoneSceneVisibilityService = require(
	script.Parent.PlayerZoneSceneVisibilityService
)
local RegionStateService = require(script.Parent.RegionStateService)
local RebirthService = require(script.Parent.RebirthService)
local SevenDayRewardService = require(script.Parent.SevenDayRewardService)
local StudioMoneyCheatService = require(script.Parent.StudioMoneyCheatService)
local StudioSaveResetService = require(script.Parent.StudioSaveResetService)
local ZoneStateService = require(script.Parent.ZoneStateService)

ContentContractValidator.AssertValid()
PlayerPlotContractValidator.AssertAll()
-- 聚合器必须先注册 PlayerRemoving，确保 GA SDK 结束玩家 Session 前刷新待发送事件。
GameAnalyticsEconomyAggregator.Start()
SecurityAnalyticsAggregator.Start()
GameAnalyticsGateway.Start()
AnalyticsIntentService.Start()
-- 必须先注册持久化生命周期，使 PlayerAdded 同步进入 Loading，PlayerRemoving 先截取快照。
PlayerPersistenceCoordinator.Start()
-- 必须在持久化注册之后、各运行时加载模块之前观察加载阶段。
PlayerLoadAnalyticsCoordinator.Start()
StudioSaveResetService.Start()
PlayerStateService.Start()
ZoneStateService.Start()
MonsterSpawnPointStateService.Start()
DefenseMonsterSpawnPointStateService.Start()
PlayerPlotAssignmentService.Start()
PlayerPlotSpawnService.Start()
PlayerCharacterMovementService.Start()
CityBuildingPresentationPublisher.Start()
MonsterBuildPresentationPublisher.Start()
IncomeGainPresentationPublisher.Start()
DiamondService.Start()
MoneyService.Start()
StudioMoneyCheatService.Start()
RegionStateService.Start()
AutomaticIncomeRatePresentationService.Start()
SevenDayRewardService.Start()
RebirthService.Start()
PlayerZoneSceneVisibilityService.Start()
PlayerCityRuntimeCoordinator.Start()
IncomeAutoCollectionService.Start()
PlayerMonsterRuntimeCoordinator.Start()
PlayerDefenseMonsterRuntimeCoordinator.Start()
