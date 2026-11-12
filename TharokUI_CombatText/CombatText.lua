-- Tharok UI - Texte de combat
-- Affiche a l'ecran les degats et soins que tu recois, ainsi que les esquives,
-- parades, absorptions, etc.
--
-- Le module s'appuie sur le texte de combat integre au jeu, qu'il active et
-- habille (contour net, taille reglable). Un addon ne peut pas produire ce
-- texte lui-meme dans ce client : les montants de degats sont des valeurs
-- secretes en combat, que seul le code du jeu peut lire.
--
--   /tharok combattext size <50-200>     taille du texte, en pourcentage
--   /tharok combattext mode up|down|arc  sens de defilement
--
-- Ce qui est affiche (soins, gains de ressources, reputation...) se regle
-- dans les options du jeu, section Combat.

local T = TharokUI

local Module = T:RegisterModule("CombatText", {
	title = "Texte de combat",
	defaults = {
		outline = true, -- contour net sur le texte
		size = 100, -- taille en pourcentage
	},
})

local MODES = { up = "1", down = "2", arc = "3" }

local styled = false

local function ApplyStyle()
	if not CombatText then
		return
	end
	if Module.db.outline and not styled and CombatTextFont then
		local file, size = CombatTextFont:GetFont()
		if file then
			CombatTextFont:SetFont(file, size, "OUTLINE")
			styled = true
		end
	end
	CombatText:SetScale(Module.db.size / 100)
end

function Module:OnCommand(args)
	local key = args[1] and strlower(args[1])
	if key == "size" then
		local size = T.ParseNumber(args[2], 50, 200)
		if not size then
			T:Print("usage : /tharok combattext size <50-200>")
			return true
		end
		self.db.size = size
		ApplyStyle()
		T:Print("texte de combat : taille", size .. "%")
		return true
	elseif key == "mode" then
		local mode = args[2] and MODES[strlower(args[2])]
		if not mode then
			T:Print("usage : /tharok combattext mode up|down|arc")
			return true
		end
		C_CVar.SetCVar("floatingCombatTextFloatMode_v2", mode)
		T:Print("texte de combat : defilement", strlower(args[2]))
		return true
	end
	return false
end

Module.options = {
	{ type = "toggle", key = "outline", label = "Contour net sur le texte" },
	{
		type = "range",
		key = "size",
		label = "Taille du texte",
		min = 50,
		max = 200,
		step = 5,
		suffix = "%",
		live = true,
		set = function(value)
			Module.db.size = value
			ApplyStyle()
		end,
	},
	{
		type = "select",
		label = "Sens de défilement",
		live = true,
		values = { { "1", "Vers le haut" }, { "2", "Vers le bas" }, { "3", "En arc" } },
		get = function()
			return C_CVar.GetCVar("floatingCombatTextFloatMode_v2")
		end,
		set = function(value)
			C_CVar.SetCVar("floatingCombatTextFloatMode_v2", value)
		end,
	},
	{ type = "note", text = "Ce qui est affiché se règle dans les options du jeu, section Combat." },
}

function Module:OnEnable()
	T:On("ADDON_LOADED", function(_, name)
		if name == "Blizzard_CombatText" then
			ApplyStyle()
		end
	end)

	T:AfterCombat(function()
		-- Option du jeu "Texte de combat defilant pour soi".
		if not C_CVar.GetCVarBool("enableFloatingCombatText") then
			C_CVar.SetCVar("enableFloatingCombatText", "1")
		end
		-- Le texte de combat est un addon Blizzard charge a la demande.
		if not CombatText and CombatText_LoadUI then
			CombatText_LoadUI()
		end
		ApplyStyle()
	end)
end
