local config = {
	IntervalSeconds = 1,
}

assert(config.IntervalSeconds > 0, "自动收入间隔必须为正数")
return table.freeze(config)
