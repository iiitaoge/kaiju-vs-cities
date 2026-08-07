--[[
	职责：显示统一的黑色提示条。
	输入：ShowMessage、ShowInsufficientMoney 或 ShowJeepUnlocked 请求。
	输出：PopUp.TipBlack.Info 的英文提示，并自动隐藏。
	内部算法：等待 PlayerGui/PopUp/TipBlack/Info → 写入文本 → 显示 → 2 秒后隐藏；
	新提示会覆盖旧提示的隐藏计时。
	不负责：判断余额、执行购买或决定购买失败原因。
]]

local Players = game:GetService("Players")

local TipBlackController = {}

local DISPLAY_DURATION_SECONDS = 2
local INSUFFICIENT_MONEY_TEXT = "Not enough money!"
local JEEP_UNLOCKED_TEXT = "Jeep Unlocked!"

type References = {
	Root: GuiObject,
	Info: TextLabel | TextButton,
}

local started = false
local references: References? = nil
local pendingText: string? = nil
local hideGeneration = 0

local function resolve(playerGui: PlayerGui): References?
	local popup = playerGui:FindFirstChild("PopUp")
	local tipBlack = popup and popup:FindFirstChild("TipBlack")
	local info = tipBlack and tipBlack:FindFirstChild("Info")
	if not tipBlack or not tipBlack:IsA("GuiObject") then
		return nil
	end
	if info and (info:IsA("TextLabel") or info:IsA("TextButton")) then
		return {
			Root = tipBlack,
			Info = info,
		}
	end
	return nil
end

local function show(text: string)
	local current = references
	if not current then
		pendingText = text
		return
	end

	pendingText = nil
	hideGeneration += 1
	local generation = hideGeneration
	current.Info.Text = text
	current.Root.Visible = true
	task.delay(DISPLAY_DURATION_SECONDS, function()
		if generation == hideGeneration and current.Root.Parent then
			current.Root.Visible = false
		end
	end)
end

function TipBlackController.Start()
	if started then
		return
	end
	started = true

	task.spawn(function()
		local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
		while playerGui.Parent do
			local resolved = resolve(playerGui)
			if resolved then
				references = resolved
				resolved.Root.Visible = false
				if pendingText then
					show(pendingText)
				end
				return
			end
			task.wait()
		end
	end)
end

function TipBlackController.ShowInsufficientMoney()
	show(INSUFFICIENT_MONEY_TEXT)
end

function TipBlackController.ShowMessage(text: string)
	show(text)
end

function TipBlackController.ShowJeepUnlocked()
	show(JEEP_UNLOCKED_TEXT)
end

return TipBlackController
