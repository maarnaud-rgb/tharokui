-- Tharok UI - Infobulles
-- Remplace le cadre arrondi des infobulles par un fond sombre et une bordure
-- fine. Le contenu des infobulles n'est jamais lu ni modifie.

local T = TharokUI

local Module = T:RegisterModule("Tooltip", {
	title = "Infobulles",
	defaults = {
		flatHealthBar = true, -- barre de vie a plat sous l'infobulle d'unite
	},
})

local TOOLTIP_NAMES = {
	"GameTooltip",
	"ItemRefTooltip",
	"ShoppingTooltip1",
	"ShoppingTooltip2",
}

local skinned = {}

local function SkinTooltip(tooltip, _, embedded)
	if not tooltip or embedded then
		return
	end
	if tooltip.IsForbidden and tooltip:IsForbidden() then
		return
	end
	local nineSlice = tooltip.NineSlice
	if not nineSlice then
		return
	end

	-- Le cadre Blizzard reste en place mais invisible.
	nineSlice:SetAlpha(0)

	if skinned[tooltip] then
		return
	end
	skinned[tooltip] = true

	-- Opacite propre : une infobulle doit rester lisible sur n'importe quel fond.
	T:CreateBackground(tooltip, nil, 0.94)
	T:CreateBorder(tooltip, tooltip, 1, 1)
	T:CreateAccentLine(tooltip, "TOP", 2)
end

Module.options = {
	{ type = "toggle", key = "flatHealthBar", label = "Barre de vie à plat sous l'infobulle d'unité" },
}

function Module:OnEnable()
	for _, name in ipairs(TOOLTIP_NAMES) do
		SkinTooltip(_G[name])
	end

	-- Appele par Blizzard a la creation de chaque infobulle et a chaque
	-- changement de style.
	if SharedTooltip_SetBackdropStyle then
		hooksecurefunc("SharedTooltip_SetBackdropStyle", SkinTooltip)
	end

	if self.db.flatHealthBar and GameTooltipStatusBar then
		GameTooltipStatusBar:SetStatusBarTexture(T.media.blank)
		T:CreateShade(GameTooltipStatusBar)
	end
end
