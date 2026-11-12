-- Tharok UI - Tiroir (mode tiroir)
-- Deux panneaux coulissants qui rangent l'interface secondaire :
--
--   Tiroir de droite : suivi de quetes, menu systeme, barre des sacs, contenu
--     des sacs, minimap, barres d'action 5 et 6, jauges d'experience et de
--     reputation, acces au menu de Tharok UI.
--   Tiroir du bas : barres d'action 1 a 4 centrees, compteur DPS/HPS, et le
--     chat qui apparait et disparait avec lui. Il s'arrete au bord du tiroir
--     de droite, qui occupe toute la hauteur.
--
-- La disposition est imposee, pour que le mode tiroir soit le meme partout :
-- barres 1 a 4 sur une ligne chacune, barres 5 et 6 en colonne, menu systeme
-- et barre des sacs en ligne, quels que soient les reglages du mode Edition.
-- Un avertissement le rappelle a la premiere activation. Si Questie est
-- installe, c'est son suivi de quetes qui est range dans le tiroir.
--
-- Activer ce module, c'est activer le mode tiroir : les elements ranges sont
-- ancres dans les tiroirs et ne se placent plus librement. Module desactive
-- (puis /reload), on ne touche plus a rien et chaque element retrouve la
-- place que lui donne le mode Edition.
--
-- Combat : les barres d'action sont des frames protegees, qu'un addon ne peut
-- ni deplacer ni masquer en combat. Un tiroir ne bouge donc jamais pendant un
-- combat. Non epingle, il se ferme d'un coup a l'entree en combat et se
-- rouvre a la sortie s'il etait ouvert ; epingle, il reste comme il est et
-- prend l'opacite de combat.
--
--   /tharok drawer right|bottom    ouvre ou ferme un tiroir
--   Raccourcis : Options du jeu > Raccourcis > Tharok UI. La touche des sacs
--   ouvre et ferme aussi le tiroir de droite.

local T = TharokUI

local Module = T:RegisterModule("Drawer", {
	title = "Tiroir",
	defaults = {
		enabled = false, -- mode tiroir : inactif tant qu'on ne l'active pas
		width = 20, -- largeur du tiroir de droite, en % de l'ecran
		alpha = 0.75, -- opacite par defaut
		version = 0, -- version des reglages (migrations)
		combatAlpha = 0.6, -- opacite en combat (tiroir epingle)
		barScale = 0.8, -- echelle des barres d'action 1 a 4 (tiroir du bas)
		sideBarScale = 0.5, -- echelle des barres 5 et 6 (tiroir de droite)
		bags = true, -- contenu des sacs dans le tiroir de droite
		chat = true, -- le chat suit le tiroir du bas
		tooltip = true, -- infobulle decalee quand le tiroir de droite est ouvert
		hideStatusBars = true, -- masque les barres d'experience / reputation du jeu
		consent = 0, -- 1 une fois l'avertissement accepte
		right = { use = true, open = true, pinned = false },
		bottom = { use = true, open = true, pinned = true },
	},
})

local IsSecret = T.IsSecret

local PAD = 8
local GAP = 4
local ANIM_TIME = 0.22
local MENU_HEIGHT = 26
local XP_HEIGHT = 8 -- jauge d'experience, en haut du tiroir de droite
local REP_HEIGHT = 4 -- jauge de reputation, juste dessous
local STRIP_MIN = 26 -- largeur minimale de la bande de droite (menu systeme)
local BOTTOM_MIN_HEIGHT = 120
local BUTTON_GAP = 2

-- Barres d'action, dans la numerotation du jeu.
local BOTTOM_BARS = { "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight" } -- 1 a 4
local RIGHT_BARS = { "MultiBarLeft", "MultiBar5" } -- 5 et 6

-- Boutons de la barre des sacs, de gauche a droite.
local BAG_BUTTONS = {
	"CharacterReagentBag0Slot", "CharacterBag3Slot", "CharacterBag2Slot", "CharacterBag1Slot",
	"CharacterBag0Slot", "BagBarExpandToggle", "MainMenuBarBackpackButton",
}

local drawers = {} -- right / bottom
local zones = {}
local inCombat = false
local animator

-------------------------------------------------------------------------------
-- Position et opacite d'un tiroir
-------------------------------------------------------------------------------

local function BaseAlpha(drawer)
	if inCombat and drawer.db.pinned then
		return Module.db.combatAlpha
	end
	return Module.db.alpha
end

local function ChatFrames()
	local list = {}
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local frame = _G["ChatFrame" .. i]
		if frame then
			list[#list + 1] = frame
		end
	end
	if GeneralDockManager then
		list[#list + 1] = GeneralDockManager
	end
	return list
end

-- Applique `drawer.progress` (0 = rentre, 1 = sorti). Ne deplace rien en
-- combat : seule l'opacite, qui n'est pas protegee, est mise a jour.
local function Place(drawer)
	local frame = drawer.frame
	local progress = drawer.progress
	local alpha = BaseAlpha(drawer) * progress
	frame:SetAlpha(alpha)

	if drawer.key == "bottom" and Module.db.chat then
		for _, chat in ipairs(drawer.chatFrames) do
			chat:SetAlpha(alpha)
		end
	end

	if InCombatLockdown() then
		return
	end

	-- Glissement adouci en fin de course.
	local eased = 1 - (1 - progress) * (1 - progress)
	local hidden = drawer.size * (1 - eased)
	frame:ClearAllPoints()
	if drawer.key == "right" then
		-- `extraTop` : zone au-dessus de l'interface (encoche de l'ecran).
		frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", hidden, drawer.extraTop or 0)
		frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", hidden, 0)
		frame:SetWidth(drawer.size)
	else
		frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, -hidden)
		frame:SetSize(drawer.width or UIParent:GetWidth(), drawer.size)
	end
	-- Le tiroir n'est jamais cache : ferme, il est hors de l'ecran et
	-- transparent. Cacher le panneau priverait son contenu de position
	-- calculee, ce que certains addons (suivi de Questie) ne supportent pas.
end

local function Animate(_, elapsed)
	local busy = false
	for _, drawer in pairs(drawers) do
		if drawer.progress ~= drawer.target then
			local step = elapsed / ANIM_TIME
			if drawer.progress < drawer.target then
				drawer.progress = math.min(drawer.target, drawer.progress + step)
			else
				drawer.progress = math.max(drawer.target, drawer.progress - step)
			end
			Place(drawer)
			busy = busy or drawer.progress ~= drawer.target
		end
	end
	if not busy then
		animator:Hide()
	end
