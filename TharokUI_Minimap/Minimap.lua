-- Tharok UI - Minimap
-- Minimap carree sans decor. Position et taille restent reglees dans le
-- mode Edition du jeu.

local T = TharokUI

local Module = T:RegisterModule("Minimap", {
	title = "Minimap",
	defaults = {
		square = true, -- forme carree (sinon ronde, sans le cadre d'origine)
		flatHeader = true, -- bandeau du nom de zone a plat
	},
})

local function ApplyShape()
	if Module.db.square then
		Minimap:SetMaskTexture(T.media.blank)
	end
	T:Fade(MinimapCompassTexture)
	T:Fade(MinimapCompassTextureUnderlay)
end

local function SkinHeader()
	local button = MinimapCluster.ZoneTextButton
	if not button then
		return
	end
	-- Blizzard reapplique l'atlas a chaque changement d'etat, mais ne touche
	-- pas a l'alpha de cette texture.
	T:Fade(button.StateTexture)
	T:CreateBackground(button)
	T:CreateBorder(button, button, 1, 1)
	T:CreateAccentLine(button, "BOTTOM", 2)
	T:StyleFont(MinimapZoneText, 12, "OUTLINE")
end

Module.options = {
	{ type = "toggle", key = "square", label = "Forme carrée" },
	{ type = "toggle", key = "flatHeader", label = "Bandeau du nom de zone à plat" },
}

function Module:OnEnable()
	if not Minimap or not MinimapCluster then
		return
	end

	ApplyShape()
	-- Blizzard remet son masque rond quand l'option "rotation" change.
	if MinimapCluster.UpdateMinimapConfig then
		hooksecurefunc(MinimapCluster, "UpdateMinimapConfig", ApplyShape)
	end

	if self.db.square then
		T:CreateBorder(Minimap, Minimap, 1, 5)

		-- Les anneaux de zone (quetes, archeologie) sont dessines pour une
		-- carte ronde.
		if Minimap.SetArchBlobRingScalar then
			Minimap:SetArchBlobRingScalar(0)
			Minimap:SetArchBlobRingAlpha(0)
		end
		if Minimap.SetQuestBlobRingScalar then
			Minimap:SetQuestBlobRingScalar(0)
			Minimap:SetQuestBlobRingAlpha(0)
		end

		-- Convention lue par les addons qui posent des boutons autour de la
		-- minimap.
		function GetMinimapShape()
			return "SQUARE"
		end
	end

	if self.db.flatHeader then
		SkinHeader()
	end
end
