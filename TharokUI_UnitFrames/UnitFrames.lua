-- Tharok UI - Cadres d'unite
-- Skin des cadres Blizzard (joueur, cible, focalisation). Toute la logique
-- (vie, ressources, auras, clics) reste celle de Blizzard : on retire le
-- decor, on rend les barres rectangulaires et on les encadre d'un trait fin.
--
-- Regle de securite : on n'ecrit jamais de champ sur les frames Blizzard et
-- on ne les deplace pas. On ne touche qu'a des textures et des polices.

local T = TharokUI

local Module = T:RegisterModule("UnitFrames", {
	title = "Cadres d'unite",
	defaults = {
		classColor = true, -- barre de vie du joueur a la couleur de classe
		flatBars = true, -- barres en aplat (sinon degrade Blizzard)
		hidePortraits = false, -- masque les portraits ronds
	},
})

-------------------------------------------------------------------------------
-- Joueur
-------------------------------------------------------------------------------

local playerHealthBar
local classR, classG, classB

local function ClearPlayerGlow()
	local container = PlayerFrame.PlayerFrameContainer
	local main = PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
	-- Halos de repos et de combat : ils epousent le cadre d'origine, qui
	-- n'est plus affiche. Blizzard remet l'atlas a chaque changement d'art.
	if container.FrameFlash then
		container.FrameFlash:SetTexture(nil)
	end
	if main.StatusTexture then
		main.StatusTexture:SetTexture(nil)
	end
end

local function SkinPlayer()
	local frame = PlayerFrame
	if not frame or not frame.PlayerFrameContainer or not frame.PlayerFrameContent then
		return
	end
	local container = frame.PlayerFrameContainer
	local main = frame.PlayerFrameContent.PlayerFrameContentMain
	local contextual = frame.PlayerFrameContent.PlayerFrameContentContextual
	local healthContainer = main.HealthBarsContainer
	local health = healthContainer.HealthBar
	local mana = main.ManaBarArea.ManaBar

	T:Fade(container.FrameTexture)
	T:Fade(container.AlternatePowerFrameTexture)
	T:Fade(container.VehicleFrameTexture)
	T:Fade(main.LevelBackgroundCircle)
	if contextual then
		T:Fade(contextual.PlayerPortraitCornerIcon)
	end
	if Module.db.hidePortraits then
		T:Fade(container.PlayerPortrait)
	end

	ClearPlayerGlow()
	hooksecurefunc("PlayerFrame_UpdateStatusTextureVisuals", ClearPlayerGlow)
	hooksecurefunc("PlayerFrame_UpdateFlashTextureVisuals", ClearPlayerGlow)

	-- Barres rectangulaires : on retire les masques arrondis.
	T:RemoveMask(health, healthContainer.HealthBarMask)
	T:RemoveMask(healthContainer.PlayerFrameHealthBarAnimatedLoss, healthContainer.HealthBarMask)
	T:RemoveMask(healthContainer.PlayerFrameTempMaxHealthLoss, healthContainer.HealthBarMask)
	T:RemoveMask(mana, mana.ManaBarMask)

	T:FrameBar(health, nil, 3, false)
	T:FrameBar(mana, nil, 3, false)

	T:OutlineFonts(PlayerName, PlayerLevelText, healthContainer.HealthBarText, healthContainer.LeftText,
		healthContainer.RightText, mana.ManaBarText, mana.LeftText, mana.RightText)

	local r, g, b
	if Module.db.classColor then
		local _, classFile = UnitClass("player")
		r, g, b = T:ClassColor(classFile)
	end

	if Module.db.flatBars then
		-- Sans couleur de classe (r = nil), la barre prend le vert adouci.
		T:FlattenHealthBar(health, r, g, b)
		T:FlattenManaBar(mana)
	elseif r then
		classR, classG, classB = r, g, b
		playerHealthBar = health
		-- Variante blanche (colorable) de la texture de vie.
		health:SetStatusBarTexture("UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health-Status")
		health:SetStatusBarColor(classR, classG, classB)
	end
end

-------------------------------------------------------------------------------
-- Cible et focalisation (meme gabarit Blizzard)
-------------------------------------------------------------------------------

