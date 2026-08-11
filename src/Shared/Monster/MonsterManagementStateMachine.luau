--[[
	职责：描述无 GUI 依赖的怪兽管理面板交互状态。

	输入：当前 State，以及面板交互或余额变化 Event。
	输出：Accepted、Reason、新 State，以及最多一个待协调 Effect。
	内部算法：按显式状态转换表处理加载、金币逐级升级、钻石满级升级和进攻选择；余额变化只重算对应货币的可负担状态。

	不负责：Remote、扣款、怪兽状态写入、目标玩家选择、相机或 GUI 表现。
]]

local MonsterManagementStateMachine = {}

export type ActionStatus = {
	Allowed: boolean,
	Reason: string?,
	Cost: number,
	Affordable: boolean,
	TargetLevel: number?,
}

export type Snapshot = {
	SpawnPointId: string,
	Built: boolean,
	Level: number,
	MonsterKey: string?,
	MonsterState: string?,
	Balance: number,
	DiamondBalance: number,
	Upgrade: ActionStatus,
	DiamondUpgrade: ActionStatus,
	Attack: ActionStatus,
}

export type Mode = "Closed" | "Loading" | "Managing" | "Upgrading" | "SelectingAttack" | "Error"

export type State = {
	Mode: Mode,
	SpawnPointId: string?,
	Snapshot: Snapshot?,
	LastReason: string?,
}

export type Effect = {
	Kind: "QuerySnapshot"
		| "RequestUpgrade"
		| "RequestMaxUpgrade"
		| "OpenAttackSelection"
		| "CloseAttackSelection",
	SpawnPointId: string,
}

export type TransitionResult = {
	Accepted: boolean,
	Reason: string?,
	State: State,
	Effect: Effect?,
}

local function state(
	mode: Mode,
	spawnPointId: string?,
	snapshot: Snapshot?,
	lastReason: string?
): State
	return {
		Mode = mode,
		SpawnPointId = spawnPointId,
		Snapshot = snapshot,
		LastReason = lastReason,
	}
end

local function result(
	accepted: boolean,
	reason: string?,
	nextState: State,
	effect: Effect?
): TransitionResult
	return {
		Accepted = accepted,
		Reason = reason,
		State = nextState,
		Effect = effect,
	}
end

local function isActionStatus(value): boolean
	return type(value) == "table"
		and type(value.Allowed) == "boolean"
		and type(value.Cost) == "number"
		and value.Cost >= 0
		and value.Cost < math.huge
		and type(value.Affordable) == "boolean"
end

local function isSnapshot(value, spawnPointId: string): boolean
	return type(value) == "table"
		and value.SpawnPointId == spawnPointId
		and value.Built == true
		and type(value.Level) == "number"
		and value.Level >= 1
		and value.Level % 1 == 0
		and type(value.Balance) == "number"
		and type(value.DiamondBalance) == "number"
		and isActionStatus(value.Upgrade)
		and isActionStatus(value.DiamondUpgrade)
		and isActionStatus(value.Attack)
end

local function rejected(current: State, reason: string): TransitionResult
	return result(
		false,
		reason,
		state(current.Mode, current.SpawnPointId, current.Snapshot, reason),
		nil
	)
end

function MonsterManagementStateMachine.New(): State
	return state("Closed", nil, nil, nil)
end

