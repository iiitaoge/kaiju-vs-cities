--[[
	职责：记录一次攻击选点会话的坐标、相机、准星和提交结果快照。
	输入：会话/目标事件、准星最近一帧、输入事件和提交结果。
	输出：带 SessionId/ClickId 的低频诊断日志。
	内部算法：每帧只覆盖最近准星快照；进入、切换、点击和结束时才打印。
	不负责：坐标转换、领地判断、相机控制、攻击提交或任何重试。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugLog = require(ReplicatedStorage.Shared.DebugLog)

local log = DebugLog.Create("AttackSelectionCoordinates")
local AttackSelectionCoordinateDiagnostics = {}
local nextSessionId = 0

export type PreviewSnapshot = {
	OccurredAt: number,
	ServerTime: number,
	Frame: number,
	Reason: string,
	RawMouseViewport: Vector2,
	GuiInset: Vector2,
	MouseScreen: Vector2,
	ResolverViewport: Vector2,
	MouseIconEnabled: boolean,
	MouseBehavior: Enum.MouseBehavior,
	WorldPoint: Vector3?,
	Allowed: boolean,
	MatchedTerritoryIndex: number?,
	Visible: boolean,
	CameraCFrame: CFrame?,
	CameraFieldOfView: number?,
	CameraViewportSize: Vector2?,
	VisualPivotWorld: Vector3?,
	VisualPivotViewport: Vector2?,
	VisualRootWorld: Vector3?,
	VisualRootViewport: Vector2?,
	VisualAnchorWorld: Vector3?,
	VisualAnchorViewport: Vector2?,
}

export type InputSnapshot = {
	OccurredAt: number,
	ServerTime: number,
	InputType: Enum.UserInputType,
	GameProcessed: boolean,
	InputScreen: Vector2,
	InputViewport: Vector2,
	GuiInset: Vector2,
	RawMouseViewport: Vector2,
	MouseScreen: Vector2,
	MouseIconEnabled: boolean,
	MouseBehavior: Enum.MouseBehavior,
	WorldPoint: Vector3?,
	CameraCFrame: CFrame?,
	CameraFieldOfView: number?,
	CameraViewportSize: Vector2?,
}

export type Session = {
	RecordTarget: (string, { string }) -> (),
	RecordCamera: (string) -> (),
	RecordCrosshair: (string, string?) -> (),
	RecordInputController: (string) -> (),
	RecordPreview: (PreviewSnapshot) -> (),
	RecordInput: (InputSnapshot) -> (),
	RecordResult: ({ Succeeded: boolean, Reason: string?, CommandId: number? }) -> (),
	End: (string) -> (),
}

local function vector2Text(value: Vector2?): string
	if not value then
		return "nil"
	end
	return string.format("(%.1f,%.1f)", value.X, value.Y)
end

local function vector3Text(value: Vector3?): string
	if not value then
		return "nil"
	end
	return string.format("(%.2f,%.2f,%.2f)", value.X, value.Y, value.Z)
end

local function numberText(value: number?): string
	return if value == nil then "nil" else string.format("%.2f", value)
end

local function cameraDeltaText(previous: CFrame?, current: CFrame?): string
	if not previous or not current then
		return "nil"
	end
	local positionDelta = (previous.Position - current.Position).Magnitude
	local dot = math.clamp(previous.LookVector:Dot(current.LookVector), -1, 1)
	local angleDelta = math.deg(math.acos(dot))
	return string.format("pos=%.3f angle=%.3fdeg", positionDelta, angleDelta)
end

local function distance2Text(a: Vector2?, b: Vector2?): string
	return if a and b then string.format("%.2fpx", (a - b).Magnitude) else "nil"
end

local function distance3Text(a: Vector3?, b: Vector3?): string
	return if a and b then string.format("%.3f", (a - b).Magnitude) else "nil"
end

local function readCamera()
	local camera = workspace.CurrentCamera
	if not camera then
		return nil, nil, nil, "nil"
	end
	return camera.CFrame, camera.FieldOfView, camera.ViewportSize, camera.CameraType.Name
end

-- 输入：本次选择的 SpawnPointId。
-- 输出：独立诊断会话；其状态不参与任何游戏决策。
function AttackSelectionCoordinateDiagnostics.Start(spawnPointId: string): Session
	nextSessionId += 1
	local sessionId = nextSessionId
	local clickId = 0
	local latestClickId = 0
	local latestPreview: PreviewSnapshot? = nil
	local ended = false

	local function tag(eventName: string): string
		return string.format("[S%d %s]", sessionId, eventName)
	end

	local cameraCFrame, fieldOfView, viewportSize, cameraType = readCamera()
	log(
		tag("SESSION_BEGIN"),
		"spawn=" .. spawnPointId,
		"serverTime=" .. numberText(workspace:GetServerTimeNow()),
		"cameraType=" .. cameraType,
		"cameraPos=" .. vector3Text(cameraCFrame and cameraCFrame.Position or nil),
		"fov=" .. numberText(fieldOfView),
		"viewport=" .. vector2Text(viewportSize)
	)

	return {
		RecordTarget = function(targetLabel: string, territoryLabels: { string })
			log(
				tag("TARGET"),
				"target=" .. targetLabel,
				"territories=" .. table.concat(territoryLabels, ",")
			)
		end,
		RecordCamera = function(phase: string)
			local cframe, fov, viewport, currentType = readCamera()
			log(
				tag("CAMERA_" .. phase),
				"serverTime=" .. numberText(workspace:GetServerTimeNow()),
				"type=" .. currentType,
				"pos=" .. vector3Text(cframe and cframe.Position or nil),
				"look=" .. vector3Text(cframe and cframe.LookVector or nil),
				"fov=" .. numberText(fov),
				"viewport=" .. vector2Text(viewport)
			)
		end,
		RecordCrosshair = function(state: string, reason: string?)
			log(tag("CROSSHAIR"), "state=" .. state, "reason=" .. tostring(reason))
		end,
		RecordInputController = function(state: string)
			log(tag("INPUT_CONTROLLER"), "state=" .. state)
		end,
		RecordPreview = function(snapshot: PreviewSnapshot)
			latestPreview = snapshot
		end,
		RecordInput = function(snapshot: InputSnapshot)
			clickId += 1
			latestClickId = clickId
			local clickTag = tag("C" .. tostring(clickId) .. " INPUT")
			log(
				clickTag,
				"serverTime=" .. numberText(snapshot.ServerTime),
				"type=" .. snapshot.InputType.Name,
				"processed=" .. tostring(snapshot.GameProcessed),
				"inputScreen=" .. vector2Text(snapshot.InputScreen),
				"guiInset=" .. vector2Text(snapshot.GuiInset),
				"inputViewport=" .. vector2Text(snapshot.InputViewport),
				"rawMouseViewport=" .. vector2Text(snapshot.RawMouseViewport),
				"mouseScreen=" .. vector2Text(snapshot.MouseScreen),
				"mouseIcon=" .. tostring(snapshot.MouseIconEnabled),
				"mouseBehavior=" .. snapshot.MouseBehavior.Name,
				"inputViewportVsRawMouse="
					.. distance2Text(snapshot.InputViewport, snapshot.RawMouseViewport),
				"world=" .. vector3Text(snapshot.WorldPoint)
			)

			local preview = latestPreview
			if not preview then
				log(tag("C" .. tostring(clickId) .. " PREVIEW"), "missing=true")
				return
			end
			log(
				tag("C" .. tostring(clickId) .. " PREVIEW"),
				"frame=" .. tostring(preview.Frame),
				"serverTime=" .. numberText(preview.ServerTime),
				"ageMs=" .. string.format("%.2f", (snapshot.OccurredAt - preview.OccurredAt) * 1000),
				"reason=" .. preview.Reason,
				"allowed=" .. tostring(preview.Allowed),
				"territoryIndex=" .. tostring(preview.MatchedTerritoryIndex),
				"visible=" .. tostring(preview.Visible),
				"mouseIcon=" .. tostring(preview.MouseIconEnabled),
				"mouseBehavior=" .. preview.MouseBehavior.Name,
				"previewResolverViewport=" .. vector2Text(preview.ResolverViewport),
				"rawMouseViewport=" .. vector2Text(preview.RawMouseViewport),
				"previewVsInput="
					.. distance2Text(preview.ResolverViewport, snapshot.InputViewport),
				"previewWorld=" .. vector3Text(preview.WorldPoint),
				"worldDelta=" .. distance3Text(preview.WorldPoint, snapshot.WorldPoint),
				"cameraDelta="
					.. cameraDeltaText(preview.CameraCFrame, snapshot.CameraCFrame)
			)
			log(
				tag("C" .. tostring(clickId) .. " VISUAL"),
				"pivotWorld=" .. vector3Text(preview.VisualPivotWorld),
				"rootWorld=" .. vector3Text(preview.VisualRootWorld),
				"anchorWorld=" .. vector3Text(preview.VisualAnchorWorld),
				"pivotViewport=" .. vector2Text(preview.VisualPivotViewport),
				"rootViewport=" .. vector2Text(preview.VisualRootViewport),
				"anchorViewport=" .. vector2Text(preview.VisualAnchorViewport),
				"pivotVsCursor="
					.. distance2Text(preview.VisualPivotViewport, preview.RawMouseViewport),
				"rootVsCursor="
					.. distance2Text(preview.VisualRootViewport, preview.RawMouseViewport),
				"anchorVsCursor="
					.. distance2Text(preview.VisualAnchorViewport, preview.RawMouseViewport)
			)
		end,
		RecordResult = function(result)
			log(
				tag("C" .. tostring(latestClickId) .. " RESULT"),
				"succeeded=" .. tostring(result.Succeeded),
				"reason=" .. tostring(result.Reason),
				"commandId=" .. tostring(result.CommandId)
			)
		end,
		End = function(reason: string)
			if ended then
				return
			end
			ended = true
			log(
				tag("SESSION_END"),
				"reason=" .. reason,
				"serverTime=" .. numberText(workspace:GetServerTimeNow())
			)
		end,
	}
end

return AttackSelectionCoordinateDiagnostics
