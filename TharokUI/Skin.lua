-- Tharok UI - outils de skin partages par les modules

local T = TharokUI

-- Matiere activee (theme) : pinceau, grain, reflet, ombre. Lue a la creation
-- des elements ; avant le chargement des reglages, on la suppose active.
local function TextureOn()
	return not T.db or not T.db.theme or T.db.theme.texture ~= false
end
T.TextureOn = TextureOn

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

-- Trait de pinceau sec, etire sur toute sa region : attaque nette d'un cote,
-- fin qui s'effiloche de l'autre. `vertical` : le trait suit la hauteur. Sans
-- la matiere, c'est un aplat. Se colore avec stroke:Paint(r, g, b, a).
local function PaintStroke(stroke, r, g, b, a)
	stroke:SetVertexColor(r, g, b, a or 1)
end

function T:CreateStroke(parent, layer, vertical, sublevel)
	local stroke = parent:CreateTexture(nil, layer or "BORDER", nil, sublevel)
	if TextureOn() then
		stroke:SetTexture(T.media.stroke)
		if vertical then
			-- Texture couchee : son axe horizontal suit la hauteur du trait.
			stroke:SetTexCoord(0, 1, 1, 1, 0, 0, 1, 0)
		end
	else
		stroke:SetTexture(T.media.blank)
	end
	stroke.Paint = PaintStroke
	return stroke
end

-- Epaisseur d'un trait qui remplace un filet de `pixels` pixels : le coup de
-- pinceau a des bords doux, il lui faut plus de place que le filet net.
function T:StrokeSize(pixels, frame)
	if TextureOn() then
		return 6 + 3 * (pixels or 1)
	end
	return T:Pixel(pixels or 1, frame)
end

-- Filet de separation discret (trait de pinceau clair). A placer par
-- l'appelant ; sa hauteur est deja reglee.
function T:CreateRule(parent)
	local rule = T:CreateStroke(parent, "BORDER")
	rule:Paint(1, 1, 1, 0.08)
	rule:SetHeight(T:StrokeSize(1, parent))
	return rule
end

-- Trait a la couleur d'accent le long d'un bord de `parent` ("TOP", "BOTTOM",
-- "LEFT" ou "RIGHT"). Le coup de pinceau est centre sur l'ancien filet : il
-- deborde legerement du bord.
function T:CreateAccentLine(parent, edge, thickness)
	local vertical = edge == "LEFT" or edge == "RIGHT"
	local line = T:CreateStroke(parent, "OVERLAY", vertical)
	local r, g, b = unpack(T.colors.accent)
	line:Paint(r, g, b, 0.9)
	local size = T:StrokeSize(thickness or 1, parent)
	local shift = (size - T:Pixel(thickness or 1, parent)) / 2
	if vertical then
		local x = edge == "LEFT" and -shift or shift
		line:SetPoint("TOP" .. edge, parent, "TOP" .. edge, x, 0)
		line:SetPoint("BOTTOM" .. edge, parent, "BOTTOM" .. edge, x, 0)
		line:SetWidth(size)
	else
		local y = edge == "TOP" and shift or -shift
		line:SetPoint(edge .. "LEFT", parent, edge .. "LEFT", 0, y)
		line:SetPoint(edge .. "RIGHT", parent, edge .. "RIGHT", 0, y)
		line:SetHeight(size)
	end
	return line
end

-- Texture de remplissage des barres : brossee, ou aplat sans la matiere.
function T:BarTexture()
	return TextureOn() and T.media.bar or T.media.blank
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
	-- Surface sans ombre (CreateSurface est defini plus bas, appele plus tard).
	T:CreateSurface(holder, alpha or 0.45, true)
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
		T:PaintSurface(backgrounds[i], r, g, b, a)
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
	bar:SetStatusBarTexture(T:BarTexture())
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
	bar:SetStatusBarTexture(T:BarTexture())
	ColorHealth(bar)
	if not healthHooked and UnitFrameHealthBar_Update then
		healthHooked = true
		hooksecurefunc("UnitFrameHealthBar_Update", ColorHealth)
	end
end

-- A rappeler quand Blizzard a remis sa propre texture sur une barre de vie.
function T:ReflattenHealthBar(bar)
	if bar and flatHealth[bar] then
		bar:SetStatusBarTexture(T:BarTexture())
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

-- Texte de panneau : sans contour, avec une ombre portee fine (plus elegant
-- que le contour, reserve au texte pose sur un fond variable). `color` :
-- "text" (defaut), "textDim" ou une table { r, g, b }.
function T:SoftFont(fontString, size, color)
	if not fontString or not fontString.GetFont then
		return
	end
	local file, currentSize = fontString:GetFont()
	if not file then
		return
	end
	fontString:SetFont(file, size or currentSize, "")
	fontString:SetShadowOffset(1, -1)
	fontString:SetShadowColor(0, 0, 0, 0.9)
	if color ~= false then
		local rgb = type(color) == "table" and color or T.colors[color or "text"]
		if rgb then
			fontString:SetTextColor(rgb[1], rgb[2], rgb[3])
		end
	end
