local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = require(
	ReplicatedStorage.Shared.Economy.IncomeGainPresentationProtocol
)

local IncomeGainPresentationProtocolSpec = {}

local function expectValid(command)
	local valid, reason = Protocol.Validate(command)
	assert(valid, "IncomeGainPresentationProtocolSpec: " .. (reason or "命令无效"))
end

local function expectInvalid(command, expectedReason: string)
	local valid, reason = Protocol.Validate(command)
	assert(
		not valid and reason == expectedReason,
		string.format(
			"IncomeGainPresentationProtocolSpec: expected %s, actual %s",
			expectedReason,
			tostring(reason)
		)
	)
end

function IncomeGainPresentationProtocolSpec.Run(): boolean
	expectValid({
		Kind = Protocol.Kinds.Automatic,
		Entries = {
			{ HouseId = "R1-H1", Amount = 25 },
			{ HouseId = "R1-H2", Amount = 12.5 },
		},
	})
	expectValid({
		Kind = Protocol.Kinds.Touch,
		Entries = {
			{ HouseId = "R1-H1", Amount = 100 },
		},
	})
	expectInvalid({ Kind = "Other", Entries = {} }, "InvalidKind")
	expectInvalid({ Kind = Protocol.Kinds.Automatic, Entries = {} }, "InvalidEntries")
	expectInvalid({
		Kind = Protocol.Kinds.Touch,
		Entries = {
			{ HouseId = "R1-H1", Amount = 1 },
			{ HouseId = "R1-H2", Amount = 1 },
		},
	}, "InvalidTouchEntryCount")
	expectInvalid({
		Kind = Protocol.Kinds.Automatic,
		Entries = {
			{ HouseId = "R1-H1", Amount = 1 },
			{ HouseId = "R1-H1", Amount = 2 },
		},
	}, "DuplicateHouseId")
	expectInvalid({
		Kind = Protocol.Kinds.Automatic,
		Entries = {
			{ HouseId = "R1-H1", Amount = 0 },
		},
	}, "InvalidAmount")
	return true
end

return IncomeGainPresentationProtocolSpec
