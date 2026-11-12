-- Tharok UI - socle
-- Aucune dependance externe. Les modules (TharokUI_*) s'enregistrent via
-- TharokUI:RegisterModule() et sont actives a PLAYER_LOGIN.

local ADDON_NAME = ...

local T = {}
_G.TharokUI = T

T.name = "Tharok UI"
T.version = "0.1.0"
T.modules = {}
T.moduleOrder = {}

-------------------------------------------------------------------------------
-- Theme
-------------------------------------------------------------------------------

T.media = {
	blank = "Interface\\Buttons\\WHITE8X8",
	-- Icone Tharok UI : complete (liste des addons) et "T" seul, blanc, a
	-- teinter a la couleur d'accent.
	icon = "Interface\\AddOns\\TharokUI\\Media\\icon",
	glyph = "Interface\\AddOns\\TharokUI\\Media\\icon-glyph",
	noise = "Interface\\AddOns\\TharokUI\\Media\\noise", -- grain des surfaces
	-- Pinceau (voir Media/generate_brush.py) : lavis des surfaces, trait sec,
	-- bords effiloches des panneaux, remplissage des barres.
	wash = "Interface\\AddOns\\TharokUI\\Media\\brush-wash",
	stroke = "Interface\\AddOns\\TharokUI\\Media\\brush-stroke",
	edgeLeft = "Interface\\AddOns\\TharokUI\\Media\\brush-edge-left",
	edgeRight = "Interface\\AddOns\\TharokUI\\Media\\brush-edge-right",
	edgeTop = "Interface\\AddOns\\TharokUI\\Media\\brush-edge-top",
	bar = "Interface\\AddOns\\TharokUI\\Media\\brush-bar",
}

T.colors = {
	bg = { 0.05, 0.05, 0.06, 0.85 },
	border = { 0, 0, 0, 1 },
	accent = { 0.31, 0.76, 0.97 }, -- remplace par la couleur de classe au login
	highlight = { 1, 1, 1, 0.18 },
	pushed = { 1, 1, 1, 0.10 },
	-- Trois niveaux de texte : principal, secondaire, (actif = accent).
	text = { 0.93, 0.92, 0.89 },
	textDim = { 0.58, 0.58, 0.60 },
}

-- Echelle typographique : deux tailles et un titre, partout.
T.fontSizes = {
	small = 10,
	normal = 12,
	title = 13,
}

-------------------------------------------------------------------------------
-- Sortie
-------------------------------------------------------------------------------

local PREFIX = "|cff4fc3f7Tharok UI|r : "

function T:Print(...)
	print(PREFIX .. strjoin(" ", tostringall(...)))
end

-------------------------------------------------------------------------------
-- Outils communs
-------------------------------------------------------------------------------

-- Vrai si `value` est une valeur secrete : le jeu la laisse afficher, mais un
-- addon ne peut ni la comparer ni calculer avec.
function T.IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value)
end

-- "on" / "1" / "oui" -> true ; "off" / "0" / "non" -> false ; sinon nil.
function T.ParseBool(text)
	text = text and strlower(text)
	if text == "on" or text == "1" or text == "oui" then
		return true
	elseif text == "off" or text == "0" or text == "non" then
		return false
	end
end

-- Nombre compris entre `min` et `max`, ou nil.
function T.ParseNumber(text, min, max)
	local number = tonumber(text)
	if not number or number < min or number > max then
		return nil
	end
	return number
end

-- "on" en vert ou "off" en rouge, pour les messages.
function T.StateText(value)
	return value and "|cff40ff40on|r" or "|cffff4040off|r"
end

-- Couleur r, g, b d'une classe ("MAGE", "WARRIOR"...), ou nil si elle est
-- inconnue ou illisible.
function T:ClassColor(classFile)
	if not classFile or T.IsSecret(classFile) then
		return
	end
	local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
	if color then
		return color.r, color.g, color.b
	end
end

