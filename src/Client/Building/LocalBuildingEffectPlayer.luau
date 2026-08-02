local TweenService = game:GetService("TweenService")

local LocalBuildingEffectPlayer = {}

export type Config = {
	ScaleMultiplier: number,
	ExpandDuration: number,
	ReturnDuration: number,
}

local activeModels = setmetatable({}, { __mode = "k" })

function LocalBuildingEffectPlayer.PlayContact(model: Model, config: Config): boolean
	assert(model:IsA("Model"), "model 必须是 Model")
	assert(type(config) == "table", "config 必须是 table")
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
			TweenInfo.new(
				config.ExpandDuration,
				Enum.EasingStyle.Back,
				Enum.EasingDirection.Out
			),
			{ Value = originalScale * config.ScaleMultiplier }
		)
		expand:Play()
		expand.Completed:Wait()
		expand:Destroy()

		local returnTween = TweenService:Create(
			scale,
			TweenInfo.new(
				config.ReturnDuration,
				Enum.EasingStyle.Back,
				Enum.EasingDirection.Out
			),
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
