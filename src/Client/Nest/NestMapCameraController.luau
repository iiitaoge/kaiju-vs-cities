--[[
	职责：管理巢穴 Map 的本地镜头会话。
	输入：Nest Model 和 CameraMarker；Focus 接收新的 CameraMarker。
	输出：可切换目标并恢复打开 Map 前相机状态的会话。
	内部算法：复用 MonsterFollowCamera 的 Scriptable 相机、Marker CFrame 平滑过渡和恢复算法；
	以首个 Nest Model 维持会话，左右切换只更换目标 CFrame。
	不负责：查找场景、巢穴状态、派遣或 UI。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterFollowCamera = require(script.Parent.Parent.Camera.MonsterFollowCamera)
local NestMapCameraConfigs = require(
	ReplicatedStorage.Shared.Nest.NestMapCameraConfigs
)

local NestMapCameraController = {}

export type Session = {
	Focus: (marker: BasePart) -> boolean,
	Stop: (string?) -> (),
	IsActive: () -> boolean,
}

local activeSession: Session? = nil

local function focus(session: Session, marker: BasePart): boolean
	return session.Focus(marker)
end

function NestMapCameraController.Open(
	nestModel: Model,
	marker: BasePart
): (Session?, string?)
	assert(typeof(nestModel) == "Instance" and nestModel:IsA("Model"), "nestModel 必须是 Model")
	assert(typeof(marker) == "Instance" and marker:IsA("BasePart"), "marker 必须是 BasePart")

	if activeSession and activeSession.IsActive() then
		local focused = focus(activeSession, marker)
		return activeSession, if focused then nil else "CameraSessionUnavailable"
	end

	local followSession = MonsterFollowCamera.Start(nestModel, {
		Offset = Vector3.zero,
		FieldOfView = NestMapCameraConfigs.FieldOfView,
		Responsiveness = NestMapCameraConfigs.Responsiveness,
		RestoreDuration = NestMapCameraConfigs.RestoreDuration,
	})
	local session: Session = {
		Focus = function(nextMarker: BasePart): boolean
			assert(
				typeof(nextMarker) == "Instance" and nextMarker:IsA("BasePart"),
				"nextMarker 必须是 BasePart"
			)
			return followSession.Focus({
				TargetCFrame = nextMarker.CFrame,
				TransitionDuration = NestMapCameraConfigs.TransitionDuration,
				FieldOfView = NestMapCameraConfigs.FieldOfView,
			})
		end,
		Stop = function(reason: string?)
			followSession.Stop(reason or "NestMapClosed")
			if activeSession == session then
				activeSession = nil
			end
		end,
		IsActive = function()
			return followSession.IsActive()
		end,
	}
	activeSession = session

	local focused = focus(session, marker)
	return session, if focused then nil else "CameraFocusFailed"
end

function NestMapCameraController.Stop(reason: string?)
	local session = activeSession
	if session then
		session.Stop(reason or "NestMapClosed")
	end
end

return NestMapCameraController
