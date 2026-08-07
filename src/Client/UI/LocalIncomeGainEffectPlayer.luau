--[[
	职责：播放单次房屋收入飘字，以及从房屋飞向指定 HUD 图标的金币动画。
	输入：运行时房屋、HUD 金币图像、表现配置；飘字额外接收格式化文本，飞行额外接收覆盖层。
	输出：效果是否成功开始；所有临时 Instance 在动画结束后自行销毁。
	内部算法：在房屋上方创建本地 BillboardGui；触碰时把房屋中心投影并限制到屏幕边缘，再错峰 Tween 五枚固定像素金币。
	不负责：验证网络命令、计算/格式化收入、查找房屋或 HUD、创建 Remote。
]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIModeVisibilityRules = require(
	ReplicatedStorage.Shared.UI.UIModeVisibilityRules
)
local LocalUIModeService = require(script.Parent.LocalUIModeService)
local LocalUIVisibilityGate = require(script.Parent.LocalUIVisibilityGate)

local LocalIncomeGainEffectPlayer = {}

export type ImageGui = ImageLabel

export type Config = {
	PopupSize: Vector2,
	PopupIconSize: number,
	PopupBaseOffsetStuds: number,
	PopupRiseStuds: number,
	PopupDuration: number,
	PopupFadeDelay: number,
	PopupMaxDistance: number,
	TouchCoinCount: number,
	TouchCoinSize: number,
	TouchCoinScatterPixels: number,
	TouchCoinStaggerSeconds: number,
	TouchCoinFlightSeconds: number,
}

local function firstBasePart(model: Model): BasePart?
	if model.PrimaryPart then
		return model.PrimaryPart
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end
	return nil
end

local function makeIcon(template: ImageGui, size: number): ImageLabel
	local icon = template:Clone()
	icon.Name = "CoinIcon"
	icon.AnchorPoint = Vector2.zero
	icon.BackgroundTransparency = 1
	icon.Position = UDim2.fromOffset(0, 0)
	icon.Rotation = 0
	icon.Size = UDim2.fromOffset(size, size)
	icon.Visible = true
	return icon
end

local function getWorldTop(model: Model, extraHeight: number): Vector3?
	if not model.Parent or not firstBasePart(model) then
		return nil
	end
	local boundsCFrame, boundsSize = model:GetBoundingBox()
	return boundsCFrame.Position
		+ boundsCFrame.UpVector * (boundsSize.Y * 0.5 + extraHeight)
end

local function getWorldCenter(model: Model): Vector3?
	if not model.Parent or not firstBasePart(model) then
		return nil
	end
	local boundsCFrame = model:GetBoundingBox()
	return boundsCFrame.Position
end

function LocalIncomeGainEffectPlayer.PlayPopup(
	model: Model,
	iconTemplate: ImageGui,
	text: string,
	config: Config
): boolean
	assert(model:IsA("Model"), "model 必须是 Model")
	assert(iconTemplate:IsA("ImageLabel"), "iconTemplate 必须是 ImageLabel")
	assert(type(text) == "string" and text ~= "", "text 必须是非空字符串")
	if not LocalUIModeService.IsAllowed(UIModeVisibilityRules.Channels.Gameplay) then
		return false
	end

	local parentPart = firstBasePart(model)
	local worldTop = getWorldTop(model, config.PopupBaseOffsetStuds)
	if not parentPart or not worldTop then
		return false
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "_LocalIncomeGainPopup"
	attachment.CFrame = CFrame.new(parentPart.CFrame:PointToObjectSpace(worldTop))

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "BillboardGui"
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = config.PopupMaxDistance
	billboard.Size = UDim2.fromOffset(config.PopupSize.X, config.PopupSize.Y)
	billboard.Parent = attachment

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.AnchorPoint = Vector2.new(0.5, 0.5)
	content.BackgroundTransparency = 1
	content.Position = UDim2.fromScale(0.5, 0.5)
	content.Size = UDim2.fromScale(1, 1)
	content.Parent = billboard

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 5)
	layout.Parent = content

	local icon = makeIcon(iconTemplate, config.PopupIconSize)
	icon.LayoutOrder = 1
	icon.Parent = content

	local label = Instance.new("TextLabel")
	label.Name = "Amount"
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.LayoutOrder = 2
	label.Size = UDim2.new(0, 125, 1, 0)
	label.Text = text
	label.TextScaled = true
	label.TextStrokeTransparency = 0
	label.Parent = content

	label.TextColor3 = Color3.fromRGB(85, 255, 120)
	label.TextStrokeColor3 = Color3.fromRGB(12, 60, 25)
	attachment.Parent = parentPart
	local visibilityGate = LocalUIVisibilityGate.Create(
		UIModeVisibilityRules.Channels.Gameplay,
		function(visible)
			billboard.Enabled = visible
			if not visible and attachment.Parent then
				attachment:Destroy()
			end
		end,
		true
	)

	local targetWorldTop = worldTop
		+ Vector3.new(0, config.PopupRiseStuds, 0)
	local targetCFrame = CFrame.new(
		parentPart.CFrame:PointToObjectSpace(targetWorldTop)
	)
	local motion = TweenService:Create(
		attachment,
		TweenInfo.new(
			config.PopupDuration,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		),
		{ CFrame = targetCFrame }
	)
	motion:Play()
	task.spawn(function()
		task.wait(config.PopupFadeDelay)
		if not attachment.Parent then
			motion:Destroy()
			visibilityGate:Destroy()
			return
		end
		local fadeDuration = math.max(0, config.PopupDuration - config.PopupFadeDelay)
		local iconFade = TweenService:Create(
			icon,
			TweenInfo.new(fadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ ImageTransparency = 1 }
		)
		local textFade = TweenService:Create(
			label,
			TweenInfo.new(fadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ TextTransparency = 1, TextStrokeTransparency = 1 }
		)
		iconFade:Play()
		textFade:Play()
		motion.Completed:Wait()
		motion:Destroy()
		iconFade:Destroy()
		textFade:Destroy()
		if attachment.Parent then
			attachment:Destroy()
		end
		visibilityGate:Destroy()
	end)
	return true
