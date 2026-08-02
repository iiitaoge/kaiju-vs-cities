local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local LocalButtonController = {}

local PRESS_COLOR = Color3.fromRGB(128, 128, 128)
local STATE_COLORS = {
	Ready = Color3.fromRGB(72, 190, 92),
	Insufficient = Color3.fromRGB(196, 64, 64),
	Processing = Color3.fromRGB(128, 128, 128),
	Locked = Color3.fromRGB(70, 125, 210),
	Special = Color3.fromRGB(235, 190, 65),
}

local PULL_DEPTH = 0.35
local BASE_DEPTH = 0.05
local PRESS_DURATION = 0.14
local RELEASE_DURATION = 0.2

local function playTweens(tweens, tweenInfo, pull, pullCFrame, pullColor, base, baseCFrame)
	for _, tween in ipairs(tweens) do
		tween:Cancel()
	end

	table.clear(tweens)
	table.insert(tweens, TweenService:Create(pull, tweenInfo, {
		CFrame = pullCFrame,
		Color = pullColor,
	}))
	table.insert(tweens, TweenService:Create(base, tweenInfo, {
		CFrame = baseCFrame,
	}))

	for _, tween in ipairs(tweens) do
		tween:Play()
	end
end

-- onActivated：按钮第一次踩下时调用的可选函数。
function LocalButtonController.Bind(button: Model, onActivated: ((string) -> ())?)
	assert(button:IsA("Model"), "LocalButtonController.Bind expected a Model")

	local pull = button:FindFirstChild("Pull")
	local base = button:FindFirstChild("Part")
	assert(pull and pull:IsA("BasePart"), "Button needs a BasePart named Pull")
	assert(base and base:IsA("BasePart"), "Button needs a BasePart named Part")

	local pullRestCFrame = pull.CFrame
	local baseRestCFrame = base.CFrame
	local downDirection = -pull.CFrame.UpVector
	local touchingParts = {}
	local activeTweens = {}
	local connections = {}
	local visualState = "Ready"
	local isPressed = false
	local isDestroyed = false

	local function setPressed(pressed: boolean)
		if isDestroyed or isPressed == pressed then
			return
		end

		isPressed = pressed

		if pressed then
			playTweens(
				activeTweens,
				TweenInfo.new(PRESS_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				pull,
				pullRestCFrame + downDirection * PULL_DEPTH,
				PRESS_COLOR,
				base,
				baseRestCFrame + downDirection * BASE_DEPTH
			)
		else
			playTweens(
				activeTweens,
				TweenInfo.new(RELEASE_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				pull,
				pullRestCFrame,
				STATE_COLORS[visualState],
				base,
				baseRestCFrame
			)
		end

		if pressed and onActivated then
			onActivated(button.Name)
		end
	end

	local function belongsToLocalCharacter(part: BasePart): boolean
		local character = Players.LocalPlayer.Character
		return character ~= nil and part:IsDescendantOf(character)
	end

	table.insert(connections, pull.Touched:Connect(function(part)
		if belongsToLocalCharacter(part) then
			touchingParts[part] = true
			setPressed(true)
		end
	end))

	table.insert(connections, pull.TouchEnded:Connect(function(part)
		if touchingParts[part] then
			touchingParts[part] = nil
			setPressed(next(touchingParts) ~= nil)
		end
	end))

	table.insert(connections, Players.LocalPlayer.CharacterAdded:Connect(function()
		table.clear(touchingParts)
		setPressed(false)
	end))

	local handle = {}

	function handle:SetState(state: string)
		assert(STATE_COLORS[state], string.format("未知按钮状态：%s", state))
		visualState = state

		if not isPressed then
			playTweens(
				activeTweens,
				TweenInfo.new(RELEASE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				pull,
				pullRestCFrame,
				STATE_COLORS[visualState],
				base,
				baseRestCFrame
			)
		end
	end

	function handle:Destroy()
		if isDestroyed then
			return
		end

		isDestroyed = true

		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end

		for _, tween in ipairs(activeTweens) do
			tween:Cancel()
		end

		pull.CFrame = pullRestCFrame
		pull.Color = STATE_COLORS[visualState]
		base.CFrame = baseRestCFrame
	end

	return handle
end

return LocalButtonController