end

local syncingBags = false

local function SyncBags(open)
	if not Module.db.bags or syncingBags then
		return
	end
	syncingBags = true
	if open then
		if OpenAllBags then
			OpenAllBags()
		end
	elseif CloseAllBags then
		CloseAllBags()
	end
	syncingBags = false
end

-- Ouvre ou ferme un tiroir. `remember` : memorise l'etat (geste du joueur).
local function SetOpen(drawer, open, remember, instant)
	if InCombatLockdown() then
		T:Print("tiroir : impossible en combat.")
		return false
	end
	if remember then
		drawer.db.open = open
	end
	drawer.reopen = nil
	drawer.target = open and 1 or 0
	if instant then
		drawer.progress = drawer.target
		Place(drawer)
	else
		animator:Show()
	end
	if drawer.key == "right" and remember then
		SyncBags(open)
	end
	return true
end

local function Toggle(key)
	local drawer = drawers[key]
	if drawer then
		SetOpen(drawer, drawer.target ~= 1, true)
	end
end

function TharokUI_ToggleDrawer(key)
	Toggle(key)
end

BINDING_NAME_THAROKUI_DRAWER_RIGHT = "Tiroir de droite"
BINDING_NAME_THAROKUI_DRAWER_BOTTOM = "Tiroir du bas"

-------------------------------------------------------------------------------
-- Adoption des elements Blizzard
-------------------------------------------------------------------------------
-- Un element adopte est reparente et ancre dans un tiroir par sa fonction
-- `place`. Le mode Edition le replace regulierement : on repasse derriere
-- lui, hors combat.

local adopted = {}
local pending = {}
local placing = false

-- Apres chaque placement, on retient ou se trouve l'element (et, pour une
-- barre ou une rangee, ses boutons). Un controle periodique compare : si le
-- jeu ou un autre addon l'a deplace sans passer par SetPoint, on le replace.
local snapshots = {}

local function Snap(frame)
	local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
	return {
		frame = frame,
		point = point,
		relativeTo = relativeTo,
		relativePoint = relativePoint,
		x = x or 0,
		y = y or 0,
		scale = frame:GetScale(),
		parent = frame:GetParent(),
	}
end

local function Drifted(snap)
	local frame = snap.frame
	local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
	if point ~= snap.point or relativeTo ~= snap.relativeTo or relativePoint ~= snap.relativePoint then
		return true
	end
	if math.abs((x or 0) - snap.x) > 0.5 or math.abs((y or 0) - snap.y) > 0.5 then
		return true
	end
	return frame:GetParent() ~= snap.parent or math.abs(frame:GetScale() - snap.scale) > 0.001
end

