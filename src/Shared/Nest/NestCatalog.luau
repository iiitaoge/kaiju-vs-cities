--[[
	职责：保存九个公共 Nest 的稳定身份和基础钻石产出配置。
	输入：nestId。
	输出：对应的只读 Nest 定义；GetAll 返回 Nest0 到 Nest8。
	内部算法：以 NestId 建立索引，不查找 Workspace、不保存占用状态。
	不负责：载具、占用、战斗或奖励写入。
]]

local NestCatalog = {}

export type NestDefinition = {
	NestId: string,
	Name: string,
	BaseIntervalSeconds: number,
	BaseDiamonds: number,
}

local definitions: { NestDefinition } = table.freeze({
	table.freeze({ NestId = "Nest0", Name = "Nest0", BaseIntervalSeconds = 60, BaseDiamonds = 20 }),
	table.freeze({ NestId = "Nest1", Name = "Nest1", BaseIntervalSeconds = 60, BaseDiamonds = 5 }),
	table.freeze({ NestId = "Nest2", Name = "Nest2", BaseIntervalSeconds = 60, BaseDiamonds = 5 }),
	table.freeze({ NestId = "Nest3", Name = "Nest3", BaseIntervalSeconds = 60, BaseDiamonds = 5 }),
	table.freeze({ NestId = "Nest4", Name = "Nest4", BaseIntervalSeconds = 60, BaseDiamonds = 5 }),
	table.freeze({ NestId = "Nest5", Name = "Nest5", BaseIntervalSeconds = 60, BaseDiamonds = 5 }),
	table.freeze({ NestId = "Nest6", Name = "Nest6", BaseIntervalSeconds = 60, BaseDiamonds = 5 }),
	table.freeze({ NestId = "Nest7", Name = "Nest7", BaseIntervalSeconds = 60, BaseDiamonds = 5 }),
	table.freeze({ NestId = "Nest8", Name = "Nest8", BaseIntervalSeconds = 60, BaseDiamonds = 5 }),
})

local byId = {}
for _, definition in definitions do
	byId[definition.NestId] = definition
end
table.freeze(byId)

function NestCatalog.Get(nestId: string): NestDefinition?
	if type(nestId) ~= "string" then
		return nil
	end
	return byId[nestId]
end

function NestCatalog.GetAll(): { NestDefinition }
	return definitions
end

return table.freeze({
	WorldRootName = "Nests",
	Get = NestCatalog.Get,
	GetAll = NestCatalog.GetAll,
})
