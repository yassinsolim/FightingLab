--!strict
local RS = game:GetService("ReplicatedStorage")
return function(t)
	local folder = RS.FightingLab.Client
	local expected = {
		ClientTypes = {},
		InputController = { "init", "setGameplayEnabled", "isGameplayEnabled", "releaseAll", "setTouchControlsVisible", "bindMenu", "practice", "bindPractice" },
		HudController = { "init", "setVisible", "onSnapshot", "onEvent", "update", "setFighterInfo", "announce", "setViewSlot", "toggleGuide", "setGuide", "guideVisible", "guideMode" },
		CameraDirector = { "init", "setMode", "impulse", "update", "getFocus", "beginFight", "endFight" },
		-- getModel/getRoot/getLimbPart return nil while no fight is running (lobby mode).
		CharacterPresenter = { "init", "listCharacters", "setCharacters", "update", "getModel", "getRoot", "getLimbPart", "setFlash", "prewarm", "acquirePreview", "releasePreview", "endFight", "setOrigin", "posePreview" },
		MotionLibrary = {},
		MotionPlayer = { "collectRig", "sample", "apply", "reset", "namedPose", "warmClips", "throwTime" },
		-- Nested modules use dotted paths below Client.
		["Motion.States"] = { "reactionKey", "floorImpact", "newImpactTracker", "fallFrames" },
		["Motion.ClipLibrary"] = { "decode", "get", "has", "find", "forMove", "forThrow", "list", "sourceIds" },
		["Motion.ClipPlayer"] = { "sample", "moveTime", "progressTime" },
		EffectsController = { "init", "onEvent", "onPhase", "update" },
		AudioController = { "init", "play", "playMusic", "onEvent", "onPhase" },
		StageController = { "init", "listStages", "load", "current", "update", "setArena", "clearArena" },
		SelectScene = { "init", "showCharacter", "showStage", "showVS", "hide", "update", "isActive", "debugInstanceCount" },
		CreditsScreen = { "render", "scroll", "hasData" },
		FrontEnd = { "init", "start", "onSnapshot", "update" },
		FightSession = { "init", "state", "info", "startPractice", "practiceCommand", "leave", "isFightActive" },
		-- Hides newly added characters on each client until their layered clothing and assets have loaded.
		AvatarGate = { "init", "start", "track", "gateCharacter", "isGated", "step" },
		SpectatorPresenter = { "init", "onSnapshot", "update", "clear" },
		LobbyUI = { "mount", "start", "stop", "active", "boards", "leaderboard", "update", "onSnapshot", "disableBackpack", "worldPrompts", "richKeys" },
		UIHelpers = { "holdPlayerList" },
		StationBoards = { "viewModel", "build", "render", "buildPadTag", "renderPadTag", "bind", "start" },
		Leaderboard = { "sortEntries", "entryFor", "collect", "build", "render", "start" },
		FighterSelect = { "mount", "acquireModel", "newViewport", "frame", "templatesReady", "awaitTemplates" },
	}
	t.test("modules require without side effects and expose contract API", function()
		local beforeWorkspace = #workspace:GetChildren()
		for name, api in expected do
			local module: Instance? = folder
			for part in string.gmatch(name, "[^%.]+") do
				module = if module then module:FindFirstChild(part) else nil
			end
			t.expect.truthy(module and module:IsA("ModuleScript"), name .. " ModuleScript exists")
			local result = require(module)
			for _, fn in api do t.expect.equal(typeof(result[fn]), "function", name .. "." .. fn) end
		end
		t.expect.equal(#workspace:GetChildren(), beforeWorkspace, "require must not create workspace instances")
	end)
	t.test("character and stage registries include baseline ids", function()
		local chars = require(folder.CharacterPresenter).listCharacters()
		t.expect.equal(chars[1].id, "Kael")
		t.expect.equal(chars[2].id, "Sierra")
		local stages = require(folder.StageController).listStages()
		local found = false
		for _, stage in stages do if stage.id == "TrainingBay" then found = true end end
		t.expect.truthy(found, "TrainingBay stage is registered")
	end)
end
