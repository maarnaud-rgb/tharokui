-- Tharok UI - Barres d'incantation
-- Barres d'incantation Blizzard (joueur, familier, cible, focalisation) :
-- cadre decore remplace par un fond sombre et une bordure fine, icone carree.
-- Le remplissage garde la texture Blizzard, qui change selon le type de sort
-- (normal, canalise, non interruptible). Position et taille de la barre du
-- joueur se reglent dans le mode Edition du jeu.

local T = TharokUI

local Module = T:RegisterModule("CastBars", {
	title = "Barres d'incantation",
})

local skinned = {}

local function SkinCastBar(bar)
	if not bar or skinned[bar] then
		return
	end
	skinned[bar] = true

	-- Blizzard change la texture de ces elements selon le style de la barre,
	-- mais pas leur opacite.
	T:Fade(bar.Border)
	T:Fade(bar.TextBorder)
	T:Fade(bar.Background)
	T:Fade(bar.DropShadow)

	T:FrameBar(bar)
	T:CropIcon(bar.Icon)
	T:StyleFont(bar.Text, nil, "OUTLINE")
	T:StyleFont(bar.CastTimeText, nil, "OUTLINE")
end

function Module:OnEnable()
	SkinCastBar(PlayerCastingBarFrame)
	SkinCastBar(PetCastingBarFrame)
	SkinCastBar(TargetFrame and TargetFrame.spellbar)
	SkinCastBar(FocusFrame and FocusFrame.spellbar)
end
