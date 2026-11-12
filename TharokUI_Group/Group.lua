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
		buffs = true, -- buffs des membres, sous leur portrait
		buffsMine = false, -- seulement les buffs que j'ai lances
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

-------------------------------------------------------------------------------
-- Buffs sous les portraits
-------------------------------------------------------------------------------
-- Le jeu n'affiche que les debuffs des membres du groupe. On ajoute une
-- rangee d'icones a nous sous chaque portrait : ce sont nos propres cadres,
-- on peut donc les mettre a jour en combat. Les donnees d'aura peuvent etre
-- secretes : l'icone et le nombre de charges s'affichent tels quels, le
-- balayage de duree seulement quand il est lisible.

local BUFF_SIZE = 16
local BUFF_GAP = 2
local BUFF_MAX = 8

local buffRows = {} -- cadre de membre -> rangee

local function MemberUnit(frame)
	local unit = frame.GetUnit and frame:GetUnit() or frame.unit
	if type(unit) == "string" and not IsSecret(unit) then
		return unit
	end
end

local function BuffFilter()
	return Module.db.buffsMine and "HELPFUL|PLAYER" or "HELPFUL"
end

local function CreateBuffButton(row, index)
	local button = CreateFrame("Frame", nil, row)
	button:SetSize(BUFF_SIZE, BUFF_SIZE)
	button:SetPoint("TOPLEFT", (index - 1) * (BUFF_SIZE + BUFF_GAP), 0)
	button.index = index

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	T:CropIcon(icon)
	button.icon = icon
	T:CreateBorder(button, button, 1, 2)

	local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	cooldown:SetAllPoints()
	cooldown:SetReverse(true)
	cooldown:SetDrawEdge(false)
	cooldown:SetHideCountdownNumbers(true)
	button.cooldown = cooldown

	local count = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	count:SetPoint("BOTTOMRIGHT", 1, 0)
	T:StyleFont(count, 9, "OUTLINE")
	button.count = count

	button:EnableMouse(true)
	button:SetScript("OnEnter", function(self)
		local unit = MemberUnit(row.member)
		if not unit then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
		if pcall(GameTooltip.SetUnitAura, GameTooltip, unit, self.index, BuffFilter()) then
			GameTooltip:Show()
		else
			GameTooltip:Hide()
		end
	end)
	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	return button
end

local function ShowBuff(button, aura)
	button.icon:SetTexture(aura.icon)

	local count = aura.applications
	if IsSecret(count) then
		button.count:SetText(count) -- affichable, pas comparable
	else
		button.count:SetText(count and count > 1 and count or "")
	end

	local duration, expiration = aura.duration, aura.expirationTime
	if
		not IsSecret(duration)
		and not IsSecret(expiration)
		and type(duration) == "number"
		and type(expiration) == "number"
		and duration > 0
	then
		button.cooldown:SetCooldown(expiration - duration, duration)
	else
		button.cooldown:Clear()
	end
	button:Show()
end

local function UpdateBuffs(frame)
	local row = buffRows[frame]
	if not row then
		return
	end
	local unit = MemberUnit(frame)
	local shown = 0
	if unit and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		local filter = BuffFilter()
		for i = 1, BUFF_MAX do
			local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
			if not ok or type(aura) ~= "table" then
				break
			end
			local button = row.buttons[i] or CreateBuffButton(row, i)
			row.buttons[i] = button
			ShowBuff(button, aura)
			shown = i
		end
	end
	for i = shown + 1, #row.buttons do
		row.buttons[i]:Hide()
	end
end

local function UpdateAllBuffs()
	for frame in pairs(buffRows) do
		UpdateBuffs(frame)
	end
end

local function AddBuffRow(frame)
	local row = CreateFrame("Frame", nil, frame)
	row:SetSize(BUFF_MAX * (BUFF_SIZE + BUFF_GAP), BUFF_SIZE)
	local anchor = frame.Portrait or frame
	row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -3)
	row:SetFrameLevel(frame:GetFrameLevel() + 5)
	row.member = frame
	row.buttons = {}
	buffRows[frame] = row
	UpdateBuffs(frame)
end

local function SkinMember(frame)
	if skinned[frame] then
		return
	end
	skinned[frame] = true

	if Module.db.buffs then
		AddBuffRow(frame)
	end

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
	{ type = "toggle", key = "buffs", label = "Buffs des membres sous leur portrait" },
	{ type = "toggle", key = "buffsMine", label = "Seulement mes buffs" },
}

function Module:OnEnable()
	if not PartyFrame then
		return
	end
	SkinAll()
	-- Les cadres des membres sont (re)pris dans un pool a chaque affichage.
	if PartyFrame.InitializePartyMemberFrames then
		hooksecurefunc(PartyFrame, "InitializePartyMemberFrames", function()
			SkinAll()
			UpdateAllBuffs()
		end)
	end

	if self.db.buffs then
		-- Une mise a jour par rafale d'auras ; le groupe qui change redistribue
		-- les unites entre les cadres.
		local Queue = T:Debounce(UpdateAllBuffs, 0)
		T:OnUnit("UNIT_AURA", Queue, "party1", "party2", "party3", "party4")
		T:On("GROUP_ROSTER_UPDATE", Queue)
		T:On("PLAYER_ENTERING_WORLD", Queue)
	end
end
