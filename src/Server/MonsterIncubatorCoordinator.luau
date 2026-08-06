--[[
	职责：协调一只服务器怪兽所在罐体的可逆释放与恢复。
	输入：玩家 Plot、SpawnPointId、怪兽 Model、可选取消检查或关闭态 SpawnCFrame。
	输出：释放/恢复是否完成、稳定原因，以及释放后的地面怪兽 CFrame。
	内部算法：从 Plot Runtime 解析罐体和配置，保存关闭态 Pivot；正向 Liquid→Glass→Base，反向 Base→Glass→Liquid；
	Base 移动时把怪兽作为通用 Follower，失败后保留会话供统一恢复。
	不负责：接受攻击命令、切换怪兽状态、运行远征、回城或复活计时。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ObjectPivotSequence = require(script.Parent.ObjectPivotSequence)
local VerticalSinkResolver = require(script.Parent.VerticalSinkResolver)
local WorkspaceMonsterIncubatorAccess = require(script.Parent.WorkspaceMonsterIncubatorAccess)
local MonsterIncubatorConfigs = require(
	ReplicatedStorage.Shared.Monster.MonsterIncubatorConfigs
)

local MonsterIncubatorCoordinator = {}

export type Result = {
	Succeeded: boolean,
	Reason: string?,
}

export type ReleaseResult = {
	Succeeded: boolean,
	Reason: string?,
	GroundMonsterCFrame: CFrame?,
}

type SessionState = "Releasing" | "Open" | "Interrupted" | "Restoring"

type Session = {
	State: SessionState,
	Incubator: WorkspaceMonsterIncubatorAccess.Incubator,
	Config: any,
	InitialLiquidCFrame: CFrame,
	InitialGlassCFrame: CFrame,
	InitialBaseCFrame: CFrame,
	GroundMonsterCFrame: CFrame,
}

local sessions: { [Model]: { [string]: Session } } = setmetatable({}, { __mode = "k" })

local function result(succeeded: boolean, reason: string?): Result
	return {
		Succeeded = succeeded,
		Reason = reason,
	}
end

local function releaseResult(
	succeeded: boolean,
	reason: string?,
	groundMonsterCFrame: CFrame?
): ReleaseResult
	return {
		Succeeded = succeeded,
		Reason = reason,
		GroundMonsterCFrame = groundMonsterCFrame,
	}
end

local function getSessions(plot: Model, create: boolean): { [string]: Session }?
	local bySpawnPoint = sessions[plot]
	if not bySpawnPoint and create then
		bySpawnPoint = {}
		sessions[plot] = bySpawnPoint
	end
	return bySpawnPoint
end

local function getActiveSession(plot: Model, spawnPointId: string): Session?
	local bySpawnPoint = getSessions(plot, false)
	local session = bySpawnPoint and bySpawnPoint[spawnPointId]
	if session and not session.Incubator.Model:IsDescendantOf(workspace) then
		(bySpawnPoint :: { [string]: Session })[spawnPointId] = nil
		if next(bySpawnPoint :: { [string]: Session }) == nil then
			sessions[plot] = nil
		end
		return nil
	end
	return session
end

local function getObjectPivot(object: BasePart | Model): CFrame
	return if object:IsA("BasePart") then object.CFrame else object:GetPivot()
end

local function resolve(plot: Model, spawnPointId: string)
	local config = MonsterIncubatorConfigs[spawnPointId]
	if not config then
		return nil, nil, "IncubatorConfigUnavailable"
	end
	local incubator, accessReason = WorkspaceMonsterIncubatorAccess.Resolve(
		plot,
		spawnPointId
	)
	if not incubator then
		return nil, nil, accessReason or "IncubatorUnavailable"
	end
	return incubator, config, nil
end

function MonsterIncubatorCoordinator.Validate(
	plot: Model,
	spawnPointId: string
): Result
	local incubator, _, reason = resolve(plot, spawnPointId)
	if not incubator then
		return result(false, reason)
	end
	if getActiveSession(plot, spawnPointId) then
		return result(false, "IncubatorBusy")
	end
	return result(true, nil)
end

function MonsterIncubatorCoordinator.Release(
	plot: Model,
	spawnPointId: string,
	monster: Model,
	isCancelled: (() -> boolean)?
): ReleaseResult
	if typeof(monster) ~= "Instance" or not monster:IsA("Model") or monster.Parent == nil then
		return releaseResult(false, "MonsterUnavailable", nil)
	end
	if isCancelled ~= nil and type(isCancelled) ~= "function" then
		return releaseResult(false, "InvalidCancellationCheck", nil)
	end
	local bySpawnPoint = getSessions(plot, true) :: { [string]: Session }
	if getActiveSession(plot, spawnPointId) then
		return releaseResult(false, "IncubatorBusy", nil)
	end
	bySpawnPoint = getSessions(plot, true) :: { [string]: Session }

	local incubator, config, resolveReason = resolve(plot, spawnPointId)
	if not incubator or not config then
		return releaseResult(false, resolveReason or "IncubatorUnavailable", nil)
	end
	local initialLiquidCFrame = getObjectPivot(incubator.Liquid)
	local initialGlassCFrame = incubator.Glass.CFrame
	local initialBaseCFrame = incubator.Base:GetPivot()
	local liquidTarget, liquidReason = VerticalSinkResolver.Resolve(
		incubator.Liquid,
		incubator.Target
	)
	local glassTarget, glassReason = VerticalSinkResolver.Resolve(
		incubator.Glass,
		incubator.Target
	)
	local baseTarget, baseReason = VerticalSinkResolver.Resolve(
		incubator.Base,
		incubator.Target
	)
	local targetReason = liquidReason or glassReason or baseReason
	if not liquidTarget or not glassTarget or not baseTarget then
		return releaseResult(false, targetReason or "IncubatorTargetResolveFailed", nil)
	end

	local groundMonsterCFrame = baseTarget
		* initialBaseCFrame:ToObjectSpace(monster:GetPivot())
	local session: Session = {
		State = "Releasing",
		Incubator = incubator,
		Config = config,
		InitialLiquidCFrame = initialLiquidCFrame,
		InitialGlassCFrame = initialGlassCFrame,
		InitialBaseCFrame = initialBaseCFrame,
		GroundMonsterCFrame = groundMonsterCFrame,
	}
	bySpawnPoint[spawnPointId] = session

	local motion = ObjectPivotSequence.Play({
		{
			Object = incubator.Liquid,
			TargetCFrame = liquidTarget,
			Duration = config.Release.Liquid.Duration,
			StartNextAt = config.Release.Liquid.StartNextAt,
			EasingStyle = config.EasingStyle,
			EasingDirection = config.EasingDirection,
		},
		{
			Object = incubator.Glass,
			TargetCFrame = glassTarget,
			Duration = config.Release.Glass.Duration,
			StartNextAt = config.Release.Glass.StartNextAt,
			EasingStyle = config.EasingStyle,
			EasingDirection = config.EasingDirection,
		},
		{
			Object = incubator.Base,
			TargetCFrame = baseTarget,
			Duration = config.Release.Base.Duration,
			EasingStyle = config.EasingStyle,
			EasingDirection = config.EasingDirection,
			Followers = { monster },
		},
	}, {
		IsCancelled = isCancelled,
	})
	if not motion.Succeeded then
		session.State = "Interrupted"
		return releaseResult(false, motion.Reason or "IncubatorReleaseFailed", groundMonsterCFrame)
	end
	session.State = "Open"
	return releaseResult(true, nil, groundMonsterCFrame)
end

-- 无活动会话时是幂等成功；monster=nil 用于战败后空罐复位。
function MonsterIncubatorCoordinator.Restore(
	plot: Model,
	spawnPointId: string,
	monster: Model?,
	homeCFrame: CFrame?
): Result
	local session = getActiveSession(plot, spawnPointId)
	local bySpawnPoint = getSessions(plot, false)
	if not session then
		if monster and homeCFrame and monster.Parent then
			monster:PivotTo(homeCFrame)
		end
		return result(true, nil)
	end
	if session.State == "Restoring" then
		return result(false, "IncubatorBusy")
	end
	if monster ~= nil
		and (typeof(monster) ~= "Instance" or not monster:IsA("Model") or monster.Parent == nil) then
		return result(false, "MonsterUnavailable")
	end
	if homeCFrame ~= nil and typeof(homeCFrame) ~= "CFrame" then
		return result(false, "InvalidHomeCFrame")
	end

	local previousState = session.State
	session.State = "Restoring"
	if monster and previousState == "Open" then
		monster:PivotTo(session.GroundMonsterCFrame)
	end

	local followers = if monster then { monster } else nil
	local config = session.Config
	local motion = ObjectPivotSequence.Play({
		{
			Object = session.Incubator.Base,
			TargetCFrame = session.InitialBaseCFrame,
			Duration = config.Restore.Base.Duration,
			StartNextAt = config.Restore.Base.StartNextAt,
			EasingStyle = config.EasingStyle,
			EasingDirection = config.EasingDirection,
			Followers = followers,
		},
		{
			Object = session.Incubator.Glass,
			TargetCFrame = session.InitialGlassCFrame,
			Duration = config.Restore.Glass.Duration,
			StartNextAt = config.Restore.Glass.StartNextAt,
			EasingStyle = config.EasingStyle,
			EasingDirection = config.EasingDirection,
		},
		{
			Object = session.Incubator.Liquid,
			TargetCFrame = session.InitialLiquidCFrame,
			Duration = config.Restore.Liquid.Duration,
			EasingStyle = config.EasingStyle,
			EasingDirection = config.EasingDirection,
		},
	})
	if not motion.Succeeded then
		session.State = "Interrupted"
		return result(false, motion.Reason or "IncubatorRestoreFailed")
	end
	if monster and homeCFrame and monster.Parent then
		monster:PivotTo(homeCFrame)
	end
	(bySpawnPoint :: { [string]: Session })[spawnPointId] = nil
	if next(bySpawnPoint :: { [string]: Session }) == nil then
		sessions[plot] = nil
	end
	return result(true, nil)
end

return MonsterIncubatorCoordinator
