--[[
	职责：为一场怪兽激光决斗创建独立场景，并把原有两只怪兽移入/移出场景。
	输入：相遇后的攻守双方、各自回到相遇点的 CFrame、战斗失败恢复状态和移动配置。
	输出：独立决斗 Session；退出时恢复模型父级、位置和镜头。
	内部算法：克隆 ServerStorage 模板，移动到隔离运行位置；先发布攻击方自动镜头并等待完成，
	再把双方放到模板出生点，原地互相转向，不再进行接近移动，随后发布防守方可选镜头。
	战斗结束后先把模型移回原运行时父级，再销毁场景。
	不负责：伤害、攻击动画、胜负计算或防守怪兽回槽。
]]

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterDuelCameraPublisher = require(script.Parent.MonsterDuelCameraPublisher)
local GodzillaMoveService = require(script.Parent.GodzillaMoveService)
local GodzillaService = require(script.Parent.GodzillaService)
local ModelMover = require(script.Parent.ModelMover)
local MonsterRosterCoordinator = require(script.Parent.MonsterRosterCoordinator)
local MonsterDuelCameraProtocol = require(
	ReplicatedStorage.Shared.Monster.MonsterDuelCameraProtocol
)
local MonsterDuelSceneConfig = require(
	ReplicatedStorage.Shared.Monster.MonsterDuelSceneConfig
)

local MonsterDuelSceneCoordinator = {}

export type Combatant = {
	Player: Player,
	SpawnPointId: string,
}

export type MovementConfig = {
	DesiredGap: number,
	MaxGap: number,
	MoveSpeed: number,
	MaxTravelDuration: number?,
	TimingSafetyMargin: number?,
	TurnDuration: number,
}

export type EnterOptions = {
	TraceId: string,
	AttackerReturnCFrame: CFrame,
	DefenderReturnCFrame: CFrame,
	AttackerFailureState: string,
	DefenderFailureState: string,
	AttackerMovement: MovementConfig,
	DefenderMovement: MovementConfig,
	SetMoving: ((Model, boolean, number?) -> ())?,
	IsCancelled: (() -> boolean)?,
}

export type Session = {
	DuelId: string,
	Scene: Model,
	Attacker: Combatant,
	Defender: Combatant,
	AttackerModel: Model,
	DefenderModel: Model,
	AttackerParent: Instance,
	DefenderParent: Instance,
	AttackerReturnCFrame: CFrame,
	DefenderReturnCFrame: CFrame,
	AttackerFailureState: string,
	DefenderFailureState: string,
	CameraCFrame: CFrame,
	CameraFitSpheres: { MonsterDuelCameraProtocol.CameraFitSphere },
	Active: boolean,
	DefenderWatching: boolean,
}

export type Result = {
	Succeeded: boolean,
	Reason: string?,
	Session: Session?,
}

export type ExitOptions = {
	RestoreAttackerToRegion: boolean?,
}

local activeSessions: { [string]: Session } = {}
local started = false
local nextSceneSlot = 0

local function result(succeeded: boolean, reason: string?, session: Session?): Result
	return {
		Succeeded = succeeded,
		Reason = reason,
		Session = session,
	}
end

local function sanitizeName(value: string): string
	local sanitized = string.gsub(value, "[^%w_%-]", "_")
	return if sanitized ~= "" then sanitized else "Duel"
end

local function getModelCameraFitRadius(model: Model): number
	local boundingBoxCFrame, boundingBoxSize = model:GetBoundingBox()
	local pivotPosition = model:GetPivot().Position
	return (boundingBoxCFrame.Position - pivotPosition).Magnitude
		+ boundingBoxSize.Magnitude * 0.5
end

local function getCameraFitSpheres(
	attackerModel: Model,
	defenderModel: Model,
	attackerSpawnPoint: BasePart,
	defenderSpawnPoint: BasePart
): { MonsterDuelCameraProtocol.CameraFitSphere }
	return {
		{
			Center = attackerSpawnPoint.Position,
			Radius = getModelCameraFitRadius(attackerModel),
		},
		{
			Center = defenderSpawnPoint.Position,
			Radius = getModelCameraFitRadius(defenderModel),
		},
	}
end

