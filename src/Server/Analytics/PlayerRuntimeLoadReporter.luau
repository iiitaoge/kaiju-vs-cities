--[[
	职责：把各运行时模块的首次加载结果发布给观察者。
	输入：Report 接收 Player、固定 Stage、Succeeded 和稳定 Reason。
	输出：Connect 返回连接；每次 Report 同步发布一条不可变事实。
	内部算法：通过模块私有 BindableEvent 解耦加载模块与分析协调器。
	不负责：保存阶段状态、判断整体 Ready、发送任何分析事件或重试加载。
]]

local PlayerRuntimeLoadReporter = {}

export type Stage = "Plot" | "City" | "Monster" | "Character"

local changed = Instance.new("BindableEvent")

function PlayerRuntimeLoadReporter.Report(
	player: Player,
	stage: Stage,
	succeeded: boolean,
	reason: string?
)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	assert(
		stage == "Plot" or stage == "City" or stage == "Monster" or stage == "Character",
		"stage 无效"
	)
	assert(type(succeeded) == "boolean", "succeeded 必须是 boolean")
	assert(reason == nil or type(reason) == "string", "reason 必须是 string 或 nil")
	changed:Fire(player, stage, succeeded, reason)
end

function PlayerRuntimeLoadReporter.Connect(callback): RBXScriptConnection
	assert(type(callback) == "function", "callback 必须是 function")
	return changed.Event:Connect(callback)
end

return PlayerRuntimeLoadReporter
