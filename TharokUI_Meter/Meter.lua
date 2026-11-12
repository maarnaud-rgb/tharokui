-- Tharok UI - Compteur (DPS / HPS)
-- Liste deplacable des joueurs du groupe ou du raid, tries par DPS ou HPS,
-- avec une jauge a la couleur de la classe et le nom du joueur dedans.
--
-- Dans ce client, un addon ne peut pas lire le journal de combat : les
-- chiffres viennent du compteur integre au jeu (C_DamageMeter), qui fournit
-- la liste deja triee. En combat, noms et montants sont des valeurs secretes :
-- on peut les afficher (texte, jauge) mais ni les comparer ni les calculer,
-- d'ou quelques detours ci-dessous.
--
--   /tharok meter dps|hps            ce qui est mesure
--   /tharok meter combat|total       combat en cours, ou cumul depuis le reset
--   /tharok meter reset              remet tout a zero
--   /tharok meter rows <1-40>        nombre de lignes affichees
--   /tharok meter width <120-500>    largeur de la liste
--   /tharok meter locked on|off      verrouille la position
--
-- Les trois boutons de l'en-tete font la meme chose a la souris. La liste se
-- deplace en la faisant glisser.

local T = TharokUI

local Module = T:RegisterModule("Meter", {
	title = "Compteur",
	defaults = {
		mode = "dps", -- "dps" ou "hps"
		segment = "current", -- "current" (combat) ou "overall" (total)
		rows = 10,
		width = 220,
		locked = false,
		pos = { point = "RIGHT", relPoint = "RIGHT", x = -40, y = -120 },
	},
})

local HEADER_HEIGHT = 18
local ROW_HEIGHT = 18
local UPDATE_INTERVAL = 0.5
local FONT_SIZE = TharokUI.fontSizes.small + 1

local frame, header, modeButton, segmentButton
local rows = {}
local dirty = true

local IsSecret = T.IsSecret

-------------------------------------------------------------------------------
-- Donnees
-------------------------------------------------------------------------------

local function MeterType()
	local types = Enum.DamageMeterType
	if Module.db.mode == "hps" then
		return types.Hps
	end
	return types.Dps
end

local function SessionType()
	local types = Enum.DamageMeterSessionType
	if Module.db.segment == "overall" then
		return types.Overall
	end
	return types.Current
end

-- Liste des sources (deja triee par le jeu), ou nil.
local function GetSources()
	local session = C_DamageMeter.GetCombatSessionFromType(SessionType(), MeterType())
	local sources = session and session.combatSources
	if type(sources) ~= "table" or #sources == 0 then
		return nil
	end
	return sources
end

local function FormatNumber(value)
	if IsSecret(value) then
		-- Fonction du jeu : accepte les valeurs secretes.
		return AbbreviateNumbers(value)
	end
	if type(value) ~= "number" then
		return ""
	end
	if value >= 1e6 then
		return format("%.2fM", value / 1e6)
	elseif value >= 1e4 then
		return format("%.1fk", value / 1e3)
	end
	return format("%d", value + 0.5)
end

local function ClassColor(classFilename)
	local r, g, b = T:ClassColor(classFilename)
	if r then
		return r, g, b
	end
	return T.colors.accent[1], T.colors.accent[2], T.colors.accent[3]
end

-------------------------------------------------------------------------------
-- Affichage
-------------------------------------------------------------------------------

local function CreateRow(index)
	local gap = T:Pixel(1, frame)
	local bar = CreateFrame("StatusBar", nil, frame)
	bar:SetHeight(ROW_HEIGHT)
	bar:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -gap - (index - 1) * (ROW_HEIGHT + gap))
	bar:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -gap - (index - 1) * (ROW_HEIGHT + gap))
	bar:SetStatusBarTexture(T.media.blank)
	bar:SetMinMaxValues(0, 1)
	T:CreateShade(bar)

	local value = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	value:SetPoint("RIGHT", -4, 0)
	value:SetJustifyH("RIGHT")
	T:SoftFont(value, FONT_SIZE)

	local name = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	name:SetPoint("LEFT", 4, 0)
	name:SetPoint("RIGHT", value, "LEFT", -6, 0)
	name:SetJustifyH("LEFT")
	name:SetWordWrap(false)
	T:SoftFont(name, FONT_SIZE)

	bar.name, bar.value = name, value
	rows[index] = bar
	return bar
end

-- Un autre module (le tiroir) peut imposer la largeur et la hauteur
-- disponibles : T:SetMeterBox(width, height), ou nil pour revenir aux
-- reglages du compteur.
local box

local function Width()
	return box and box.width or Module.db.width