local function getRuntimeFolder(): Folder
	local existing = Workspace:FindFirstChild(MonsterDuelSceneConfig.RuntimeFolderName)
	if existing then
		assert(existing:IsA("Folder"), "Workspace 决斗运行时目录必须是 Folder")
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = MonsterDuelSceneConfig.RuntimeFolderName
	folder.Parent = Workspace
	return folder
end

local function getTemplate(): Model?
	local serverTemplate = ServerStorage:FindFirstChild(MonsterDuelSceneConfig.TemplateName)
	if serverTemplate and serverTemplate:IsA("Model") then
		return serverTemplate
	end
	local workspaceTemplate = Workspace:FindFirstChild(MonsterDuelSceneConfig.TemplateName)
	if workspaceTemplate and workspaceTemplate:IsA("Model") then
		return workspaceTemplate
	end
	return nil
end

local function getBasePart(parent: Instance, name: string): BasePart?
	local child = parent:FindFirstChild(name)
	return if child and child:IsA("BasePart") then child else nil
end

local function getDefenderSpawnPoint(scene: Model): BasePart?
	return getBasePart(scene, MonsterDuelSceneConfig.DefenderSpawnPointName)
		or getBasePart(scene, MonsterDuelSceneConfig.DefenderSpawnPointFallbackName)
end

local function setSceneStatic(scene: Model)
	for _, descendant in scene:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
	local cameraMarker = getBasePart(scene, MonsterDuelSceneConfig.CameraMarkerName)
	if cameraMarker then
		cameraMarker.CanCollide = false
		cameraMarker.CanTouch = false
		cameraMarker.CanQuery = false
	end
	local attackerSpawnPoint = getBasePart(
		scene,
		MonsterDuelSceneConfig.AttackerSpawnPointName
	)
	if attackerSpawnPoint then
		attackerSpawnPoint.CanCollide = false
		attackerSpawnPoint.CanTouch = false
		attackerSpawnPoint.CanQuery = false
	end
	local defenderSpawnPoint = getDefenderSpawnPoint(scene)
	if defenderSpawnPoint then
		defenderSpawnPoint.CanCollide = false
		defenderSpawnPoint.CanTouch = false
		defenderSpawnPoint.CanQuery = false
	end
end

local function restoreFailureState(combatant: Combatant, state: string)
	local latest = MonsterRosterCoordinator.Get(combatant.Player, combatant.SpawnPointId)
	if not latest or latest.State == "Defeated" or latest.State == "Recovering" then
		return
	end
	if latest.State == state then
		return
	end
	local restored = MonsterRosterCoordinator.Transition(
		combatant.Player,
		combatant.SpawnPointId,
		state
	)
	if not restored.Succeeded then
		warn("决斗场景失败后恢复怪兽状态失败：", restored.Reason)
	end
end

local function isAliveRecord(record): boolean
	return record ~= nil
		and record.Model ~= nil
		and record.State ~= "Defeated"
		and record.State ~= "Recovering"
		and record.Health > 0
end

local function prepareModel(model: Model)
	GodzillaMoveService.Cancel(model)
	GodzillaService.StopMoving(model)
end

local function clearDuelAttributes(model: Model)
	model:SetAttribute("MonsterDuelId", nil)
	model:SetAttribute("MonsterDuelRole", nil)
end

local function restoreModelParent(model: Model, parent: Instance, scene: Model)
	if model.Parent == scene then
		if parent:IsDescendantOf(Workspace) then
			model.Parent = parent
		else
			model.Parent = Workspace
		end
	end
end

local function publishFocus(
	session: Session,
	player: Player,
	role: MonsterDuelCameraProtocol.Role
): (MonsterDuelCameraPublisher.Result, number)
	local commandId = MonsterDuelCameraPublisher.NextCommandId()
	local published = MonsterDuelCameraPublisher.Publish(player, {
		Kind = MonsterDuelCameraProtocol.FocusKind,
		CommandId = commandId,
		DuelId = session.DuelId,
		Role = role,
		AttackerUserId = session.Attacker.Player.UserId,
		AttackerSpawnPointId = session.Attacker.SpawnPointId,
		DefenderUserId = session.Defender.Player.UserId,
		CameraCFrame = session.CameraCFrame,
		CameraFitSpheres = session.CameraFitSpheres,
		FieldOfView = MonsterDuelSceneConfig.Camera.FieldOfView,
		TransitionDuration = MonsterDuelSceneConfig.Camera.TransitionDuration,
		RestoreDuration = MonsterDuelSceneConfig.Camera.RestoreDuration,
	})
	return published, commandId
