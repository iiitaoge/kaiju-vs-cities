local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local TopDownCamera = require(script.Parent.TopDownCamera)
local WorldPointResolver = require(script.Parent.Parent.WorldPointResolver)

local WorldPointSelectionController = {}

export type SelectionOptions = {
	Height: number,
	FieldOfView: number,
	EnterDuration: number,
	RestoreDuration: number,
}

export type SelectionResult = {
	Selected: boolean,
	Position: Vector3?,
	Restored: boolean,
}

-- 输入：
--   targetPart：俯视相机看向的世界 Part。
--   options：相机高度、FOV、进入时间和恢复时间。
--   onSelected：首次有效鼠标左键射线命中后，接收世界 Vector3 的显式回调。
-- 输出：
--   返回是否选中坐标、选中坐标和相机是否成功恢复。
-- 内部算法：
--   平滑进入俯视视角，等待首次命中任意可查询表面的左键点击，
--   先断开输入并调用 onSelected，再平滑恢复此前相机。
-- 副作用：临时接管本地相机和鼠标点击监听。
function WorldPointSelectionController.Run(
	targetPart: BasePart,
	options: SelectionOptions,
	onSelected: (Vector3) -> ()
): SelectionResult
	assert(targetPart:IsA("BasePart"), "targetPart 必须是 BasePart")
	assert(type(options) == "table", "options 必须是 table")
	assert(type(onSelected) == "function", "onSelected 必须是 function")

	local previousState = TopDownCamera.Set(
		targetPart,
		options.Height,
		options.FieldOfView,
		options.EnterDuration
	)
	local selectedEvent = Instance.new("BindableEvent")
	local connection: RBXScriptConnection? = nil

	connection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end

		local inputScreen = Vector2.new(input.Position.X, input.Position.Y)
		local inputViewport = inputScreen + GuiService:GetGuiInset()
		local position = WorldPointResolver.Resolve(inputViewport)
		if position then
			selectedEvent:Fire(position)
		end
	end)

	local position = selectedEvent.Event:Wait()
	if connection then
		connection:Disconnect()
	end
	selectedEvent:Destroy()

	-- 先发出目的地，服务端即可开始攻击；相机恢复与攻击在时间上并行。
	local callbackSucceeded, callbackError = pcall(onSelected, position)
	local restoreSucceeded, restoreError = pcall(
		TopDownCamera.Restore,
		previousState,
		options.RestoreDuration
	)

	if not callbackSucceeded then
		error(callbackError, 0)
	end
	if not restoreSucceeded then
		error(restoreError, 0)
	end

	return {
		Selected = true,
		Position = position,
		Restored = true,
	}
end

return WorldPointSelectionController
