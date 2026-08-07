--[[
	职责：显示 PopUp.Expanded 的区域扩展和培养罐建造英文提示。
	输入：ExpandedPresentation RemoteEvent 的合法 command。
	输出：区域扩展显示 Title；培养罐建造显示 Name；2 秒后自动隐藏。
	内部算法：新提示覆盖旧提示并刷新隐藏计时；UI 尚未加载时暂存最后一条提示。
	不负责：判断业务成功、发送购买请求、播放建筑动画或修改服务器状态。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ExpandedPresentationProtocol = require(
	ReplicatedStorage.Shared.UI.ExpandedPresentationProtocol
)

local ExpandedController = {}

local DISPLAY_DURATION_SECONDS = 2

type TextObject = TextLabel | TextButton

type References = {
	Root: GuiObject,
	Title: TextObject,
	Name: TextObject,
}

local started = false
local references: References? = nil
local pendingCommand: ExpandedPresentationProtocol.Command? = nil
local hideGeneration = 0

local function findTextObject(parent: Instance?, name: string): TextObject?
	local child = parent and parent:FindFirstChild(name)
	if child and child:IsA("TextLabel") then
		return child
	end
	if child and child:IsA("TextButton") then
		return child
	end
	return nil
end

local function resolve(playerGui: PlayerGui): References?
	local popup = playerGui:FindFirstChild("PopUp")
	local expanded = popup and popup:FindFirstChild("Expanded")
	if not expanded or not expanded:IsA("GuiObject") then
		return nil
	end
	local title = findTextObject(expanded, "Title")
	local name = findTextObject(expanded, "Name")
	if not title or not name then
		return nil
	end
	return {
		Root = expanded,
		Title = title,
		Name = name,
	}
end

local function formatRegionText(regionId: string): string
	local regionNumber = string.match(regionId, "%d+")
	return string.format("Region %s Expanded!", regionNumber or regionId)
end

local function show(command: ExpandedPresentationProtocol.Command)
	local current = references
	if not current then
		pendingCommand = command
		return
	end

	pendingCommand = nil
	hideGeneration += 1
	local generation = hideGeneration
	current.Title.Visible = false
	current.Name.Visible = false

	if command.Kind == ExpandedPresentationProtocol.Kinds.RegionExpanded then
		current.Title.Text = formatRegionText(command.RegionId)
		current.Title.Visible = true
	else
		current.Name.Text = "Monster Incubator Built!"
		current.Name.Visible = true
	end
	current.Root.Visible = true

	task.delay(DISPLAY_DURATION_SECONDS, function()
		if generation == hideGeneration and current.Root.Parent then
			current.Root.Visible = false
			current.Title.Visible = false
			current.Name.Visible = false
		end
	end)
end

local function getRemote(): RemoteEvent
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
	assert(remotes and remotes:IsA("Folder"), "找不到 ReplicatedStorage/Remotes")
	local remote = remotes:WaitForChild(ExpandedPresentationProtocol.RemoteName, 10)
	assert(
		remote and remote:IsA("RemoteEvent"),
		"找不到区域扩展提示 RemoteEvent：" .. ExpandedPresentationProtocol.RemoteName
	)
	return remote
end

function ExpandedController.Start()
	if started then
		return
	end
	started = true

	getRemote().OnClientEvent:Connect(function(command)
		local valid, reason = ExpandedPresentationProtocol.Validate(command)
		if not valid then
			warn("拒绝区域扩展提示命令：", reason)
			return
		end
		show(command)
	end)

	task.spawn(function()
		local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
		while playerGui.Parent do
			local resolved = resolve(playerGui)
			if resolved then
				references = resolved
				resolved.Root.Visible = false
				resolved.Title.Visible = false
				resolved.Name.Visible = false
				local queuedCommand = pendingCommand
				pendingCommand = nil
				if queuedCommand then
					show(queuedCommand)
				end
				return
			end
			task.wait()
		end
	end)
end

return ExpandedController
