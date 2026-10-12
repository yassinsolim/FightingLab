--!strict
-- Minimal unit-test runner for FightingLab. Usage: require(RunUnitTest)(filter?, timeoutSeconds?)
type Expect = {
	equal: (actual: any, expected: any, msg: string?) -> (),
	truthy: (value: any, msg: string?) -> (),
	falsy: (value: any, msg: string?) -> (),
	near: (actual: number, expected: number, eps: number?, msg: string?) -> (),
	throws: (fn: () -> (), msg: string?) -> (),
}

export type T = {
	test: (name: string, fn: () -> ()) -> (),
	expect: Expect,
}

local function fail(msg: string?, detail: string)
	error((if msg then msg .. ": " else "") .. detail, 3)
end

local expect: Expect = {
	equal = function(actual: any, expected: any, msg: string?)
		if actual ~= expected then
			fail(msg, string.format("expected %s, got %s", tostring(expected), tostring(actual)))
		end
	end,
	truthy = function(value: any, msg: string?)
		if not value then
			fail(msg, "expected truthy, got " .. tostring(value))
		end
	end,
	falsy = function(value: any, msg: string?)
		if value then
			fail(msg, "expected falsy, got " .. tostring(value))
		end
	end,
	near = function(actual: number, expected: number, eps: number?, msg: string?)
		if math.abs(actual - expected) > (eps or 1e-3) then
			fail(msg, string.format("expected %.4f, got %.4f", expected, actual))
		end
	end,
	throws = function(fn: () -> (), msg: string?)
		if pcall(fn) then
			fail(msg, "expected an error")
		end
	end,
}

return function(filter: string?, timeout: number?): (number, number)
	local cases = script.Parent:WaitForChild("Cases")
	local limit = timeout or 5
	local run, passed = 0, 0
	for _, case in cases:GetChildren() do
		if not case:IsA("ModuleScript") then
			continue
		end
		local suite = require(case)
		local tests: { { name: string, fn: () -> () } } = {}
		suite({
			test = function(name: string, fn: () -> ())
				table.insert(tests, { name = case.Name .. " > " .. name, fn = fn })
			end,
			expect = expect,
		})
		for _, entry in tests do
			if filter and not string.find(entry.name, filter, 1, true) then
				continue
			end
			run += 1
			local started = os.clock()
			local ok, err = xpcall(entry.fn, debug.traceback)
			if os.clock() - started > limit then
				print("[TIMEOUT] " .. entry.name)
			elseif ok then
				passed += 1
				print("[PASS] " .. entry.name)
			else
				print("[FAIL] " .. entry.name .. "\n" .. tostring(err))
			end
		end
	end
	print(string.format("[SUMMARY] %d run, %d passed, %d failed", run, passed, run - passed))
	return run, passed
end
