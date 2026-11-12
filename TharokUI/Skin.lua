-- Tharok UI - outils de skin partages par les modules

local T = TharokUI

-------------------------------------------------------------------------------
-- Pixel perfect
-------------------------------------------------------------------------------

-- Taille, dans le repere de `frame`, de `n` pixels physiques de l'ecran.
function T:Pixel(n, frame)
	local _, physicalHeight = GetPhysicalScreenSize()
	local scale = (frame or UIParent):GetEffectiveScale()
	if not physicalHeight or physicalHeight == 0 or not scale or scale == 0 then
		return n
	end
	return n * (768 / physicalHeight) / scale
end

-- Les bordures deja creees sont redimensionnees quand l'echelle change.
local borders = {}

local function LayoutBorder(border)
	local size = T:Pixel(border.thickness, border)

	-- Bordure decollee du contenu : elle entoure `anchor` a l'exterieur, en
	-- laissant `padding` pixels de fond entre le trait et le contenu.
	if border.padding then
		local outset = T:Pixel(border.thickness + border.padding, border)
		border:ClearAllPoints()
		border:SetPoint("TOPLEFT", border.anchor, "TOPLEFT", -outset, outset)
		border:SetPoint("BOTTOMRIGHT", border.anchor, "BOTTOMRIGHT", outset, -outset)
	end
	local top, bottom, left, right = border.top, border.bottom, border.left, border.right

	top:ClearAllPoints()
	top:SetPoint("TOPLEFT")
	top:SetPoint("TOPRIGHT")
	top:SetHeight(size)

	bottom:ClearAllPoints()
	bottom:SetPoint("BOTTOMLEFT")
	bottom:SetPoint("BOTTOMRIGHT")
	bottom:SetHeight(size)

	left:ClearAllPoints()
	left:SetPoint("TOPLEFT")
	left:SetPoint("BOTTOMLEFT")
	left:SetWidth(size)

	right:ClearAllPoints()
	right:SetPoint("TOPRIGHT")
	right:SetPoint("BOTTOMRIGHT")
	right:SetWidth(size)
end

local function RelayoutBorders()
	for i = 1, #borders do
		LayoutBorder(borders[i])
	end
end

T.RelayoutBorders = RelayoutBorders
T:On("UI_SCALE_CHANGED", RelayoutBorders)
T:On("DISPLAY_SIZE_CHANGED", RelayoutBorders)

