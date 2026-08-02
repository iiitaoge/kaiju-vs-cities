local UserInputService = game:GetService("UserInputService")

local WorldPointInputController = {}

local MAX_RAY_DISTANCE = 10_000

export type Session = {
	Stop: () -> (),
	IsActive: () -> boolean,
}

local function resolve(screenPosition: Vector2): Vector3?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local ray = camera:ScreenPointToRay(screenPosition.X, screenPosition.Y)
	local result = workspace:Raycast(ray.Origin, ray.Direction * MAX_RAY_DISTANCE)
	return if result then result.Position else nil
end

-- 输入：每次有效世界点击的回调。
-- 输出：持续监听鼠标和触摸的输入会话，直到显式 Stop。
-- 内部算法：忽略被 UI 消费的输入，把屏幕坐标射线解析为世界坐标；不决定地盘是否合法。
function WorldPointInputController.Start(onSelected: (Vector3) -> ()): Session
	assert(type(onSelected) == "function", "onSelected 必须是 function")
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
		if not active or gameProcessed then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local point = resolve(Vector2.new(input.Position.X, input.Position.Y))
		if point then
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
