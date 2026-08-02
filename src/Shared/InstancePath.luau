local InstancePath = {}

local WAIT_TIMEOUT = 5 -- 等待时间

local function getSegments(path: string): { string }
	local segments = {}

	for segment in string.gmatch(path, "[^/]+") do
		if #segments == 0 and segment == "game" then
			continue
		end

		table.insert(segments, segment)
	end

	return segments
end

function InstancePath.Get(path: string): Instance
	local current: Instance = game

	for _, segment in getSegments(path) do
		local child = current:FindFirstChild(segment)
		assert(child, string.format("找不到 Instance：%s", path))
		current = child
	end

	return current
end

function InstancePath.Wait(path: string): Instance
	local current: Instance = game
	local deadline = os.clock() + WAIT_TIMEOUT

	for _, segment in getSegments(path) do
		local child = current:FindFirstChild(segment)

		if not child then
			local remainingTime = math.max(0, deadline - os.clock())
			child = current:WaitForChild(segment, remainingTime)
		end

		assert(child, string.format("等待 Instance 超过 %d 秒：%s", WAIT_TIMEOUT, path))
		current = child
	end

	return current
end

return InstancePath
