--[[
	职责：管理客户端本地音乐和交互音效。
	输入：ReplicatedStorage.Sound 下的 Sound 模板，以及 Play(soundName) 调用。
	输出：SoundService 中的本地 BGM 和一次性音效播放。
	内部算法：BGM 启动时克隆为唯一循环实例；一次性音效每次克隆并在播放结束后清理；
	独立扫描 PlayerGui/Workspace 中的 GuiButton，为实际 Activated 事件播放 Click。
	不负责：业务成功/失败判断、按钮状态、UI 展示、服务器请求或音效资源创建。
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local LocalGuiButtonState = require(script.Parent.Parent.UI.LocalGuiButtonState)

local SoundController = {}

local SOUND_ROOT_NAME = "Sound"
local BGM_NAME = "BGM"
local BGM_RUNTIME_NAME = "KaijuBGM"
local BGM_VOLUME = 0.16
local ONE_SHOT_CLEANUP_SECONDS = 15

type ButtonConnections = { RBXScriptConnection }

local soundRoot: Folder? = nil
local bgm: Sound? = nil
local buttonConnections: { [GuiButton]: ButtonConnections } = setmetatable(
	{},
	{ __mode = "k" }
)
local started = false

local function disconnectButton(button: GuiButton)
	local connections = buttonConnections[button]
	if not connections then
		return
	end

	for _, connection in connections do
		connection:Disconnect()
	end
	buttonConnections[button] = nil
end

local function resolveTemplate(soundName: string): Sound?
	local root = soundRoot
	if not root then
		return nil
	end

	local candidate = root:FindFirstChild(soundName)
	if not candidate or not candidate:IsA("Sound") then
		warn(string.format("音效模板不可用：ReplicatedStorage.Sound.%s", soundName))
		return nil
	end
	return candidate
end

local function playOneShot(soundName: string)
	local template = resolveTemplate(soundName)
	if not template then
		return
	end

	local sound = template:Clone()
	sound.Name = "LocalSound_" .. soundName
	sound.Looped = false
	sound.Parent = SoundService
	sound.Ended:Connect(function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
	Debris:AddItem(sound, ONE_SHOT_CLEANUP_SECONDS)
	sound:Play()
end

local function startBGM()
	if bgm then
		return
	end

	local template = resolveTemplate(BGM_NAME)
	if not template then
		return
	end

	local sound = template:Clone()
	sound.Name = BGM_RUNTIME_NAME
	sound.Looped = true
	sound.Volume = BGM_VOLUME
	sound.Parent = SoundService
	sound:Play()
	bgm = sound
end

local function bindButton(button: GuiButton)
	if buttonConnections[button] then
		return
	end

	local connections: ButtonConnections = {}
	buttonConnections[button] = connections

	table.insert(connections, button.Activated:Connect(function()
		if LocalGuiButtonState.IsEnabled(button) then
			playOneShot("Click")
		end
	end))
	table.insert(connections, button.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			disconnectButton(button)
		end
	end))
end

local function scanButtons(root: Instance)
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("GuiButton") then
			bindButton(descendant)
		end
	end

	root.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("GuiButton") then
			bindButton(descendant)
		end
	end)
end

function SoundController.Play(soundName: string)
	if soundName == BGM_NAME then
		startBGM()
		return
	end
	if soundName == "Click" or soundName == "Yes" or soundName == "No" then
		playOneShot(soundName)
		return
	end
	warn("未知音效名称：" .. tostring(soundName))
end

function SoundController.Start()
	if started then
		return
	end
	started = true

	local candidate = ReplicatedStorage:WaitForChild(SOUND_ROOT_NAME, 10)
	if candidate and candidate:IsA("Folder") then
		soundRoot = candidate
	else
		warn("ReplicatedStorage.Sound 不存在或不是 Folder")
	end

	startBGM()

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	scanButtons(playerGui)
	scanButtons(Workspace)
end

return table.freeze(SoundController)