end

local function MaxRows()
	if box then
		local gap = frame and T:Pixel(1, frame) or 1
		return math.max(1, math.floor((box.height - HEADER_HEIGHT) / (ROW_HEIGHT + gap)))
	end
	return Module.db.rows
end

local function Resize(shown)
	local gap = T:Pixel(1, frame)
	frame:SetSize(Width(), HEADER_HEIGHT + shown * (ROW_HEIGHT + gap))
end

local function Clear()
	for i = 1, #rows do
		rows[i]:Hide()
	end
	Resize(0)
end

-- `clearIfEmpty` : vide la liste s'il n'y a rien a afficher (apres un reset
-- ou un changement de mesure). Sinon on garde le dernier combat a l'ecran.
local function Refresh(clearIfEmpty)
	dirty = false
	local sources = GetSources()
	if not sources then
		if clearIfEmpty then
			Clear()
		end
		return
	end

	-- La liste est triee par ordre decroissant : la premiere source donne le
	-- maximum de la jauge (on ne peut pas comparer des valeurs secretes).
	local maxValue = sources[1].amountPerSecond
	if not IsSecret(maxValue) and (type(maxValue) ~= "number" or maxValue <= 0) then
		maxValue = 1
	end

	local shown = math.min(#sources, MaxRows())
	for i = 1, shown do
		local source = sources[i]
		local row = rows[i] or CreateRow(i)

		local amount = source.amountPerSecond
		row:SetMinMaxValues(0, maxValue)
		row:SetValue(amount)
		row:SetStatusBarColor(ClassColor(source.classFilename))

		local name = source.name
		if not IsSecret(name) and type(name) == "string" then
			name = Ambiguate(name, "short")
		end
		row.name:SetText(name)
		row.value:SetText(FormatNumber(amount))
		row:Show()
	end
	for i = shown + 1, #rows do
		rows[i]:Hide()
	end
	Resize(shown)
end

local function UpdateHeader()
	modeButton.text:SetText(Module.db.mode == "hps" and "HPS" or "DPS")
	segmentButton.text:SetText(Module.db.segment == "overall" and "Total" or "Combat")
end

-------------------------------------------------------------------------------
-- Actions
-------------------------------------------------------------------------------

local function SetMode(mode)
	Module.db.mode = mode
	UpdateHeader()
	Refresh(true)
end

local function SetSegment(segment)
	Module.db.segment = segment
	UpdateHeader()
	Refresh(true)
end

local function Reset()
	C_DamageMeter.ResetAllCombatSessions()
	Clear()
	dirty = true
end

local function ApplyPosition()
	local pos = Module.db.pos
	frame:ClearAllPoints()
	frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
end

-------------------------------------------------------------------------------
-- Construction
-------------------------------------------------------------------------------

local function CreateHeaderButton(label, onClick)
	local button = CreateFrame("Button", nil, header)
	button:SetHeight(HEADER_HEIGHT)

	local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("CENTER")
	T:SoftFont(text, FONT_SIZE, "textDim")
	text:SetText(label)
	button.text = text
	button:SetWidth(52)

	local highlight = button:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(unpack(T.colors.highlight))

	button:SetScript("OnClick", onClick)

	-- Glisser depuis un bouton deplace aussi la liste.
	button:RegisterForDrag("LeftButton")
	button:SetScript("OnDragStart", function()
		frame:GetScript("OnDragStart")(frame)
	end)
	button:SetScript("OnDragStop", function()
		frame:GetScript("OnDragStop")(frame)
	end)
	return button
end

local function Build()
	frame = CreateFrame("Frame", "TharokUIMeter", UIParent)
	frame:SetFrameStrata("LOW")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		if not Module.db.locked then
			self:StartMoving()
		end
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint(1)
		if point then
			local pos = Module.db.pos
			pos.point, pos.relPoint, pos.x, pos.y = point, relPoint, x, y
		end
	end)

	T:CreateSurface(frame, nil, true)
	T:CreateBorder(frame)

	header = CreateFrame("Frame", nil, frame)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header:SetHeight(HEADER_HEIGHT)
	T:CreateAccentLine(header, "BOTTOM")

	modeButton = CreateHeaderButton("DPS", function()
		SetMode(Module.db.mode == "hps" and "dps" or "hps")
	end)
	modeButton:SetPoint("LEFT")
	modeButton:SetWidth(40)
	modeButton.text:SetTextColor(unpack(T.colors.accent))

	local resetButton = CreateHeaderButton("Reset", Reset)
	resetButton:SetPoint("RIGHT")
	resetButton:SetWidth(44)

	segmentButton = CreateHeaderButton("Combat", function()
		SetSegment(Module.db.segment == "overall" and "current" or "overall")
	end)
	segmentButton:SetPoint("RIGHT", resetButton, "LEFT")

	ApplyPosition()
	UpdateHeader()
	Resize(0)

	T:Every(UPDATE_INTERVAL, function()
		if dirty or InCombatLockdown() then
			Refresh()
		end
	end, frame)