-- Cree un cadre fin (bordure de `thickness` pixels physiques) autour de
-- `anchor` (par defaut `parent`). Renvoie la frame qui porte la bordure.
-- Avec `padding`, la bordure est posee a l'exterieur de `anchor`, a `padding`
-- pixels du contenu ; ancre alors le fond sur la frame renvoyee.
function T:CreateBorder(parent, anchor, thickness, levelOffset, padding)
	local border = CreateFrame("Frame", nil, parent)
	border:SetAllPoints(anchor or parent)
	border:SetFrameLevel(parent:GetFrameLevel() + (levelOffset or 1))
	border.thickness = thickness or 1
	border.anchor = anchor or parent
	border.padding = padding

	local r, g, b, a = unpack(T.colors.border)
	for _, key in ipairs({ "top", "bottom", "left", "right" }) do
		local edge = border:CreateTexture(nil, "OVERLAY")
		edge:SetColorTexture(r, g, b, a)
		border[key] = edge
	end

	function border:Paint(red, green, blue, alpha)
		self.top:SetColorTexture(red, green, blue, alpha or 1)
		self.bottom:SetColorTexture(red, green, blue, alpha or 1)
		self.left:SetColorTexture(red, green, blue, alpha or 1)
		self.right:SetColorTexture(red, green, blue, alpha or 1)
	end

	-- Couleur propre a cette bordure : elle ne suivra plus le theme.
	function border:SetColor(red, green, blue, alpha)
		self.customColor = true
		self:Paint(red, green, blue, alpha)
	end

	LayoutBorder(border)
	borders[#borders + 1] = border
	return border
end

-- Fond uni sombre derriere `anchor` (par defaut `parent`). `alpha` force une
-- opacite propre a ce fond ; sinon il suit l'opacite du theme.
local backgrounds = {}

function T:CreateBackground(parent, anchor, alpha)
	local bg = parent:CreateTexture(nil, "BACKGROUND", nil, -8)
	bg:SetAllPoints(anchor or parent)
	local r, g, b, a = unpack(T.colors.bg)
	bg:SetColorTexture(r, g, b, alpha or a)
	if not alpha then
		backgrounds[#backgrounds + 1] = bg
	end
	return bg
end

-- Trait fin a la couleur d'accent, le long d'un bord de `parent`
-- ("TOP" ou "BOTTOM").
function T:CreateAccentLine(parent, edge, thickness)
	local line = parent:CreateTexture(nil, "OVERLAY")
	local r, g, b = unpack(T.colors.accent)
	line:SetColorTexture(r, g, b, 0.9)
	line:SetPoint(edge .. "LEFT", parent, edge .. "LEFT", 0, 0)
	line:SetPoint(edge .. "RIGHT", parent, edge .. "RIGHT", 0, 0)
	line:SetHeight(T:Pixel(thickness or 1, parent))
	return line
end

-- Leger degrade vers le sombre, du haut vers le bas, pose par-dessus le
-- remplissage d'une barre (`fill` : texture de remplissage, par defaut celle
-- de la StatusBar). L'intensite suit le theme (/tharok theme shade).
local shades = {}

local function PaintShade(shade)
	local alpha = (T.db and T.db.theme and T.db.theme.shade) or 0.35
	shade:SetGradient("VERTICAL", CreateColor(0, 0, 0, alpha), CreateColor(0, 0, 0, 0))
end

function T:CreateShade(bar, fill)
	if not bar or not bar.CreateTexture then
		return
	end
	fill = fill or (bar.GetStatusBarTexture and bar:GetStatusBarTexture())
	local shade = bar:CreateTexture(nil, "ARTWORK", nil, 7)
	shade:SetAllPoints(fill or bar)
	shade:SetTexture(T.media.blank)
	PaintShade(shade)
	shades[#shades + 1] = shade
	return shade
end

-- Retire les masques (coins arrondis) poses sur une texture.
function T:RemoveMasks(texture)
	if not texture or not texture.GetNumMaskTextures or not texture.RemoveMaskTexture then
		return
	end
	for i = texture:GetNumMaskTextures(), 1, -1 do
		local mask = texture:GetMaskTexture(i)
		if mask then
			texture:RemoveMaskTexture(mask)
		end
	end
end

-- Retire d'une barre un masque precis (coins arrondis des cadres d'unite).
function T:RemoveMask(bar, mask)
	if not bar or not mask or not bar.GetStatusBarTexture then
		return
	end
	local texture = bar:GetStatusBarTexture()
	if texture and texture.RemoveMaskTexture then
		texture:RemoveMaskTexture(mask)
	end
end

-- Coins carres : retire tous les masques de toutes les textures d'une barre.
function T:SquareBar(bar)
	if not bar or not bar.GetRegions then
		return
	end
	for _, region in ipairs({ bar:GetRegions() }) do
		if region.IsObjectType and region:IsObjectType("Texture") then
			T:RemoveMasks(region)
		end
	end
end

-- Habillage complet d'une barre : fond sombre, bordure fine, degrade. Par
-- defaut la bordure est decollee d'un pixel du contenu (`padding`) ; avec
-- `padding = false` elle reste dans les limites de la barre, pour des barres
-- empilees (vie et ressource). Renvoie la bordure.
function T:FrameBar(bar, fill, levelOffset, padding)
	if not bar then
		return
	end
	if padding == nil then
		padding = 1
	end
	local border = T:CreateBorder(bar, bar, 1, levelOffset or 1, padding or nil)
	T:CreateBackground(bar, padding and border or bar)
	T:CreateShade(bar, fill)
	return border
end

-- Panneau translucide derriere `frame`, legerement plus grand qu'elle. Il lui
-- appartient : il suit sa position et sa visibilite. Renvoie le panneau.
function T:CreatePanel(frame, padding, alpha)
	padding = padding or 4
	local holder = CreateFrame("Frame", nil, frame)
	holder:SetPoint("TOPLEFT", frame, "TOPLEFT", -padding, padding)
	holder:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", padding, -padding)
	holder:SetFrameLevel(math.max(frame:GetFrameLevel() - 1, 0))
	T:CreateBackground(holder, nil, alpha or 0.45)
	T:CreateBorder(holder, holder, 1, 0)
	return holder
end

-- Reapplique en direct l'opacite des fonds et la couleur des bordures apres
-- un changement de theme.
function T:RefreshTheme()
	for i = 1, #shades do
		PaintShade(shades[i])
	end
	local r, g, b, a = unpack(T.colors.bg)
	for i = 1, #backgrounds do
		backgrounds[i]:SetColorTexture(r, g, b, a)
	end
	local br, bgc, bb = unpack(T.colors.border)
	for i = 1, #borders do
		if not borders[i].customColor then
			borders[i]:Paint(br, bgc, bb, 1)
		end
	end
end

-------------------------------------------------------------------------------
-- Barres en aplat
-------------------------------------------------------------------------------
-- Les barres de vie et de ressource des cadres d'unite Blizzard utilisent des
-- textures a degrade dont la couleur est peinte dans l'image. En aplat, on
-- pose une texture blanche et on la colore nous-memes, apres chaque mise a
-- jour de Blizzard.

local SOFT_GREEN = { 0.27, 0.78, 0.32 }
local POWER_COLORS = {
	MANA = { 0.30, 0.55, 1.00 },
}

local flatHealth = {}
local flatMana = {}
local healthHooked, manaHooked = false, false

local IsSecret = T.IsSecret

local function ColorHealth(bar)
	local color = flatHealth[bar]
	if not color then
		return
	end
	if type(color) == "function" then
		-- Couleur calculee a chaque mise a jour (couleur de classe d'un membre
		-- du groupe, par exemple). Sans resultat, on retombe sur le vert.
		local r, g, b = color(bar)
		if r then
			bar:SetStatusBarColor(r, g, b)
			return
		end
	elseif color ~= true then
		bar:SetStatusBarColor(color[1], color[2], color[3])
		return
	end
	-- Blizzard met un vert pur (0, 1, 0) ; les autres couleurs (gris pour un
	-- joueur deconnecte, par exemple) sont laissees telles quelles.
	local r, g, b = bar:GetStatusBarColor()
	if r == 0 and g == 1 and b == 0 then
		bar:SetStatusBarColor(SOFT_GREEN[1], SOFT_GREEN[2], SOFT_GREEN[3])
	end
end

local function ColorMana(bar)
	if not flatMana[bar] then
		return
	end
	local unit = bar.unit
	if not unit then
		return
	end
	local powerType, powerToken = UnitPowerType(unit)
	if IsSecret(powerType) or IsSecret(powerToken) then
		return -- type de ressource illisible : on garde la texture Blizzard
	end
	local r, g, b
	local color = POWER_COLORS[powerToken]
	if color then
		r, g, b = color[1], color[2], color[3]
	else
		local info = PowerBarColor and (PowerBarColor[powerToken] or PowerBarColor[powerType])
		if not info or not info.r then
			return
		end
		r, g, b = info.r, info.g, info.b
	end
	bar:SetStatusBarTexture(T.media.blank)
	bar:SetStatusBarColor(r, g, b)
end

-- Passe une barre de vie en aplat. `r, g, b` impose une couleur (couleur de
-- classe du joueur, par exemple) ; `r` peut aussi etre une fonction
-- (bar) -> r, g, b appelee a chaque mise a jour ; sinon vert adouci.
function T:FlattenHealthBar(bar, r, g, b)
	if not bar or not bar.SetStatusBarTexture then
		return
	end
	if type(r) == "function" then
		flatHealth[bar] = r
	else
		flatHealth[bar] = r and { r, g, b } or true
	end
	bar:SetStatusBarTexture(T.media.blank)
	ColorHealth(bar)
	if not healthHooked and UnitFrameHealthBar_Update then
		healthHooked = true
		hooksecurefunc("UnitFrameHealthBar_Update", ColorHealth)
	end
end

-- A rappeler quand Blizzard a remis sa propre texture sur une barre de vie.
function T:ReflattenHealthBar(bar)
	if bar and flatHealth[bar] then
		bar:SetStatusBarTexture(T.media.blank)
		ColorHealth(bar)
	end
end

-- Passe une barre de ressource en aplat, coloree selon le type de ressource.
function T:FlattenManaBar(bar)
	if not bar or not bar.SetStatusBarTexture then
		return
	end
	flatMana[bar] = true
	ColorMana(bar)
	if not manaHooked and UnitFrameManaBar_UpdateType then
		manaHooked = true
		hooksecurefunc("UnitFrameManaBar_UpdateType", ColorMana)
	end
end

-------------------------------------------------------------------------------
-- Textures et polices
-------------------------------------------------------------------------------

-- Rend une texture Blizzard invisible sans la cacher (Show/Hide restent a
-- Blizzard, ce qui evite de perturber son code).
function T:Fade(region)
	if region and region.SetAlpha then
		region:SetAlpha(0)
	end
end

-- Recadre une icone pour supprimer le lisere d'origine.
function T:CropIcon(texture)
	if texture and texture.SetTexCoord then
		texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end
end

-- Contour net sur une serie de textes (les nil sont ignores).
function T:OutlineFonts(...)
	for i = 1, select("#", ...) do
		local fontString = select(i, ...)
		if fontString then
			T:StyleFont(fontString, nil, "OUTLINE")
		end
	end
end

-- Change taille et contour d'un texte en gardant sa police d'origine
-- (compatible avec toutes les langues du client).
function T:StyleFont(fontString, size, flags)
	if not fontString or not fontString.GetFont then
		return
	end
	local file, currentSize = fontString:GetFont()
	if not file then
		return
	end
	fontString:SetFont(file, size or currentSize, flags or "OUTLINE")
	fontString:SetShadowOffset(0, 0)
end
