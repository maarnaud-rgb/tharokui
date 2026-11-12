-- Tharok UI - police unique
-- Remplace la police latine de base du client (Friz Quadrata et Arial Narrow)
-- par Barlow Medium dans toutes les familles de polices listees dans
-- FontList.lua. Tailles, contours et couleurs d'origine sont conserves ; tous
-- les textes qui heritent de ces familles suivent automatiquement.
--
-- Barlow est distribuee sous licence SIL Open Font License (voir
-- Media\Barlow-OFL.txt).

local T = TharokUI

T.media.font = "Interface\\AddOns\\TharokUI\\Media\\Barlow-Medium.ttf"
T.media.fontNarrow = "Interface\\AddOns\\TharokUI\\Media\\BarlowSemiCondensed-Medium.ttf"

local function Replace(names, path)
	for _, name in ipairs(names) do
		local object = _G[name]
		if type(object) == "table" and object.GetFont and object.SetFont then
			pcall(function()
				local _, size, flags = object:GetFont()
				if size and size > 0 then
					object:SetFont(path, size, flags or "")
				end
			end)
		end
	end
end

function T:ApplyFonts()
	if not self.fontFamilies then
		return
	end
	Replace(self.fontFamilies.regular, self.media.font)
	Replace(self.fontFamilies.narrow, self.media.fontNarrow)
end
