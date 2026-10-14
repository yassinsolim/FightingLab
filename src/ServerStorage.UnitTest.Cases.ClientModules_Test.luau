--!strict
local RS = game:GetService("ReplicatedStorage")
return function(t)
	local folder = RS.FightingLab.Client
	local expected = {
		ClientTypes = {},
		InputController = { "init", "setGameplayEnabled", "isGameplayEnabled", "releaseAll", "setTouchControlsVisible", "bindMenu", "practice", "bindPractice" },
		HudController = { "init", "setVisible", "onSnapshot", "onEvent", "update", "setFighterInfo", "announce", "setViewSlot", "toggleGuide", "setGuide", "guideVisible", "guideMode", "ultimateKey", "statusFor", "stanceName", "recordInput", "inputLog" },
		-- Round 6 (look): the HUD's drawing kit and its big moments (round intro, K.O., winner, Ultimate card).
		HudKit = { "capGradient", "cap", "slab", "paintSlab", "chip", "healthBar", "stepTrail", "fillColors" },
		HudBanners = { "roundIntroText", "roundEndText", "isPerfect", "ultimateName", "build", "show", "flash", "setCinematic", "showUltimate", "showWinner", "hideAll" },
		-- Round 6 (look): per-arena moods for the fighting client.
		LightingProfile = { "apply", "clearStaleLighting", "neutraliseStagePresets", "profileFor", "applyArena", "restore", "activeArena", "setFocus", "rigFor" },
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
		StageController = { "init", "listStages", "load", "current", "update", "setArena", "clearArena", "occluderRelevant", "rigFrames" },
		SelectScene = { "init", "showCharacter", "showStage", "showVS", "hide", "update", "isActive", "debugInstanceCount" },
		CreditsScreen = { "render", "scroll", "hasData" },
		FrontEnd = { "init", "start", "onSnapshot", "update" },
		FightSession = { "init", "state", "info", "startPractice", "practiceCommand", "leave", "isFightActive", "quickPlay", "cancelQueue", "travel" },
		-- Hides newly added characters on each client until their layered clothing and assets have loaded.
		AvatarGate = { "init", "start", "track", "trackPreview", "gateCharacter", "isGated", "step", "decide", "contentReady" },
		-- Round 5: the bare-frame / pose-pop detector (QA recorder + the reveal check every preview gate uses).
		FlashDetector = { "inventory", "contentIds", "allContent", "pendingTextures", "check", "fetchStatus", "templateInventory", "poseOf", "maxJointDelta", "newRecorder", "observe", "start", "summary" },
		-- Round 5: lobby sprint (Controls.lobby.sprint), driven by LobbyUI.
		LobbySprint = { "new", "bindInput", "stepAlpha", "speedFor", "fovFor" },
		-- Round 6: the lobby camera framed over the player's shoulder after a fight, a practice or a quick travel.
		LobbyCamera = { "new", "frameBehind", "markerAt", "worldMarkers", "facingOf" },
		SpectatorPresenter = { "init", "onSnapshot", "update", "clear" },
		LobbyUI = { "mount", "start", "stop", "active", "boards", "leaderboard", "update", "onSnapshot", "disableBackpack", "worldPrompts", "richKeys" },
		-- Round 7: the PLAY flow (who -> map -> fight, practice, searching) behind the bar's PLAY button.
		PlayFlow = { "new", "cards", "act", "rejected", "arenaModel", "arenaLook", "collectArenas", "previewFrame", "previewFov", "lobbyCameraType", "mount" },
		-- Round 7: practice tools (input display, frame advantage, combo trials on ComboTrial).
		PracticeTools = { "inputRows", "readout", "formatValue", "comboTrialModule", "mount" },
		-- Round 5: the custom prompt style + world prompt set, split out of LobbyUI (re-exported there).
		LobbyPrompts = { "worldPrompts" },
		UIHelpers = { "holdPlayerList", "attributes", "isAttack" },
		StationBoards = { "viewModel", "build", "render", "buildPadTag", "renderPadTag", "bind", "start" },
		Leaderboard = { "sortEntries", "entryFor", "collect", "build", "render", "start" },
		FighterSelect = { "mount", "acquireModel", "newViewport", "frame", "templatesReady", "awaitTemplates", "gatePreview" },
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
	t.test("the legacy pre-lobby menu modules are gone", function()
		t.expect.equal(folder:FindFirstChild("ArcadeMode"), nil, "ArcadeMode (title -> arcade ladder) deleted in round 5")
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
