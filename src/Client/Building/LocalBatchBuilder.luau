local LocalModelBuilder = require(script.Parent.LocalModelBuilder)

local LocalBatchBuilder = {}

function LocalBatchBuilder.Build(items): { Model }
	local results = table.create(#items)
	local errors = {}
	local remaining = #items

	for index, item in ipairs(items) do
		task.spawn(function()
			local success, result = pcall(
				LocalModelBuilder.Build,
				item.Template,
				item.TargetCFrame
			)

			if success then
				results[index] = result
			else
				table.insert(errors, tostring(result))
			end

			remaining -= 1
		end)
	end

	while remaining > 0 do
		task.wait()
	end

	assert(#errors == 0, "批量建造失败：\n" .. table.concat(errors, "\n"))
	return results
end

return LocalBatchBuilder
