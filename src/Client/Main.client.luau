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
local EconomyHUDController = require(script.Parent.UI.EconomyHUDController)
local LocalPlayerBuildingInteractionCoordinator = require(
	script.Parent.Building.LocalPlayerBuildingInteractionCoordinator
)
local IncomeHouseWorldUIController = require(
	script.Parent.Building.IncomeHouseWorldUIController
)
local MonsterBuildPresentationController = require(
	script.Parent.Monster.MonsterBuildPresentationController
)
local MonsterIncubatorUIController = require(
	script.Parent.Monster.MonsterIncubatorUIController
)
local RebirthButtonController = require(
	script.Parent.Progression.RebirthButtonController
)
local StudioSaveResetController = require(script.Parent.StudioSaveResetController)
local TutorialController = require(script.Parent.Tutorial.TutorialController)

-- 输入：服务器意外返回的旧式客户端 Action。
-- 输出：无；立即报错，避免重新引入只在本机生成建筑的链路。
-- 算法：所有现有按钮均由服务器完成状态变更，因此任何客户端 Action 都属于合同错误。
local function rejectLegacyClientAction(action)
	error("服务器返回了已废弃的客户端 Action：" .. tostring(action and action.Kind))
end

GameAnalyticsClientService.Start()
StudioSaveResetController.Start()
TutorialController.Start()
AttackSelectionHUDController.Start()
EconomyHUDController.Start()
CityBuildingPresentationController.Start()
MonsterBuildPresentationController.Start()
MonsterIncubatorUIController.Start()
task.spawn(RebirthButtonController.Start)
LocalPlayerBuildingInteractionCoordinator.Start()
IncomeHouseWorldUIController.Start()
ButtonController.Start(rejectLegacyClientAction)
