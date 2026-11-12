-- Tharok UI - Barres de nom
-- Style plat et net sur les barres de nom Blizzard : barre de vie en aplat
-- aux coins carres, leger degrade, fond sombre, bordure d'un pixel decollee
-- du contenu (elle passe en blanc sur la cible), barre d'incantation encadree
-- avec icone carree.
--
-- On ne lit aucune valeur d'unite (elles sont secretes en combat) : on ne
-- change que des textures et des ancrages de textures, apres que Blizzard a
-- applique son propre style. Taille des barres et informations affichees se
-- reglent toujours dans les options du jeu.

local T = TharokUI

local Module = T:RegisterModule("Nameplates", {
	title = "Barres de nom",
	defaults = {
		flatBars = true, -- barre de vie en aplat (sinon texture Blizzard)
	},
})

local skinned = {} -- unitFrame -> bordure de sa barre de vie

-- La surbrillance de cible de Blizzard (arrondie) est rendue invisible ;
-- notre bordure passe en blanc quand elle est affichee.
local function SyncSelection(unitFrame)
	local border = skinned[unitFrame]
	local container = unitFrame.HealthBarsContainer
	local selected = container and container.healthBar and container.healthBar.selectedBorder
	if not border or border == true then
		return
	end
	if selected and selected:IsShown() then
		border:Paint(1, 1, 1, 1)
	else
		local r, g, b = unpack(T.colors.border)
		border:Paint(r, g, b, 1)
	end
end

-- Reapplique ce que Blizzard reinitialise dans UpdateAnchors() et
-- ApplyFrameOptions().
local function Restyle(unitFrame)
	local container = unitFrame.HealthBarsContainer
	local healthBar = container and container.healthBar
	if not healthBar then
		return
	end

	if Module.db.flatBars and healthBar.barTexture then
		healthBar.barTexture:SetTexture(T:BarTexture())
	end

	-- Fond Blizzard (avec ombre asymetrique) remplace par le notre.
	T:Fade(healthBar.bgTexture)

	T:Fade(healthBar.selectedBorder)
	SyncSelection(unitFrame)
end

local function SkinCastBar(castBar)
	if not castBar then
		return
	end
	T:SquareBar(castBar)
	T:FrameBar(castBar)
	T:CropIcon(castBar.Icon)
end

local function SkinUnitFrame(unitFrame)
	local container = unitFrame.HealthBarsContainer
	local healthBar = container and container.healthBar
	if not healthBar or skinned[unitFrame] then
		return
	end
	skinned[unitFrame] = T:FrameBar(healthBar, healthBar.barTexture)
	T:SquareBar(healthBar)

	local selected = healthBar.selectedBorder
	if selected then
		local function Sync()
			SyncSelection(unitFrame)
		end
		hooksecurefunc(selected, "Show", Sync)
		hooksecurefunc(selected, "Hide", Sync)
		hooksecurefunc(selected, "SetShown", Sync)
	end

	local castContainer = unitFrame.CastBarsContainer
	SkinCastBar(castContainer and castContainer.castBar)

	Restyle(unitFrame)
	if unitFrame.UpdateAnchors then
		hooksecurefunc(unitFrame, "UpdateAnchors", Restyle)
	end
	if unitFrame.ApplyFrameOptions then
		hooksecurefunc(unitFrame, "ApplyFrameOptions", Restyle)
	end
end

local function SkinNamePlate(unit)
	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	if not plate or (plate.IsForbidden and plate:IsForbidden()) then
		return
	end
	if plate.UnitFrame then
		SkinUnitFrame(plate.UnitFrame)
	end
end

Module.options = {
	{ type = "toggle", key = "flatBars", label = "Barre de vie en aplat" },
	{ type = "note", text = "Taille des barres et informations affichées : options du jeu." },
}

function Module:OnEnable()
	if not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then
		return
	end
	T:On("NAME_PLATE_UNIT_ADDED", function(_, unit)
		if type(unit) == "string" and strfind(unit, "^nameplate%d+$") then
			SkinNamePlate(unit)
		end
	end)
end
