-- Tharok UI - Sacs
-- Skin des sacs Blizzard : fond sombre, bordure fine, emplacements carres.
-- On ne touche qu'a des textures : les boutons d'objets sont securises
-- (utiliser un objet est une action protegee).

local T = TharokUI

local Module = T:RegisterModule("Bags", {
	title = "Sacs",
})

local skinnedFrames = {}
local skinnedButtons = {}

local function SkinItemButton(button)
	if skinnedButtons[button] then
		return
	end
	skinnedButtons[button] = true

	T:CropIcon(button.icon)
	if button.GetNormalTexture then
		T:Fade(button:GetNormalTexture())
	end
	T:CreateBackground(button)
	T:CreateBorder(button, button, 1, 1)
	T:StyleFont(button.Count, nil, "OUTLINE")
end

local function SkinItems(frame)
	if not frame.EnumerateValidItems then
		return
	end
	-- Tant qu'un sac n'a pas ete ouvert, ses boutons n'existent pas encore :
	-- l'iterateur renvoie alors un index sans bouton.
	for _, button in frame:EnumerateValidItems() do
		if button then
			SkinItemButton(button)
		end
	end
end

local function SkinFrame(frame)
	if not frame or skinnedFrames[frame] then
		return
	end
	skinnedFrames[frame] = true

	T:Fade(frame.NineSlice)
	T:Fade(frame.Bg)
	T:CreateBackground(frame)
	T:CreateBorder(frame, frame, 1, 1)

	SkinItems(frame)
	-- Les boutons sont (re)attribues a chaque mise a jour du sac.
	if frame.UpdateItems then
		hooksecurefunc(frame, "UpdateItems", SkinItems)
	end
	if frame.Update then
		hooksecurefunc(frame, "Update", SkinItems)
	end
end

-- Boutons de la barre des sacs (sac a dos et sacs equipes).
local BAG_BAR_BUTTONS = {
	"MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot",
	"CharacterBag3Slot", "CharacterReagentBag0Slot",
}

function Module:OnEnable()
	for _, name in ipairs(BAG_BAR_BUTTONS) do
		local button = _G[name]
		if button then
			SkinItemButton(button)
		end
	end
	if ContainerFrameUtil_EnumerateContainerFrames then
		for _, frame in ContainerFrameUtil_EnumerateContainerFrames() do
			SkinFrame(frame)
		end
	end
	SkinFrame(ContainerFrameCombinedBags)
end
