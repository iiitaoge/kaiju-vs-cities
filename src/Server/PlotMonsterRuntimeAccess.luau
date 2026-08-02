--[[
	输入：已经通过场景合同验证的玩家 Plot。
	输出：Plot/Runtime/Monsters Folder，或稳定失败原因。
	内部算法：只解析并按需创建怪兽运行时目录。
	不负责：查找玩家 Plot、生成模型、维护怪兽状态或清理其他 Runtime 内容。
]]

local PlotMonsterRuntimeAccess = {}

local ROOT_NAME = "Monsters"

function PlotMonsterRuntimeAccess.GetOrCreate(plot: Model): (Folder?, string?)
	assert(plot:IsA("Model"), "plot 必须是 Model")
	local runtime = plot:FindFirstChild("Runtime")
	if not runtime or not runtime:IsA("Folder") then
		return nil, "MissingPlotRuntime"
	end

	local existing = runtime:FindFirstChild(ROOT_NAME)
	if existing then
		if not existing:IsA("Folder") then
			return nil, "InvalidMonsterRuntime"
		end
		return existing, nil
	end

	local folder = Instance.new("Folder")
	folder.Name = ROOT_NAME
	folder.Parent = runtime
	return folder, nil
end

function PlotMonsterRuntimeAccess.Get(plot: Model): Folder?
	assert(plot:IsA("Model"), "plot 必须是 Model")
	local runtime = plot:FindFirstChild("Runtime")
	local monsters = runtime and runtime:FindFirstChild(ROOT_NAME)
	return if monsters and monsters:IsA("Folder") then monsters else nil
end

return PlotMonsterRuntimeAccess
