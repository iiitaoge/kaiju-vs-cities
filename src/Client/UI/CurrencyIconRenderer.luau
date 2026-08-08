--[[
	职责：把配置中的货币类型渲染为 ReplicatedStorage Assets/CurrencyIcons 下的图片。
	输入：目标 ImageLabel/ImageButton、货币类型。
	输出：成功应用图片时返回 true；配置、资源或图片无效时返回 false 并记录警告。
	内部算法：按 CurrencyIconConfigs 定位资源，读取 ImageLabel/ImageButton、Decal、Texture
	或 StringValue 的图片内容，同时复制图片的裁剪、缩放和宽高比约束属性。
	不负责：奖励数值、余额、发奖、存档或面板显隐。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CurrencyIconConfigs = require(
	ReplicatedStorage.Shared.Economy.CurrencyIconConfigs
)

local CurrencyIconRenderer = {}

type ImageTarget = ImageLabel | ImageButton

local function resolveChild(parent: Instance?, name: string): Instance?
	if not parent then
		return nil
	end
	return parent:FindFirstChild(name)
end

local function resolveInstanceByPath(root: Instance, path: { string }): Instance?
	local current: Instance? = root
	for _, name in path do
		current = resolveChild(current, name)
		if not current then
			return nil
		end
	end
	return current
end

local function copyImageProperties(target: ImageTarget, source: Instance)
	if not source:IsA("ImageLabel") and not source:IsA("ImageButton") then
		return
	end

	target.ImageRectOffset = source.ImageRectOffset
	target.ImageRectSize = source.ImageRectSize
	target.ScaleType = source.ScaleType
	target.ImageColor3 = source.ImageColor3
	target.ImageTransparency = source.ImageTransparency
	target.SliceCenter = source.SliceCenter
	target.SliceScale = source.SliceScale
	target.TileSize = source.TileSize

	local sourceAspectRatio = source:FindFirstChildOfClass("UIAspectRatioConstraint")
	if sourceAspectRatio then
		local targetAspectRatio = target:FindFirstChildOfClass("UIAspectRatioConstraint")
		if not targetAspectRatio then
			targetAspectRatio = Instance.new("UIAspectRatioConstraint")
			targetAspectRatio.Parent = target
		end
		targetAspectRatio.AspectRatio = sourceAspectRatio.AspectRatio
		targetAspectRatio.AspectType = sourceAspectRatio.AspectType
		targetAspectRatio.DominantAxis = sourceAspectRatio.DominantAxis
	end
end

local function readImageAsset(source: Instance): (string?, Instance?)
	if source:IsA("ImageLabel") or source:IsA("ImageButton") then
		return source.Image, source
	end
	if source:IsA("Decal") or source:IsA("Texture") then
		return source.Texture, source
	end
	if source:IsA("StringValue") then
		return source.Value, source
	end

	local iconChild = source:FindFirstChild("Icon")
	if iconChild then
		return readImageAsset(iconChild)
	end
	return nil, nil
end

local function applyNamed(target: ImageTarget, iconName: string): boolean
	assert(
		target:IsA("ImageLabel") or target:IsA("ImageButton"),
		"target 必须是 ImageLabel 或 ImageButton"
	)
	if type(iconName) ~= "string" or iconName == "" then
		warn("图标名称无效：" .. tostring(iconName))
		return false
	end

	local iconRoot = resolveInstanceByPath(
		ReplicatedStorage,
		CurrencyIconConfigs.RootPath
	)
	local source = iconRoot and iconRoot:FindFirstChild(iconName)
	if not source then
		warn(string.format("货币图标不存在：%s", iconName))
		return false
	end

	local image, imageSource = readImageAsset(source)
	if type(image) ~= "string" or image == "" then
		warn(string.format("货币图标没有有效 Image：%s", iconName))
		return false
	end

	target.Image = image
	target.Visible = true
	if imageSource then
		copyImageProperties(target, imageSource)
	end
	return true
end

function CurrencyIconRenderer.Apply(target: ImageTarget, currencyType: string): boolean
	local iconName = CurrencyIconConfigs.IconNames[currencyType]
	if type(iconName) ~= "string" then
		warn("没有配置货币图标名称：" .. tostring(currencyType))
		return false
	end
	return applyNamed(target, iconName)
end

function CurrencyIconRenderer.ApplyNamed(target: ImageTarget, iconName: string): boolean
	return applyNamed(target, iconName)
end

return table.freeze(CurrencyIconRenderer)
