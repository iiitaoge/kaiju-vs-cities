local SpawnPointMonsterBinding = {}

local ID_ATTRIBUTE = "MonsterSpawnPointId"
local KEY_ATTRIBUTE = "MonsterKey"

export type BindResult = {
	Succeeded: boolean,
	Reason: string?,
	Created: boolean,
}

-- 输入：服务器出生点实例、稳定 ID 和当前怪兽类型。
-- 输出：是否建立一出生点一怪兽绑定，以及本次是否首次写入。
-- 内部算法：允许相同绑定幂等执行，拒绝覆盖属于其他稳定 ID 的出生点。
function SpawnPointMonsterBinding.Bind(
	spawnPoint: BasePart,
	spawnPointId: string,
	monsterKey: string
): BindResult
	assert(spawnPoint:IsA("BasePart"), "spawnPoint 必须是 BasePart")
	assert(type(spawnPointId) == "string" and spawnPointId ~= "", "spawnPointId 无效")
	assert(type(monsterKey) == "string" and monsterKey ~= "", "monsterKey 无效")

	local currentId = spawnPoint:GetAttribute(ID_ATTRIBUTE)
	if currentId ~= nil and currentId ~= spawnPointId then
		return {
			Succeeded = false,
			Reason = "SpawnPointBoundToAnotherMonster",
			Created = false,
		}
	end
	local created = currentId == nil
	spawnPoint:SetAttribute(ID_ATTRIBUTE, spawnPointId)
	spawnPoint:SetAttribute(KEY_ATTRIBUTE, monsterKey)
	return {
		Succeeded = true,
		Reason = nil,
		Created = created,
	}
end

-- 输入：已绑定出生点、预期稳定 ID 和升级后的怪兽类型。
-- 输出：是否更新 MonsterKey。
-- 内部算法：先验证稳定 ID，绝不通过升级改变出生点身份。
function SpawnPointMonsterBinding.SetMonsterKey(
	spawnPoint: BasePart,
	spawnPointId: string,
	monsterKey: string
): boolean
	if spawnPoint:GetAttribute(ID_ATTRIBUTE) ~= spawnPointId then
		return false
	end
	if type(monsterKey) ~= "string" or monsterKey == "" then
		return false
	end
	spawnPoint:SetAttribute(KEY_ATTRIBUTE, monsterKey)
	return true
end

function SpawnPointMonsterBinding.Unbind(spawnPoint: BasePart, spawnPointId: string): boolean
	if spawnPoint:GetAttribute(ID_ATTRIBUTE) ~= spawnPointId then
		return false
	end
	spawnPoint:SetAttribute(ID_ATTRIBUTE, nil)
	spawnPoint:SetAttribute(KEY_ATTRIBUTE, nil)
	return true
end

function SpawnPointMonsterBinding.Get(spawnPoint: BasePart)
	return {
		SpawnPointId = spawnPoint:GetAttribute(ID_ATTRIBUTE),
		MonsterKey = spawnPoint:GetAttribute(KEY_ATTRIBUTE),
	}
end

return SpawnPointMonsterBinding