end

-------------------------------------------------------------------------------
-- Commande
-------------------------------------------------------------------------------

function Module:OnCommand(args)
	if not frame then
		return false
	end
	local key = args[1] and strlower(args[1])
	if key == "dps" or key == "hps" then
		SetMode(key)
		T:Print("compteur :", strupper(key))
		return true
	elseif key == "combat" or key == "current" then
		SetSegment("current")
		T:Print("compteur : combat en cours")
		return true
	elseif key == "total" or key == "overall" then
		SetSegment("overall")
		T:Print("compteur : total depuis le dernier reset")
		return true
	elseif key == "reset" then
		Reset()
		T:Print("compteur remis a zero.")
		return true
	elseif key == "rows" then
		local count = T.ParseNumber(args[2], 1, 40)
		if not count then
			T:Print("usage : /tharok meter rows <1-40>")
			return true
		end
		self.db.rows = math.floor(count)
		Refresh(true)
		return true
	elseif key == "width" then
		local width = T.ParseNumber(args[2], 120, 500)
		if not width then
			T:Print("usage : /tharok meter width <120-500>")
			return true
		end
		self.db.width = math.floor(width)
		Refresh(true)
		frame:SetWidth(Width())
		return true
	elseif key == "locked" then
		local value = T.ParseBool(args[2])
		if value ~= nil then
			self.db.locked = value
			T:Print("compteur : position", self.db.locked and "verrouillee" or "libre")
			return true
		end
	end
	return false
end

-------------------------------------------------------------------------------
-- Activation
-------------------------------------------------------------------------------

Module.options = {
	{
		type = "select",
		key = "mode",
		label = "Mesure",
		live = true,
		values = { { "dps", "DPS (dégâts par seconde)" }, { "hps", "HPS (soins par seconde)" } },
		set = function(value)
			if frame then
				SetMode(value)
			else
				Module.db.mode = value
			end
		end,
	},
	{
		type = "select",
		key = "segment",
		label = "Période",
		live = true,
		values = { { "current", "Combat en cours" }, { "overall", "Total depuis le reset" } },
		set = function(value)
			if frame then
				SetSegment(value)
			else
				Module.db.segment = value
			end
		end,
	},
	{
		type = "range",
		key = "rows",
		label = "Nombre de lignes",
		min = 1,
		max = 40,
		live = true,
		set = function(value)
			Module.db.rows = value
			if frame then
				Refresh(true)
			end
		end,
	},
	{
		type = "range",
		key = "width",
		label = "Largeur de la liste",
		min = 120,
		max = 500,
		step = 10,
		live = true,
		set = function(value)
			Module.db.width = value
			if frame then
				Refresh(true)
				frame:SetWidth(Width())
			end
		end,
	},
	{ type = "toggle", key = "locked", label = "Verrouiller la position", live = true },
	{
		type = "action",
		label = "Remettre le compteur à zéro",
		func = function()
			if frame then
				Reset()
			end
		end,
	},
}

function T:SetMeterBox(width, height)
	if width and height then
		box = { width = width, height = height }
	else
		box = nil
	end
	if frame then
		Refresh(true)
		frame:SetWidth(Width())
	end
end

function Module:OnEnable()
	if not C_DamageMeter or not C_DamageMeter.GetCombatSessionFromType or not Enum.DamageMeterType then
		T:Print("compteur : ce client ne fournit pas le compteur de degats integre.")
		return
	end

	-- Le jeu ne collecte les chiffres que si son compteur est active.
	if C_DamageMeter.IsDamageMeterAvailable and not C_DamageMeter.IsDamageMeterAvailable() then
		T:AfterCombat(function()
			C_CVar.SetCVar("damageMeterEnabled", "1")
		end)
	end

	Build()

	local function MarkDirty()
		dirty = true
	end
	T:On("DAMAGE_METER_COMBAT_SESSION_UPDATED", MarkDirty)
	T:On("DAMAGE_METER_CURRENT_SESSION_UPDATED", MarkDirty)
	T:On("PLAYER_REGEN_ENABLED", MarkDirty)
	T:On("DAMAGE_METER_RESET", function()
		Clear()
		dirty = true
	end)
end