end

-------------------------------------------------------------------------------
-- Matiere : surfaces avec grain, reflet et ombre portee
-------------------------------------------------------------------------------

local function MotionOn()
	return not T.db or not T.db.theme or T.db.theme.motion ~= false
end
T.MotionOn = MotionOn

-- Ombre douce autour de `frame` : quatre degrades vers l'exterieur, un peu
-- plus marquee en bas (lumiere venant du haut).
function T:CreateShadow(frame, size, alpha, skip)
	if not TextureOn() or not frame or not frame.CreateTexture then
		return
	end
	size = size or 8
	alpha = alpha or 0.35
	skip = skip or ""
	local function Edge(side)
		local edge = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
		edge:SetTexture(T.media.blank)
		-- Pas d'ombre droite sous un bord effiloche : elle le trahirait.
		edge:SetShown(not skip:find(side, 1, true))
		return edge
	end
	local dark, clear = CreateColor(0, 0, 0, alpha), CreateColor(0, 0, 0, 0)

	local top = Edge("TOP")
	top:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 0)
	top:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, 0)
	top:SetHeight(size * 0.6)
	top:SetGradient("VERTICAL", CreateColor(0, 0, 0, alpha * 0.6), clear)

	local bottom = Edge("BOTTOM")
	bottom:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, 0)
	bottom:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	bottom:SetHeight(size)
	bottom:SetGradient("VERTICAL", clear, dark)

	local left = Edge("LEFT")
	left:SetPoint("TOPRIGHT", frame, "TOPLEFT", 0, 0)
	left:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", 0, 0)
	left:SetWidth(size)
	left:SetGradient("HORIZONTAL", clear, dark)

	local right = Edge("RIGHT")
	right:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, 0)
	right:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 0, 0)
	right:SetWidth(size)
	right:SetGradient("HORIZONTAL", dark, clear)
end

-- Bord effiloche : la peinture du fond deborde de `frame` du cote `side` et
-- s'y termine en fins de coups de pinceau au lieu d'une arete droite.
local FRINGE_SIZE = 18

local function AddFringe(frame, bg, side)
	local fringe = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
	if side == "TOP" then
		fringe:SetTexture(T.media.edgeTop, "REPEAT", "CLAMP")
		fringe:SetHorizTile(true)
		fringe:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 0)
		fringe:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, 0)
		fringe:SetHeight(FRINGE_SIZE)
	elseif side == "LEFT" then
		fringe:SetTexture(T.media.edgeLeft, "CLAMP", "REPEAT")
		fringe:SetVertTile(true)
		fringe:SetPoint("TOPRIGHT", frame, "TOPLEFT", 0, 0)
		fringe:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", 0, 0)
		fringe:SetWidth(FRINGE_SIZE)
	elseif side == "RIGHT" then
		fringe:SetTexture(T.media.edgeRight, "CLAMP", "REPEAT")
		fringe:SetVertTile(true)
		fringe:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, 0)
		fringe:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 0, 0)
		fringe:SetWidth(FRINGE_SIZE)
	else
		return
	end
	bg.fringes = bg.fringes or {}
	bg.fringes[#bg.fringes + 1] = fringe
end

-- Recolore un fond cree par CreateSurface ou CreateBackground, bords
-- effiloches compris.
function T:PaintSurface(bg, r, g, b, a)
	bg:SetColorTexture(r, g, b, a)
	if bg.fringes then
		for i = 1, #bg.fringes do
			bg.fringes[i]:SetVertexColor(r, g, b, a)
		end
	end
end

-- Surface de panneau : fond du theme, plus (si la matiere est activee) un
-- reflet zenithal, un lavis brosse, un grain tres leger, un liseré clair en
-- haut et sombre en bas, et une ombre portee. `edges` : cotes a effilocher,
-- parmi "LEFT", "RIGHT" et "TOP" (ex. "LEFT RIGHT"). Renvoie la texture de
-- fond ; la recolorer avec T:PaintSurface.
function T:CreateSurface(frame, alpha, noShadow, edges)
	local bg = T:CreateBackground(frame, nil, alpha)
	if not TextureOn() then
		return bg
	end
	edges = edges or ""

	-- Lumiere venant du haut : le haut un peu plus clair que le bas.
	local sheen = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
	sheen:SetAllPoints(frame)
	sheen:SetTexture(T.media.blank)
	sheen:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 0.02))

	-- Grain : un aplat parfait fait "ecran", le grain fait "matiere".
	-- Lavis : stries de pinceau, claires la ou la lumiere accroche, denses la
	-- ou la peinture est plus chargee.
	local wash = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
	wash:SetAllPoints(frame)
	wash:SetTexture(T.media.wash, "REPEAT", "REPEAT")
	wash:SetHorizTile(true)
	wash:SetVertTile(true)
	wash:SetAlpha(0.32)

	local grain = frame:CreateTexture(nil, "BACKGROUND", nil, -5)
	grain:SetAllPoints(frame)
	grain:SetTexture(T.media.noise, "REPEAT", "REPEAT")
	grain:SetHorizTile(true)
	grain:SetVertTile(true)
	grain:SetBlendMode("ADD")
	grain:SetAlpha(0.035)

	-- Epaisseur : liseré clair en haut, sombre en bas.
	local lightEdge = frame:CreateTexture(nil, "BORDER", nil, -8)
	lightEdge:SetShown(not edges:find("TOP", 1, true))
	lightEdge:SetColorTexture(1, 1, 1, 0.06)
	lightEdge:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	lightEdge:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	lightEdge:SetHeight(T:Pixel(1, frame))

	local darkEdge = frame:CreateTexture(nil, "BORDER", nil, -8)
	darkEdge:SetColorTexture(0, 0, 0, 0.35)
	darkEdge:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
	darkEdge:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	darkEdge:SetHeight(T:Pixel(1, frame))

	for side in edges:gmatch("%a+") do
		AddFringe(frame, bg, side)
	end
	if bg.fringes then
		local r, g, b, a = unpack(T.colors.bg)
		T:PaintSurface(bg, r, g, b, alpha or a)
	end

	if not noShadow then
		T:CreateShadow(frame, nil, nil, edges)
	end
	return bg
