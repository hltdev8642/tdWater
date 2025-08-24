--Place a configurable smoke emitter in the world
-- Now with: color modes, toggle/hold, safety checks, secondary boost, better config, performance tweaks, and original silly comments!

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------
local snd = nil
local emit = false
local shutup = false
local ui = false

local emitBody = nil
local emitPos = Vec(0,0,0)
local emitDir = Vec(0,0,1)
local emitTimer = 0
local lastSoundPos = Vec(0,0,0)

-- Cached config (refreshed each tick so options can be changed live)
local CFG = {}

----------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------

--Helper to return a random vector of particular length
function rndVec(length)
	local v = VecNormalize(Vec(math.random(-100,100), math.random(-100,100), math.random(-100,100)))
	return VecScale(v, length)	
end

--Helper to return a random number in range mi to ma
function rnd(mi, ma)
	return math.random(1000)/1000*(ma-mi) + mi
end

local function clamp(v, mi, ma)
	if v < mi then return mi end
	if v > ma then return ma end
	return v
end

local function bodyValid(b)
	if not b then return false end
	local ok, t = pcall(GetBodyTransform, b)
	return ok and t ~= nil
end

----------------------------------------------------------------
-- CONFIG LOADING
----------------------------------------------------------------
local function readConfig()
	CFG.mode            = GetString("savegame.mod.tdwater.mode")
	if CFG.mode == "" then CFG.mode = "toggle" end

	CFG.secondaryBoost  = GetBool("savegame.mod.tdwater.secondaryBoost")
	CFG.droplets        = GetBool("savegame.mod.tdwater.droplets")

	CFG.baseCount       = tonumber(GetString("savegame.mod.tdwater.count"))    or 3
	CFG.radius          = tonumber(GetString("savegame.mod.tdwater.radius"))   or 0.7
	CFG.life            = tonumber(GetString("savegame.mod.tdwater.life"))     or 20
	CFG.gravity         = tonumber(GetString("savegame.mod.tdwater.gravity"))  or -30
	CFG.drag            = tonumber(GetString("savegame.mod.tdwater.drag"))     or 1.0
	CFG.velocity        = tonumber(GetString("savegame.mod.tdwater.velocity")) or 10
	CFG.alphaStart      = 1.0
	CFG.alphaEnd        = 0.0

	CFG.colorMode       = GetString("savegame.mod.tdwater.colormode")
	if CFG.colorMode == "" then CFG.colorMode = "Preset" end
	CFG.preset          = GetString("savegame.mod.color")

	CFG.customR         = tonumber(GetString("savegame.mod.tdwater.custom.r")) or 0
	CFG.customG         = tonumber(GetString("savegame.mod.tdwater.custom.g")) or 0.5
	CFG.customB         = tonumber(GetString("savegame.mod.tdwater.custom.b")) or 1

	if CFG.droplets then
		CFG.radius     = CFG.radius * 0.35
		CFG.gravity    = CFG.gravity * 3.5
		CFG.drag       = clamp(CFG.drag * 0.5, 0.1, 5)
		CFG.velocity   = CFG.velocity * 1.2
		CFG.baseCount  = math.max(1, math.floor(CFG.baseCount * 1.5))
		CFG.life       = CFG.life * 0.6
	end
end

----------------------------------------------------------------
-- COLOR LOGIC
----------------------------------------------------------------
local function computeColor(dt, t)
	-- RGB stuff.
	local red,green,blue = 0,0.498,1
	if CFG.colorMode == "Preset" then
		local propColor = CFG.preset
		if propColor == "Classic tdWater" then
			red = 0
			green = 0
			blue = 1
		elseif propColor == "Toxic Chemicals" then
			red = 0
			green = 1
			blue = 0
		elseif propColor == "Oil" then
			red = 0
			green = 0
			blue = 0
		end
	elseif CFG.colorMode == "Custom" then
		red, green, blue = CFG.customR, CFG.customG, CFG.customB
	elseif CFG.colorMode == "Rainbow" then
		local speed = 0.25
		local h = (t * speed) % 1.0
		local s = 0.9
		local v = 1.0
		local i = math.floor(h*6)
		local f = h*6 - i
		local p = v*(1-s)
		local q = v*(1-f*s)
		local tt = v*(1-(1-f)*s)
		if i % 6 == 0 then red,green,blue = v,tt,p
		elseif i == 1 then red,green,blue = q,v,p
		elseif i == 2 then red,green,blue = p,v,tt
		elseif i == 3 then red,green,blue = p,q,v
		elseif i == 4 then red,green,blue = tt,p,v
		else red,green,blue = v,p,q end
	elseif CFG.colorMode == "Random" then
		red = 0.2 + math.random()*0.8
		green = 0.2 + math.random()*0.8
		blue = 0.2 + math.random()*0.8
	end
	return red, green, blue
end

