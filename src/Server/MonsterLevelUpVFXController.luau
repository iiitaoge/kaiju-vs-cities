--[[
	职责：播放一次玩家怪兽升级特效。
	输入：玩家 Plot、怪兽 Home CFrame。
	输出：Succeeded、稳定失败 Reason；特效失败不应影响升级事务。
	内部算法：读取 ReplicatedStorage.VFX.LevelUpVFX，克隆到 Plot/Runtime/VFX，
		先对齐整个 Model Pivot，再短暂开启粒子发射器，等待粒子生命周期后销毁。
	不负责：决定升级条件、扣款、保存等级或解析 MonsterHomeAttachment。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterLevelUpVFXController = {}

local VFX_ROOT_NAME = "VFX"
local LEVEL_UP_VFX_NAME = "LevelUpVFX"
local PLOT_RUNTIME_NAME = "Runtime"
local RUNTIME_VFX_NAME = "VFX"

-- 当前资源最长粒子生命周期为 2 秒；短暂开启发射器后再等待尾粒子自然消失。
local EMITTER_ACTIVE_DURATION = 0.6
local EFFECT_LIFETIME = 2.8

export type Result = {
	Succeeded: boolean,
	Reason: string?,
}

local function result(succeeded: boolean, reason: string?): Result
	return {
		Succeeded = succeeded,
		Reason = reason,
	}
end

local function getTemplate(): (Model?, string?)
	local root = ReplicatedStorage:FindFirstChild(VFX_ROOT_NAME)
	if not root or not root:IsA("Folder") then
		return nil, "MissingVFXRoot"
	end

	local template = root:FindFirstChild(LEVEL_UP_VFX_NAME)
	if not template or not template:IsA("Model") then
		return nil, "MissingLevelUpVFXTemplate"
	end
	if not template.Archivable then
		return nil, "LevelUpVFXTemplateNotArchivable"
	end
	return template, nil
end

local function getRuntimeVFXFolder(plot: Model): (Folder?, string?)
	local runtime = plot:FindFirstChild(PLOT_RUNTIME_NAME)
	if not runtime or not runtime:IsA("Folder") then
		return nil, "MissingPlotRuntime"
	end

	local existing = runtime:FindFirstChild(RUNTIME_VFX_NAME)
	if existing then
		if not existing:IsA("Folder") then
			return nil, "InvalidRuntimeVFXFolder"
		end
		return existing, nil
	end

	local folder = Instance.new("Folder")
	folder.Name = RUNTIME_VFX_NAME
	folder.Parent = runtime
	return folder, nil
end

local function getParticleEmitters(model: Model): { ParticleEmitter }
	local emitters = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			table.insert(emitters, descendant)
		end
	end
	return emitters
end

local function setEmittersEnabled(emitters: { ParticleEmitter }, enabled: boolean)
	for _, emitter in emitters do
		emitter.Enabled = enabled
	end
end

-- 输入：已克隆且未放入 Workspace 的升级特效、目标世界 CFrame。
-- 输出：已经进入 Plot Runtime 并开始播放的特效 Model。
-- 内部算法：先关闭发射器并定位，Parent 后再开启，避免克隆瞬间在错误位置发射。
local function createEffect(
	template: Model,
	runtimeVFXFolder: Folder,
	homeCFrame: CFrame
): (Model?, string?)
	local effect = template:Clone()
	if not effect then
		return nil, "LevelUpVFXCloneFailed"
	end

	local emitters = getParticleEmitters(effect)
	if #emitters == 0 then
		return nil, "LevelUpVFXHasNoParticleEmitter"
	end

	setEmittersEnabled(emitters, false)
	effect.Name = LEVEL_UP_VFX_NAME
	effect.Parent = runtimeVFXFolder
	effect:PivotTo(homeCFrame)
	setEmittersEnabled(emitters, true)

	task.delay(EMITTER_ACTIVE_DURATION, function()
		if effect.Parent then
			setEmittersEnabled(emitters, false)
		end
	end)

	task.delay(EFFECT_LIFETIME, function()
		if effect.Parent then
			effect:Destroy()
		end
	end)

	return effect, nil
end

-- 输入：拥有 Runtime 的玩家 Plot，以及当前怪兽的 Home CFrame。
-- 输出：升级特效是否成功进入播放；失败只返回 Reason，不抛出事务错误。
-- 内部算法：解析模板和运行时 VFX Folder，克隆后以 Home CFrame 对齐 Model Pivot。
function MonsterLevelUpVFXController.Play(plot: Model, homeCFrame: CFrame): Result
	if typeof(plot) ~= "Instance" or not plot:IsA("Model") then
		return result(false, "InvalidPlot")
	end
	if typeof(homeCFrame) ~= "CFrame" then
		return result(false, "InvalidHomeCFrame")
	end

	local template, templateReason = getTemplate()
	if not template then
		return result(false, templateReason or "LevelUpVFXTemplateUnavailable")
	end

	local runtimeVFXFolder, runtimeReason = getRuntimeVFXFolder(plot)
	if not runtimeVFXFolder then
		return result(false, runtimeReason or "RuntimeVFXUnavailable")
	end

	local called, effect, createReason = pcall(
		createEffect,
		template,
		runtimeVFXFolder,
		homeCFrame
	)
	if not called then
		return result(false, "LevelUpVFXCreateFailed")
	end
	if not effect then
		return result(false, createReason or "LevelUpVFXCreateFailed")
	end

	return result(true, nil)
end

return MonsterLevelUpVFXController