end

local function publishRestore(
	session: Session,
	player: Player,
	role: MonsterDuelCameraProtocol.Role,
	restoreToRegion: boolean
)
	MonsterDuelCameraPublisher.Publish(player, {
		Kind = MonsterDuelCameraProtocol.RestoreKind,
		CommandId = MonsterDuelCameraPublisher.NextCommandId(),
		DuelId = session.DuelId,
		Role = role,
		AttackerUserId = session.Attacker.Player.UserId,
		AttackerSpawnPointId = session.Attacker.SpawnPointId,
		DefenderUserId = session.Defender.Player.UserId,
		TransitionDuration = MonsterDuelSceneConfig.Camera.RestoreDuration,
		RestoreToRegion = restoreToRegion,
	})
end

local function handleCameraRequest(
	player: Player,
	request: MonsterDuelCameraProtocol.ToggleRequest
)
	local session = activeSessions[request.DuelId]
	if not session or not session.Active then
		return
	end
	if session.Defender.Player ~= player then
		return
	end
	if request.Enabled then
		session.DefenderWatching = true
		publishFocus(session, player, "Defender")
	else
		session.DefenderWatching = false
		publishRestore(session, player, "Defender", false)
	end
end

function MonsterDuelSceneCoordinator.Start()
	if started then
		return
	end
	started = true
	MonsterDuelCameraPublisher.Start(handleCameraRequest)
	Players.PlayerRemoving:Connect(function(player)
		local sessions = {}
		for _, session in activeSessions do
			if session.Attacker.Player == player or session.Defender.Player == player then
				table.insert(sessions, session)
			end
		end
		for _, session in sessions do
			MonsterDuelSceneCoordinator.Exit(session)
		end
	end)
end

