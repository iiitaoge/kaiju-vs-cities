local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local WorldPointResolver = require(script.Parent.Parent.WorldPointResolver)

local WorldPointInputController = {}

export type Session = {
	Stop: () -> (),
	IsActive: () -> boolean,
}

export type InputSnapshot = {
	OccurredAt: number,
	ServerTime: number,
	InputType: Enum.UserInputType,
	GameProcessed: boolean,
	InputScreen: Vector2,
	InputViewport: Vector2,
	GuiInset: Vector2,
	RawMouseViewport: Vector2,
	MouseScreen: Vector2,
	MouseIconEnabled: boolean,
	MouseBehavior: Enum.MouseBehavior,
	WorldPoint: Vector3?,
	CameraCFrame: CFrame?,
	CameraFieldOfView: number?,
	CameraViewportSize: Vector2?,
}

-- 输入：每次有效世界点击的回调，以及可选的只读输入快照观察者。
-- 输出：持续监听鼠标和触摸的输入会话，直到显式 Stop。
-- 内部算法：把已计入 CoreUI inset 的 InputObject.Position 加回左上 inset，转换为 DeviceSafe viewport 坐标；不决定地盘是否合法。
function WorldPointInputController.Start(
	onSelected: (Vector3) -> (),
	onObserved: ((InputSnapshot) -> ())?
): Session
	assert(type(onSelected) == "function", "onSelected 必须是 function")
	assert(onObserved == nil or type(onObserved) == "function", "onObserved 必须是 function")
	local active = true
	local connection: RBXScriptConnection? = nil

	local function stop()
		if not active then
			return
		end
		active = false
		if connection then
			connection:Disconnect()
			connection = nil
		end
	end

	connection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not active then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local inputScreen = Vector2.new(input.Position.X, input.Position.Y)
		local guiInset = GuiService:GetGuiInset()
		local inputViewport = inputScreen + guiInset
		local rawMouseViewport = UserInputService:GetMouseLocation()
		local camera = workspace.CurrentCamera
		local point = WorldPointResolver.Resolve(inputViewport)
		if onObserved then
			onObserved({
				OccurredAt = os.clock(),
				ServerTime = workspace:GetServerTimeNow(),
				InputType = input.UserInputType,
				GameProcessed = gameProcessed,
				InputScreen = inputScreen,
				InputViewport = inputViewport,
				GuiInset = guiInset,
				RawMouseViewport = rawMouseViewport,
				MouseScreen = rawMouseViewport - guiInset,
				MouseIconEnabled = UserInputService.MouseIconEnabled,
				MouseBehavior = UserInputService.MouseBehavior,
				WorldPoint = point,
				CameraCFrame = if camera then camera.CFrame else nil,
				CameraFieldOfView = if camera then camera.FieldOfView else nil,
				CameraViewportSize = if camera then camera.ViewportSize else nil,
			})
		end
		if not gameProcessed and point then
			onSelected(point)
		end
	end)

	return {
		Stop = stop,
		IsActive = function()
			return active
		end,
	}
end

return WorldPointInputController
