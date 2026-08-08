--[[
	职责：保存客户端当前正在进入部署流程的载具实例。
	输入：Begin 接收 VehicleInstanceId；Clear 清除当前部署载具。
	输出：Get 返回当前部署状态，供 Map/Nest 选择 UI 后续读取。
	内部算法：同一时刻只保留一个待部署载具实例 ID；不执行派遣、不访问服务器、不修改载具拥有关系。
]]

local VehicleDeploymentState = {}

export type Snapshot = {
	Active: boolean,
	VehicleInstanceId: string?,
}

local vehicleInstanceId: string? = nil

function VehicleDeploymentState.Begin(nextVehicleInstanceId: string)
	assert(
		type(nextVehicleInstanceId) == "string" and nextVehicleInstanceId ~= "",
		"VehicleInstanceId 必须是非空字符串"
	)
	vehicleInstanceId = nextVehicleInstanceId
end

function VehicleDeploymentState.Clear()
	vehicleInstanceId = nil
end

function VehicleDeploymentState.Get(): Snapshot
	return {
		Active = vehicleInstanceId ~= nil,
		VehicleInstanceId = vehicleInstanceId,
	}
end

return VehicleDeploymentState
