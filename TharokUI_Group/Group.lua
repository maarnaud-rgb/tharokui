-- Tharok UI - Groupe
-- Cadres de groupe Blizzard, dans le meme style que la cible : decor retire,
-- barres rectangulaires encadrees.
--
-- Position et taille se reglent dans le mode Edition du jeu : le cadre
-- "Groupe" s'y deplace librement (par defaut il est ancre au gestionnaire de
-- raid, d'ou sa position collee aux symboles) et dispose d'un reglage de
-- taille.

local T = TharokUI

local Module = T:RegisterModule("Group", {
	title = "Groupe",
	defaults = {
		hidePortraits = false, -- masque les portraits ronds
		flatBars = true, -- barres en aplat (sinon degrade Blizzard)
		classColor = true, -- barre de vie a la couleur de classe (avec flatBars)
	},
})

local skinned = {}

local IsSecret = T.IsSecret

-- Couleur de classe du membre affiche par `frame`, ou nil (deconnecte, classe
-- illisible) pour laisser la couleur par defaut.
local function MemberClassColor(frame)
	local unit = frame.GetUnit and frame:GetUnit() or frame.unit
	if type(unit) ~= "string" then
		return
	end
	local connected = UnitIsConnected(unit)
	if IsSecret(connected) or not connected then
		return
	end
	local _, classFile = UnitClass(unit)
	return T:ClassColor(classFile)
end

local function SkinMember(frame)
	if skinned[frame] then
		return
	end
	skinned[frame] = true

	T:Fade(frame.Texture)
	T:Fade(frame.VehicleTexture)
	T:Fade(frame.Flash)
	if Module.db.hidePortraits then
		T:Fade(frame.Portrait)
	end

	local healthContainer = frame.HealthBarContainer
	local health = healthContainer and healthContainer.HealthBar
	local mana = frame.ManaBar

	if health then
		T:RemoveMask(health, healthContainer.HealthBarMask)
		T:RemoveMask(healthContainer.TempMaxHealthLoss, healthContainer.HealthBarMask)
		T:FrameBar(health, nil, 3, false)
		T:OutlineFonts(healthContainer.CenterText, healthContainer.LeftText, healthContainer.RightText)
	end
	if mana then
		T:RemoveMask(mana, mana.ManaBarMask)
		T:FrameBar(mana, nil, 3, false)
		T:OutlineFonts(mana.CenterText, mana.LeftText, mana.RightText)
	end
	T:StyleFont(frame.Name, nil, "OUTLINE")

	if Module.db.flatBars then
		if Module.db.classColor then
			T:FlattenHealthBar(health, function()
				return MemberClassColor(frame)
			end)
		else
			T:FlattenHealthBar(health)
		end
		T:FlattenManaBar(mana)
		-- Blizzard remet sa texture de vie quand l'art du cadre change
		-- (vehicule, changement de membre).
		if health and frame.UpdateArt then
			hooksecurefunc(frame, "UpdateArt", function()
				T:ReflattenHealthBar(health)
			end)
		end
	end
end

local function SkinAll()
	local pool = PartyFrame and PartyFrame.PartyMemberFramePool
	if not pool then
		return
	end
	for frame in pool:EnumerateActive() do
		SkinMember(frame)
	end
end

Module.options = {
	{ type = "toggle", key = "flatBars", label = "Barres en aplat" },
	{ type = "toggle", key = "classColor", label = "Barre de vie à la couleur de classe (avec les barres en aplat)" },
	{ type = "toggle", key = "hidePortraits", label = "Masquer les portraits" },
}

function Module:OnEnable()
	if not PartyFrame then
		return
	end
	SkinAll()
	-- Les cadres des membres sont (re)pris dans un pool a chaque affichage.
	if PartyFrame.InitializePartyMemberFrames then
		hooksecurefunc(PartyFrame, "InitializePartyMemberFrames", SkinAll)
	end
end
