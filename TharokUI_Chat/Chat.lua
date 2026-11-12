-- Tharok UI - Chat
-- Onglets sans decor et zone de saisie a plat. Les messages eux-memes ne sont
-- ni lus ni modifies ; le fond des fenetres reste regle dans les options de
-- chat du jeu.

local T = TharokUI

local Module = T:RegisterModule("Chat", {
	title = "Chat",
	defaults = {
		flatTabs = true, -- onglets sans decor
		flatEditBox = true, -- zone de saisie a plat
		panels = true, -- panneau de fond translucide derriere chaque fenetre
	},
})

local TAB_ART = {
	"Left", "Middle", "Right",
	"ActiveLeft", "ActiveMiddle", "ActiveRight",
	"HighlightLeft", "HighlightMiddle", "HighlightRight",
}

local EDITBOX_ART = { "Left", "Mid", "Right", "FocusLeft", "FocusMid", "FocusRight" }

local function ClearTexture(texture)
	if texture and texture.SetTexture then
		texture:SetTexture(nil)
	end
end

local function SkinTab(tab)
	if not tab then
		return
	end
	for _, key in ipairs(TAB_ART) do
		ClearTexture(tab[key])
	end
	local text = tab.Text or (tab.GetFontString and tab:GetFontString())
	T:StyleFont(text, nil, "OUTLINE")
end

local function SkinEditBox(editBox)
	if not editBox then
		return
	end
	local name = editBox:GetName()
	if name then
		for _, suffix in ipairs(EDITBOX_ART) do
			ClearTexture(_G[name .. suffix])
		end
	end
	T:CreateBackground(editBox)
	T:CreateBorder(editBox, editBox, 1, 1)
end

Module.options = {
	{ type = "toggle", key = "flatTabs", label = "Onglets sans décor" },
	{ type = "toggle", key = "flatEditBox", label = "Zone de saisie à plat" },
	{ type = "toggle", key = "panels", label = "Panneau de fond derrière chaque fenêtre" },
}

function Module:OnEnable()
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local frame = _G["ChatFrame" .. i]
		if frame then
			if self.db.panels then
				-- Meme panneau que derriere les barres d'action, avec un trait
				-- d'accent en haut. Le fond propre au chat reste par-dessus.
				T:CreateAccentLine(T:CreatePanel(frame), "TOP", 2)
			end
			if self.db.flatTabs then
				SkinTab(_G["ChatFrame" .. i .. "Tab"])
			end
			if self.db.flatEditBox then
				SkinEditBox(frame.editBox or _G["ChatFrame" .. i .. "EditBox"])
			end
		end
	end
end
