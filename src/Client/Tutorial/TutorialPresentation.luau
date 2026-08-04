--[[
	职责：用 ReplicatedStorage/TutorialAssets 中的 PopUp 与 Beam 模板显示一个客户端引导步骤。
	输入：Create 接收 PlayerGui；Show 接收英文步骤定义和可选目标 BasePart。
	输出：可 Show/Hide/Destroy 的表现句柄，模板无效时返回 nil 和稳定原因。
	内部算法：克隆顶部 Tip；在角色 HumanoidRootPart 与目标间创建本地 Attachment 和 Beam。
	不负责：步骤判断、服务器查询、Plot/按钮/建筑定位或完成持久化。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ResponsiveUIScale = require(ReplicatedStorage.Shared.UI.ResponsiveUIScale)

local TutorialPresentation = {}

export type Definition = {
	Title: string,
	Info: string,
	TargetKind: string?,
}

export type Handle = {
	Show: (Definition, BasePart?) -> (),
	Hide: () -> (),
	Destroy: () -> (),
}

local GUI_NAME = "TutorialPopUp"
local ORIGIN_ATTACHMENT_NAME = "TutorialGuideOrigin"
local TARGET_ATTACHMENT_NAME = "TutorialGuideTarget"
local RESPONSIVE_CONFIG = table.freeze({
	ReferenceViewport = Vector2.new(1280, 720),
	MinScale = 0.58,
	MaxScale = 1,
	TouchMinScale = 0.58,
})

local function childOfClass(parent: Instance?, name: string, className: string): Instance?
	local child = parent and parent:FindFirstChild(name)
	return if child and child:IsA(className) then child else nil
end

local function getCharacterRoot(): BasePart?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

function TutorialPresentation.Create(playerGui: PlayerGui): (Handle?, string?)
	assert(playerGui:IsA("PlayerGui"), "playerGui 必须是 PlayerGui")
	local assets = ReplicatedStorage:WaitForChild("TutorialAssets", 20)
	if not assets or not assets:IsA("Folder") then
		return nil, "TutorialAssetsUnavailable"
	end
	local popupTemplate = childOfClass(assets, "PopUp", "ScreenGui")
	local beamTemplate = childOfClass(assets, "Beam", "Beam")
	if not popupTemplate or not beamTemplate then
		return nil, "InvalidTutorialAssets"
	end

	local previous = playerGui:FindFirstChild(GUI_NAME)
	if previous then
		previous:Destroy()
	end
	local gui = popupTemplate:Clone() :: ScreenGui
	gui.Name = GUI_NAME
	gui.Enabled = false
	gui.ResetOnSpawn = false
	gui.DisplayOrder = math.max(gui.DisplayOrder, 200)
	gui.AutoLocalize = false
	local tip = childOfClass(gui, "Tip", "Frame")
	local titleFrame = childOfClass(tip, "Title", "Frame")
	local title = childOfClass(titleFrame, "Title", "TextLabel")
	local info = childOfClass(tip, "Info", "TextLabel")
	local uiScale = gui:FindFirstChildOfClass("UIScale")
	if not tip or not title or not info or not uiScale then
		gui:Destroy()
		return nil, "InvalidTutorialPopupHierarchy"
	end
	title.AutoLocalize = false
	info.AutoLocalize = false
	info.RichText = true
	info.TextScaled = true
	gui.Parent = playerGui

	local beam: Beam? = nil
	local originAttachment: Attachment? = nil
	local targetAttachment: Attachment? = nil
	local currentTarget: BasePart? = nil
	local connections: { RBXScriptConnection } = {}
	local cameraConnection: RBXScriptConnection? = nil
	local destroyed = false

	local function updateScale()
		local camera = Workspace.CurrentCamera
		if camera and camera.ViewportSize.X > 0 and camera.ViewportSize.Y > 0 then
			uiScale.Scale = ResponsiveUIScale.Compute(
				camera.ViewportSize,
				game:GetService("UserInputService").TouchEnabled,
				RESPONSIVE_CONFIG
			)
		end
	end

	local function bindCamera()
		if cameraConnection then
			cameraConnection:Disconnect()
			cameraConnection = nil
		end
		local camera = Workspace.CurrentCamera
		if camera then
			cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
		end
		updateScale()
	end

	local function clearBeam()
		currentTarget = nil
		if beam then
			beam:Destroy()
			beam = nil
		end
		if originAttachment then
			originAttachment:Destroy()
			originAttachment = nil
		end
		if targetAttachment then
			targetAttachment:Destroy()
			targetAttachment = nil
		end
	end

	local function setTarget(target: BasePart?)
		local root = getCharacterRoot()
		if target == currentTarget
			and target ~= nil
			and target.Parent ~= nil
			and root ~= nil
			and originAttachment ~= nil
			and originAttachment.Parent == root
			and targetAttachment ~= nil
			and targetAttachment.Parent == target
		then
			return
		end
		clearBeam()
		if not target or not target.Parent or not root then
			return
		end

		currentTarget = target
		originAttachment = Instance.new("Attachment")
		originAttachment.Name = ORIGIN_ATTACHMENT_NAME
		originAttachment.Position = Vector3.new(0, -2, 0)
		originAttachment.Parent = root
		targetAttachment = Instance.new("Attachment")
		targetAttachment.Name = TARGET_ATTACHMENT_NAME
		targetAttachment.Position = Vector3.new(0, target.Size.Y * 0.5 + 0.5, 0)
		targetAttachment.Parent = target
		beam = beamTemplate:Clone() :: Beam
		beam.Attachment0 = originAttachment
		beam.Attachment1 = targetAttachment
		beam.Enabled = true
		beam.Parent = originAttachment
	end

	bindCamera()
	table.insert(connections, Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera))

	local handle = {} :: any
	function handle.Show(definition: Definition, target: BasePart?)
		if destroyed then
			return
		end
		title.Text = "TIP:"
		info.Text = string.format("<b>%s</b>\n%s", definition.Title, definition.Info)
		gui.Enabled = true
		setTarget(target)
	end

	function handle.Hide()
		if destroyed then
			return
		end
		gui.Enabled = false
		clearBeam()
	end

	function handle.Destroy()
		if destroyed then
			return
		end
		destroyed = true
		clearBeam()
		if cameraConnection then
			cameraConnection:Disconnect()
			cameraConnection = nil
		end
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
		gui:Destroy()
	end

	return handle, nil
end

return TutorialPresentation