local function Reapply(frame)
	local place = adopted[frame]
	if not place then
		return
	end
	if InCombatLockdown() then
		if not pending[frame] then
			pending[frame] = true
			T:AfterCombat(function()
				pending[frame] = nil
				Reapply(frame)
			end)
		end
		return
	end
	placing = true
	-- Un element range doit pouvoir sortir de l'ecran avec son tiroir.
	if frame.SetClampedToScreen then
		frame:SetClampedToScreen(false)
	end
	local ok, watched = T.SafeCall(place, frame)
	placing = false

	local list = { Snap(frame) }
	if ok and type(watched) == "table" then
		for _, other in ipairs(watched) do
			list[#list + 1] = Snap(other)
		end
	end
	snapshots[frame] = list
end

local function Adopt(frame, place)
	if not frame or adopted[frame] then
		return
	end
	adopted[frame] = place
	T.alphaOwned[frame] = true
	frame:SetAlpha(1)
	hooksecurefunc(frame, "SetPoint", function()
		if not placing then
			Reapply(frame)
		end
	end)
	Reapply(frame)
end

local function Enforce()
	if InCombatLockdown() then
		return
	end
	for frame, list in pairs(snapshots) do
		if not frame:IsVisible() then
			list = {} -- replace un element cache fausserait ses mesures
		end
		for _, snap in ipairs(list) do
			local ok, drifted = pcall(Drifted, snap)
			if ok and drifted then
				Reapply(frame)
				break
			end
		end
	end
end

-- Range `frame` dans `zone`, reduit si besoin pour y tenir.
local function Fit(frame, zone, point, widthOnly, maxScale)
	frame:SetParent(zone)
	local width, height = frame:GetWidth(), frame:GetHeight()
	local scale = maxScale or 1
	if width and width > 0 then
		scale = math.min(scale, zone.w / width)
	end
	if not widthOnly and height and height > 0 then
		scale = math.min(scale, zone.h / height)
	end
	scale = math.max(scale, 0.3)
	frame:SetScale(scale)
	frame:ClearAllPoints()
	frame:SetPoint(point, zone, point, 0, 0)
	return scale
end

-- Aligne sur une ligne les enfants visibles de `container` (boutons du menu
-- systeme, de la barre des sacs) et ajuste sa taille. L'ordre visuel actuel
-- est conserve, que la rangee d'origine soit horizontale ou verticale.
local function RowChildren(container, asColumn, names)
	local children = {}
	local minLeft, maxLeft, minTop, maxTop
	local candidates = {}
	if names then
		-- Ordre impose, pour des boutons connus par leur nom.
		for _, name in ipairs(names) do
			if _G[name] then
				candidates[#candidates + 1] = _G[name]
			end
		end
	else
		candidates = { container:GetChildren() }
	end
	for index, child in ipairs(candidates) do
		if child:IsShown() and child:GetWidth() > 1 and child:GetHeight() > 1 then
			local left, top = child:GetLeft(), child:GetTop()
			children[#children + 1] = { frame = child, index = index, left = left, top = top }
			if left and top then
				minLeft, maxLeft = math.min(minLeft or left, left), math.max(maxLeft or left, left)
				minTop, maxTop = math.min(minTop or top, top), math.max(maxTop or top, top)
			end
		end
	end
	if #children == 0 then
		return {}
	end
	if not names then
		local vertical = minLeft and (maxTop - minTop) > (maxLeft - minLeft)
		table.sort(children, function(a, b)
			if vertical and a.top and b.top and a.top ~= b.top then
				return a.top > b.top
			elseif not vertical and a.left and b.left and a.left ~= b.left then
				return a.left < b.left
			end
			return a.index < b.index
		end)
	end

	local placed = {}
	local offset, thickness = 0, 1
	for _, item in ipairs(children) do
		local child = item.frame
		placed[#placed + 1] = child
		local scale = child:GetScale()
		local width, height = child:GetWidth() * scale, child:GetHeight() * scale
		child:ClearAllPoints()
		if asColumn then
			child:SetPoint("TOP", container, "TOP", 0, -offset / scale)
			offset = offset + height + BUTTON_GAP
			thickness = math.max(thickness, width)
		else
			child:SetPoint("LEFT", container, "LEFT", offset / scale, 0)
			offset = offset + width + BUTTON_GAP
			thickness = math.max(thickness, height)
		end
	end
	local length = math.max(offset - BUTTON_GAP, 1)
	if asColumn then
		container:SetSize(thickness, length)
	else
		container:SetSize(length, thickness)
	end
	return placed
end

-- Taille d'un bouton d'une barre d'action, nombre de boutons, pas entre deux.
local function BarMetrics(bar)
	local buttons = bar.actionButtons
	local first = type(buttons) == "table" and buttons[1]
	if not first then
		return
	end
	local size = first:GetWidth() * first:GetScale()
	if not size or size <= 0 then
		return
	end
	return size, #buttons, size + BUTTON_GAP
end

-- Dimensions d'une barre une fois ses boutons alignes par nos soins.
local function BarSize(bar, vertical)
	local size, count, step = BarMetrics(bar)
	if not size then
		return
	end
	local length = count * step - BUTTON_GAP
	if vertical then
		return size, length
	end
	return length, size
end

-- Aligne les boutons de la barre (ligne ou colonne, quel que soit le reglage
-- du mode Edition), puis range la barre a sa place dans le tiroir.
local function PlaceBar(bar)
	local slot = (drawers.right and drawers.right.slots[bar]) or (drawers.bottom and drawers.bottom.slots[bar])
	local size, count, step = BarMetrics(bar)
	if not slot or not size then
		return
	end

	for i = 1, count do
		local button = bar.actionButtons[i]
		local buttonScale = button:GetScale()
		local offset = (i - 1) * step / buttonScale
		button:ClearAllPoints()
		if slot.vertical then
			button:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, -offset)
		else
			button:SetPoint("TOPLEFT", bar, "TOPLEFT", offset, 0)
		end
	end

	local scale = slot.scale
	local frame = slot.drawer.frame
	bar:SetParent(frame)
	bar:SetSize(slot.w, slot.h)
	bar:SetScale(scale)
	bar:ClearAllPoints()
	if slot.drawer.key == "right" then
		bar:SetPoint("TOPLEFT", frame, "TOPLEFT", slot.x / scale, -slot.top / scale)
	else
		bar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", slot.x / scale, slot.y / scale)
	end
	return { bar.actionButtons[1], bar.actionButtons[count] }
end

-------------------------------------------------------------------------------
-- Mise en page
-------------------------------------------------------------------------------

local function SetZone(zone, parent, x, top, width, height)
	zone:ClearAllPoints()
	zone:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -top)
	zone:SetSize(math.max(width, 1), math.max(height, 1))
	zone.w, zone.h = math.max(width, 1), math.max(height, 1)
	zone.x, zone.top = x, top
end

-- Colonne de contenu du tiroir de droite. Les sacs sont cales en bas, juste
-- au-dessus de la minimap, avec la barre des sacs ; ils prennent la hauteur
-- dont ils ont besoin et le suivi de quetes occupe tout le reste. Quand les
-- sacs grandissent, le suivi retrecit, et inversement.
local function ZoneColumn()
	local right = drawers.right
	local column = right and right.column
	if not column then
		return
	end
	local used = right.bagsUsed or 0
	local barTop = column.bottom - MENU_HEIGHT
	local bagTop = barTop - (used > 0 and used + GAP or 0)
	SetZone(zones.bagBar, right.frame, column.x, barTop, column.width, MENU_HEIGHT)
	SetZone(zones.bags, right.frame, column.x, bagTop, column.width, math.max(used, 1))
	SetZone(zones.quests, right.frame, column.x, column.top, column.width, bagTop - GAP - column.top)
end

-- Hauteur maximale accordee aux sacs dans la colonne.
local function MaxBagHeight()
	local column = drawers.right.column
	return (column.bottom - column.top - MENU_HEIGHT - 2 * GAP) * 0.65
end

-- Part de la minimap dans son cadre Blizzard (qui a des marges) : sert a
-- aligner la carte elle-meme, et non son cadre, sur les autres blocs.
local mapRatio = { left = 0, width = 1 }

local function MeasureMap()
	local cluster, map = MinimapCluster, Minimap
	if not cluster or not map then
		return
	end
	local clusterScale, mapScale = cluster:GetEffectiveScale(), map:GetEffectiveScale()
	local clusterLeft, clusterWidth = cluster:GetLeft(), cluster:GetWidth()
	local mapLeft, mapWidth = map:GetLeft(), map:GetWidth()
	if not clusterLeft or not mapLeft or clusterWidth <= 0 or mapWidth <= 0 then
		return
	end
	local width = (mapWidth * mapScale) / (clusterWidth * clusterScale)
	local left = (mapLeft * mapScale - clusterLeft * clusterScale) / (clusterWidth * clusterScale)
	if width > 0.3 and width <= 1 and left >= 0 and left < 0.7 then
		mapRatio.width, mapRatio.left = width, left
	end
end

local function Layout()
	local db = Module.db
	local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight()
	local right, bottom = drawers.right, drawers.bottom

	if right then
		right.size = math.floor(screenWidth * db.width / 100)
		wipe(right.slots)

		-- L'interface du jeu peut s'arreter sous le haut de l'ecran (encoche) :
		-- le tiroir, lui, monte jusqu'au bord. Tout ce qui suit est mesure
		-- depuis ce bord.
		local extraTop = 0
		local worldTop, uiTop = WorldFrame and WorldFrame:GetTop(), UIParent:GetTop()
		if worldTop and uiTop then
			local uiScale = UIParent:GetEffectiveScale()
			extraTop = math.max(0, (worldTop * WorldFrame:GetEffectiveScale() - uiTop * uiScale) / uiScale)
		end
		right.extraTop = extraTop
		screenHeight = screenHeight + extraTop

		-- Tout en haut, sans marge : jauges d'experience et de reputation.
		local topBar = XP_HEIGHT + REP_HEIGHT
		local firstTop = topBar + PAD

		-- Bande de droite, sur toute la hauteur : barres 5 et 6 en colonne en
		-- haut, menu systeme en colonne en bas, acces au menu tout en bas.
		local sideBars, barsWidth, barsHeight = {}, 0, 0
		for _, name in ipairs(RIGHT_BARS) do
			local bar = _G[name]
			local width, height = nil, nil
			if bar and bar:IsShown() then
				width, height = BarSize(bar, true)
			end
			if width then
				local scale = math.min(db.sideBarScale, (screenHeight * 0.45) / height)
				sideBars[#sideBars + 1] = { bar = bar, scale = scale, w = width, h = height }
				barsWidth = barsWidth + width * scale + GAP
				barsHeight = math.max(barsHeight, height * scale)
			end
		end
		local stripWidth = math.max(barsWidth - GAP, STRIP_MIN)
		local stripX = right.size - PAD - stripWidth

		local x = right.size - PAD - math.max(barsWidth - GAP, 0)
		for _, item in ipairs(sideBars) do
			right.slots[item.bar] =
				{ drawer = right, vertical = true, x = x, top = firstTop, scale = item.scale, w = item.w, h = item.h }
			x = x + item.w * item.scale + GAP
		end

		local menuTop = firstTop + barsHeight + 2 * GAP
		local toolsHeight = 20
		SetZone(zones.menu, right.frame, right.size - PAD - STRIP_MIN, menuTop, STRIP_MIN,
			screenHeight - menuTop - PAD - toolsHeight - GAP)
		SetZone(zones.tools, right.frame, right.size - PAD - STRIP_MIN, screenHeight - PAD - toolsHeight,
			STRIP_MIN, toolsHeight)
		SetZone(zones.strip, right.frame, stripX - GAP, topBar, stripWidth + GAP + PAD, screenHeight - topBar)

		-- Colonne de contenu : quetes, sacs, barre des sacs, minimap. Tous les
		-- blocs ont les memes bords gauche et droit.
		local contentWidth = stripX - GAP - 2 * PAD
		local mapScale, mapHeight = 1, contentWidth
		if MinimapCluster and MinimapCluster:GetWidth() > 0 then
			-- La carte (et non son cadre) prend toute la largeur du contenu.
			mapScale = contentWidth / (mapRatio.width * MinimapCluster:GetWidth())
			mapHeight = MinimapCluster:GetHeight() * mapScale
			if mapHeight > screenHeight * 0.45 then
				mapScale = screenHeight * 0.45 / MinimapCluster:GetHeight()
				mapHeight = screenHeight * 0.45
			end
		end
		right.mapScale = mapScale

		right.column = {
			x = PAD,
			width = contentWidth,
			top = firstTop,
			bottom = screenHeight - mapHeight - GAP,
		}
		ZoneColumn()
		SetZone(zones.map, right.frame, PAD, screenHeight - mapHeight, contentWidth, mapHeight)
	end

	if bottom then
		-- Le tiroir du bas s'arrete au bord du tiroir de droite, qu'il soit
		-- sorti ou non : la disposition ne change pas.
		screenHeight = UIParent:GetHeight()
		bottom.width = screenWidth - (right and right.size or 0)
		bottom.barsLeft = bottom.width
		wipe(bottom.slots)
		bottom.barsWidth = 0
		local y = PAD
		for _, name in ipairs(BOTTOM_BARS) do
			local bar = _G[name]
			local width, height = nil, nil
			if bar and bar:IsShown() then
				width, height = BarSize(bar, false)
			end
			if width then
				local scale = math.min(db.barScale, bottom.width * 0.6 / width)
				bottom.slots[bar] = {
					drawer = bottom,
					vertical = false,
					-- Centrees sur l'ecran, pas sur le tiroir (sans deborder).
					x = math.max(PAD, math.min((screenWidth - width * scale) / 2, bottom.width - width * scale - PAD)),
					y = y,
					scale = scale,
					w = width,
					h = height,
				}
				y = y + height * scale + GAP
				bottom.barsWidth = math.max(bottom.barsWidth, width * scale)
				bottom.barsLeft = math.min(bottom.barsLeft, bottom.slots[bar].x)
			end
		end
		bottom.size = math.max(y + PAD - GAP, BOTTOM_MIN_HEIGHT)
	end

	for _, drawer in pairs(drawers) do
		Place(drawer)
	end
	for frame in pairs(adopted) do
		Reapply(frame)
	end
end

local function QueueLayout()
	T:AfterCombat(Layout)
end

-------------------------------------------------------------------------------
-- Sacs
-------------------------------------------------------------------------------

local strippedBags = {}

-- Retire le decor des fenetres de sac (portrait, titre, croix) : dans le
-- tiroir, elles n'ont plus besoin d'etre des fenetres.
local function StripBag(frame)
	if strippedBags[frame] then
		return
	end
	strippedBags[frame] = true
	T.alphaOwned[frame] = true
	frame:SetClampedToScreen(false)
	T:Fade(frame.PortraitContainer)
	T:Fade(frame.TitleContainer)
	T:Fade(frame.NineSlice)
	T:Fade(frame.Bg)
	local close = frame.CloseButton
	if close then
		close:SetAlpha(0)
		close:EnableMouse(false)
	end
end

-- Sacs du personnage actuellement ouverts : sacs combines ou sacs separes,
-- sac de composants compris. Les sacs de banque ne sont pas concernes.
local function OpenBagFrames()
	local list = {}
	local combined = ContainerFrameCombinedBags
	if combined and combined:IsShown() then
		list[1] = combined
	end
	if ContainerFrameUtil_EnumerateContainerFrames then
		for _, frame in ContainerFrameUtil_EnumerateContainerFrames() do
			local id = frame.GetBagID and frame:GetBagID() or frame:GetID()
			if frame ~= combined and frame:IsShown() and type(id) == "number" and id >= 0 and id <= 5 then
				list[#list + 1] = frame
			end
		end
	end
	return list
end

-- Blizzard replace les sacs a chaque ouverture : on les empile dans le
-- tiroir, a une echelle commune qui fait tout tenir dans la zone.
local function PlaceBags()
	local right = drawers.right
	if not right or not Module.db.bags or not right.column then
		return
	end
	local frames = OpenBagFrames()
	if #frames == 0 then
		if (right.bagsUsed or 0) ~= 0 then
			right.bagsUsed = 0
			ZoneColumn()
			if BagsBar and adopted[BagsBar] then
				Reapply(BagsBar)
			end
		end
		return
	end

	if right.target ~= 1 then
		if InCombatLockdown() then
			-- Tiroir ferme et verrouille par le combat : les sacs redeviennent
			-- flottants, a la place que Blizzard vient de leur donner.
			for _, frame in ipairs(frames) do
				frame:SetParent(UIParent)
				frame:SetScale(1)
			end
			return
		end
		SetOpen(right, true, true)
	end

	local totalHeight, maxWidth = 0, 1
	for _, frame in ipairs(frames) do
		totalHeight = totalHeight + frame:GetHeight() + GAP
		maxWidth = math.max(maxWidth, frame:GetWidth())
	end
	totalHeight = math.max(totalHeight - GAP, 1)
	-- Toute la largeur de la colonne (agrandis au besoin), tant que la hauteur
	-- reste dans la limite accordee aux sacs.
	local scale = math.max(0.3, math.min(1.6, right.column.width / maxWidth, MaxBagHeight() / totalHeight))

	local used = totalHeight * scale
	if math.abs(used - (right.bagsUsed or 0)) > 0.5 then
		right.bagsUsed = used
		ZoneColumn()
		if BagsBar and adopted[BagsBar] then
			Reapply(BagsBar)
		end
		-- Le suivi de quetes du jeu se redimensionne ; celui de Questie est
		-- simplement coupe par sa zone.
		if ObjectiveTrackerFrame and adopted[ObjectiveTrackerFrame] then
			Reapply(ObjectiveTrackerFrame)
		end
	end

	local zone = zones.bags
	local y = 0
	for _, frame in ipairs(frames) do
		StripBag(frame)
		frame:SetParent(zone)
		frame:SetScale(scale)
		frame:ClearAllPoints()
		frame:SetPoint("TOPRIGHT", zone, "TOPRIGHT", 0, -y)
		y = y + frame:GetHeight() + GAP
	end
end

-- Touche des sacs : le tiroir se ferme quand le dernier sac se ferme.
local function OnBagToggle()
	local right = drawers.right
	if syncingBags or not right or not Module.db.bags then
		return
	end
	if #OpenBagFrames() == 0 and right.target == 1 and not InCombatLockdown() then
		syncingBags = true
		SetOpen(right, false, true)
		syncingBags = false
	end
end

-------------------------------------------------------------------------------
-- Jauges d'experience et de reputation
-------------------------------------------------------------------------------

local xpGauge, repGauge

local function CreateGauge(parent, title, height)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetHeight(height)
	bar:SetStatusBarTexture(T.media.blank)
	bar:SetMinMaxValues(0, 1)
	T:CreateBackground(bar)
	T:CreateShade(bar)

	local text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
	T:StyleFont(text, 9, "OUTLINE")
	bar.text = text

	bar:EnableMouse(true)
	bar:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
		GameTooltip:AddLine(self.title or title)
		if self.detail then
			GameTooltip:AddLine(self.detail, 1, 1, 1)
		end
		GameTooltip:Show()
	end)
	bar:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	return bar
end

local function UpdateXP()
	if not xpGauge then
		return
	end
	local atMax = IsPlayerAtEffectiveMaxLevel and IsPlayerAtEffectiveMaxLevel()
	local xp, xpMax = UnitXP("player"), UnitXPMax("player")
	if atMax or IsSecret(xp) or IsSecret(xpMax) or type(xpMax) ~= "number" or xpMax <= 0 then
		xpGauge:Hide()
		return
	end
	local ratio = xp / xpMax
	xpGauge:SetValue(ratio)
	-- Du bleu vers l'or a mesure qu'on approche du niveau suivant.
	xpGauge:SetStatusBarColor(0.25 + 0.75 * ratio, 0.55 + 0.27 * ratio, 1 - ratio)
	xpGauge.text:SetText(format("%d%%", ratio * 100))
	xpGauge.detail = format("%d / %d", xp, xpMax)
	xpGauge:Show()
end

local function UpdateReputation()
	if not repGauge then
		return
	end
	local name, minValue, maxValue, value
	if C_Reputation and C_Reputation.GetWatchedFactionData then
		local data = C_Reputation.GetWatchedFactionData()
		if data then
			name, value = data.name, data.currentStanding
			minValue, maxValue = data.currentReactionThreshold, data.nextReactionThreshold
		end
	elseif GetWatchedFactionInfo then
		local _
		name, _, minValue, maxValue, value = GetWatchedFactionInfo()
	end
	if
		not name
		or IsSecret(name)
		or IsSecret(value)
		or type(value) ~= "number"
		or type(minValue) ~= "number"
		or type(maxValue) ~= "number"
	then
		repGauge:Hide()
		return
	end
	local range = maxValue - minValue
	local ratio = range > 0 and (value - minValue) / range or 1
	ratio = math.max(0, math.min(1, ratio))
	repGauge:SetValue(ratio)
	repGauge:SetStatusBarColor(0.27, 0.78, 0.32)
	repGauge.text:SetText("")
	repGauge.title = name
	repGauge.detail = format("%d / %d", value - minValue, range)
	repGauge:Show()
end

-------------------------------------------------------------------------------
-- Construction
-------------------------------------------------------------------------------

local function CreateDrawer(key)
	local drawer = {
		key = key,
		db = Module.db[key],
		slots = {},
		size = 100,
		chatFrames = {},
	}
	drawer.progress = drawer.db.open and 1 or 0
	drawer.target = drawer.progress

	local frame = CreateFrame("Frame", "TharokUIDrawer" .. (key == "right" and "Right" or "Bottom"), UIParent)
	frame:SetFrameStrata("LOW")
	frame:EnableMouse(true) -- les clics ne traversent pas le panneau
	T:CreateBackground(frame)
	T:CreateBorder(frame)
	T:CreateAccentLine(frame, key == "right" and "TOP" or "TOP", 2)
	drawer.frame = frame

	-- Poignee : toujours a l'ecran, collee au bord interieur du tiroir.
	local handle = CreateFrame("Button", nil, UIParent)
	handle:SetFrameStrata("MEDIUM")
	handle:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	if key == "right" then
		handle:SetSize(12, 64)
		handle:SetPoint("RIGHT", frame, "LEFT", 0, 0)
	else
		handle:SetSize(64, 12)
		handle:SetPoint("BOTTOM", frame, "TOP", 0, 0)
	end
	T:CreateBackground(handle)
	T:CreateBorder(handle)
	local mark = handle:CreateTexture(nil, "ARTWORK")
	mark:SetPoint("TOPLEFT", 3, -3)
	mark:SetPoint("BOTTOMRIGHT", -3, 3)
	local highlight = handle:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(unpack(T.colors.highlight))

	-- Repere : couleur d'accent quand le tiroir est epingle, gris sinon.
	function drawer.UpdateHandle()
		if drawer.db.pinned then
			local r, g, b = unpack(T.colors.accent)
			mark:SetColorTexture(r, g, b, 0.9)
		else
			mark:SetColorTexture(0.5, 0.5, 0.5, 0.6)
		end
	end
	drawer.UpdateHandle()

	handle:SetScript("OnClick", function(_, button)
		if button == "RightButton" then
			drawer.db.pinned = not drawer.db.pinned
			drawer.UpdateHandle()
			T:Print("tiroir :", drawer.db.pinned and "epingle" or "libre (se ferme en combat)")
		else
			Toggle(key)
		end
	end)
	handle:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
		GameTooltip:AddLine(key == "right" and "Tiroir de droite" or "Tiroir du bas")
		GameTooltip:AddLine("Clic : ouvrir ou fermer", 1, 1, 1)
		GameTooltip:AddLine("Clic droit : épingler ou libérer", 1, 1, 1)
		GameTooltip:Show()
	end)
	handle:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	drawers[key] = drawer
	return drawer
end

local function BuildRight()
	local right = CreateDrawer("right")
	for _, name in ipairs({ "strip", "menu", "bagBar", "quests", "bags", "map", "tools" }) do
		zones[name] = CreateFrame("Frame", nil, right.frame)
	end

	-- Bande de droite legerement plus sombre, et un filet entre les blocs :
	-- les elements ranges se lisent comme un seul panneau.
	local stripFill = zones.strip:CreateTexture(nil, "BACKGROUND")
	stripFill:SetAllPoints()
	stripFill:SetColorTexture(0, 0, 0, 0.25)
	for _, name in ipairs({ "bags", "map" }) do
		local line = zones[name]:CreateTexture(nil, "BORDER")
		line:SetColorTexture(1, 1, 1, 0.08)
		line:SetPoint("BOTTOMLEFT", zones[name], "TOPLEFT", 0, GAP / 2)
		line:SetPoint("BOTTOMRIGHT", zones[name], "TOPRIGHT", 0, GAP / 2)
		line:SetHeight(T:Pixel(1, zones[name]))
	end

	-- Jauges d'experience et de reputation : tout en haut, bord a bord.
	xpGauge = CreateGauge(right.frame, "Expérience", XP_HEIGHT)
	xpGauge:SetPoint("TOPLEFT", right.frame, "TOPLEFT", 0, 0)
	xpGauge:SetPoint("TOPRIGHT", right.frame, "TOPRIGHT", 0, 0)
	repGauge = CreateGauge(right.frame, "Réputation", REP_HEIGHT)
	repGauge:SetPoint("TOPLEFT", right.frame, "TOPLEFT", 0, -XP_HEIGHT)
	repGauge:SetPoint("TOPRIGHT", right.frame, "TOPRIGHT", 0, -XP_HEIGHT)

	-- Acces au menu Tharok UI, en bas de la bande de droite.
	local menu = CreateFrame("Button", nil, zones.tools)
	menu:SetAllPoints()
	T:CreateBackground(menu)
	T:CreateBorder(menu)
	local letter = menu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	letter:SetPoint("CENTER")
	T:StyleFont(letter, 12, "OUTLINE")
	letter:SetText("T")
	letter:SetTextColor(unpack(T.colors.accent))
	local highlight = menu:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(unpack(T.colors.highlight))
	menu:SetScript("OnClick", function()
		T:ToggleOptions()
	end)
end

-- Suivi de quetes : celui de Questie s'il est installe (il remplace celui du
-- jeu), sinon celui de Blizzard. Questie cree sa fenetre apres le chargement.
local function QuestieLoaded()
	local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
	return isLoaded and isLoaded("Questie")
end

local function AdoptQuests()
	local frame
	if QuestieLoaded() then
		frame = _G.Questie_BaseFrame
		-- Questie cache sa fenetre pendant son premier calcul : on attend
		-- qu'elle soit affichee pour ne pas fausser ses mesures.
		if frame and not frame:IsVisible() then
			return false
		end
	else
		frame = ObjectiveTrackerFrame
	end
	if not frame then
		return false
	end
	local isQuestie = frame ~= ObjectiveTrackerFrame
	Adopt(frame, function(tracker)
		if isQuestie then
			Fit(tracker, zones.quests, "TOPLEFT", true)
		else
			local scale = Fit(tracker, zones.quests, "TOPRIGHT", true)
			tracker:SetHeight(zones.quests.h / scale)
		end
	end)
	if isQuestie then
		-- Sa taille suit son contenu. Questie mesure ses lignes juste apres
		-- avoir change sa largeur : y toucher a ce moment-la invalide leurs
		-- positions et fait planter son calcul de hauteur. On ajuste donc
		-- seulement l'echelle, et a l'image suivante.
		local queued = false
		frame:HookScript("OnSizeChanged", function()
			if queued then
				return
			end
			queued = true
			C_Timer.After(0, function()
				queued = false
				local width = frame:GetWidth()
				if InCombatLockdown() or not frame:IsVisible() or not width or width <= 0 then
					return
				end
				local scale = math.max(0.3, math.min(1, zones.quests.w / width))
				if math.abs(scale - frame:GetScale()) > 0.01 then
					frame:SetScale(scale)
					if snapshots[frame] and snapshots[frame][1] then
						snapshots[frame][1].scale = scale
					end
				end
			end)
		end)
	end
	return true
end

local lastMapScale

local function AdoptAll()
	local right, bottom = drawers.right, drawers.bottom

	local function AdoptBar(name)
		local bar = _G[name]
		if not bar then
			return
		end
		Adopt(bar, PlaceBar)
		-- Blizzard realigne les boutons a chaque changement de la barre.
		if bar.UpdateGridLayout then
			hooksecurefunc(bar, "UpdateGridLayout", function()
				if not placing then
					Reapply(bar)
				end
			end)
		end
	end

	-- Menu systeme et barre des sacs : boutons remis en ligne, puis reduits
	-- pour tenir dans leur zone.
	local function AdoptRow(container, inner, zone, point, asColumn, names)
		if not container then
			return
		end
		Adopt(container, function(frame)
			local placed
			if inner and inner ~= frame then
				placed = RowChildren(inner, asColumn, names)
				-- Cale du meme cote que la zone, pour que la rangee touche
				-- bien son bord meme si le conteneur garde une autre taille.
				inner:ClearAllPoints()
				inner:SetPoint(point, frame, point, 0, 0)
				frame:SetSize(inner:GetWidth(), inner:GetHeight())
			else
				placed = RowChildren(frame, asColumn, names)
			end
			Fit(frame, zone, point)
			return placed
		end)
		local layoutOwner = inner or container
		if layoutOwner.Layout then
			hooksecurefunc(layoutOwner, "Layout", function()
				if not placing then
					Reapply(container)
				end
			end)
		end
	end

	if right then
		for _, name in ipairs(RIGHT_BARS) do
			AdoptBar(name)
		end

		zones.quests:SetClipsChildren(true)
		if not AdoptQuests() then
			C_Timer.NewTicker(1, function(ticker)
				if AdoptQuests() then
					ticker:Cancel()
				end
			end, 60)
		end

		AdoptRow(MicroMenuContainer, MicroMenu, zones.menu, "BOTTOM", true)
		-- Cadre Blizzard du menu systeme : les textures posees directement sur
		-- le conteneur et sur le menu (les boutons, eux, sont des enfants).
		for _, holder in ipairs({ MicroMenuContainer, MicroMenu }) do
			if holder and holder.GetRegions then
				for _, region in ipairs({ holder:GetRegions() }) do
					T:Fade(region)
				end
			end
			if holder then
				T:Fade(holder.NineSlice)
				T:Fade(holder.Background)
				T:Fade(holder.Bg)
			end
		end
		AdoptRow(BagsBar, nil, zones.bagBar, "RIGHT", false, BAG_BUTTONS)

		Adopt(MinimapCluster, function(frame)
			-- La carte prend la largeur du contenu ; son cadre Blizzard, plus
			-- large qu'elle, deborde a gauche de facon invisible.
			local scale = right.mapScale or 1
			frame:SetParent(zones.map)
			frame:SetScale(scale)
			frame:ClearAllPoints()
			frame:SetPoint("BOTTOMLEFT", zones.map, "BOTTOMLEFT", -mapRatio.left * frame:GetWidth(), 0)
			-- La carte ne se redessine pas seule apres un changement d'echelle :
			-- un aller-retour de zoom la force a le faire.
			if scale ~= lastMapScale and Minimap and Minimap.GetZoom then
				lastMapScale = scale
				local zoom = Minimap:GetZoom()
				Minimap:SetZoom(zoom > 0 and zoom - 1 or zoom + 1)
				Minimap:SetZoom(zoom)
			end
		end)

		if Module.db.bags then
			if UpdateContainerFrameAnchors then
				hooksecurefunc("UpdateContainerFrameAnchors", function()
					T.SafeCall(PlaceBags)
				end)
			end
			if ToggleBackpack then
				hooksecurefunc("ToggleBackpack", OnBagToggle)
			end
			if ToggleAllBags then
				hooksecurefunc("ToggleAllBags", OnBagToggle)
			end
		end

		-- Barres d'experience et de reputation du jeu : remplacees par les
		-- jauges du tiroir. Rendues invisibles et insensibles a la souris.
		if Module.db.hideStatusBars then
			for _, name in ipairs({
				"MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer", "StatusTrackingBarManager",
				"MainMenuExpBar", "ReputationWatchBar", "MainMenuBarMaxLevelBar", "MainMenuBarExpText",
			}) do
				local bar = _G[name]
				if bar then
					T:Fade(bar)
					if bar.EnableMouse then
						pcall(bar.EnableMouse, bar, false)
					end
					T.alphaOwned[bar] = true
				end
			end
		end

		-- Infobulle : a gauche du tiroir quand il est ouvert.
		if Module.db.tooltip and GameTooltip_SetDefaultAnchor then
			hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip)
				if right.progress > 0 and tooltip and not (tooltip.IsForbidden and tooltip:IsForbidden()) then
					tooltip:ClearAllPoints()
					tooltip:SetPoint("BOTTOMRIGHT", right.frame, "BOTTOMLEFT", -PAD, 90)
				end
			end)
		end
	end

	if bottom then
		for _, name in ipairs(BOTTOM_BARS) do
			AdoptBar(name)
		end
		-- Compteur DPS/HPS de Tharok UI, dans le coin droit du tiroir.
		Adopt(TharokUIMeter, function(frame)
			frame:SetParent(bottom.frame)
			frame:ClearAllPoints()
			frame:SetPoint("BOTTOMRIGHT", bottom.frame, "BOTTOMRIGHT", -PAD, PAD)
		end)
		if Module.db.chat then
			-- Fenetre de chat principale : calee dans la partie gauche du
			-- tiroir, a gauche des barres. Elle reste hors du tiroir dans la
			-- hierarchie (le jeu gere ses onglets), mais glisse avec lui.
			Adopt(ChatFrame1, function(frame)
				local width = math.max(bottom.barsLeft - 3 * PAD - 30, 150)
				-- Le champ de saisie s'affiche sous la fenetre : on lui garde
				-- sa place, sinon il sort de l'ecran par le bas.
				local editBox = frame.editBox or ChatFrame1EditBox
				local reserve = (editBox and editBox:GetHeight() or 32) + 4
				local height = math.max(bottom.size - 2 * PAD - 26 - reserve, 60)
				frame:ClearAllPoints()
				frame:SetPoint("BOTTOMLEFT", bottom.frame, "BOTTOMLEFT", PAD + 30, PAD + reserve)
				frame:SetSize(width, height)
			end)
			bottom.chatFrames = ChatFrames()
			for _, chat in ipairs(bottom.chatFrames) do
				T.alphaOwned[chat] = true
			end
		end
	end
