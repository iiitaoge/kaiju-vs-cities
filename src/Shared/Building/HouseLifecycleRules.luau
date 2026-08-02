--[[
	职责：描述单栋房屋生命周期的纯状态转换。
	输入：当前 LifeState 和 EventKind。
	输出：Accepted、Reason、PreviousState、NewState。
	内部算法：只查询显式转换表；不读取 Instance、时间、配置或玩家数据。
]]

local HouseLifecycleRules = {}

export type LifeState = "Unbuilt" | "Alive" | "Destroyed" | "Rebuilding"
export type EventKind =
	"Build"
	| "Destroy"
	| "RollbackDestroy"
	| "BeginRebuild"
	| "AbortRebuild"
	| "CompleteRebuild"

export type TransitionResult = {
	Accepted: boolean,
	Reason: string?,
	PreviousState: LifeState?,
	NewState: LifeState?,
}

local transitions = {
	Unbuilt = {
		Build = "Alive",
	},
	Alive = {
		Destroy = "Destroyed",
	},
	Destroyed = {
		RollbackDestroy = "Alive",
		BeginRebuild = "Rebuilding",
	},
	Rebuilding = {
		AbortRebuild = "Destroyed",
		CompleteRebuild = "Alive",
	},
}

local function isLifeState(value): boolean
	return value == "Unbuilt"
		or value == "Alive"
		or value == "Destroyed"
		or value == "Rebuilding"
end

function HouseLifecycleRules.Apply(
	currentState: LifeState,
	eventKind: EventKind
): TransitionResult
	if not isLifeState(currentState) then
		return {
			Accepted = false,
			Reason = "InvalidLifeState",
			PreviousState = nil,
			NewState = nil,
		}
	end
	if type(eventKind) ~= "string" then
		return {
			Accepted = false,
			Reason = "InvalidEvent",
			PreviousState = currentState,
			NewState = currentState,
		}
	end

	local nextState = transitions[currentState][eventKind]
	if not nextState then
		return {
			Accepted = false,
			Reason = "InvalidTransition",
			PreviousState = currentState,
			NewState = currentState,
		}
	end
	return {
		Accepted = true,
		Reason = nil,
		PreviousState = currentState,
		NewState = nextState,
	}
end

return HouseLifecycleRules
