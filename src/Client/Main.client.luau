local AnalyticsIntentClient = require(
	script.Parent.Analytics.AnalyticsIntentClient
)
local GameAnalyticsClientService = require(
	script.Parent.Analytics.GameAnalyticsClientService
)
local ButtonController = require(script.Parent.Button.ButtonController)
local AttackSelectionHUDController = require(
	script.Parent.Monster.AttackSelectionHUDController
)
local CityBuildingPresentationController = require(
	script.Parent.Building.CityBuildingPresentationController
)
local CombatHealthBarController = require(
	script.Parent.UI.CombatHealthBarController
)
local EconomyHUDController = require(script.Parent.UI.EconomyHUDController)
local ExpandedController = require(script.Parent.UI.ExpandedController)
local IncomeGainPresentationController = require(
	script.Parent.UI.IncomeGainPresentationController
)
local ButtonFeedbackController = require(
	script.Parent.UI.ButtonFeedbackController
)
local ResponsiveScreenGuiController = require(
	script.Parent.UI.ResponsiveScreenGuiController
)
local DefenseMonsterUIController = require(
	script.Parent.Monster.DefenseMonsterUIController
)
local LocalPlayerBuildingInteractionCoordinator = require(
	script.Parent.Building.LocalPlayerBuildingInteractionCoordinator
)
local IncomeHouseWorldUIController = require(
	script.Parent.Building.IncomeHouseWorldUIController
)
local TipBlackController = require(script.Parent.UI.TipBlackController)
local MonsterBuildPresentationController = require(
	script.Parent.Monster.MonsterBuildPresentationController
)
local MonsterDuelCameraController = require(
	script.Parent.Monster.MonsterDuelCameraController
)
local MonsterDuelWatchButtonController = require(
	script.Parent.Monster.MonsterDuelWatchButtonController
)
local MonsterExpeditionProgressUIController = require(
	script.Parent.Monster.MonsterExpeditionProgressUIController
)
local MonsterIncubatorUIController = require(
	script.Parent.Monster.MonsterIncubatorUIController
)
local MonsterAttackRosterUIController = require(
	script.Parent.Monster.MonsterAttackRosterUIController
)
local RebirthButtonController = require(
	script.Parent.Progression.RebirthButtonController
)
local StudioSaveResetController = require(script.Parent.StudioSaveResetController)
local SoundController = require(script.Parent.Sound.SoundController)
local TutorialController = require(script.Parent.Tutorial.TutorialController)
local GroupRewardUIController = require(
	script.Parent.UI.GroupRewardUIController
)
local SevenDayRewardUIController = require(
	script.Parent.UI.SevenDayRewardUIController
)
local VehicleUIController = require(script.Parent.UI.VehicleUIController)

-- 输入：服务器意外返回的旧式客户端 Action。
-- 输出：无；立即报错，避免重新引入只在本机生成建筑的链路。
-- 算法：所有现有按钮均由服务器完成状态变更，因此任何客户端 Action 都属于合同错误。
local function rejectLegacyClientAction(action)
	error("服务器返回了已废弃的客户端 Action：" .. tostring(action and action.Kind))
end

GameAnalyticsClientService.Start()
AnalyticsIntentClient.Start()
SoundController.Start()
StudioSaveResetController.Start()
task.spawn(SevenDayRewardUIController.Start)
task.spawn(GroupRewardUIController.Start)
VehicleUIController.Start()
TutorialController.Start()
AttackSelectionHUDController.Start()
EconomyHUDController.Start()
IncomeGainPresentationController.Start()
ButtonFeedbackController.Start()
ResponsiveScreenGuiController.Start()
CombatHealthBarController.Start()
CityBuildingPresentationController.Start()
MonsterBuildPresentationController.Start()
MonsterDuelCameraController.Start()
MonsterDuelWatchButtonController.Start()
MonsterExpeditionProgressUIController.Start()
MonsterIncubatorUIController.Start()
MonsterAttackRosterUIController.Start()
DefenseMonsterUIController.Start()
task.spawn(RebirthButtonController.Start)
LocalPlayerBuildingInteractionCoordinator.Start(
	IncomeGainPresentationController.PlayTouchContact
)
IncomeHouseWorldUIController.Start()
TipBlackController.Start()
ExpandedController.Start()
ButtonController.Start(rejectLegacyClientAction)