end

-------------------------------------------------------------------------------
-- Mouvement
-------------------------------------------------------------------------------

-- Moteur d'animations : une seule frame, des taches cle -> { duree, fn }.
-- fn(t) recoit l'avancement adouci (0 -> 1). Relancer une cle remplace
-- l'animation en cours.
local tweens = {}
local tweenDriver = CreateFrame("Frame")
tweenDriver:Hide()

local function EaseOut(t)
	return 1 - (1 - t) * (1 - t) * (1 - t)
end
T.EaseOut = EaseOut

tweenDriver:SetScript("OnUpdate", function(self, elapsed)
	local busy = false
	for key, tween in pairs(tweens) do
		tween.time = tween.time + elapsed
		local t = math.min(1, tween.time / tween.duration)
		local ok = pcall(tween.fn, EaseOut(t))
		if t >= 1 or not ok then
			tweens[key] = nil
		else
			busy = true
		end
	end
	if not busy then
		self:Hide()
	end
end)

function T:Tween(key, duration, fn)
	if not MotionOn() or duration <= 0 then
		fn(1)
		tweens[key] = nil
		return
	end
	tweens[key] = { time = 0, duration = duration, fn = fn }
	tweenDriver:Show()
end

-- Apparition en fondu (a appeler juste apres Show). Pour nos propres cadres
-- uniquement (pas les cadres proteges de Blizzard).
function T:FadeIn(frame, duration, target)
	if not frame then
		return
	end
	target = target or 1
	if not MotionOn() then
		frame:SetAlpha(target)
		return
	end
	frame:SetAlpha(0)
	T:Tween(frame, duration or 0.18, function(t)
		frame:SetAlpha(target * t)
	end)
end

-- Opacite qui glisse vers `target` au lieu de sauter.
function T:FadeTo(frame, target, duration)
	if not frame then
		return
	end
	local from = frame:GetAlpha()
	if math.abs(from - target) < 0.01 then
		frame:SetAlpha(target)
		return
	end
	T:Tween(frame, duration or 0.25, function(t)
		frame:SetAlpha(from + (target - from) * t)
	end)
end

-- Barre dont la valeur glisse vers la nouvelle au lieu de sauter. Une valeur
-- secrete est posee telle quelle (on ne peut pas calculer avec).
function T:SetSmoothValue(bar, value, duration)
	if not bar then
		return
	end
	if T.IsSecret(value) or not MotionOn() then
		bar:SetValue(value)
		return
	end
	local from = bar:GetValue()
	if T.IsSecret(from) or type(from) ~= "number" or type(value) ~= "number" then
		bar:SetValue(value)
		return
	end
	T:Tween(bar, duration or 0.35, function(t)
		bar:SetValue(from + (value - from) * t)
	end)
end

-- Eclat bref : une texture qui s'allume puis s'eteint. Cree au besoin sur
-- `parent`, couvrant `anchor`.
local flashes = {}

function T:Flash(parent, anchor, color, peak, duration)
	if not MotionOn() or not parent then
		return
	end
	local flash = flashes[parent]
	if not flash then
		flash = parent:CreateTexture(nil, "OVERLAY", nil, 7)
		flash:SetBlendMode("ADD")
		flash:SetAlpha(0)
		flashes[parent] = flash
	end
	flash:ClearAllPoints()
	flash:SetAllPoints(anchor or parent)
	local c = color or { 1, 1, 1 }
	flash:SetColorTexture(c[1], c[2], c[3], 1)
	peak = peak or 0.35
	T:Tween(flash, duration or 0.35, function(t)
		flash:SetAlpha(peak * (1 - t))
	end)
end