end

local function Setup()
	animator = CreateFrame("Frame")
	animator:Hide()
	animator:SetScript("OnUpdate", Animate)

	if Module.db.right.use then
		BuildRight()
	end
	if Module.db.bottom.use then
		CreateDrawer("bottom")
	end

	-- Reglages enregistres avant le changement d'opacite par defaut.
	if Module.db.version < 2 then
		if Module.db.alpha == 0.95 then
			Module.db.alpha = 0.75
		end
		Module.db.version = 2
	end

	pcall(MeasureMap) -- avant tout deplacement de la minimap
	Layout()
	AdoptAll()
	Layout()
	if T.RefreshFade then
		T.RefreshFade()
	end

	UpdateXP()
	UpdateReputation()
	T:On("PLAYER_XP_UPDATE", UpdateXP)
	T:On("PLAYER_LEVEL_UP", UpdateXP)
	T:On("UPDATE_FACTION", UpdateReputation)

	T:Every(1.5, Enforce)

	T:On("DISPLAY_SIZE_CHANGED", QueueLayout)
	T:On("UI_SCALE_CHANGED", QueueLayout)

	-- A cet evenement le verrouillage de combat n'est pas encore actif : on
	-- peut encore fermer les tiroirs, mais d'un coup (pas le temps d'animer).
	T:On("PLAYER_REGEN_DISABLED", function()
		for _, drawer in pairs(drawers) do
			local wasOpen = drawer.target == 1
			drawer.progress = drawer.target
			if not drawer.db.pinned and wasOpen then
				drawer.progress, drawer.target = 0, 0
				drawer.reopen = true
			end
		end
		inCombat = true
		for _, drawer in pairs(drawers) do
			Place(drawer)
		end
	end)
	T:On("PLAYER_REGEN_ENABLED", function()
		inCombat = false
		for _, drawer in pairs(drawers) do
			if drawer.reopen then
				drawer.reopen = nil
				drawer.target = 1
				animator:Show()
			else
				Place(drawer)
			end
		end
	end)