-- 支持的 Event.Kind：Open、Close、SnapshotLoaded、SnapshotFailed、Retry、BalanceChanged、
-- ChooseUpgrade、ChooseDiamondUpgrade、UpgradeResolved、ChooseAttack、AttackCancelled、AttackAccepted、AttackUnavailable。
function MonsterManagementStateMachine.Apply(current: State, event): TransitionResult
	if type(current) ~= "table" or type(event) ~= "table" or type(event.Kind) ~= "string" then
		return rejected(MonsterManagementStateMachine.New(), "InvalidEvent")
	end

	if event.Kind == "Close" then
		local effect = if current.Mode == "SelectingAttack" and current.SpawnPointId
			then { Kind = "CloseAttackSelection", SpawnPointId = current.SpawnPointId }
			else nil
		return result(true, nil, MonsterManagementStateMachine.New(), effect)
	end

	if event.Kind == "Open" then
		if type(event.SpawnPointId) ~= "string" or event.SpawnPointId == "" then
			return rejected(current, "InvalidSpawnPointId")
		end
		if current.Mode == "SelectingAttack" then
			return rejected(current, "AttackSelectionActive")
		end
		if current.Mode == "Upgrading" then
			return rejected(current, "RequestBusy")
		end
		local nextState = state("Loading", event.SpawnPointId, nil, nil)
		return result(true, nil, nextState, {
			Kind = "QuerySnapshot",
			SpawnPointId = event.SpawnPointId,
		})
	end

	if event.Kind == "BalanceChanged" then
		local balance = event.Balance
		local currency = event.Currency or "Money"
		if type(balance) ~= "number" or balance ~= balance
			or balance < 0 or balance >= math.huge
			or (currency ~= "Money" and currency ~= "Diamond")
		then
			return rejected(current, "InvalidBalance")
		end
		if not current.Snapshot then
			return result(true, nil, current, nil)
		end

		local snapshot = table.clone(current.Snapshot)
		if currency == "Diamond" then
			snapshot.DiamondBalance = balance
			snapshot.DiamondUpgrade = table.clone(current.Snapshot.DiamondUpgrade)
			snapshot.DiamondUpgrade.Affordable = balance >= snapshot.DiamondUpgrade.Cost
		else
			snapshot.Balance = balance
			snapshot.Upgrade = table.clone(current.Snapshot.Upgrade)
			snapshot.Upgrade.Affordable = balance >= snapshot.Upgrade.Cost
		end
		snapshot.Attack = table.clone(current.Snapshot.Attack)
		local lastReason = if currency == "Diamond"
			and snapshot.DiamondUpgrade.Affordable
			and current.LastReason == "InsufficientDiamonds"
			then nil
			elseif currency == "Money"
			and snapshot.Upgrade.Affordable
			and current.LastReason == "InsufficientMoney"
			then nil
			else current.LastReason
		return result(
			true,
			nil,
			state(current.Mode, current.SpawnPointId, snapshot, lastReason),
			nil
		)
	end

	local spawnPointId = current.SpawnPointId
	if not spawnPointId then
		return rejected(current, "PanelClosed")
	end

	if event.Kind == "SnapshotLoaded" then
		if current.Mode ~= "Loading" then
			return rejected(current, "InvalidTransition")
		end
		if not isSnapshot(event.Snapshot, spawnPointId) then
			return rejected(current, "InvalidSnapshot")
		end
		return result(true, nil, state("Managing", spawnPointId, event.Snapshot, nil), nil)
	end

	if event.Kind == "SnapshotFailed" then
		if current.Mode ~= "Loading" then
			return rejected(current, "InvalidTransition")
		end
		local reason = if type(event.Reason) == "string" and event.Reason ~= ""
			then event.Reason
			else "SnapshotUnavailable"
		return result(true, nil, state("Error", spawnPointId, nil, reason), nil)
	end

	if event.Kind == "Retry" then
		if current.Mode ~= "Error" and current.Mode ~= "Managing" then
			return rejected(current, "InvalidTransition")
		end
		return result(true, nil, state("Loading", spawnPointId, current.Snapshot, nil), {
			Kind = "QuerySnapshot",
			SpawnPointId = spawnPointId,
		})
	end

	if event.Kind == "ChooseDiamondUpgrade" then
		if current.Mode ~= "Managing" or not current.Snapshot then
			return rejected(current, "InvalidTransition")
		end
		local diamondUpgrade = current.Snapshot.DiamondUpgrade
		if not diamondUpgrade.Allowed then
			return rejected(current, diamondUpgrade.Reason or "MaxUpgradeLocked")
		end
		if not diamondUpgrade.Affordable then
			return rejected(current, "InsufficientDiamonds")
		end
		return result(true, nil, state("Upgrading", spawnPointId, current.Snapshot, nil), {
			Kind = "RequestMaxUpgrade",
			SpawnPointId = spawnPointId,
		})
	end

	if event.Kind == "ChooseUpgrade" then
		if current.Mode ~= "Managing" or not current.Snapshot then
			return rejected(current, "InvalidTransition")
		end
		local upgrade = current.Snapshot.Upgrade
		if not upgrade.Allowed then
			return rejected(current, upgrade.Reason or "UpgradeLocked")
		end
		if not upgrade.Affordable then
			return rejected(current, "InsufficientMoney")
		end
		return result(true, nil, state("Upgrading", spawnPointId, current.Snapshot, nil), {
			Kind = "RequestUpgrade",
			SpawnPointId = spawnPointId,
		})
	end

	if event.Kind == "UpgradeResolved" then
		if current.Mode ~= "Upgrading" then
			return rejected(current, "InvalidTransition")
		end
		if event.Snapshot ~= nil and isSnapshot(event.Snapshot, spawnPointId) then
			local reason = if event.Succeeded == true
				then nil
				else event.Reason or "UpgradeRejected"
			return result(
				true,
				nil,
				state("Managing", spawnPointId, event.Snapshot, reason),
				nil
			)
		end
		local reason = if type(event.Reason) == "string" and event.Reason ~= ""
			then event.Reason
			else "UpgradeResponseUnavailable"
		return result(true, nil, state("Loading", spawnPointId, current.Snapshot, reason), {
			Kind = "QuerySnapshot",
			SpawnPointId = spawnPointId,
		})
	end

	if event.Kind == "ChooseAttack" then
		if current.Mode ~= "Managing" or not current.Snapshot then
			return rejected(current, "InvalidTransition")
		end
		local attack = current.Snapshot.Attack
		if not attack.Allowed then
			return rejected(current, attack.Reason or "AttackLocked")
		end
		return result(true, nil, state("SelectingAttack", spawnPointId, current.Snapshot, nil), {
			Kind = "OpenAttackSelection",
			SpawnPointId = spawnPointId,
		})
	end

	if event.Kind == "AttackCancelled" or event.Kind == "AttackUnavailable" then
		if current.Mode ~= "SelectingAttack" then
			return rejected(current, "InvalidTransition")
		end
		local reason = if event.Kind == "AttackUnavailable"
			then event.Reason or "AttackSelectionUnavailable"
			else nil
		return result(true, nil, state("Managing", spawnPointId, current.Snapshot, reason), nil)
	end

	if event.Kind == "AttackAccepted" then
		if current.Mode ~= "SelectingAttack" then
			return rejected(current, "InvalidTransition")
		end
		return result(true, nil, MonsterManagementStateMachine.New(), nil)
	end

	return rejected(current, "UnknownEvent")
end

return MonsterManagementStateMachine
