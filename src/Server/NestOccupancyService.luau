--[[
	职责：维护九个 Nest 的单驻留者和挑战队列。
	输入：NestId，以及驻留/排队的载具派遣记录。
	输出：当前驻留者、行驶中的载具、排队顺序和占用状态。
	内部算法：每个 Nest 一个 Occupant 槽位和一个 Traveling 预留槽位；其余载具 FIFO 排队；不执行战斗或奖励。
	不负责：载具模型、战斗、钻石、玩家拥有关系或存档。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NestCatalog = require(ReplicatedStorage.Shared.Nest.NestCatalog)

local NestOccupancyService = {}

export type NestState = {
	NestId: string,
	Occupant: any?,
	Traveling: any?,
	Queue: { any },
	BattleActive: boolean,
}

local states: { [string]: NestState } = {}
for _, definition in NestCatalog.GetAll() do
	states[definition.NestId] = {
		NestId = definition.NestId,
		Occupant = nil,
		Traveling = nil,
		Queue = {},
		BattleActive = false,
	}
end

local function getState(nestId: string): NestState
	assert(NestCatalog.Get(nestId), "未知 NestId：" .. tostring(nestId))
	return states[nestId]
end

function NestOccupancyService.Get(nestId: string): NestState
	return getState(nestId)
end

function NestOccupancyService.SetOccupant(nestId: string, record: any)
	local state = getState(nestId)
	assert(state.Occupant == nil, "Nest 已有驻留载具")
	state.Occupant = record
end

function NestOccupancyService.ClearOccupant(nestId: string, expected: any?): boolean
	local state = getState(nestId)
	if expected and state.Occupant ~= expected then
		return false
	end
	state.Occupant = nil
	return true
end

function NestOccupancyService.SetTraveling(nestId: string, record: any)
	local state = getState(nestId)
	assert(state.Traveling == nil, "Nest 已有行驶中的载具")
	state.Traveling = record
end

function NestOccupancyService.ClearTraveling(nestId: string, expected: any?): boolean
	local state = getState(nestId)
	if expected and state.Traveling ~= expected then
		return false
	end
	state.Traveling = nil
	return true
end

function NestOccupancyService.Enqueue(nestId: string, record: any)
	local state = getState(nestId)
	table.insert(state.Queue, record)
end

function NestOccupancyService.EnqueueFront(nestId: string, record: any)
	local state = getState(nestId)
	table.insert(state.Queue, 1, record)
end

function NestOccupancyService.Dequeue(nestId: string): any?
	local state = getState(nestId)
	return table.remove(state.Queue, 1)
end

function NestOccupancyService.RemoveFromQueue(nestId: string, record: any): boolean
	local state = getState(nestId)
	for index, queued in state.Queue do
		if queued == record then
			table.remove(state.Queue, index)
			return true
		end
	end
	return false
end

function NestOccupancyService.ContainsPlayer(nestId: string, player: Player): boolean
	local state = getState(nestId)
	if state.Occupant and state.Occupant.Player == player then
		return true
	end
	if state.Traveling and state.Traveling.Player == player then
		return true
	end
	for _, record in state.Queue do
		if record.Player == player then
			return true
		end
	end
	return false
end

function NestOccupancyService.GetQueuePosition(nestId: string, record: any): number?
	local state = getState(nestId)
	for index, queued in state.Queue do
		if queued == record then
			return index
		end
	end
	return nil
end

function NestOccupancyService.SetBattleActive(nestId: string, active: boolean)
	getState(nestId).BattleActive = active
end

function NestOccupancyService.GetAll(): { NestState }
	local result = {}
	for _, definition in NestCatalog.GetAll() do
		table.insert(result, states[definition.NestId])
	end
	return result
end

return NestOccupancyService
