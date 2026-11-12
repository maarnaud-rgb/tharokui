-- Tharok UI - Menace
-- Colore la barre de vie des barres de nom ennemies selon ta menace.
--
--   Mode normal (DPS / soigneur) :
--     vert   = peu de menace
--     jaune  = la menace monte
--     orange = tu es sur le point de reprendre l'aggro
--     rouge  = tu as l'aggro
--
--   Mode tank (/tharok threat tankMode on) : lecture inversee
--     vert   = tu tiens l'aggro
--     jaune  = tu la tiens mais quelqu'un te rattrape
--     orange = tu ne l'as pas, mais tu es proche de la reprendre
--     rouge  = tu ne l'as pas
--
-- Si le client rend ces valeurs secretes en combat, le module ne fait rien
-- et laisse la couleur de Blizzard.

local T = TharokUI

local Module = T:RegisterModule("Threat", {
	title = "Menace",
	defaults = {
		tankMode = false, -- lecture inversee pour les tanks
		soloToo = false, -- colorer aussi en solo sans familier
	},
})

local GREEN = { 0.20, 0.85, 0.25 }
local YELLOW = { 1.00, 0.85, 0.10 }
local ORANGE = { 1.00, 0.50, 0.05 }
local RED = { 0.95, 0.15, 0.15 }

local IsSecret = T.IsSecret

-- Degrade vert -> jaune -> rouge pour un pourcentage de 0 a 100.
local function Gradient(percent)
	if percent < 0 then
		percent = 0
	elseif percent > 100 then
		percent = 100
	end
	local from, to, t
	if percent < 50 then
		from, to, t = GREEN, YELLOW, percent / 50
	else
		from, to, t = YELLOW, RED, (percent - 50) / 50
	end
	return from[1] + (to[1] - from[1]) * t, from[2] + (to[2] - from[2]) * t, from[3] + (to[3] - from[3]) * t
end

-- Renvoie r, g, b ou nil s'il ne faut pas toucher a la barre.
local function ThreatColor(unit)
	if not Module.db.soloToo and not IsInGroup() and not UnitExists("pet") then
		return
	end

	local canAttack = UnitCanAttack("player", unit)
	local isPlayer = UnitIsPlayer(unit)
	if IsSecret(canAttack) or IsSecret(isPlayer) or not canAttack or isPlayer then
		return
	end

	local isTanking, status, scaledPercent = UnitDetailedThreatSituation("player", unit)
	if IsSecret(isTanking) or IsSecret(status) or IsSecret(scaledPercent) then
		return
	end
	if status == nil then
		return -- pas sur la liste de menace de cette unite
	end

	if Module.db.tankMode then
		if status == 3 then
			return unpack(GREEN)
		elseif status == 2 then
			return unpack(YELLOW)
		elseif status == 1 then
			return unpack(ORANGE)
		end
		return unpack(RED)
	end

	if isTanking or status >= 2 then
		return unpack(RED)
	elseif status == 1 then
		return unpack(ORANGE)
	elseif type(scaledPercent) == "number" then
		return Gradient(scaledPercent)
	end
	return unpack(GREEN)
end

local function HealthBarForUnit(unit)
	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	if not plate or (plate.IsForbidden and plate:IsForbidden()) then
		return
	end
	local unitFrame = plate.UnitFrame
	local container = unitFrame and unitFrame.HealthBarsContainer
	return container and container.healthBar
end

local function UpdateUnit(unit)
	-- Seuls les jetons "nameplateN" sont acceptes par l'API des barres de nom
	-- (les jetons du type "targettarget" la font echouer).
	if type(unit) ~= "string" or not strfind(unit, "^nameplate%d+$") then
		return
	end
	local healthBar = HealthBarForUnit(unit)
	if not healthBar then
		return
	end
	local r, g, b = ThreatColor(unit)
	if r then
		healthBar:SetStatusBarColor(r, g, b)
	end
end

Module.options = {
	{ type = "toggle", key = "tankMode", label = "Mode tank (lecture inversée)", live = true },
	{ type = "toggle", key = "soloToo", label = "Colorer aussi en solo sans familier", live = true },
}

function Module:OnEnable()
	if not C_NamePlate or not C_NamePlate.GetNamePlateForUnit or not UnitDetailedThreatSituation then
		return
	end

	-- Les evenements de menace arrivent avec des jetons varies (joueur,
	-- membre du groupe, cible de la cible...) : on rafraichit donc toutes les
	-- barres de nom affichees, au plus une fois tous les dixiemes de seconde.
	local refreshQueued = false

	local function RefreshAll()
		refreshQueued = false
		for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
			local unitFrame = plate.UnitFrame
			UpdateUnit(plate.namePlateUnitToken or (unitFrame and unitFrame.unit))
		end
	end

	local function QueueRefresh()
		if refreshQueued then
			return
		end
		refreshQueued = true
		C_Timer.After(0.1, RefreshAll)
	end

	T:On("UNIT_THREAT_LIST_UPDATE", QueueRefresh)
	T:On("UNIT_THREAT_SITUATION_UPDATE", QueueRefresh)
	T:On("NAME_PLATE_UNIT_ADDED", function(_, unit)
		UpdateUnit(unit)
	end)

	-- Blizzard remet sa couleur a chaque changement de vie : on repasse apres.
	if CompactUnitFrame_UpdateHealthColor then
		hooksecurefunc("CompactUnitFrame_UpdateHealthColor", function(frame)
			local unit = frame and (frame.displayedUnit or frame.unit)
			if type(unit) == "string" and strfind(unit, "^nameplate") then
				UpdateUnit(unit)
			end
		end)
	end
end