end

-------------------------------------------------------------------------------
-- Commande et options
-------------------------------------------------------------------------------

function Module:OnCommand(args)
	local key = args[1] and strlower(args[1])
	if key == "right" or key == "droite" then
		Toggle("right")
		return true
	elseif key == "bottom" or key == "bas" then
		Toggle("bottom")
		return true
	end
	return false
end

local function Nested(key, field, label, live)
	return {
		type = "toggle",
		label = label,
		live = live,
		get = function()
			return Module.db[key][field]
		end,
		set = function(value)
			Module.db[key][field] = value
			if drawers[key] then
				drawers[key].UpdateHandle()
			end
		end,
	}
end

local function LiveRange(key, label, min, max, step, factor, relayout)
	return {
		type = "range",
		label = label,
		min = min,
		max = max,
		step = step,
		suffix = "%",
		factor = factor,
		live = true,
		get = function()
			return Module.db[key]
		end,
		set = function(value)
			Module.db[key] = value
			if not animator then
				return
			end
			if relayout then
				QueueLayout()
			else
				for _, drawer in pairs(drawers) do
					Place(drawer)
				end
			end
		end,
	}
end

Module.options = {
	{ type = "note", text = "Activer ce module active le mode tiroir : les éléments rangés ne se placent plus librement." },

	{ type = "header", label = "Tiroir de droite" },
	Nested("right", "use", "Utiliser le tiroir de droite"),
	Nested("right", "pinned", "Épinglé (ne se ferme pas en combat)", true),
	LiveRange("width", "Largeur", 12, 35, 1, 1, true),
	{ type = "toggle", key = "bags", label = "Contenu des sacs dans le tiroir" },
	{ type = "toggle", key = "tooltip", label = "Décaler l'infobulle quand le tiroir est ouvert" },
	{ type = "toggle", key = "hideStatusBars", label = "Masquer les barres d'expérience et de réputation du jeu" },

	{ type = "header", label = "Tiroir du bas" },
	Nested("bottom", "use", "Utiliser le tiroir du bas"),
	Nested("bottom", "pinned", "Épinglé (ne se ferme pas en combat)", true),
	{ type = "toggle", key = "chat", label = "Chat rangé dans le tiroir (à gauche des barres)" },

	{ type = "header", label = "Apparence" },
	LiveRange("alpha", "Opacité par défaut", 20, 100, 5, 100),
	LiveRange("combatAlpha", "Opacité en combat (tiroir épinglé)", 20, 100, 5, 100),
	LiveRange("barScale", "Échelle des barres 1 à 4 (tiroir du bas)", 50, 100, 5, 100, true),
	LiveRange("sideBarScale", "Échelle des barres 5 et 6 (tiroir de droite)", 30, 100, 5, 100, true),
}

StaticPopupDialogs["THAROKUI_DRAWER_CONFIRM"] = {
	text = "Tharok UI : mode tiroir\n\n"
		.. "Ce mode impose la disposition de l'interface : barres d'action, suivi de quêtes, sacs, "
		.. "minimap, menu système et compteur sont rangés dans deux tiroirs et ne se placent plus "
		.. "librement. Tes réglages du mode Édition ne sont pas modifiés : en désactivant le module "
		.. "Tiroir, tout reprend sa place après rechargement.\n\nActiver le mode tiroir ?",
	button1 = "Activer",
	button2 = "Annuler",
	OnAccept = function()
		Module.db.consent = 1
		T:AfterCombat(Setup)
	end,
	OnCancel = function()
		Module.db.enabled = false
		T:Print("mode tiroir non active (module Tiroir desactive).")
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

function Module:OnEnable()
	-- Apres le demarrage de tous les modules (le compteur doit exister), et
	-- hors combat : les barres d'action ne se deplacent pas en combat.
	C_Timer.After(0, function()
		if Module.db.consent == 1 then
			T:AfterCombat(Setup)
		else
			StaticPopup_Show("THAROKUI_DRAWER_CONFIRM")
		end
	end)
end