-- Transparence : un seul reglage prime par element. Un module qui prend la
-- main sur l'opacite d'une frame (le tiroir, pour ce qu'il contient) l'inscrit
-- ici ; le module Transparence ne touche alors plus a cette frame. Apres une
-- modification, appeler T.RefreshFade() s'il existe.
T.alphaOwned = {}

-- Minuteurs : une seule frame fait tourner tous les minuteurs du socle et
-- des modules (une frame OnUpdate par minuteur coute plus cher).
local timers = {}
local timerFrame = CreateFrame("Frame")
timerFrame:Hide()
timerFrame:SetScript("OnUpdate", function(self, delta)
	for i = #timers, 1, -1 do
		local timer = timers[i]
		if timer.cancelled then
			table.remove(timers, i)
		else
			timer.elapsed = timer.elapsed + delta
			if timer.elapsed >= timer.interval then
				timer.elapsed = 0
				T.SafeCall(timer.fn)
			end
		end
	end
	if #timers == 0 then
		self:Hide()
	end
end)

-- Appelle fn() toutes les `interval` secondes. Renvoie un objet dont
-- :Cancel() arrete le minuteur.
function T:Every(interval, fn)
	local timer = { interval = interval, fn = fn, elapsed = 0 }
	function timer:Cancel()
		self.cancelled = true
	end
	timers[#timers + 1] = timer
	timerFrame:Show()
	return timer
end

-- Renvoie une fonction qui, appelee plusieurs fois de suite, n'execute fn()
-- qu'une fois, `delay` secondes apres le premier appel (0 = image suivante).
-- Pour absorber les rafales d'evenements.
function T:Debounce(fn, delay)
	local queued = false
	local function Run()
		queued = false
		T.SafeCall(fn)
	end
	return function()
		if queued then
			return
		end
		queued = true
		C_Timer.After(delay or 0, Run)
	end
end

-------------------------------------------------------------------------------
-- Evenements
-------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local handlers = {}

local function SafeCall(fn, ...)
	return xpcall(fn, geterrorhandler(), ...)
end
T.SafeCall = SafeCall

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	if not list then
		return
	end
	for i = 1, #list do
		SafeCall(list[i], event, ...)
	end
end)

-- Enregistre fn(event, ...) sur un evenement du jeu.
function T:On(event, fn)
	local list = handlers[event]
	if not list then
		list = {}
		handlers[event] = list
		eventFrame:RegisterEvent(event)
	end
	list[#list + 1] = fn
end

-- Evenement d'unite filtre par le jeu lui-meme : fn(event, unit, ...) n'est
-- appele que pour les unites donnees. Bien moins couteux que T:On pour les
-- evenements frequents (UNIT_POWER_UPDATE arrive pour chaque unite
-- visible, barres de nom comprises).
function T:OnUnit(event, fn, ...)
	local frame = CreateFrame("Frame")
	frame:RegisterUnitEvent(event, ...)
	frame:SetScript("OnEvent", function(_, ...)
		SafeCall(fn, ...)
	end)
	return frame
end

-- Etat de combat partage : mis a jour avant les gestionnaires des modules
-- (ceux-ci s'inscrivent apres le socle).
T.inCombat = false

T:On("PLAYER_REGEN_DISABLED", function()
	T.inCombat = true
end)

-- Execute fn tout de suite, ou a la sortie du combat si on est en combat.
local afterCombat = {}

function T:AfterCombat(fn)
	if InCombatLockdown() then
		afterCombat[#afterCombat + 1] = fn
	else
		SafeCall(fn)
	end
end

T:On("PLAYER_REGEN_ENABLED", function()
	T.inCombat = false
	if #afterCombat == 0 then
		return
	end
	local queue = afterCombat
	afterCombat = {}
	for i = 1, #queue do
		SafeCall(queue[i])
	end
end)

-------------------------------------------------------------------------------
-- Base de donnees
-------------------------------------------------------------------------------

local function ApplyDefaults(target, defaults)
	for key, value in pairs(defaults) do
		if type(value) == "table" then
			if type(target[key]) ~= "table" then
				target[key] = {}
			end
			ApplyDefaults(target[key], value)
		elseif target[key] == nil then
			target[key] = value
		end
	end
end

-------------------------------------------------------------------------------
-- Modules
-------------------------------------------------------------------------------

-- module = {
--   title    = "Nom affiche",
--   defaults = { option = valeur, ... },   -- "enabled" est ajoute d'office
--   OnEnable = function(self) ... end,     -- self.db = options sauvegardees
-- }
function T:RegisterModule(name, module)
	if self.modules[name] then
		error("Tharok UI : module deja enregistre : " .. tostring(name), 2)
	end
	module.name = name
	module.title = module.title or name
	module.defaults = module.defaults or {}
	if module.defaults.enabled == nil then
		module.defaults.enabled = true
	end
	self.modules[name] = module
	self.moduleOrder[#self.moduleOrder + 1] = name
	return module
end

local function EnableModule(module)
	if module.active or not module.db.enabled then
		return
	end
	if module.OnEnable then
		local ok = SafeCall(module.OnEnable, module)
		if not ok then
			T:Print("le module", module.title, "a rencontre une erreur au demarrage.")
			return
		end
	end
	module.active = true
end

T:On("ADDON_LOADED", function(_, loadedName)
	if loadedName ~= ADDON_NAME then
		return
	end
	if type(TharokUIDB) ~= "table" then
		TharokUIDB = {}
	end
	if type(TharokUIDB.modules) ~= "table" then
		TharokUIDB.modules = {}
	end
	T.db = TharokUIDB

	-- Theme commun a tous les modules (voir /tharok theme).
	if type(T.db.theme) ~= "table" then
		T.db.theme = {}
	end
	ApplyDefaults(T.db.theme, {
		font = true, -- police unique (Barlow)
		bgAlpha = 0.85, -- opacite des fonds sombres
		border = { 0, 0, 0 }, -- couleur des bordures
		shade = 0.35, -- intensite du degrade sombre des barres (0 = aucun)
		texture = true, -- matiere des panneaux : grain, reflet, ombre portee
		motion = true, -- animations : fondus, retour au clic, jauges glissantes
		-- accent = { r, g, b } ; absent = couleur de classe
	})
	local theme = T.db.theme
	T.colors.bg[4] = theme.bgAlpha
	T.colors.border = { theme.border[1], theme.border[2], theme.border[3], 1 }

	if theme.font and T.ApplyFonts then
		T:ApplyFonts()
	end
end)

T:On("PLAYER_LOGIN", function()
	-- /reload en plein combat : l'etat ne vient pas d'un evenement.
	T.inCombat = InCombatLockdown() and true or false

	-- Avant les modules : leurs tailles au pixel dependent de l'echelle.
	if T.InitScale then
		SafeCall(T.InitScale, T)
	end

	local custom = T.db.theme.accent
	if type(custom) == "table" then
		T.colors.accent = { custom[1], custom[2], custom[3] }
	else
		local _, classFile = UnitClass("player")
		local r, g, b = T:ClassColor(classFile)
		if r then
			T.colors.accent = { r, g, b }
		end
	end

	for _, name in ipairs(T.moduleOrder) do
		local module = T.modules[name]
		if type(T.db.modules[name]) ~= "table" then
			T.db.modules[name] = {}
		end
		ApplyDefaults(T.db.modules[name], module.defaults)
		module.db = T.db.modules[name]
		EnableModule(module)
	end
end)
