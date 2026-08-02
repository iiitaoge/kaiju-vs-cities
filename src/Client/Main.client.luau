local ButtonController = require(script.Parent.Button.ButtonController)
local CityBuildingPresentationController = require(
	script.Parent.Building.CityBuildingPresentationController
)
local LocalPlayerBuildingInteractionCoordinator = require(
	script.Parent.Building.LocalPlayerBuildingInteractionCoordinator
)
local LocalActionController = require(script.Parent.LocalActionController)

CityBuildingPresentationController.Start()
LocalPlayerBuildingInteractionCoordinator.Start()
ButtonController.Start(LocalActionController.Run)
