-- Tharok UI - menu des parametres
-- Une pastille "T" sur le bord de la minimap ouvre une fenetre qui regroupe
-- les reglages du socle et de tous les modules (/tharok config l'ouvre aussi).
--
-- La fenetre est construite a partir de la liste des modules : un nouveau
-- module y apparait tout seul, avec sa case "Activer" et une case par option
-- booleenne de ses `defaults`. Pour des libelles soignes ou d'autres types de
-- reglages, le module declare `Module.options`, une liste d'entrees :
--
--   { type = "toggle", key = "panels", label = "Panneau de fond" }
--   { type = "range",  key = "size", label = "Taille", min = 50, max = 200,
--     step = 1, suffix = "%", factor = 1 }      -- factor : valeur affichee = valeur stockee x factor
--   { type = "select", key = "mode", label = "Mesure",
--     values = { { "dps", "DPS" }, { "hps", "HPS" } } }
--   { type = "color",  label = "Couleur", get = ..., set = ... }   -- { r, g, b }
--   { type = "action", label = "Remettre a zero", func = function() end }
--   { type = "header", label = "Titre de section" }
--   { type = "note",   text = "Texte d'aide" }   -- ou text = function() return ... end
--
-- Par defaut une entree lit et ecrit Module.db[key] ; `get` et `set(value)`
-- remplacent ce comportement. Sans `live = true`, un changement affiche
-- l'invitation a recharger l'interface.

local T = TharokUI

local WIDTH, HEIGHT = 660, 500
local NAV_WIDTH = 160
local PAD = 12
local TITLE_HEIGHT = 30
local FOOTER_HEIGHT = 36
local ROW_GAP = 6

local window, reloadNotice
local categories = {}
local pages = {}
local navButtons = {}
local currentId

local function Accent()
	return T.colors.accent[1], T.colors.accent[2], T.colors.accent[3]
end

-------------------------------------------------------------------------------
-- Briques de base
-------------------------------------------------------------------------------

local function Text(parent, size, r, g, b)
	local fontString = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	T:StyleFont(fontString, size or 12, "")
	fontString:SetJustifyH("LEFT")
	if r then
		fontString:SetTextColor(r, g, b)
	end
	return fontString
end

local function FlatButton(parent, label, width, onClick)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(width, 22)
	T:CreateBackground(button)
	T:CreateBorder(button)

	local highlight = button:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(unpack(T.colors.highlight))

	local text = Text(button, 12)
	text:SetPoint("CENTER")
	text:SetText(label)
	button.text = text

	button:SetScript("OnClick", onClick)
	return button
end

-- Zone defilante a la molette, sans barre de defilement.
local function ScrollArea(parent, width)
	local scroll = CreateFrame("ScrollFrame", nil, parent)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(width, 1)
	scroll:SetScrollChild(content)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local range = self:GetVerticalScrollRange()
		local target = self:GetVerticalScroll() - delta * 40
		self:SetVerticalScroll(math.max(0, math.min(range, target)))
	end)
	return scroll, content
end

-------------------------------------------------------------------------------
-- Lecture et ecriture d'une entree
-------------------------------------------------------------------------------

local RefreshPage

local function GetValue(entry, module)
	if entry.get then
		return entry.get()
	end
	return module and module.db and module.db[entry.key]
end

local function SetValue(entry, module, value)
	if entry.set then
		entry.set(value)
	elseif module and module.db then
		module.db[entry.key] = value
	end
	if not entry.live and reloadNotice then
		reloadNotice:Show()
	end
end

-------------------------------------------------------------------------------
-- Controles : chacun renvoie une ligne munie de Refresh()
-------------------------------------------------------------------------------

local widgets = {}

function widgets.header(parent, entry)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(28)
	local label = Text(row, 13, Accent())
	label:SetPoint("BOTTOMLEFT", 0, 5)
	label:SetText(entry.label)
	T:CreateAccentLine(row, "BOTTOM")
	return row
end

function widgets.note(parent, entry)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(16)
	local label = Text(row, 11, 0.65, 0.65, 0.65)
	label:SetPoint("LEFT")
	label:SetPoint("RIGHT")
	label:SetWordWrap(false)
	function row.Refresh()
		local text = entry.text
		if type(text) == "function" then
			text = text()
		end
		label:SetText(text or "")
	end
	return row
end

