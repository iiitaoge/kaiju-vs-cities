--[[
	职责：等待一个服务器权威房屋在本客户端达到可安全绑定状态。
	输入：运行时 Model、预期 OwnerUserId、可选超时秒数。
	输出：成功返回已验证身份和锚点 BasePart；失败返回稳定原因。
	内部算法：逐帧等待身份、复制协议和全部预期 BasePart 到齐，并在删除、异主或超时时退出。
	不负责：创建 UI、触碰触发器、保存句柄或修改房屋。
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RuntimeBuildingIdentity = require(
	ReplicatedStorage.Shared.Building.RuntimeBuildingIdentity
)
local RuntimeBuildingReplicationProtocol = require(
	ReplicatedStorage.Shared.Building.RuntimeBuildingReplicationProtocol
)

local LocalRuntimeBuildingReadiness = {}

export type ReadyBuilding = {
	Identity: RuntimeBuildingIdentity.Identity,
	AnchorPart: BasePart,
}

local DEFAULT_TIMEOUT_SECONDS = 10

local function findAnchorPart(model: Model): BasePart?
	local primaryPart = model.PrimaryPart
	if primaryPart and primaryPart:IsDescendantOf(model) then
		return primaryPart
	end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function countBaseParts(model: Model): number
	local count = 0
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			count += 1
		end
	end
	return count
end

function LocalRuntimeBuildingReadiness.Wait(
	model: Model,
	expectedOwnerUserId: number,
	timeoutSeconds: number?
): (ReadyBuilding?, string?)
	assert(typeof(model) == "Instance" and model:IsA("Model"), "model 必须是 Model")
	assert(
		type(expectedOwnerUserId) == "number"
			and expectedOwnerUserId == expectedOwnerUserId
			and expectedOwnerUserId % 1 == 0
			and expectedOwnerUserId ~= 0,
		"expectedOwnerUserId 必须是非零整数"
	)
	local timeout = timeoutSeconds or DEFAULT_TIMEOUT_SECONDS
	assert(
		type(timeout) == "number"
			and timeout == timeout
			and timeout < math.huge
			and timeout > 0,
		"timeoutSeconds 必须是有限正数"
	)

	local deadline = os.clock() + timeout
	while model.Parent do
		local identity, identityReason = RuntimeBuildingIdentity.Read(model)
		if identity and identity.OwnerUserId ~= expectedOwnerUserId then
			return nil, "OwnerMismatch"
		end

		local expectedBasePartCount =
			RuntimeBuildingReplicationProtocol.GetExpectedBasePartCount(model)
		local anchorPart = findAnchorPart(model)
		if identity
			and expectedBasePartCount
			and anchorPart
			and countBaseParts(model) >= expectedBasePartCount
		then
			return {
				Identity = identity,
				AnchorPart = anchorPart,
			}, nil
		end

		if os.clock() >= deadline then
			return nil, "ReplicationTimeout:" .. (identityReason or "BuildingPartsUnavailable")
		end
		RunService.Heartbeat:Wait()
	end

	return nil, "ModelRemoved"
end

return LocalRuntimeBuildingReadiness
