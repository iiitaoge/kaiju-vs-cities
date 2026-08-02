local TweenService = game:GetService("TweenService")

local LocalBuildingEffectPlayer = {}

local SCALE_MULTIPLIER = 1.3
local EXPAND_DURATION = 0.2
local RETURN_DURATION = 0.25

local activeModels = setmetatable({}, { __mode = "k" })

function LocalBuildingEffectPlayer.PlayContact(model: Model): boolean
	assert(model:IsA("Model"), "model 必须是 Model")
	if activeModels[model] then
		return false
	end
	activeModels[model] = true

	local originalScale = model:GetScale()
	local scale = Instance.new("NumberValue")
	scale.Value = originalScale

	local scaleConnection = scale:GetPropertyChangedSignal("Value"):Connect(function()
		if model.Parent then
			model:ScaleTo(scale.Value)
		end
	end)

	local ok, message = xpcall(function()
		local expand = TweenService:Create(
			scale,
			TweenInfo.new(EXPAND_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Value = originalScale * SCALE_MULTIPLIER }
		)
		expand:Play()
		expand.Completed:Wait()
		expand:Destroy()

		local returnTween = TweenService:Create(
			scale,
			TweenInfo.new(RETURN_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Value = originalScale }
		)
		returnTween:Play()
		returnTween.Completed:Wait()
		returnTween:Destroy()
	end, debug.traceback)

	scaleConnection:Disconnect()
	scale:Destroy()
	activeModels[model] = nil

	if model.Parent then
		model:ScaleTo(originalScale)
	end

	if not ok then
		warn("[LocalBuildingEffectPlayer] 接触效果失败：\n" .. message)
		return false
	end

	return true
end

return LocalBuildingEffectPlayer