function widgets.toggle(parent, entry, module)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(22)

	local box = CreateFrame("Frame", nil, row)
	box:SetSize(14, 14)
	box:SetPoint("LEFT")
	T:CreateBackground(box)
	T:CreateBorder(box)

	local check = box:CreateTexture(nil, "ARTWORK")
	check:SetPoint("TOPLEFT", 3, -3)
	check:SetPoint("BOTTOMRIGHT", -3, 3)
	check:SetColorTexture(Accent())

	local label = Text(row)
	label:SetPoint("LEFT", box, "RIGHT", 8, 0)
	label:SetText(entry.label)

	function row.Refresh()
		check:SetShown(GetValue(entry, module) and true or false)
	end
	row:SetScript("OnClick", function()
		SetValue(entry, module, not GetValue(entry, module))
		RefreshPage()
	end)
	return row
end

function widgets.range(parent, entry, module)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(38)

	local step = entry.step or 1
	local factor = entry.factor or 1

	local label = Text(row)
	label:SetPoint("TOPLEFT")
	label:SetText(entry.label)

	local valueText = Text(row, 12, Accent())
	valueText:SetPoint("TOPRIGHT")

	local slider = CreateFrame("Slider", nil, row)
	slider:SetPoint("BOTTOMLEFT", 0, 3)
	slider:SetPoint("BOTTOMRIGHT", 0, 3)
	slider:SetHeight(10)
	slider:SetOrientation("HORIZONTAL")
	slider:SetMinMaxValues(entry.min, entry.max)
	slider:SetValueStep(step)
	slider:SetObeyStepOnDrag(true)
	slider:SetThumbTexture(T.media.blank)
	local thumb = slider:GetThumbTexture()
	thumb:SetSize(8, 14)
	thumb:SetVertexColor(Accent())
	T:CreateBackground(slider)
	T:CreateBorder(slider)

	local function Show(value)
		valueText:SetText(format("%d%s", math.floor(value + 0.5), entry.suffix or ""))
	end

	slider:SetScript("OnValueChanged", function(_, value, userInput)
		value = math.floor(value / step + 0.5) * step
		Show(value)
		if userInput then
			SetValue(entry, module, value / factor)
		end
	end)

	function row.Refresh()
		local value = (GetValue(entry, module) or entry.min / factor) * factor
		slider:SetValue(value)
		Show(value)
	end
	return row
end