function MonsterDuelSceneCoordinator.Enter(
	attacker: Combatant,
	defender: Combatant,
	options: EnterOptions
): Result
	assert(type(options) == "table", "options 必须是 table")
	assert(type(options.TraceId) == "string" and options.TraceId ~= "", "TraceId 无效")
	assert(typeof(options.AttackerReturnCFrame) == "CFrame", "AttackerReturnCFrame 无效")
	assert(typeof(options.DefenderReturnCFrame) == "CFrame", "DefenderReturnCFrame 无效")
	assert(type(options.AttackerFailureState) == "string", "AttackerFailureState 无效")
	assert(type(options.DefenderFailureState) == "string", "DefenderFailureState 无效")
	assert(type(options.AttackerMovement) == "table", "AttackerMovement 无效")
	assert(type(options.DefenderMovement) == "table", "DefenderMovement 无效")
	if activeSessions[options.TraceId] then
		restoreFailureState(attacker, options.AttackerFailureState)
		restoreFailureState(defender, options.DefenderFailureState)
		return result(false, "DuelAlreadyActive", nil)
	end

	local attackerRecord = MonsterRosterCoordinator.Get(
		attacker.Player,
		attacker.SpawnPointId
	)
	local defenderRecord = MonsterRosterCoordinator.Get(
		defender.Player,
		defender.SpawnPointId
	)
	if not attackerRecord or not attackerRecord.Model then
		return result(false, "AttackerUnavailable", nil)
	end
	if not defenderRecord or not defenderRecord.Model then
		return result(false, "DefenderUnavailable", nil)
	end
	if attackerRecord.State ~= "Encountering" or defenderRecord.State ~= "Encountering" then
		return result(false, "CombatantsNotEncountering", nil)
	end
	local attackerParent = attackerRecord.Model.Parent
	local defenderParent = defenderRecord.Model.Parent
	if not attackerParent or not defenderParent then
		restoreFailureState(attacker, options.AttackerFailureState)
		restoreFailureState(defender, options.DefenderFailureState)
		return result(false, "CombatantParentUnavailable", nil)
	end

	local template = getTemplate()
	if not template then
		restoreFailureState(attacker, options.AttackerFailureState)
		restoreFailureState(defender, options.DefenderFailureState)
		return result(false, "DuelSceneTemplateUnavailable", nil)
	end

	local attackerEntering = MonsterRosterCoordinator.Transition(
		attacker.Player,
		attacker.SpawnPointId,
		"EnteringDuel"
	)
	if not attackerEntering.Succeeded then
		restoreFailureState(defender, options.DefenderFailureState)
		return result(false, attackerEntering.Reason or "AttackerDuelTransitionFailed", nil)
	end
	local defenderEntering = MonsterRosterCoordinator.Transition(
		defender.Player,
		defender.SpawnPointId,
		"EnteringDuel"
	)
	if not defenderEntering.Succeeded then
		restoreFailureState(attacker, options.AttackerFailureState)
		restoreFailureState(defender, options.DefenderFailureState)
		return result(false, defenderEntering.Reason or "DefenderDuelTransitionFailed", nil)
	end

	local scene = template:Clone()
	nextSceneSlot += 1
	scene.Name = "Duel_" .. sanitizeName(options.TraceId)
	scene.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local templatePivot = scene:GetPivot()
	scene:PivotTo(templatePivot * CFrame.new(
		MonsterDuelSceneConfig.RuntimeSceneSpacing * nextSceneSlot,
		0,
		0
	))
	setSceneStatic(scene)
	scene.Parent = getRuntimeFolder()

	local attackerSpawnPoint = getBasePart(
		scene,
		MonsterDuelSceneConfig.AttackerSpawnPointName
	)
	local defenderSpawnPoint = getDefenderSpawnPoint(scene)
	local cameraMarker = getBasePart(scene, MonsterDuelSceneConfig.CameraMarkerName)
	local arena = scene:FindFirstChild(MonsterDuelSceneConfig.ArenaName)
	if not arena or not arena:IsA("Model") then
		if scene.Parent then
			scene:Destroy()
		end
		restoreFailureState(attacker, options.AttackerFailureState)
		restoreFailureState(defender, options.DefenderFailureState)
		return result(false, "DuelArenaUnavailable", nil)
	end
	if not attackerSpawnPoint or not defenderSpawnPoint or not cameraMarker then
		if scene.Parent then
			scene:Destroy()
		end
		restoreFailureState(attacker, options.AttackerFailureState)
		restoreFailureState(defender, options.DefenderFailureState)
		return result(false, "DuelScenePointsUnavailable", nil)
	end

	local attackerModel = attackerEntering.Record and attackerEntering.Record.Model
	local defenderModel = defenderEntering.Record and defenderEntering.Record.Model
	if not attackerModel or not defenderModel then
		if scene.Parent then
			scene:Destroy()
		end
		restoreFailureState(attacker, options.AttackerFailureState)
		restoreFailureState(defender, options.DefenderFailureState)
		return result(false, "CombatantUnavailableAfterTransition", nil)
	end

	local session: Session = {
		DuelId = options.TraceId,
		Scene = scene,
		Attacker = attacker,
		Defender = defender,
		AttackerModel = attackerModel,
		DefenderModel = defenderModel,
		AttackerParent = attackerParent,
		DefenderParent = defenderParent,
		AttackerReturnCFrame = options.AttackerReturnCFrame,
		DefenderReturnCFrame = options.DefenderReturnCFrame,
		AttackerFailureState = options.AttackerFailureState,
		DefenderFailureState = options.DefenderFailureState,
		CameraCFrame = cameraMarker.CFrame,
		CameraFitSpheres = getCameraFitSpheres(
			attackerModel,
			defenderModel,
			attackerSpawnPoint,
			defenderSpawnPoint
		),
		Active = true,
		DefenderWatching = false,
	}
	activeSessions[session.DuelId] = session

	local focusPublished, focusCommandId = publishFocus(
		session,
		attacker.Player,
		"Attacker"
	)
	if not focusPublished.Succeeded then
		MonsterDuelSceneCoordinator.Exit(session)
		return result(false, focusPublished.Reason or "DuelCameraPublishFailed", nil)
	end
	local cameraReady = MonsterDuelCameraPublisher.WaitForCompletion(
		attacker.Player,
		attacker.SpawnPointId,
		focusCommandId,
		MonsterDuelSceneConfig.Camera.CompletionTimeout,
		function()
			return not session.Active
				or (options.IsCancelled ~= nil and options.IsCancelled())
		end
	)
	if not cameraReady.Succeeded then
		MonsterDuelSceneCoordinator.Exit(session)
		return result(false, cameraReady.Reason or "DuelCameraTransitionFailed", nil)
	end

	attackerModel.Parent = scene
	defenderModel.Parent = scene
	attackerModel:SetAttribute("MonsterDuelId", options.TraceId)
	attackerModel:SetAttribute("MonsterDuelRole", "Attacker")
	defenderModel:SetAttribute("MonsterDuelId", options.TraceId)
	defenderModel:SetAttribute("MonsterDuelRole", "Defender")
	local attackerMoved = ModelMover.Snap(attackerModel, attackerSpawnPoint.CFrame)
	local defenderMoved = ModelMover.Snap(defenderModel, defenderSpawnPoint.CFrame)
	if not attackerMoved or not defenderMoved then
		MonsterDuelSceneCoordinator.Exit(session)
		return result(false, "DuelScenePlacementFailed", nil)
	end

	MonsterDuelCameraPublisher.Publish(defender.Player, {
		Kind = MonsterDuelCameraProtocol.AvailableKind,
		CommandId = MonsterDuelCameraPublisher.NextCommandId(),
		DuelId = session.DuelId,
		Role = "Defender",
		AttackerUserId = attacker.Player.UserId,
		AttackerSpawnPointId = attacker.SpawnPointId,
		DefenderUserId = defender.Player.UserId,
		CameraCFrame = session.CameraCFrame,
		CameraFitSpheres = session.CameraFitSpheres,
		FieldOfView = MonsterDuelSceneConfig.Camera.FieldOfView,
		TransitionDuration = MonsterDuelSceneConfig.Camera.TransitionDuration,
		RestoreDuration = MonsterDuelSceneConfig.Camera.RestoreDuration,
	})

	-- Battle 场景不再从出生点移动到中点；两只怪兽保留出生点位置，原地转向对方。
	-- FaceTo 只改变旋转，不改变模型位置，之后由激光决斗协调器直接开始对波。
	local attackerFaced = GodzillaMoveService.FaceTo(
		attackerModel,
		defenderModel:GetPivot().Position,
		options.AttackerMovement.TurnDuration
	)
	local defenderFaced = GodzillaMoveService.FaceTo(
		defenderModel,
		attackerModel:GetPivot().Position,
		options.DefenderMovement.TurnDuration
	)
	if not attackerFaced or not defenderFaced then
		MonsterDuelSceneCoordinator.Exit(session)
		return result(false, "DuelFacingFailed", nil)
	end

	return result(true, nil, session)
