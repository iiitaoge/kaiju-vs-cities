local ButtonController = require(script.Parent.Button.ButtonController)
local CityBuildingPresentationController = require(
	script.Parent.Building.CityBuildingPresentationController
)
local LocalActionController = require(script.Parent.LocalActionController)

CityBuildingPresentationController.Start()
ButtonController.Start(LocalActionController.Run)
