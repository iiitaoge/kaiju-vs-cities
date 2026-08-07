--[[
	职责：为防守玩家执行可选的决斗场景静态镜头，并在退出时恢复原镜头。
	输入：服务端 DuelAvailable/DuelFocus/DuelRestore 命令。
	输出：CurrentCamera 的平滑切换；不改变怪兽或战斗状态。
	内部算法：首次聚焦时保存相机快照；RenderStepped 内插值到 CameraMarker CFrame，
	收到恢复命令后插值回原快照并交还默认相机控制器。
]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local MonsterDuelCameraProtocol = require(
	game:GetService("ReplicatedStorage").Shared.Monster.MonsterDuelCameraProtocol
)
local MonsterDuelCameraRemoteClient = require(script.Parent.MonsterDuelCameraRemoteClient)

local MonsterDuelCameraController = {}

type CameraSnapshot = {
	CameraType: Enum.CameraType,
	CameraSubject: Instance?,
	CFrame: CFrame,
	FieldOfView: number,
}

type Transition = {
	StartCFrame: CFrame,
	TargetCFrame: CFrame,
	StartFieldOfView: number,
	TargetFieldOfView: number,
	Duration: number,
	Elapsed: number,
	OnCompleted: (() -> ())?,
}

local started = false
local active = false
local activeDuelId: string? = nil
local previous: CameraSnapshot? = nil
local transition: Transition? = nil
local targetCFrame: CFrame? = nil
local targetFieldOfView = 70
local latestCommandId = 0

local function getCamera(): Camera?
	return Workspace.CurrentCamera
end

local function finishRestore()
	local camera = getCamera()
	local snapshot = previous
	if camera and snapshot then
		camera.CameraType = snapshot.CameraType
		camera.CameraSubject = snapshot.CameraSubject
		camera.CFrame = snapshot.CFrame
		camera.FieldOfView = snapshot.FieldOfView
	end
	active = false
	activeDuelId = nil
	previous = nil
	transition = nil
	targetCFrame = nil
end

local function beginTransition(
	target: CFrame,
	fieldOfView: number,
	duration: number,
	onCompleted: (() -> ())?
)
	local camera = getCamera()
	if not camera then
		return
	end
	transition = {
		StartCFrame = camera.CFrame,
		TargetCFrame = target,
		StartFieldOfView = camera.FieldOfView,
		TargetFieldOfView = fieldOfView,
		Duration = duration,
		Elapsed = 0,
		OnCompleted = onCompleted,
	}
	camera.CameraType = Enum.CameraType.Scriptable
end

local function focus(command: MonsterDuelCameraProtocol.CameraCommand)
	if command.Role ~= "Defender"
		or command.DefenderUserId ~= Players.LocalPlayer.UserId
	then
		return
	end
	if command.CommandId <= latestCommandId then
		return
	end
	latestCommandId = command.CommandId
	local camera = getCamera()
	if not camera then
		return
	end
	if not active then
		previous = {
			CameraType = camera.CameraType,
			CameraSubject = camera.CameraSubject,
			CFrame = camera.CFrame,
			FieldOfView = camera.FieldOfView,
		}
		active = true
	end
	activeDuelId = command.DuelId
	targetCFrame = command.CameraCFrame
	targetFieldOfView = command.FieldOfView
	beginTransition(
		command.CameraCFrame,
		command.FieldOfView,
		command.TransitionDuration,
		nil
	)
end

local function restore(command: MonsterDuelCameraProtocol.RestoreCommand)
	if command.Role ~= "Defender"
		or command.DefenderUserId ~= Players.LocalPlayer.UserId
	then
		return
	end
	if command.CommandId <= latestCommandId then
		return
	end
	latestCommandId = command.CommandId
	if not active or activeDuelId ~= command.DuelId then
		return
	end
	local snapshot = previous
	if not snapshot then
		finishRestore()
		return
	end
	beginTransition(
		snapshot.CFrame,
		snapshot.FieldOfView,
		command.TransitionDuration,
		finishRestore
	)
end

function MonsterDuelCameraController.Start()
	if started then
		return
	end
	started = true
	MonsterDuelCameraRemoteClient.Observe(function(command)
		if command.Kind == MonsterDuelCameraProtocol.AvailableKind then
			if command.CommandId > latestCommandId then
				latestCommandId = command.CommandId
			end
		elseif command.Kind == MonsterDuelCameraProtocol.FocusKind then
			focus(command)
		elseif command.Kind == MonsterDuelCameraProtocol.RestoreKind then
			restore(command)
		end
	end)
	RunService.RenderStepped:Connect(function(deltaTime)
		if not active then
			return
		end
		local camera = getCamera()
		if not camera then
			return
		end
		local currentTransition = transition
		if currentTransition then
			currentTransition.Elapsed += deltaTime
			local alpha = if currentTransition.Duration <= 0
				then 1
				else math.clamp(
					currentTransition.Elapsed / currentTransition.Duration,
					0,
					1
				)
			local easedAlpha = TweenService:GetValue(
				alpha,
				Enum.EasingStyle.Sine,
				Enum.EasingDirection.InOut
			)
			camera.CameraType = Enum.CameraType.Scriptable
			camera.CFrame = currentTransition.StartCFrame:Lerp(
				currentTransition.TargetCFrame,
				easedAlpha
			)
			camera.FieldOfView = currentTransition.StartFieldOfView
				+ (currentTransition.TargetFieldOfView - currentTransition.StartFieldOfView)
					* easedAlpha
			if alpha >= 1 and transition == currentTransition then
				transition = nil
				if currentTransition.OnCompleted then
					currentTransition.OnCompleted()
				end
			end
			return
		end
		if targetCFrame then
			camera.CameraType = Enum.CameraType.Scriptable
			camera.CFrame = targetCFrame
			camera.FieldOfView = targetFieldOfView
		end
	end)
end

return MonsterDuelCameraController