function widgets.select(parent, entry, module)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(24)

	local label = Text(row)
	label:SetPoint("LEFT")
	label:SetText(entry.label)

	local function IndexOf(value)
		for i, item in ipairs(entry.values) do
			if item[1] == value then
				return i
			end
		end
	end

	local button
	button = FlatButton(row, "", 170, function()
		local index = IndexOf(GetValue(entry, module)) or 0
		local nextItem = entry.values[index % #entry.values + 1]
		SetValue(entry, module, nextItem[1])
		RefreshPage()
	end)
	button:SetPoint("RIGHT")

	function row.Refresh()
		local index = IndexOf(GetValue(entry, module))
		button.text:SetText(index and entry.values[index][2] or "-")
	end
	return row
end

function widgets.action(parent, entry)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(24)
	local button = FlatButton(row, entry.label, 10, function()
		entry.func()
		RefreshPage()
	end)
	button:SetWidth(button.text:GetStringWidth() + 28)
	button:SetPoint("LEFT")
	return row
end

function widgets.color(parent, entry, module)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(24)

	local label = Text(row)
	label:SetPoint("LEFT")
	label:SetText(entry.label)

	local swatch = CreateFrame("Button", nil, row)
	swatch:SetSize(44, 16)
	swatch:SetPoint("RIGHT")
	local fill = swatch:CreateTexture(nil, "ARTWORK")
	fill:SetAllPoints()
	T:CreateBorder(swatch)

	function row.Refresh()
		local color = GetValue(entry, module)
		if type(color) == "table" then
			fill:SetColorTexture(color[1], color[2], color[3], 1)
		end
	end

	swatch:SetScript("OnClick", function()
		local color = GetValue(entry, module)
		if type(color) ~= "table" then
			return
		end
		if not ColorPickerFrame or not ColorPickerFrame.SetupColorPickerAndShow then
			T:Print("selecteur de couleur indisponible ; utilise /tharok theme.")
			return
		end
		local r, g, b = color[1], color[2], color[3]
		ColorPickerFrame:SetupColorPickerAndShow({
			r = r,
			g = g,
			b = b,
			hasOpacity = false,
			swatchFunc = function()
				local nr, ng, nb = ColorPickerFrame:GetColorRGB()
				SetValue(entry, module, { nr, ng, nb })
				row.Refresh()
			end,
			cancelFunc = function()
				SetValue(entry, module, { r, g, b })
				row.Refresh()
			end,
		})
	end)
	return row
end

-------------------------------------------------------------------------------
-- Categories
-------------------------------------------------------------------------------

local function GeneralEntries()
	local theme = T.db.theme
	local function RefreshTheme()
		T.colors.bg[4] = theme.bgAlpha
		T.colors.border = { theme.border[1], theme.border[2], theme.border[3], 1 }
		T:RefreshTheme()
	end

	return {
		{ type = "header", label = "Thème" },
		{
			type = "toggle",
			label = "Accent à la couleur de classe",
			get = function()
				return theme.accent == nil
			end,
			set = function(value)
				if value then
					theme.accent = nil
				else
					theme.accent = { Accent() }
				end
			end,
		},
		{
			type = "color",
			label = "Couleur d'accent personnalisée",
			get = function()
				return theme.accent or T.colors.accent
			end,
			set = function(color)
				theme.accent = color
			end,
		},
		{
			type = "range",
			label = "Opacité des fonds",
			min = 0,
			max = 100,
			suffix = "%",
			factor = 100,
			live = true,
			get = function()
				return theme.bgAlpha
			end,
			set = function(value)
				theme.bgAlpha = value
				RefreshTheme()
			end,
		},
		{
			type = "color",
			label = "Couleur des bordures",
			live = true,
			get = function()
				return theme.border
			end,
			set = function(color)
				theme.border = color
				RefreshTheme()
			end,
		},
		{
			type = "range",
			label = "Dégradé sombre des barres",
			min = 0,
			max = 100,
			suffix = "%",
			factor = 100,
			live = true,
			get = function()
				return theme.shade
			end,
			set = function(value)
				theme.shade = value
				RefreshTheme()
			end,
		},
		{
			type = "toggle",
			label = "Police unique (Barlow)",
			get = function()
				return theme.font
			end,
			set = function(value)
				theme.font = value
			end,
		},

		{ type = "header", label = "Mise à l'échelle" },
		{
			type = "toggle",
			label = "Adapter l'interface à la résolution de l'écran",
			live = true,
			get = function()
				return T.db.scale and T.db.scale.enabled
			end,
			set = function(value)
				T:ScaleCommand({ "scale", value and "on" or "off" })
			end,
		},
		{
			type = "note",
			text = function()
				local resolution = T.db.scale and T.db.scale.resolution
				return "Écran de référence : " .. (resolution or "aucun")
			end,
		},
		{
			type = "action",
			label = "Prendre l'écran actuel comme référence",
			func = function()
				T:ScaleCommand({ "scale", "ref" })
			end,
		},

		{ type = "header", label = "Minimap" },
		{
			type = "toggle",
			label = "Afficher la pastille Tharok UI",
			live = true,
			get = function()
				return not T.db.minimap.hide
			end,
			set = function(value)
				T.db.minimap.hide = not value
				T:UpdateMinimapButton()
			end,
		},
		{ type = "note", text = "Sans la pastille, le menu reste accessible avec /tharok config." },
	}
end

local function ModuleEntries(module)
	local entries = { { type = "toggle", key = "enabled", label = "Activer le module" } }
	local declared = { enabled = true }

	if type(module.options) == "table" then
		for _, entry in ipairs(module.options) do
			entries[#entries + 1] = entry
			if entry.key then
				declared[entry.key] = true
			end
		end
	end

	-- Options booleennes non declarees : une case par option, au nom brut.
	local extra = {}
	for key, value in pairs(module.defaults) do
		if type(value) == "boolean" and not declared[key] then
			extra[#extra + 1] = key
		end
	end
	table.sort(extra)
	for _, key in ipairs(extra) do
		entries[#entries + 1] = { type = "toggle", key = key, label = key }
	end
	return entries
end

local function BuildCategories()
	wipe(categories)
	categories[1] = { id = "general", title = "Général", entries = GeneralEntries }
	for _, name in ipairs(T.moduleOrder) do
		local module = T.modules[name]
		if module.db then
			categories[#categories + 1] = {
				id = "module:" .. name,
				title = module.title,
				module = module,
				entries = function()
					return ModuleEntries(module)
				end,
			}
		end
	end
end

-------------------------------------------------------------------------------
-- Pages
-------------------------------------------------------------------------------

local function BuildPage(category)
	local width = WIDTH - NAV_WIDTH - 3 * PAD
	local scroll, content = ScrollArea(window, width)
	scroll:SetPoint("TOPLEFT", NAV_WIDTH + 2 * PAD, -TITLE_HEIGHT - PAD)
	scroll:SetPoint("BOTTOMRIGHT", -PAD, FOOTER_HEIGHT + PAD)

	local rows = {}
	local y = 0
	for _, entry in ipairs(category.entries()) do
		local factory = widgets[entry.type]
		if factory then
			local row = factory(content, entry, category.module)
			row:SetPoint("TOPLEFT", 0, -y)
			row:SetPoint("TOPRIGHT", 0, -y)
			rows[#rows + 1] = row
			y = y + row:GetHeight() + ROW_GAP
		end
	end
	content:SetHeight(math.max(y, 1))

	scroll.rows = rows
	return scroll
end

function RefreshPage()
	local page = currentId and pages[currentId]
	if not page then
		return
	end
	for _, row in ipairs(page.rows) do
		if row.Refresh then
			row.Refresh()
		end
	end
end

local function Select(category)
	for id, page in pairs(pages) do
		page:SetShown(id == category.id)
	end
	if not pages[category.id] then
		pages[category.id] = BuildPage(category)
	end
	currentId = category.id
	for id, button in pairs(navButtons) do
		button.marker:SetShown(id == category.id)
	end
	RefreshPage()
end

-------------------------------------------------------------------------------
-- Fenetre
-------------------------------------------------------------------------------

local function BuildWindow()
	window = CreateFrame("Frame", "TharokUIOptions", UIParent)
	window:SetSize(WIDTH, HEIGHT)
	window:SetPoint("CENTER")
	window:SetFrameStrata("HIGH")
	window:SetClampedToScreen(true)
	window:SetMovable(true)
	window:EnableMouse(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", window.StartMoving)
	window:SetScript("OnDragStop", window.StopMovingOrSizing)
	window:Hide()
	tinsert(UISpecialFrames, "TharokUIOptions") -- se ferme avec Echap

	T:CreateBackground(window, nil, 0.95)
	T:CreateBorder(window)
	T:CreateAccentLine(window, "TOP", 2)

	local title = Text(window, 14, Accent())
	title:SetPoint("TOPLEFT", PAD, -9)
	title:SetText("Tharok UI")
	local version = Text(window, 11, 0.6, 0.6, 0.6)
	version:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 8, 1)
	version:SetText(T.version)

	local close = FlatButton(window, "X", 22, function()
		window:Hide()
	end)
	close:SetPoint("TOPRIGHT", -6, -6)

	-- Pied : invitation a recharger apres un changement qui le demande.
	local reload = FlatButton(window, "Recharger l'interface", 160, ReloadUI)
	reload:SetPoint("BOTTOMRIGHT", -PAD, 8)
	reloadNotice = Text(window, 11, 1, 0.82, 0)
	reloadNotice:SetPoint("RIGHT", reload, "LEFT", -10, 0)
	reloadNotice:SetText("Certains changements s'appliquent après rechargement.")
	reloadNotice:Hide()

	-- Navigation.
	local navScroll, navContent = ScrollArea(window, NAV_WIDTH)
	navScroll:SetPoint("TOPLEFT", PAD, -TITLE_HEIGHT - PAD)
	navScroll:SetPoint("BOTTOMLEFT", PAD, FOOTER_HEIGHT + PAD)
	navScroll:SetWidth(NAV_WIDTH)

	BuildCategories()
	for i, category in ipairs(categories) do
		local button = CreateFrame("Button", nil, navContent)
		button:SetSize(NAV_WIDTH, 24)
		button:SetPoint("TOPLEFT", 0, -(i - 1) * 25)

		local highlight = button:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetAllPoints()
		highlight:SetColorTexture(unpack(T.colors.highlight))

		local marker = button:CreateTexture(nil, "BACKGROUND")
		marker:SetAllPoints()
		local r, g, b = Accent()
		marker:SetColorTexture(r, g, b, 0.30)
		marker:Hide()
		button.marker = marker

		local label = Text(button, 12)
		label:SetPoint("LEFT", 8, 0)
		label:SetText(category.title)
		-- Module desactive : libelle grise.
		if category.module and not category.module.db.enabled then
			label:SetTextColor(0.55, 0.55, 0.55)
		end

		button:SetScript("OnClick", function()
			Select(category)
		end)
		navButtons[category.id] = button
	end
	navContent:SetHeight(#categories * 25)

	Select(categories[1])
end

function T:ToggleOptions()
	if not T.db then
		return
	end
	if not window then
		BuildWindow()
		window:Show()
		return
	end
	window:SetShown(not window:IsShown())
	if window:IsShown() then
		RefreshPage()
	end
end

-------------------------------------------------------------------------------
-- Pastille de la minimap
-------------------------------------------------------------------------------

local BUTTON_SIZE = 24
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local minimapButton

local function Disc(parent, inset, layer)
	local texture = parent:CreateTexture(nil, layer)
	texture:SetPoint("TOPLEFT", inset, -inset)
	texture:SetPoint("BOTTOMRIGHT", -inset, inset)
	local mask = parent:CreateMaskTexture()
	mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(texture)
	texture:AddMaskTexture(mask)
	return texture
end

local function PlaceMinimapButton()
	local angle = math.rad(T.db.minimap.angle)
	local cos, sin = math.cos(angle), math.sin(angle)
	local halfWidth, halfHeight = Minimap:GetWidth() / 2, Minimap:GetHeight() / 2
	local x, y
	if GetMinimapShape and GetMinimapShape() == "SQUARE" then
		-- Minimap carree : la pastille suit le bord du carre.
		local reach = 1.4143
		x = math.max(-halfWidth, math.min(halfWidth, cos * halfWidth * reach))
		y = math.max(-halfHeight, math.min(halfHeight, sin * halfHeight * reach))
	else
		x, y = cos * (halfWidth + 4), sin * (halfHeight + 4)
	end
	minimapButton:ClearAllPoints()
	minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function DragMinimapButton()
	local centerX, centerY = Minimap:GetCenter()
	local cursorX, cursorY = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	if not centerX or not scale or scale == 0 then
		return
	end
	local angle = math.deg(math.atan2(cursorY / scale - centerY, cursorX / scale - centerX))
	T.db.minimap.angle = angle
	PlaceMinimapButton()
end

local function BuildMinimapButton()
	local button = CreateFrame("Button", "TharokUIMinimapButton", Minimap)
	minimapButton = button
	button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(Minimap:GetFrameLevel() + 10)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")

	-- Anneau a la couleur d'accent, disque sombre, lettre "T".
	local ring = Disc(button, 0, "BACKGROUND")
	ring:SetColorTexture(Accent())
	local fill = Disc(button, 2, "ARTWORK")
	fill:SetColorTexture(0.06, 0.06, 0.07, 1)

	local letter = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	T:StyleFont(letter, 13, "OUTLINE")
	letter:SetPoint("CENTER", 0, 0)
	letter:SetText("T")
	letter:SetTextColor(Accent())

	button:SetScript("OnClick", function()
		T:ToggleOptions()
	end)
	button:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", DragMinimapButton)
	end)
	button:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
	end)
	button:SetScript("OnEnter", function(self)
		fill:SetColorTexture(0.16, 0.16, 0.18, 1)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Tharok UI")
		GameTooltip:AddLine("Clic : ouvrir les paramètres", 1, 1, 1)
		GameTooltip:AddLine("Glisser : déplacer la pastille", 1, 1, 1)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function()
		fill:SetColorTexture(0.06, 0.06, 0.07, 1)
		GameTooltip:Hide()
	end)

	PlaceMinimapButton()
end

function T:UpdateMinimapButton()
	if not Minimap then
		return
	end
	if T.db.minimap.hide then
		if minimapButton then
			minimapButton:Hide()
		end
		return
	end
	if not minimapButton then
		BuildMinimapButton()
	end
	minimapButton:Show()
end

-- Apres le demarrage des modules (le module Minimap decide de la forme).
T:On("PLAYER_LOGIN", function()
	if type(T.db.minimap) ~= "table" then
		T.db.minimap = {}
	end
	if type(T.db.minimap.angle) ~= "number" then
		T.db.minimap.angle = 215
	end
	T:UpdateMinimapButton()
end)
