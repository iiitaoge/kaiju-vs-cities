--[[
	职责：定义服务器权威房屋完整复制到客户端所需的最小元数据。
	输入：GetExpectedBasePartCount 接收运行时房屋 Model。
	输出：合法时返回服务器写入的预期 BasePart 数量，否则返回 nil。
	内部算法：读取并验证 BuildingExpectedBasePartCount Attribute。
	不负责：等待复制、读取房屋身份、创建 UI、触碰或修改实例。
]]

local RuntimeBuildingReplicationProtocol = {}

RuntimeBuildingReplicationProtocol.ExpectedBasePartCountAttributeName =
	"BuildingExpectedBasePartCount"

function RuntimeBuildingReplicationProtocol.GetExpectedBasePartCount(
	model: Model
): number?
	local value = model:GetAttribute(
		RuntimeBuildingReplicationProtocol.ExpectedBasePartCountAttributeName
	)
	return if type(value) == "number"
		and value == value
		and value < math.huge
		and value >= 1
		and value % 1 == 0
		then value
		else nil
end

return table.freeze(RuntimeBuildingReplicationProtocol)
