-- Tharok UI - Barres d'action
-- Skin des boutons Blizzard : on ne remplace ni les barres ni les boutons,
-- on ne touche qu'a leurs textures. Position, taille, nombre de boutons et
-- espacement restent regles dans le mode Edition du jeu.

local T = TharokUI

local BAR_NAMES = {
	"MainActionBar",
	"MultiBarBottomLeft",
	"MultiBarBottomRight",
	"MultiBarLeft",
	"MultiBarRight",
	"MultiBar5",
	"MultiBar6",
	"MultiBar7",
	"StanceBar",
	"PetActionBar",
	"PossessActionBar",
}

local Module = T:RegisterModule("ActionBars", {
	title = "Barres d'action",
	defaults = {
		hideBarArt = true, -- cadre et griffons de la barre principale
		hideMacroNames = true, -- nom des macros sur les boutons
		panels = true, -- panneau de fond translucide derriere chaque barre
		cooldownNumbers = true, -- secondes de recharge sur les icones
	},
})

-- Etat de skin garde hors des boutons pour ne rien ecrire sur les frames
-- securisees de Blizzard.
local skinned = {}

-- Reapplique ce que Blizzard reinitialise dans UpdateButtonArt().
local function RestyleButton(button)
	local icon = button.icon

	T:Fade(button.NormalTexture)
	T:Fade(button.SlotArt)
	T:Fade(button.SlotBackground)

	local pushed = button.PushedTexture
	if pushed then
		pushed:SetColorTexture(unpack(T.colors.pushed))
		pushed:ClearAllPoints()
		pushed:SetAllPoints(icon)
	end
end

local function SkinButton(button)
	if skinned[button] then
		return
	end
	local icon = button.icon
	if not icon then
		return
	end
	skinned[button] = true

	-- Icone carree, pleine taille.
	if button.IconMask then
		icon:RemoveMaskTexture(button.IconMask)
	end
	T:CropIcon(icon)

	T:CreateBackground(button, icon)
	T:CreateBorder(button, icon, 1, 2)

	local highlight = button.HighlightTexture
	if highlight then
		highlight:SetColorTexture(unpack(T.colors.highlight))
		highlight:ClearAllPoints()
		highlight:SetAllPoints(icon)
	end

	local checked = button.CheckedTexture
	if checked then
		local r, g, b = unpack(T.colors.accent)
		checked:SetColorTexture(r, g, b, 0.35)
		checked:SetBlendMode("BLEND")
		checked:ClearAllPoints()
		checked:SetAllPoints(icon)
	end

	-- Le balayage de recharge couvre toute l'icone.
	for _, key in ipairs({ "cooldown", "lossOfControlCooldown", "chargeCooldown" }) do
		local cooldown = button[key]
		if cooldown then
			cooldown:ClearAllPoints()
			cooldown:SetAllPoints(icon)
		end
	end

	T:StyleFont(button.HotKey, 11, "OUTLINE")
	T:StyleFont(button.Count, 12, "OUTLINE")
	if button.Name then
		T:StyleFont(button.Name, 9, "OUTLINE")
		if Module.db.hideMacroNames then
			T:Fade(button.Name)
		end
	end

	RestyleButton(button)
	if button.UpdateButtonArt then
		hooksecurefunc(button, "UpdateButtonArt", RestyleButton)
	end
end

local function SkinBar(bar)
	if not bar or not bar.actionButtons then
		return
	end
	if Module.db.panels then
		T:CreatePanel(bar)
	end
	for _, button in pairs(bar.actionButtons) do
		SkinButton(button)
	end
end

-- Les separateurs sont geres par des pools Blizzard : on les rend seulement
-- invisibles, sans modifier les pools (pour ne pas propager de taint).
local function FadePool(pool)
	if not pool then
		return
	end
	for divider in pool:EnumerateActive() do
		divider:SetAlpha(0)
	end
end

local function FadeDividers(bar)
	FadePool(bar.HorizontalDividersPool)
	FadePool(bar.VerticalDividersPool)
end

local function HideMainBarArt()
	local bar = MainActionBar
	if not bar then
		return
	end
	T:Fade(bar.BorderArt)
	T:Fade(bar.EndCaps)
	FadeDividers(bar)
	if bar.UpdateDividers then
		hooksecurefunc(bar, "UpdateDividers", FadeDividers)
	end
end

Module.options = {
	{ type = "toggle", key = "hideBarArt", label = "Masquer le décor de la barre principale" },
	{ type = "toggle", key = "hideMacroNames", label = "Masquer le nom des macros" },
	{ type = "toggle", key = "panels", label = "Panneau de fond derrière chaque barre" },
	{ type = "toggle", key = "cooldownNumbers", label = "Chiffres de recharge sur les icônes" },
	{ type = "note", text = "Position et taille des barres : mode Édition du jeu." },
}

function Module:OnEnable()
	for _, name in ipairs(BAR_NAMES) do
		SkinBar(_G[name])
	end
	if self.db.hideBarArt then
		HideMainBarArt()
	end

	-- Compte a rebours sur les icones : c'est une option du jeu (barres
	-- d'action > afficher les chiffres de recharge), qu'on active ici. Elle
	-- vaut aussi pour les boutons de familier et de posture.
	if self.db.cooldownNumbers and not C_CVar.GetCVarBool("countdownForCooldowns") then
		C_CVar.SetCVar("countdownForCooldowns", "1")
	end
end
