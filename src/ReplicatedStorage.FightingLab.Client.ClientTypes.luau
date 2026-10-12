--!strict
local RenderBuffer = require(script.Parent.Parent:WaitForChild("RenderBuffer"))
export type FighterView = RenderBuffer.Rendered
export type RenderFrame = { now: number, dt: number, renderFrame: number, fighters: { FighterView }, entry: RenderBuffer.Entry?, mode: string, phase: string, timer: number, scores: { number }, round: number, winner: number, reason: string, sparring: boolean, ko: boolean, paused: boolean, hitstop: number }
export type CombatEvent = RenderBuffer.SnapEvent
export type Ctx = { send: (kind: string, a: any?, b: any?) -> (), config: any, gui: ScreenGui, modules: { Input: any, Hud: any, Camera: any, Characters: any, Effects: any, Audio: any, Stage: any, FrontEnd: any } }
return {}

-- vfx-feel: RenderFrame.hitstop, SnapEvent.counter, and SnapEvent.launch mirror authoritative server snapshots.
