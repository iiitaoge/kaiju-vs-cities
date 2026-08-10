local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local LocalButtonController = {}

local PRESS_COLOR = Color3.fromRGB(128, 128, 128)
local STATE_COLORS = {
	Ready = Color3.fromRGB(72, 190, 92),
	Insufficient = Color3.fromRGB(196, 64, 64),
	Processing = Color3.fromRGB(70, 125, 210),
	Locked = Color3.fromRGB(82, 82, 82),
	Special = Color3.fromRGB(235, 190, 65),
}

local ACTIVATABLE_STATES = {
	Ready = true,
	Insufficient = true,
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
	-- 状态请求完成前禁止误触发；调用方会在首个快照返回后替换它。
	local visualState = "Processing"
	local inputEnabled = true
	local activationConsumed = false
	local isPressed = false
	local isDestroyed = false

	local function setPressed(pressed: boolean)
		local shouldPress = pressed
			and inputEnabled
			and not activationConsumed
			and ACTIVATABLE_STATES[visualState] == true
		if isDestroyed or isPressed == shouldPress then
			return
		end

		isPressed = shouldPress

		if shouldPress then
			activationConsumed = true
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

		if shouldPress and onActivated then
			onActivated(button.Name)
		end
	end

	local function belongsToLocalCharacter(part: BasePart): boolean
		local character = Players.LocalPlayer.Character
		return character ~= nil and part:IsDescendantOf(character)
	end

	local function refreshTouchingParts()
		table.clear(touchingParts)
		activationConsumed = false
		for _, part in pull:GetTouchingParts() do
			if belongsToLocalCharacter(part) then
				touchingParts[part] = true
			end
		end
		setPressed(next(touchingParts) ~= nil)
	end

	table.insert(connections, pull.Touched:Connect(function(part)
		if belongsToLocalCharacter(part) then
			if next(touchingParts) == nil then
				activationConsumed = false
			end
			touchingParts[part] = true
			setPressed(true)
		end
	end))

	table.insert(connections, pull.TouchEnded:Connect(function(part)
		if touchingParts[part] then
			touchingParts[part] = nil
			if next(touchingParts) == nil then
				activationConsumed = false
			end
			setPressed(next(touchingParts) ~= nil)
		end
	end))

	table.insert(connections, Players.LocalPlayer.CharacterAdded:Connect(function()
		table.clear(touchingParts)
		activationConsumed = false
		setPressed(false)
		task.defer(refreshTouchingParts)
	end))
	task.defer(refreshTouchingParts)

	local handle = {}

	function handle:SetState(state: string)
		assert(STATE_COLORS[state], string.format("未知按钮状态：%s", state))
		visualState = state

		if not ACTIVATABLE_STATES[visualState] and isPressed then
			setPressed(false)
		elseif not isPressed then
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

	function handle:CanActivate(): boolean
		return not isDestroyed
			and inputEnabled
			and ACTIVATABLE_STATES[visualState] == true
	end

	function handle:RefreshTouching()
		if next(touchingParts) == nil then
			activationConsumed = false
		end
		setPressed(next(touchingParts) ~= nil)
	end

	function handle:SetInputEnabled(enabled: boolean)
		inputEnabled = enabled
		if not enabled and isPressed then
			setPressed(false)
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
