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
}

T.colors = {
	bg = { 0.05, 0.05, 0.06, 0.85 },
	border = { 0, 0, 0, 1 },
	accent = { 0.31, 0.76, 0.97 }, -- remplace par la couleur de classe au login
	highlight = { 1, 1, 1, 0.18 },
	pushed = { 1, 1, 1, 0.10 },
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

-- Appelle fn() toutes les `interval` secondes. Le minuteur vit sur `owner`
-- (il ne tourne alors que quand cette frame est affichee) ou, a defaut, sur
-- une frame a part toujours active. Renvoie la frame qui le porte.
function T:Every(interval, fn, owner)
	local driver = owner or CreateFrame("Frame")
	local elapsed = 0
	driver:SetScript("OnUpdate", function(_, delta)
		elapsed = elapsed + delta
		if elapsed < interval then
			return
		end
		elapsed = 0
		fn()
	end)
	return driver
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