----------------------------------------------------------------
-- EMISSION
----------------------------------------------------------------
local function startEmissionFromRay()
	local ct = GetCameraTransform()
	local pos = ct.pos
	local dir = TransformToParentVec(ct, Vec(0,0,-1))
	local hit, dist, normal, shape = QueryRaycast(pos, dir, 500)
	if hit then
		local hitPoint = VecAdd(pos, VecScale(dir, dist))
		local b = GetShapeBody(shape)
		local t = GetBodyTransform(b)
		emitBody = b
		emitPos = TransformToLocalPoint(t, hitPoint)
		emitDir = TransformToLocalVec(t, normal)
		emitTimer = 0
		emit = true
		shutup = false
	end
end

local function stopEmission()
	emit = false
	shutup = true
end

local function doEmission(dt)
	if not emit then return end
	if not bodyValid(emitBody) then
		stopEmission()
		return
	end

	readConfig()

	local t = GetTime()
	emitTimer = emitTimer + dt

	-- Secondary spray (if enabled) shrinks radius but boosts velocity
	local secondary = CFG.secondaryBoost and InputDown("secondary")
	local radius = CFG.radius * (secondary and 0.4 or 1.0)
	local vel    = CFG.velocity * (secondary and 1.6 or 1.0)
	local count  = CFG.baseCount * (secondary and 2 or 1)

	local red, green, blue = computeColor(dt, t)

	local bt = GetBodyTransform(emitBody)
	local pos = TransformToParentPoint(bt, emitPos)
	local dir = TransformToParentVec(bt, emitDir)
	lastSoundPos = pos

	if snd then
		local vol = clamp(0.15 + 0.02*count, 0, 1)
		PlayLoop(snd, pos, vol)
	end

	--Set up the particle state
	ParticleReset()
	ParticleType("smoke")             -- no shit
	ParticleRadius(radius)
	ParticleAlpha(CFG.alphaStart, CFG.alphaEnd)	-- Ramp up fast, ramp down after 50%
	ParticleGravity(CFG.gravity)				-- common hellishly randomized gravity W
	ParticleDrag(CFG.drag)                      -- Do it go up or down?
	ParticleColor(red, green, blue)				-- RGB stuff.

	--Emit particles
	for i=1, count do
		--Randomize position slightly. This is important when spawning multiple particles at the same time
		local p = VecAdd(pos, VecAdd(VecScale(dir, radius), rndVec(radius*0.6)))
		--Randomize velocity slightly
		local v = VecScale(VecAdd(dir, rndVec(0.15)), vel)
		--Include some of the movement of the attachment body
		v = VecAdd(v, VecScale(GetBodyVelocityAtPos(emitBody, pos), 0.5))
		--Randomize lifetime
		local l = rnd(CFG.life*0.6, CFG.life*1.3)
		--Spawn particle into the world
		SpawnParticle(p, v, l)
	end
end

----------------------------------------------------------------
-- INIT / UPDATE / TICK
----------------------------------------------------------------

function init()
	RegisterTool("tdwater", "TeardownWater", "MOD/vox/smokegun.vox")
	SetBool("game.tool.tdwater.enabled", true)
	snd = LoadLoop("MOD/snd/watta.ogg")
	math.randomseed(GetTime() * 100000)
	readConfig()
end

function update(dt)
	if emit and shutup then
		stopEmission()
	end
	if emit then
		doEmission(dt)
	end
end

--Main tick function handles tool logic
function tick(dt)
	local selected = (GetString("game.player.tool") == "tdwater")
	if selected then
		if CFG.mode == "hold" then
			-- Start on press, stop on release
			if GetBool("game.player.canusetool") then
				if InputPressed("usetool") then
					startEmissionFromRay()
				end
				if InputReleased("usetool") then
					stopEmission()
				end
			end
		else
			-- toggle mode
			if GetBool("game.player.canusetool") and InputPressed("usetool") then
				if emit then
					stopEmission()
				else
					startEmissionFromRay()
				end
			end
		end

		-- Allow reposition by pressing reload while emitting
		if emit and InputPressed("reload") then
			startEmissionFromRay()
		end

		--HUD message
		if emit then
			SetString("game.tool.tdwater.ammo.display", "Emitting (Pause > Stop or use tool)")
		else
			if CFG.mode == "hold" then
				SetString("game.tool.tdwater.ammo.display", "Hold LMB to pour")
			else
				SetString("game.tool.tdwater.ammo.display", "Click to start / stop")
			end
		end
	end

	-- Pause menu control
	if PauseMenuButton("tdWater: Stop emitting") then
		shutup = true
	end
	if PauseMenuButton("tdWater: Cycle color mode") then
		local order = {"Preset","Custom","Rainbow","Random"}
		local idx = 1
		for i,v in ipairs(order) do
			if v == CFG.colorMode then idx = i break end
		end
		idx = idx % #order + 1
		SetString("savegame.mod.tdwater.colormode", order[idx])
	end
end