end

function MonsterDuelSceneCoordinator.Exit(
	session: Session,
	options: ExitOptions?
): Result
	if not session.Active then
		return result(true, nil, session)
	end
	session.Active = false
	activeSessions[session.DuelId] = nil

	publishRestore(
		session,
		session.Attacker.Player,
		"Attacker",
		options ~= nil and options.RestoreAttackerToRegion == true
	)
	publishRestore(session, session.Defender.Player, "Defender", false)

	local attackerRecord = MonsterRosterCoordinator.Get(
		session.Attacker.Player,
		session.Attacker.SpawnPointId
	)
	local defenderRecord = MonsterRosterCoordinator.Get(
		session.Defender.Player,
		session.Defender.SpawnPointId
	)
	if attackerRecord and attackerRecord.Model then
		prepareModel(attackerRecord.Model)
	end
	if defenderRecord and defenderRecord.Model then
		prepareModel(defenderRecord.Model)
	end

	if attackerRecord and attackerRecord.Model then
		restoreFailureState(session.Attacker, session.AttackerFailureState)
		restoreModelParent(attackerRecord.Model, session.AttackerParent, session.Scene)
		clearDuelAttributes(attackerRecord.Model)
		local latest = MonsterRosterCoordinator.Get(
			session.Attacker.Player,
			session.Attacker.SpawnPointId
		)
		if isAliveRecord(latest) then
			ModelMover.Snap(attackerRecord.Model, session.AttackerReturnCFrame)
		end
	end

	if defenderRecord and defenderRecord.Model then
		restoreFailureState(session.Defender, session.DefenderFailureState)
		restoreModelParent(defenderRecord.Model, session.DefenderParent, session.Scene)
		clearDuelAttributes(defenderRecord.Model)
		local latest = MonsterRosterCoordinator.Get(
			session.Defender.Player,
			session.Defender.SpawnPointId
		)
		if isAliveRecord(latest) then
			ModelMover.Snap(defenderRecord.Model, session.DefenderReturnCFrame)
		end
	end

	if session.Scene.Parent then
		session.Scene:Destroy()
	end
	return result(true, nil, session)
end

return MonsterDuelSceneCoordinator
