-- Tharok UI - Auras
-- Buffs et debuffs du joueur : icones carrees a bordure fine, duree affichee
-- dans l'icone. Position, taille des icones, sens de remplissage et nombre
-- par ligne se reglent dans le mode Edition du jeu (cadres "Buffs" et
-- "Debuffs", deplacables separement).
--
-- Les auras de la cible ne sont pas touchees : dans ce client, leurs boutons
-- sont des objets interdits aux addons.

local T = TharokUI

local Module = T:RegisterModule("Auras", {
	title = "Auras",
	defaults = {
		durationInside = true, -- duree dans l'icone plutot que dessous
		containers = true, -- conteneur bleu (buffs) et rouge (debuffs)
	},
})

local skinned = {}

local function SkinAura(aura)
	local icon, duration = aura.Icon, aura.Duration
	-- Les ancres d'auras privees n'ont ni texture d'icone ni texte de duree.
	if not icon or not icon.SetTexCoord or not duration or not duration.SetFont then
		return false
	end
	if not skinned[aura] then
		skinned[aura] = true
		T:CropIcon(icon)
		T:CreateBorder(aura, icon, 1, 1)
		T:StyleFont(duration, 10, "OUTLINE")
		T:StyleFont(aura.Count, 11, "OUTLINE")
		-- La duree partage la couche de l'icone : on la passe au-dessus.
		duration:SetDrawLayer("OVERLAY")
	end
	return true
end

-- Blizzard replace le texte de duree sous l'icone a chaque mise en page.
local function OnLayout(_, auras)
	if type(auras) ~= "table" then
		return
	end
	for _, aura in ipairs(auras) do
		if SkinAura(aura) and Module.db.durationInside then
			aura.Duration:ClearAllPoints()
			aura.Duration:SetPoint("BOTTOM", aura.Icon, "BOTTOM", 0, 1)
		end
	end
end

local function SetupFrame(frame)
	if not frame or not frame.AuraContainer or not frame.auraFrames then
		return
	end
	OnLayout(frame.AuraContainer, frame.auraFrames)
	hooksecurefunc(frame.AuraContainer, "UpdateGridLayout", OnLayout)
end

-------------------------------------------------------------------------------
-- Conteneurs teintes
-------------------------------------------------------------------------------
-- Un cadre translucide (bleu pour les buffs, rouge pour les debuffs) qui
-- epouse les icones actuellement affichees. Le cadre Blizzard, lui, reserve
-- la place de toutes les icones possibles : on ne peut pas le teinter tel
-- quel sans obtenir un grand rectangle vide.

local PADDING = 4
local UPDATE_INTERVAL = 0.2

local IsSecret = T.IsSecret

-- Rectangle englobant des icones visibles, en coordonnees de UIParent.
local function VisibleBounds(frame)
	local uiScale = UIParent:GetEffectiveScale()
	local left, bottom, right, top
	for _, aura in ipairs(frame.auraFrames) do
		local icon = aura.Icon
		if icon and icon.SetTexCoord then
			local visible = aura:IsVisible()
			if IsSecret(visible) then
				return nil, true
			end
			if visible then
				local l, b, w, h = icon:GetScaledRect()
				if IsSecret(l) then
					return nil, true
				end
				if l and w and w > 0 then
					l, b, w, h = l / uiScale, b / uiScale, w / uiScale, h / uiScale
					left = left and math.min(left, l) or l
					bottom = bottom and math.min(bottom, b) or b
					right = right and math.max(right, l + w) or (l + w)
					top = top and math.max(top, b + h) or (b + h)
				end
			end
		end
	end
	if not left then
		return nil, false
	end
	return left, bottom, right, top
end

local function UpdateBox(box)
	local left, bottom, right, top = VisibleBounds(box.source)
	if not left then
		-- bottom vaut true quand les valeurs sont secretes : on ne change rien.
		if bottom ~= true then
			box:Hide()
		end
		return
	end
	if left ~= box.left or bottom ~= box.bottom or right ~= box.right or top ~= box.top then
		box.left, box.bottom, box.right, box.top = left, bottom, right, top
		box:ClearAllPoints()
		box:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left - PADDING, bottom - PADDING)
		box:SetSize(right - left + 2 * PADDING, top - bottom + 2 * PADDING)
	end
	box:Show()
end

local boxes = {}

local function CreateBox(source, r, g, b)
	if not source or not source.auraFrames then
		return
	end
	local box = CreateFrame("Frame", nil, UIParent)
	box:SetFrameStrata("BACKGROUND")
	box:Hide()
	box.source = source

	local fill = box:CreateTexture(nil, "BACKGROUND")
	fill:SetAllPoints()
	fill:SetColorTexture(r, g, b, 0.16)

	local border = T:CreateBorder(box, box, 1, 1)
	border:SetColor(r, g, b, 0.55)

	boxes[#boxes + 1] = box
end

-- Le suivi tourne sur une seule frame toujours visible, a faible cadence.
local function StartBoxDriver()
	if #boxes == 0 then
		return
	end
	T:Every(UPDATE_INTERVAL, function()
		for i = 1, #boxes do
			pcall(UpdateBox, boxes[i])
		end
	end)
end

Module.options = {
	{ type = "toggle", key = "durationInside", label = "Durée affichée dans l'icône" },
	{ type = "toggle", key = "containers", label = "Conteneurs colorés (buffs en bleu, débuffs en rouge)" },
}

function Module:OnEnable()
	SetupFrame(BuffFrame)
	SetupFrame(DebuffFrame)

	if self.db.containers then
		CreateBox(BuffFrame, 0.25, 0.55, 1.00)
		CreateBox(DebuffFrame, 1.00, 0.25, 0.25)
		StartBoxDriver()
	end
end
