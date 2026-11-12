-- Tharok UI - Transparence
-- Chaque zone de l'interface a deux opacites : au repos et au survol de la
-- souris. Par defaut tout est a 100 / 100, donc le module ne change rien tant
-- que tu n'as pas regle une zone.
--
--   /tharok fade                      liste les zones et leurs reglages
--   /tharok fade <zone> <repos> <survol>   en pourcentage, ex. actionbars 30 100
--   /tharok fade all <repos> <survol>      meme reglage pour toutes les zones
--   /tharok fade combat on|off        en combat, tout passe a l'opacite de survol
--
-- Les changements sont immediats (pas de /reload).

local T = TharokUI

-- Zone -> frames Blizzard concernees. Chaque frame reagit a son propre survol.
local ZONES = {
	actionbars = {
		"MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarLeft", "MultiBarRight",
		"MultiBar5", "MultiBar6", "MultiBar7", "StanceBar", "PetActionBar",
	},
	player = { "PlayerFrame" },
	pet = { "PetFrame" },
	target = { "TargetFrame" },
	focus = { "FocusFrame" },
	group = { "PartyFrame" },
	minimap = { "MinimapCluster" },
	buffs = { "BuffFrame", "DebuffFrame" },
	quests = { "ObjectiveTrackerFrame" },
	menu = { "MicroMenuContainer", "BagsBar" },
}

local ZONE_ORDER = { "actionbars", "player", "pet", "target", "focus", "group", "minimap", "buffs", "quests", "menu" }

local zoneDefaults = {}
for _, zone in ipairs(ZONE_ORDER) do
	zoneDefaults[zone] = { idle = 1, hover = 1 }
end

local Module = T:RegisterModule("Fade", {
	title = "Transparence",
	defaults = {
		combat = true, -- en combat, tout passe a l'opacite de survol
		zones = zoneDefaults,
	},
})

local FADE_SPEED = 4 -- variation d'opacite par seconde
local current = {} -- frame -> opacite que nous avons appliquee
local inCombat = false

-- Frames a suivre : celles des zones reglees en dessous de 100 %, plus celles
-- que nous avons estompees et qui doivent encore revenir a 100 %. Tant que la
-- liste est vide, le pilote est cache et le module ne coute rien.
local active = {}
local driver

local function Rebuild()
	if not driver then
		return
	end
	wipe(active)
	for _, zone in ipairs(ZONE_ORDER) do
		local settings = Module.db.zones[zone]
		local inert = settings.idle >= 1 and settings.hover >= 1
		for _, name in ipairs(ZONES[zone]) do
			local frame = _G[name]
			if frame and (not inert or current[frame]) then
				active[#active + 1] = { frame = frame, settings = settings }
			end
		end
	end
	driver:SetShown(#active > 0)
end

local function Step(elapsed)
	local delta = FADE_SPEED * elapsed
	local editing = EditModeManagerFrame and EditModeManagerFrame:IsEditModeActive()
	local forceHover = inCombat and Module.db.combat
	local stale = false

	for i = 1, #active do
		local entry = active[i]
		local frame, settings = entry.frame, entry.settings
		-- Une zone repassee a 100 / 100 n'est plus touchee, sauf pour la
		-- ramener a 100 si nous l'avions estompee avant.
		local inert = settings.idle >= 1 and settings.hover >= 1
		local goal
		if inert or editing then
			goal = 1
		elseif forceHover or frame:IsMouseOver() then
			goal = settings.hover
		else
			goal = settings.idle
		end

		local alpha = current[frame] or 1
		if alpha ~= goal then
			if alpha < goal then
				alpha = math.min(goal, alpha + delta)
			else
				alpha = math.max(goal, alpha - delta)
			end
			frame:SetAlpha(alpha)
			current[frame] = alpha
		end
		if inert and alpha >= 1 then
			current[frame] = nil
			stale = true
		end
	end

	if stale then
		Rebuild()
	end
end

-------------------------------------------------------------------------------
-- Commande
-------------------------------------------------------------------------------

local function Percent(value)
	return format("%d%%", math.floor(value * 100 + 0.5))
end

local function ParsePercent(text)
	local number = T.ParseNumber(text, 0, 100)
	return number and number / 100
end

local function PrintStatus()
	T:Print("transparence (repos / survol) :")
	for _, zone in ipairs(ZONE_ORDER) do
		local settings = Module.db.zones[zone]
		print(format("  |cffffd100%s|r : %s / %s", zone, Percent(settings.idle), Percent(settings.hover)))
	end
	print("  combat : " .. (Module.db.combat and "on (opacite de survol en combat)" or "off"))
	print("  /tharok fade <zone|all> <repos> <survol>   (0 a 100)")
	print("  /tharok fade combat on|off")
end

-- Appele par /tharok fade ... ; renvoie true si la commande est traitee.
function Module:OnCommand(args)
	local zone = args[1] and strlower(args[1])
	if not zone then
		PrintStatus()
		return true
	end

	if zone == "combat" then
		local value = T.ParseBool(args[2])
		if value ~= nil then
			self.db.combat = value
			T:Print("transparence : combat", T.StateText(value))
			return true
		end
		return false
	end

	-- "on" / "off" seuls : activation du module, geree par la commande commune.
	if zone == "on" or zone == "off" then
		return false
	end

	local idle, hover = ParsePercent(args[2]), ParsePercent(args[3])
	if not idle or not hover or (zone ~= "all" and not self.db.zones[zone]) then
		PrintStatus()
		return true
	end

	for _, name in ipairs(ZONE_ORDER) do
		if zone == "all" or zone == name then
			self.db.zones[name].idle = idle
			self.db.zones[name].hover = hover
		end
	end
	Rebuild()
	T:Print("transparence :", zone, "=", Percent(idle), "au repos,", Percent(hover), "au survol")
	return true
end

-------------------------------------------------------------------------------
-- Activation
-------------------------------------------------------------------------------

local ZONE_LABELS = {
	actionbars = "Barres d'action",
	player = "Joueur",
	pet = "Familier",
	target = "Cible",
	focus = "Focalisation",
	group = "Groupe",
	minimap = "Minimap",
	buffs = "Buffs et débuffs",
	quests = "Quêtes",
	menu = "Menu et sacs",
}

Module.options = {
	{ type = "toggle", key = "combat", label = "En combat, tout passe à l'opacité de survol", live = true },
}

for _, zone in ipairs(ZONE_ORDER) do
	Module.options[#Module.options + 1] = { type = "header", label = ZONE_LABELS[zone] or zone }
	for _, state in ipairs({ { "idle", "Au repos" }, { "hover", "Au survol" } }) do
		local field, label = state[1], state[2]
		Module.options[#Module.options + 1] = {
			type = "range",
			label = label,
			min = 0,
			max = 100,
			step = 5,
			suffix = "%",
			factor = 100,
			live = true,
			get = function()
				return Module.db.zones[zone][field]
			end,
			set = function(value)
				Module.db.zones[zone][field] = value
				Rebuild()
			end,
		}
	end
end

function Module:OnEnable()
	inCombat = InCombatLockdown() and true or false
	T:On("PLAYER_REGEN_DISABLED", function()
		inCombat = true
	end)
	T:On("PLAYER_REGEN_ENABLED", function()
		inCombat = false
	end)

	driver = CreateFrame("Frame")
	driver:SetScript("OnUpdate", function(_, elapsed)
		Step(elapsed)
	end)
	Rebuild()
	-- Certaines frames Blizzard n'existent qu'une fois le monde charge.
	T:On("PLAYER_ENTERING_WORLD", Rebuild)
end
