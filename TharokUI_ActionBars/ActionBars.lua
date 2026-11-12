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
		hideEmpty = true, -- emplacements vides invisibles (sauf en glissant un sort)
	},
})

-------------------------------------------------------------------------------
-- Emplacements vides
-------------------------------------------------------------------------------

-- Un emplacement vide affiche quand meme son raccourci (a-1, m-2...) : du
-- texte sans information. On le rend invisible (l'opacite n'est pas
-- protegee, on peut la changer en combat), et on le remontre pendant qu'un
-- sort ou un objet est tenu au curseur, pour pouvoir le deposer.
local allButtons = {}
local showGrid = false

local function UpdateEmpty(button)
	if not Module.db.hideEmpty then
		return
	end
	local action = button.action
	local has = showGrid or (type(action) == "number" and HasAction(action))
	button:SetAlpha(has and 1 or 0)
end

local function UpdateAllEmpty()
	for button in pairs(allButtons) do
		UpdateEmpty(button)
	end
end

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

-------------------------------------------------------------------------------
-- Retour visuel : appui et fin de recharge
-------------------------------------------------------------------------------

-- Animations jouees par le moteur du jeu (AnimationGroup) : rien n'est
-- protege, elles fonctionnent en combat. Tout est cree au skin, hors combat.

-- Eclat additif sur l'icone, qui s'eteint en `duration` secondes.
local function CreateGlow(button, icon, color, peak, duration)
	local glow = button:CreateTexture(nil, "OVERLAY", nil, 6)
	glow:SetAllPoints(icon)
	glow:SetColorTexture(color[1], color[2], color[3], 1)
	glow:SetBlendMode("ADD")
	glow:SetAlpha(0)
	local group = glow:CreateAnimationGroup()
	local fade = group:CreateAnimation("Alpha")
	fade:SetFromAlpha(peak)
	fade:SetToAlpha(0)
	fade:SetDuration(duration)
	fade:SetSmoothing("OUT")
	return group
end

-- Icone qui se comprime puis revient (appui), ou gonfle puis revient (sort
-- de nouveau disponible).
local function CreateBounce(icon, scale, inTime, outTime)
	local group = icon:CreateAnimationGroup()
	local first = group:CreateAnimation("Scale")
	first:SetScaleFrom(1, 1)
	first:SetScaleTo(scale, scale)
	first:SetDuration(inTime)
	first:SetOrder(1)
	first:SetSmoothing("OUT")
	local second = group:CreateAnimation("Scale")
	second:SetScaleFrom(scale, scale)
	second:SetScaleTo(1, 1)
	second:SetDuration(outTime)
	second:SetOrder(2)
	second:SetSmoothing("IN_OUT")
	return group
end

local feedback = {} -- bouton -> { press, pressGlow, ready, readyGlow, duration }

local function PlayPress(button)
	local fx = feedback[button]
	if not fx or not T.MotionOn() then
		return
	end
	fx.press:Stop()
	fx.press:Play()
	fx.pressGlow:Stop()
	fx.pressGlow:Play()
end

local function SetupFeedback(button, icon)
	if feedback[button] or not icon.CreateAnimationGroup then
		return
	end
	local r, g, b = unpack(T.colors.accent)
	local fx = {
		press = CreateBounce(icon, 0.9, 0.05, 0.14),
		pressGlow = CreateGlow(button, icon, { 1, 1, 1 }, 0.22, 0.25),
		ready = CreateBounce(icon, 1.08, 0.1, 0.2),
		readyGlow = CreateGlow(button, icon, { r, g, b }, 0.55, 0.6),
		duration = 0,
	}
	feedback[button] = fx

	-- Touche du clavier : Blizzard passe le bouton a l'etat "enfonce".
	hooksecurefunc(button, "SetButtonState", function(self, state)
		if state == "PUSHED" then
			PlayPress(self)
		end
	end)
	-- Clic souris.
	button:HookScript("OnMouseDown", PlayPress)

	-- Fin d'une vraie recharge (pas le temps de recharge global) : le sort
	-- est de nouveau disponible, l'icone le signale une fois.
	local cooldown = button.cooldown
	if cooldown then
		hooksecurefunc(cooldown, "SetCooldown", function(_, _, duration)
			if T.IsSecret(duration) or type(duration) ~= "number" then
				fx.duration = 0
			else
				fx.duration = duration
			end
		end)
		cooldown:HookScript("OnCooldownDone", function()
			if fx.duration > 2 and T.MotionOn() then
				fx.ready:Stop()
				fx.ready:Play()
				fx.readyGlow:Stop()
				fx.readyGlow:Play()
			end
			fx.duration = 0
		end)
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

	SetupFeedback(button, icon)

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
		if not allButtons[button] and button.action ~= nil then
			allButtons[button] = true
			if button.Update then
				hooksecurefunc(button, "Update", UpdateEmpty)
			end
		end
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
	{ type = "toggle", key = "hideEmpty", label = "Masquer les emplacements vides" },
	{ type = "note", text = "Position et taille des barres : mode Édition du jeu." },
}

function Module:OnEnable()
	for _, name in ipairs(BAR_NAMES) do
		SkinBar(_G[name])
	end
	if self.db.hideBarArt then
		HideMainBarArt()
	end

	if self.db.hideEmpty then
		T:On("ACTIONBAR_SHOWGRID", function()
			showGrid = true
			UpdateAllEmpty()
		end)
		T:On("ACTIONBAR_HIDEGRID", function()
			showGrid = false
			UpdateAllEmpty()
		end)
		for _, event in ipairs({
			"PLAYER_ENTERING_WORLD", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED",
			"UPDATE_BONUS_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM",
		}) do
			T:On(event, function()
				C_Timer.After(0, UpdateAllEmpty) -- apres la mise a jour Blizzard
			end)
		end
		UpdateAllEmpty()
	end

	-- Compte a rebours sur les icones : c'est une option du jeu (barres
	-- d'action > afficher les chiffres de recharge), qu'on active ici. Elle
	-- vaut aussi pour les boutons de familier et de posture.
	if self.db.cooldownNumbers and not C_CVar.GetCVarBool("countdownForCooldowns") then
		C_CVar.SetCVar("countdownForCooldowns", "1")
	end
end