end

function LocalIncomeGainEffectPlayer.PlayTouchFlight(
	model: Model,
	iconTemplate: ImageGui,
	targetIcon: GuiObject,
	overlay: ScreenGui,
	config: Config
): boolean
	assert(model:IsA("Model"), "model 必须是 Model")
	assert(iconTemplate:IsA("ImageLabel"), "iconTemplate 必须是 ImageLabel")
	assert(targetIcon:IsA("GuiObject"), "targetIcon 必须是 GuiObject")
	assert(overlay:IsA("ScreenGui"), "overlay 必须是 ScreenGui")
	if not LocalUIModeService.IsAllowed(UIModeVisibilityRules.Channels.Gameplay) then
		return false
	end

	local camera = workspace.CurrentCamera
	local worldCenter = getWorldCenter(model)
	if not camera or not worldCenter then
		return false
	end
	local screenPoint = camera:WorldToScreenPoint(worldCenter)

	-- Overlay 忽略 GUI inset；WorldToScreenPoint 与 GuiObject.AbsolutePosition
	-- 都使用屏幕坐标。金币保持固定像素大小；房屋位于画面外或相机背后时，
	-- 把投影限制到最近的屏幕边缘，保证已确认的触碰收益不会漏播。
	local halfCoinSize = config.TouchCoinSize * 0.5
	local viewportSize = camera.ViewportSize
	local rawSource = Vector2.new(screenPoint.X, screenPoint.Y)
	if screenPoint.Z <= 0 then
		local cameraSpace = camera.CFrame:PointToObjectSpace(worldCenter)
		local direction = Vector2.new(cameraSpace.X, -cameraSpace.Y)
		if direction.Magnitude < 1e-6 then
			direction = Vector2.new(0, 1)
		else
			direction = direction.Unit
		end
		local halfViewport = viewportSize * 0.5
		local horizontalScale = if math.abs(direction.X) > 1e-6
			then (halfViewport.X - halfCoinSize) / math.abs(direction.X)
			else math.huge
		local verticalScale = if math.abs(direction.Y) > 1e-6
			then (halfViewport.Y - halfCoinSize) / math.abs(direction.Y)
			else math.huge
		rawSource = halfViewport + direction * math.min(horizontalScale, verticalScale)
	end
	local source = Vector2.new(
		math.clamp(rawSource.X, halfCoinSize, viewportSize.X - halfCoinSize),
		math.clamp(rawSource.Y, halfCoinSize, viewportSize.Y - halfCoinSize)
	)
	local target = targetIcon.AbsolutePosition + targetIcon.AbsoluteSize * 0.5
	local randomGenerator = Random.new()

	for index = 1, config.TouchCoinCount do
		local scatter = Vector2.new(
			randomGenerator:NextNumber(-config.TouchCoinScatterPixels, config.TouchCoinScatterPixels),
			randomGenerator:NextNumber(-config.TouchCoinScatterPixels, config.TouchCoinScatterPixels)
		)
		local coin = makeIcon(iconTemplate, config.TouchCoinSize)
		coin.AnchorPoint = Vector2.new(0.5, 0.5)
		coin.Position = UDim2.fromOffset(source.X + scatter.X, source.Y + scatter.Y)
		coin.ZIndex = 100
		coin.Parent = overlay

		task.delay((index - 1) * config.TouchCoinStaggerSeconds, function()
			if not coin.Parent then
				return
			end
			local tween = TweenService:Create(
				coin,
				TweenInfo.new(
					config.TouchCoinFlightSeconds,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.In
				),
				{
					ImageTransparency = 1,
					Position = UDim2.fromOffset(target.X, target.Y),
					Size = UDim2.fromOffset(
						config.TouchCoinSize * 0.65,
						config.TouchCoinSize * 0.65
					),
				}
			)
			tween:Play()
			tween.Completed:Wait()
			tween:Destroy()
			coin:Destroy()
		end)
	end
	return true
end

return LocalIncomeGainEffectPlayer