local function SkinTargetLike(frame)
	if not frame or not frame.TargetFrameContainer or not frame.TargetFrameContent then
		return
	end
	local container = frame.TargetFrameContainer
	local main = frame.TargetFrameContent.TargetFrameContentMain
	local healthContainer = main.HealthBarsContainer
	local health = healthContainer.HealthBar
	local mana = main.ManaBar

	T:Fade(container.FrameTexture)
	T:Fade(container.Flash)
	T:Fade(container.BossPortraitFrameTexture)
	T:Fade(main.LevelBackgroundCircle)
	if Module.db.hidePortraits then
		T:Fade(container.Portrait)
	end

	T:RemoveMask(health, healthContainer.HealthBarMask)
	T:RemoveMask(healthContainer.TempMaxHealthLoss, healthContainer.HealthBarMask)
	T:RemoveMask(mana, mana.ManaBarMask)

	T:FrameBar(health, nil, 3, false)
	T:FrameBar(mana, nil, 3, false)

	T:OutlineFonts(main.Name, main.LevelText, healthContainer.HealthBarText, healthContainer.LeftText,
		healthContainer.RightText, healthContainer.DeadText, mana.ManaBarText, mana.LeftText, mana.RightText)

	if Module.db.flatBars then
		T:FlattenHealthBar(health)
		T:FlattenManaBar(mana)
		-- Blizzard remet sa texture de vie a chaque changement de cible.
		if frame.UpdateHealthBarVisuals then
			hooksecurefunc(frame, "UpdateHealthBarVisuals", function()
				T:ReflattenHealthBar(health)
			end)
		end
	end
end

-------------------------------------------------------------------------------
-- Cible de la cible (et de la focalisation)
-------------------------------------------------------------------------------

local function SkinTargetOfTarget(frame)
	if not frame or not frame.HealthBar or not frame.ManaBar then
		return
	end
	T:Fade(frame.FrameTexture)
	if Module.db.hidePortraits then
		T:Fade(frame.Portrait)
	end

	T:RemoveMask(frame.HealthBar, frame.HealthBar.HealthBarMask)
	T:RemoveMask(frame.ManaBar, frame.ManaBar.ManaBarMask)

	T:FrameBar(frame.HealthBar, nil, 3, false)
	T:FrameBar(frame.ManaBar, nil, 3, false)

	T:OutlineFonts(frame.Name, frame.HealthBar.DeadText)

	if Module.db.flatBars then
		T:FlattenHealthBar(frame.HealthBar)
		T:FlattenManaBar(frame.ManaBar)
	end
end

-------------------------------------------------------------------------------
-- Familier
-------------------------------------------------------------------------------

local function SkinPet()
	if not PetFrame or not PetFrameHealthBar or not PetFrameManaBar then
		return
	end
	T:Fade(PetFrameTexture)
	T:Fade(PetFrameFlash)
	if Module.db.hidePortraits then
		T:Fade(PetPortrait)
	end

	T:RemoveMask(PetFrameHealthBar, PetFrameHealthBarMask)
	T:RemoveMask(PetFrameManaBar, PetFrameManaBarMask)

	T:FrameBar(PetFrameHealthBar, nil, 3, false)
	T:FrameBar(PetFrameManaBar, nil, 3, false)

	if Module.db.flatBars then
		T:FlattenHealthBar(PetFrameHealthBar)
		T:FlattenManaBar(PetFrameManaBar)
	end

	T:OutlineFonts(PetName, PetFrameHealthBarText, PetFrameHealthBarTextLeft, PetFrameHealthBarTextRight,
		PetFrameManaBarText, PetFrameManaBarTextLeft, PetFrameManaBarTextRight)
end

-------------------------------------------------------------------------------
-- Activation
-------------------------------------------------------------------------------

Module.options = {
	{ type = "toggle", key = "flatBars", label = "Barres en aplat" },
	{ type = "toggle", key = "classColor", label = "Barre de vie du joueur à la couleur de classe" },
	{ type = "toggle", key = "hidePortraits", label = "Masquer les portraits" },
}

function Module:OnEnable()
	SkinPlayer()
	SkinTargetLike(TargetFrame)
	SkinTargetLike(FocusFrame)
	SkinTargetOfTarget(TargetFrame and TargetFrame.totFrame)
	SkinTargetOfTarget(FocusFrame and FocusFrame.totFrame)
	SkinPet()

	if playerHealthBar then
		-- Blizzard repasse la barre en vert a chaque mise a jour.
		hooksecurefunc("UnitFrameHealthBar_Update", function(statusbar)
			if statusbar == playerHealthBar then
				statusbar:SetStatusBarColor(classR, classG, classB)
			end
		end)
	end
end
