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
-- barres 1 a 4 sur une ligne chacune, barres 5 et 6 en ligne, menu systeme
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
-- combat : il reste tel quel, son fond vire au rouge leger et il prend
-- l'opacite de combat.
--
--   /tharok drawer right|bottom    ouvre ou ferme un tiroir
--   Raccourci du tiroir du bas : Options du jeu > Raccourcis > Tharok UI.
--   Le tiroir de droite est ouvert a chaque chargement ; la touche des sacs
--   ouvre et ferme les sacs seulement, jamais le tiroir.

local T = TharokUI

local Module = T:RegisterModule("Drawer", {
	title = "Tiroir",
	defaults = {
		enabled = false, -- mode tiroir : inactif tant qu'on ne l'active pas
		width = 17, -- largeur du tiroir de droite, en % de l'ecran
		alpha = 0.75, -- opacite par defaut
		version = 0, -- version des reglages (migrations)
		combatAlpha = 0.6, -- opacite en combat
		idleBars = 0.5, -- opacite des barres 1 a 4 au repos (1 = toujours pleines)
		lowMana = 30, -- seuil de mana faible en % (liseré violet en combat), 0 = jamais
		barScale = 0.8, -- echelle des barres d'action 1 a 4 (tiroir du bas)
		bags = true, -- contenu des sacs dans le tiroir de droite
		chat = true, -- le chat suit le tiroir du bas
		tooltip = true, -- infobulle decalee quand le tiroir de droite est ouvert
		hideStatusBars = true, -- masque les barres d'experience / reputation du jeu
		consent = 0, -- 1 une fois l'avertissement accepte
		right = { use = true, open = true },
		bottom = { use = true, open = true },
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

local function BaseAlpha()
	if inCombat then
		return Module.db.combatAlpha
	end
	return Module.db.alpha
end

-- En combat, le signal passe par le liseré (bordure et trait du haut en
-- rouge) et une teinte tres legere du fond : le contenu reste lisible.
-- Textures non protegees : on peut les changer en combat.
-- Violet au lieu du rouge quand le mana est bas : combat + mana faible.
local COMBAT_RED = { 0.9, 0.15, 0.12 }
local COMBAT_LOW_MANA = { 0.62, 0.25, 0.95 }
local COMBAT_TINT = 0.12 -- part de couleur melangee au fond
local lowMana = false

-- Melanges animes : combatMix (0 = hors combat, 1 = combat) et manaMix
-- (0 = rouge, 1 = violet). Les couleurs glissent au lieu de sauter.
local combatMix, manaMix = 0, 0
local pulse = 1 -- intensite du liseré, qui respire quand le mana est bas

local function Mix(a, b, t)
	return a + (b - a) * t
end

local function CombatColor()
	return Mix(COMBAT_RED[1], COMBAT_LOW_MANA[1], manaMix),
		Mix(COMBAT_RED[2], COMBAT_LOW_MANA[2], manaMix),
		Mix(COMBAT_RED[3], COMBAT_LOW_MANA[3], manaMix)
end

local function BackgroundColor()
	local r, g, b, a = unpack(T.colors.bg)
	local cr, cg, cb = CombatColor()
	local t = COMBAT_TINT * combatMix
	return Mix(r, cr, t), Mix(g, cg, t), Mix(b, cb, t), a
end

-- Mana du joueur sous le seuil (en %). Faux pour une classe sans mana, si
-- l'option est a 0, ou si le jeu masque la valeur (valeur secrete).
local MANA = Enum and Enum.PowerType and Enum.PowerType.Mana or 0

local function IsLowMana()
	local threshold = Module.db.lowMana or 0
	if threshold <= 0 then
		return false
	end
	local ok, low = pcall(function()
		local max = UnitPowerMax("player", MANA)
		local current = UnitPower("player", MANA)
		if T.IsSecret(max) or T.IsSecret(current) or not max or max <= 0 then
			return false
		end
		return current / max * 100 < threshold
	end)
	return ok and low or false
end

local function PaintBackground(drawer)
	if not drawer.bg then
		return
	end
	local r, g, b, a = BackgroundColor()
	T:PaintSurface(drawer.bg, r, g, b, a)
	local cr, cg, cb = CombatColor()
	if drawer.border then
		local br, bgc, bb = unpack(T.colors.border)
		drawer.border:Paint(Mix(br, cr, combatMix), Mix(bgc, cg, combatMix), Mix(bb, cb, combatMix), Mix(1, pulse, combatMix))
	end
	if drawer.accent then
		local ar, ag, ab = unpack(T.colors.accent)
		drawer.accent:Paint(Mix(ar, cr, combatMix), Mix(ag, cg, combatMix), Mix(ab, cb, combatMix), 0.9 * Mix(1, pulse, combatMix))
	end
	-- Fondu en bas du suivi de quetes : meme couleur que le fond.
	if drawer.questFade then
		drawer.questFade:SetGradient("VERTICAL", CreateColor(r, g, b, math.min(1, a + 0.1)), CreateColor(r, g, b, 0))
	end
end

local function PaintAll()
	for _, drawer in pairs(drawers) do
		PaintBackground(drawer)
	end
end

-- Transitions : vers le combat (0,3 s) et entre rouge et violet (0,5 s).
local function AnimateCombat(target)
	local from = combatMix
	T:Tween("drawerCombat", 0.3, function(t)
		combatMix = Mix(from, target, t)
		PaintAll()
	end)
end

local function AnimateMana(target)
	local from = manaMix
	T:Tween("drawerMana", 0.5, function(t)
		manaMix = Mix(from, target, t)
		PaintAll()
	end)
end

-- Respiration du liseré en combat avec peu de mana (1,6 s par cycle).
local breather = CreateFrame("Frame")
breather:Hide()
local breathTime = 0
local breathPending = 0
breather:SetScript("OnUpdate", function(_, elapsed)
	breathTime = breathTime + elapsed
	-- 30 images par seconde suffisent a une respiration lente.
	breathPending = breathPending + elapsed
	if breathPending < 1 / 30 then
		return
	end
	breathPending = 0
	pulse = 0.55 + 0.45 * (0.5 + 0.5 * math.cos(breathTime * math.pi * 2 / 1.6))
	PaintAll()
end)

local function UpdateBreath()
	if inCombat and lowMana and T.MotionOn and T.MotionOn() then
		breathTime = 0
		breather:Show()
	else
		breather:Hide()
		pulse = 1
		PaintAll()
	end
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
	local alpha = BaseAlpha() * progress
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

-- Ouvre ou ferme un tiroir. `remember` : memorise l'etat (geste du joueur).
local function SetOpen(drawer, open, remember, instant)
	if InCombatLockdown() then
		T:Print("tiroir : impossible en combat.")
		return false
	end
	if remember then
		drawer.db.open = open
	end
	drawer.target = open and 1 or 0
	if instant then
		drawer.progress = drawer.target
		Place(drawer)
	else
		animator:Show()
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
local QueueLayout -- defini plus bas, utilise par PlaceBar
local holders = {} -- barre d'action -> support qui porte son echelle

-- Le mode Edition enregistre dans sa disposition le cadre auquel chaque
-- barre est ancree (par son nom). Au chargement suivant, il reapplique cette
-- disposition tres tot : les cadres du tiroir et les supports des barres
-- doivent donc exister des le chargement de l'addon, sinon "Couldn't find
-- region named ...". Ils couvrent l'ecran tant que le tiroir ne les a pas
-- places (module desactive : les barres restent visibles).
local function EarlyFrame(name)
	local frame = _G[name] or CreateFrame("Frame", name, UIParent)
	frame:SetAllPoints(UIParent)
	return frame
end

EarlyFrame("TharokUIDrawerRight")
EarlyFrame("TharokUIDrawerBottom")
for _, list in ipairs({ BOTTOM_BARS, RIGHT_BARS }) do
	for _, barName in ipairs(list) do
		EarlyFrame("TharokUIBarHolder" .. barName)
	end
end

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
		width = frame:GetWidth(),
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
	if snap.frame.actionButtons or snap.frame.action then
		-- Barre ou bouton d'action : le jeu peut changer sa taille (taille
		-- des icones du mode Edition, barre principale...).
		if math.abs((frame:GetWidth() or 0) - (snap.width or 0)) > 0.5 then
			return true
		end
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
	if not size then
		return
	end
	-- Barre apparue apres la mise en page (vehicule, changement de barre...)
	-- ou boutons redimensionnes par le jeu : les mesures sont perimees, on
	-- refait la mise en page plutot que de la laisser a sa taille Blizzard.
	if not slot then
		if bar:IsShown() then
			QueueLayout()
		end
		return
	end
	local width, height = BarSize(bar, slot.vertical)
	if math.abs(width - slot.w) > 1 or math.abs(height - slot.h) > 1 then
		QueueLayout()
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

	-- La reduction est portee par un support a nous, pas par la barre : le
	-- gestionnaire de positions de Blizzard (UIParentPanelManager) remet
	-- l'echelle de la barre principale a 1, y compris en combat, ou on ne
	-- peut pas la corriger. La barre reste donc a l'echelle 1.
	local scale = slot.scale
	local frame = slot.drawer.frame
	local holder = holders[bar]
	if not holder then
		-- Nomme et cree des le chargement : le mode Edition peut l'enregistrer
		-- comme ancre de la barre.
		local holderName = "TharokUIBarHolder" .. (bar:GetName() or "")
		holder = _G[holderName] or CreateFrame("Frame", holderName, frame)
		holders[bar] = holder
	end
	holder:SetParent(frame)
	holder:SetScale(scale)
	holder:SetSize(slot.w, slot.h)
	holder:ClearAllPoints()
	if slot.drawer.key == "right" then
		holder:SetPoint("TOPLEFT", frame, "TOPLEFT", slot.x / scale, -slot.top / scale)
	else
		holder:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", slot.x / scale, slot.y / scale)
	end

	bar:SetParent(holder)
	bar:SetSize(slot.w, slot.h)
	bar:SetScale(1)
	bar:ClearAllPoints()
	bar:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
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

	-- Bandeau (zone, heure) colle juste au-dessus de la carte : dans le cadre
	-- Blizzard, il reste en haut et laisse un vide quand la carte est plus
	-- petite que son cadre. La partie du cadre au-dessus du bandeau, vide,
	-- n'est pas comptee dans la hauteur de la zone de la carte.
	mapRatio.topCut = 0
	local header = cluster.BorderTop
	if header and not cluster.headerUnderneath then
		header:ClearAllPoints()
		header:SetPoint("BOTTOM", map, "TOP", 0, 2)
		local clusterTop, headerTop = cluster:GetTop(), header:GetTop()
		local clusterHeight = cluster:GetHeight()
		if clusterTop and headerTop and clusterHeight > 0 then
			local cut = (clusterTop * clusterScale - headerTop * header:GetEffectiveScale()) / (clusterHeight * clusterScale)
			if cut > 0 and cut < 0.6 then
				mapRatio.topCut = cut
			end
		end
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

		-- Juste sous les jauges : le menu systeme en ligne, et l'acces au menu
		-- Tharok UI au bout de la ligne.
		local menuTop = topBar + GAP
		SetZone(zones.menu, right.frame, PAD, menuTop, right.size - 2 * PAD - STRIP_MIN - GAP, MENU_HEIGHT)
		SetZone(zones.tools, right.frame, right.size - PAD - STRIP_MIN, menuTop, STRIP_MIN, MENU_HEIGHT)
		local firstTop = menuTop + MENU_HEIGHT + PAD

		-- Une seule colonne de contenu, sur toute la largeur du tiroir : tous
		-- les blocs ont les memes bords gauche et droit.
		local contentWidth = right.size - 2 * PAD

		-- Barres 5 et 6 : en ligne, au-dessus de la minimap, a l'echelle qui
		-- fait tenir la barre 5 dans la largeur. La barre 6 prend la meme
		-- taille de bouton.
		local sideBars, barsHeight = {}, 0
		local buttonSize -- taille d'un bouton a l'ecran, fixee par la barre 5
		for _, name in ipairs(RIGHT_BARS) do
			local bar = _G[name]
			local width, height = nil, nil
			if bar and bar:IsShown() then
				width, height = BarSize(bar, false)
			end
			if width then
				local size = BarMetrics(bar)
				local scale
				if buttonSize then
					scale = buttonSize / size
				else
					scale = math.min(1, contentWidth / width)
					buttonSize = size * scale
				end
				sideBars[#sideBars + 1] = { bar = bar, scale = scale, w = width, h = height }
				barsHeight = barsHeight + height * scale + BUTTON_GAP
			end
		end
		barsHeight = math.max(barsHeight - BUTTON_GAP, 0)

		local mapScale, mapHeight = 1, contentWidth
		if MinimapCluster and MinimapCluster:GetWidth() > 0 then
			-- La carte (et non son cadre) prend toute la largeur du contenu.
			-- Hauteur utile : du haut du bandeau au bas du cadre.
			local usefulHeight = MinimapCluster:GetHeight() * (1 - (mapRatio.topCut or 0))
			mapScale = contentWidth / (mapRatio.width * MinimapCluster:GetWidth())
			mapHeight = usefulHeight * mapScale
			if mapHeight > screenHeight * 0.45 then
				mapScale = screenHeight * 0.45 / usefulHeight
				mapHeight = screenHeight * 0.45
			end
		end
		right.mapScale = mapScale

		local mapTop = screenHeight - mapHeight
		local barsTop = mapTop - GAP - barsHeight
		local y = barsTop
		for _, item in ipairs(sideBars) do
			right.slots[item.bar] = {
				drawer = right,
				vertical = false,
				x = PAD,
				top = y,
				scale = item.scale,
				w = item.w,
				h = item.h,
			}
			y = y + item.h * item.scale + BUTTON_GAP
		end

		if right.barsLine then
			right.barsLine:ClearAllPoints()
			right.barsLine:SetShown(barsHeight > 0)
			local y = -(barsTop - GAP / 2) + right.barsLine:GetHeight() / 2
			right.barsLine:SetPoint("TOPLEFT", right.frame, "TOPLEFT", PAD, y)
			right.barsLine:SetPoint("TOPRIGHT", right.frame, "TOPRIGHT", -PAD, y)
		end

		right.column = {
			x = PAD,
			width = contentWidth,
			top = firstTop,
			bottom = (barsHeight > 0 and barsTop or mapTop) - GAP,
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
		bottom.barsRight = nil
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
				bottom.barsRight = math.max(bottom.barsRight or 0, bottom.slots[bar].x + width * scale)
			end
		end
		bottom.size = math.max(y + PAD - GAP, BOTTOM_MIN_HEIGHT)
		bottom.barsRight = bottom.barsRight or bottom.barsLeft

		-- Trois blocs de meme hauteur : chat | barres | compteur. Le compteur
		-- prend la place libre a droite des barres (plafonnee), le chat une
		-- largeur raisonnable a gauche.
		local meterSpace = bottom.width - bottom.barsRight - 3 * PAD
		bottom.meterWidth = math.max(160, math.min(420, meterSpace))
		bottom.meterHeight = bottom.size - 2 * PAD
		local chatSpace = bottom.barsLeft - 3 * PAD - 30
		bottom.chatWidth = math.max(150, math.min(chatSpace, math.max(320, bottom.width * 0.25)))
	end

	for _, drawer in pairs(drawers) do
		Place(drawer)
	end
	for frame in pairs(adopted) do
		Reapply(frame)
	end
end

-- Une seule mise en page en attente a la fois, a la frame suivante (evite
-- une recursion Layout -> PlaceBar -> Layout).
local layoutQueued = false

function QueueLayout()
	if layoutQueued then
		return
	end
	layoutQueued = true
	C_Timer.After(0, function()
		T:AfterCombat(function()
			layoutQueued = false
			Layout()
		end)
	end)
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
	-- Le tiroir fournit le fond : le fond et la bordure du module Sacs, poses
	-- sur chaque sac empile, recouvriraient la rangee du sac du dessus.
	if T.ShowBagDecor then
		T:ShowBagDecor(frame, false)
	end
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
local REAGENT_BAG = 5
local REAGENT_TINT = { 0.30, 0.75, 0.45, 0.30 } -- cases du sac de composants
local tints = {}

-- Hauteur de l'en-tete d'une fenetre de sac (titre, recherche) : l'espace
-- entre le haut de la fenetre et la premiere rangee de cases.
-- Mesuree une seule fois par sac : une fois les cases replacees par nos
-- soins, la mesurer a nouveau la ferait deriver.
local headerCache = {}

local function HeaderHeight(frame)
	if headerCache[frame] then
		return headerCache[frame]
	end
	if not frame.EnumerateValidItems then
		return 0
	end
	local frameTop = frame:GetTop()
	local highest
	for _, button in frame:EnumerateValidItems() do
		local top = button and button:GetTop()
		if top then
			top = top * button:GetEffectiveScale() / frame:GetEffectiveScale()
			highest = highest and math.max(highest, top) or top
		end
	end
	if not frameTop or not highest then
		return 0
	end
	headerCache[frame] = math.max(0, frameTop - highest - 2)
	return headerCache[frame]
end

-- Teinte des cases du sac de composants, pour les distinguer sans les
-- separer. Recalculee a chaque placement : les boutons sont recycles.
local function TintItems(frame)
	if not frame.EnumerateValidItems then
		return
	end
	for _, button in frame:EnumerateValidItems() do
		if button then
			local tint = tints[button]
			if not tint then
				tint = button:CreateTexture(nil, "BACKGROUND", nil, -7)
				tint:SetAllPoints()
				tint:SetColorTexture(unpack(REAGENT_TINT))
				tints[button] = tint
			end
			local id = button.GetBagID and button:GetBagID()
			tint:SetShown(id == REAGENT_BAG)
		end
	end
end

-- Grille des cases d'un sac : position de chaque colonne (distance entre le
-- bord droit du sac et le bord gauche de la case), pas entre deux rangees.
local function GridOf(frame)
	if not frame.EnumerateValidItems then
		return
	end
	local right, top = frame:GetRight(), frame:GetTop()
	if not right or not top then
		return
	end
	local scale = frame:GetEffectiveScale()
	local lefts, tops = {}, {}
	local size
	for _, button in frame:EnumerateValidItems() do
		local left, buttonTop = button and button:GetLeft(), button and button:GetTop()
		if left and buttonTop then
			local ratio = button:GetEffectiveScale() / scale
			lefts[#lefts + 1] = left * ratio
			tops[#tops + 1] = buttonTop * ratio
			size = size or button:GetWidth() * ratio
		end
	end
	if #lefts == 0 then
		return
	end

	-- Valeurs distinctes (a un pixel pres), triees.
	local function Distinct(values, descending)
		table.sort(values, function(a, b)
			if descending then
				return a > b
			end
			return a < b
		end)
		local list = {}
		for _, value in ipairs(values) do
			if #list == 0 or math.abs(list[#list] - value) > 1 then
				list[#list + 1] = value
			end
		end
		return list
	end

	local columns = {}
	for _, left in ipairs(Distinct(lefts)) do
		columns[#columns + 1] = right - left
	end
	local rows = Distinct(tops, true)
	local rowStep = #rows > 1 and (rows[1] - rows[2]) or (size + 4)
	return { columns = columns, rowStep = rowStep }
end

-- Range les cases du sac de composants sur la grille du sac principal : meme
-- nombre de colonnes, memes positions, donc moins de rangees.
local function RegridReagents(frame, grid, header)
	if not grid or InCombatLockdown() or not frame.EnumerateValidItems then
		return
	end
	local buttons = {}
	for _, button in frame:EnumerateValidItems() do
		if button then
			buttons[#buttons + 1] = button
		end
	end
	if #buttons == 0 then
		return
	end
	table.sort(buttons, function(a, b)
		return a:GetID() < b:GetID()
	end)

	local count = #grid.columns
	for index, button in ipairs(buttons) do
		local row, column = math.floor((index - 1) / count), (index - 1) % count
		local buttonScale = button:GetScale()
		button:ClearAllPoints()
		button:SetPoint(
			"TOPLEFT",
			frame,
			"TOPRIGHT",
			-grid.columns[column + 1] / buttonScale,
			-(header + row * grid.rowStep) / buttonScale
		)
	end
	local rows = math.ceil(#buttons / count)
	frame:SetHeight(header + rows * grid.rowStep + 2)
end

local regridHooks = {}
local placingBags = false
local PlaceBagsNow

-- Redimensionner le sac de composants relance sa mise a jour Blizzard, que
-- l'on suit : sans garde, PlaceBags se rappellerait en boucle.
local function PlaceBags()
	if placingBags then
		return
	end
	placingBags = true
	local ok, err = pcall(PlaceBagsNow)
	placingBags = false
	if not ok then
		error(err, 0)
	end
end

function PlaceBagsNow()
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
		-- Tiroir rentre a la main : on le ressort pour montrer les sacs (la
		-- touche des sacs ne le referme jamais).
		SetOpen(right, true, false)
	end

	-- Les sacs suivants (dont le sac de composants) perdent leur en-tete et se
	-- collent sous le premier : un seul bloc de cases a l'ecran.
	local headers = {}
	local grid = GridOf(frames[1])
	local regridHooked = regridHooks
	for i, frame in ipairs(frames) do
		headers[i] = i > 1 and HeaderHeight(frame) or 0
		local id = frame.GetBagID and frame:GetBagID() or frame:GetID()
		if i > 1 and id == REAGENT_BAG then
			RegridReagents(frame, grid, headers[i])
			-- Blizzard remet ses cases en place quand le sac change de taille.
			if not regridHooked[frame] and frame.UpdateItemLayout then
				regridHooked[frame] = true
				hooksecurefunc(frame, "UpdateItemLayout", function()
					T.SafeCall(PlaceBags)
				end)
			end
		end
	end
	local totalHeight, maxWidth = 0, 1
	for i, frame in ipairs(frames) do
		totalHeight = totalHeight + frame:GetHeight() - headers[i] + (i > 1 and BUTTON_GAP or 0)
		maxWidth = math.max(maxWidth, frame:GetWidth())
	end
	totalHeight = math.max(totalHeight, 1)
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
	for i, frame in ipairs(frames) do
		StripBag(frame)
		frame:SetParent(zone)
		frame:SetScale(scale)
		frame:ClearAllPoints()
		local header = headers[i]
		if i > 1 then
			y = y + BUTTON_GAP
			-- Detail de l'en-tete masque, qui recouvre le bas du sac du dessus :
			-- il ne doit pas intercepter la souris.
			frame:SetHitRectInsets(0, 0, header, 0)
			for _, part in ipairs({ frame.SearchBox, frame.FilterDropdown, frame.TitleContainer }) do
				T:Fade(part)
				if part and part.EnableMouse then
					part:EnableMouse(false)
				end
			end
		end
		frame:SetPoint("TOPRIGHT", zone, "TOPRIGHT", 0, -(y - header))
		y = y + frame:GetHeight() - header
		TintItems(frame)
	end
end

-------------------------------------------------------------------------------
-- Jauges d'experience et de reputation
-------------------------------------------------------------------------------

local xpGauge, repGauge

local function CreateGauge(parent, title, height)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetHeight(height)
	bar:SetStatusBarTexture(T:BarTexture())
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
	-- Gain d'experience : la jauge glisse et s'eclaire brievement ; passage
	-- de niveau (la jauge repart de zero) : eclat dore plus marque.
	local level = UnitLevel("player")
	if xpGauge.lastLevel and level > xpGauge.lastLevel then
		xpGauge:SetValue(0)
		T:Flash(xpGauge, nil, { 1, 0.82, 0.3 }, 0.9, 1.2)
	elseif xpGauge.lastXP and xp > xpGauge.lastXP then
		T:Flash(xpGauge, nil, { 1, 1, 1 }, 0.45, 0.5)
	end
	xpGauge.lastLevel, xpGauge.lastXP = level, xp
	T:SetSmoothValue(xpGauge, ratio, 0.6)
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
	T:SetSmoothValue(repGauge, ratio, 0.6)
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
	-- Le tiroir de droite (sacs, quetes, minimap) s'ouvre toujours au
	-- chargement ; celui du bas reprend son dernier etat.
	drawer.progress = (key == "right" or drawer.db.open) and 1 or 0
	drawer.target = drawer.progress

	-- Cadre cree des le chargement (voir EarlyFrame) : on le reprend.
	local name = "TharokUIDrawer" .. (key == "right" and "Right" or "Bottom")
	local frame = _G[name] or CreateFrame("Frame", name, UIParent)
	frame:ClearAllPoints()
	frame:SetFrameStrata("LOW")
	frame:EnableMouse(true) -- les clics ne traversent pas le panneau
	-- Fond gere ici (et non par le theme) pour pouvoir le teinter en combat.
	-- Bord ouvert (cote ecran) : la peinture s'y effiloche et le trait
	-- d'accent le longe ; le cadre net ne garde que les trois autres cotes.
	local open = key == "right" and "LEFT" or "TOP"
	drawer.bg = T:CreateSurface(frame, T.colors.bg[4], nil, open)
	drawer.border = T:CreateBorder(frame)
	if T.TextureOn() then
		drawer.border[open:lower()]:Hide()
	end
	drawer.accent = T:CreateAccentLine(frame, open, 2)
	PaintBackground(drawer)
	drawer.frame = frame

	-- Poignee : toujours a l'ecran, collee au bord interieur du tiroir.
	local handle = CreateFrame("Button", nil, UIParent)
	handle:SetFrameStrata("MEDIUM")
	handle:RegisterForClicks("LeftButtonUp")
	if key == "right" then
		handle:SetSize(12, 64)
		handle:SetPoint("RIGHT", frame, "LEFT", 0, 0)
	else
		handle:SetSize(64, 12)
		handle:SetPoint("BOTTOM", frame, "TOP", 0, 0)
	end
	local vertical = key == "right"
	local mark = T:CreateStroke(handle, "ARTWORK", vertical)
	local highlight = T:CreateStroke(handle, "HIGHLIGHT", vertical)
	if T.TextureOn() then
		-- Une touche de peinture sombre, et un coup de pinceau d'accent dessus.
		local dab = T:CreateStroke(handle, "BACKGROUND", vertical)
		dab:SetPoint("TOPLEFT", -5, 5)
		dab:SetPoint("BOTTOMRIGHT", 5, -5)
		local r, g, b = unpack(T.colors.bg)
		dab:Paint(r, g, b, 0.92)
		mark:SetPoint("TOPLEFT", -1, 1)
		mark:SetPoint("BOTTOMRIGHT", 1, -1)
		highlight:SetAllPoints(dab)
	else
		T:CreateBackground(handle)
		T:CreateBorder(handle)
		mark:SetPoint("TOPLEFT", 3, -3)
		mark:SetPoint("BOTTOMRIGHT", -3, 3)
		highlight:SetAllPoints()
	end
	highlight:Paint(unpack(T.colors.highlight))

	do
		local r, g, b = unpack(T.colors.accent)
		mark:Paint(r, g, b, 0.9)
	end

	handle:SetScript("OnClick", function()
		Toggle(key)
	end)
	handle:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
		GameTooltip:AddLine(key == "right" and "Tiroir de droite" or "Tiroir du bas")
		GameTooltip:AddLine("Clic : ouvrir ou fermer", 1, 1, 1)
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
	for _, name in ipairs({ "menu", "bagBar", "quests", "bags", "map", "tools" }) do
		zones[name] = CreateFrame("Frame", nil, right.frame)
	end

	-- Un filet entre les blocs : les elements ranges se lisent comme un seul
	-- panneau.
	for _, name in ipairs({ "bags", "map" }) do
		local line = T:CreateRule(zones[name])
		local y = GAP / 2 - line:GetHeight() / 2 -- centre dans l'intervalle
		line:SetPoint("BOTTOMLEFT", zones[name], "TOPLEFT", 0, y)
		line:SetPoint("BOTTOMRIGHT", zones[name], "TOPRIGHT", 0, y)
	end
	-- Meme filet entre la barre des sacs et les barres 5 et 6 (place par
	-- Layout).
	right.barsLine = T:CreateRule(right.frame)

	-- Fondu en bas du suivi de quetes : une ligne coupee a mi-hauteur se
	-- fond dans le tiroir au lieu d'etre tranchee net. Cadre au-dessus du
	-- suivi (strate et niveau ajustes a l'adoption).
	local fader = CreateFrame("Frame", nil, right.frame)
	fader:SetPoint("BOTTOMLEFT", zones.quests, "BOTTOMLEFT", 0, 0)
	fader:SetPoint("BOTTOMRIGHT", zones.quests, "BOTTOMRIGHT", 0, 0)
	fader:SetHeight(18)
	fader:EnableMouse(false)
	right.questFader = fader
	right.questFade = fader:CreateTexture(nil, "OVERLAY")
	right.questFade:SetAllPoints()
	right.questFade:SetColorTexture(1, 1, 1, 1)
	PaintBackground(right)

	-- Jauges d'experience et de reputation : tout en haut, bord a bord.
	xpGauge = CreateGauge(right.frame, "Expérience", XP_HEIGHT)
	xpGauge:SetPoint("TOPLEFT", right.frame, "TOPLEFT", 0, 0)
	xpGauge:SetPoint("TOPRIGHT", right.frame, "TOPRIGHT", 0, 0)
	repGauge = CreateGauge(right.frame, "Réputation", REP_HEIGHT)
	repGauge:SetPoint("TOPLEFT", right.frame, "TOPLEFT", 0, -XP_HEIGHT)
	repGauge:SetPoint("TOPRIGHT", right.frame, "TOPRIGHT", 0, -XP_HEIGHT)

	-- Acces au menu Tharok UI, au bout de la ligne du menu systeme.
	local menu = CreateFrame("Button", nil, zones.tools)
	menu:SetAllPoints()
	T:CreateBackground(menu)
	T:CreateBorder(menu)
	-- "T" de l'icone Tharok UI, a la couleur d'accent.
	local glyph = menu:CreateTexture(nil, "OVERLAY")
	glyph:SetTexture(T.media.glyph)
	glyph:SetPoint("CENTER")
	glyph:SetSize(STRIP_MIN - 2, STRIP_MIN - 2)
	glyph:SetVertexColor(unpack(T.colors.accent))
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
	-- Le fondu doit passer au-dessus du suivi.
	local fader = drawers.right and drawers.right.questFader
	if fader then
		fader:SetFrameStrata(frame:GetFrameStrata())
		fader:SetFrameLevel(math.min(frame:GetFrameLevel() + 30, 9000))
	end
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
		-- Une barre qui apparait ou disparait change la hauteur du tiroir.
		bar:HookScript("OnShow", QueueLayout)
		bar:HookScript("OnHide", QueueLayout)
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

		AdoptRow(MicroMenuContainer, MicroMenu, zones.menu, "CENTER", false)
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

		-- Taille de la carte ou position du bandeau changees (mode Edition) :
		-- on remesure et on refait la mise en page.
		local remeasureQueued = false
		local function Remeasure()
			if remeasureQueued then
				return
			end
			remeasureQueued = true
			C_Timer.After(0, function()
				T:AfterCombat(function()
					remeasureQueued = false
					pcall(MeasureMap)
					QueueLayout()
				end)
			end)
		end
		if Minimap then
			Minimap:HookScript("OnSizeChanged", Remeasure)
		end
		for _, method in ipairs({ "SetHeaderUnderneath", "UpdateHeaderPosition" }) do
			if MinimapCluster and MinimapCluster[method] then
				hooksecurefunc(MinimapCluster, method, Remeasure)
			end
		end

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
		end

		-- Ancien conteneur du menu systeme et des sacs, vide une fois ceux-ci
		-- ranges : il reste en bas a droite, par-dessus la minimap, et
		-- intercepterait la souris.
		if MicroButtonAndBagsBar then
			pcall(MicroButtonAndBagsBar.EnableMouse, MicroButtonAndBagsBar, false)
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
		-- Cadres de groupe : colles a gauche du cadre du joueur, alignes sur
		-- son bas (ils s'empilent vers le haut). Le regard reste au centre.
		if PartyFrame and PlayerFrame then
			Adopt(PartyFrame, function(frame)
				frame:ClearAllPoints()
				frame:SetPoint("BOTTOMRIGHT", PlayerFrame, "BOTTOMLEFT", -3 * PAD, 0)
			end)
		end

		-- Compteur DPS/HPS de Tharok UI, dans le coin droit du tiroir.
		Adopt(TharokUIMeter, function(frame)
			frame:SetParent(bottom.frame)
			-- Compteur cale en haut a droite, sur la hauteur du tiroir : ses
			-- lignes s'ajoutent vers le bas.
			if T.SetMeterBox then
				T:SetMeterBox(bottom.meterWidth, bottom.meterHeight)
			end
			frame:ClearAllPoints()
			frame:SetPoint("TOPRIGHT", bottom.frame, "TOPRIGHT", -PAD, -PAD)
		end)
		if Module.db.chat then
			-- Fenetre de chat principale : calee dans la partie gauche du
			-- tiroir, a gauche des barres. Elle reste hors du tiroir dans la
			-- hierarchie (le jeu gere ses onglets), mais glisse avec lui.
			Adopt(ChatFrame1, function(frame)
				local width = bottom.chatWidth or math.max(bottom.barsLeft - 3 * PAD - 30, 150)
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
	-- Largeur par defaut reduite (20 % -> 17 %) : contenu plus compact.
	if Module.db.version < 3 then
		if Module.db.width == 20 then
			Module.db.width = 17
		end
		Module.db.version = 3
	end

	-- Le bouton "T" du tiroir donne acces au menu : pas de pastille sur la
	-- minimap, qui en masquerait un coin.
	if drawers.right then
		T.minimapButtonElsewhere = true
		if T.UpdateMinimapButton then
			T:UpdateMinimapButton()
		end
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

	-- Discretion : au repos (hors combat, sans cible, souris ailleurs, rien
	-- au curseur), les barres du tiroir du bas s'estompent ; elles reviennent
	-- en douceur des qu'il se passe quelque chose.
	local barsIdle
	T:Every(0.15, function()
		local bottom = drawers.bottom
		if not bottom then
			return
		end
		local idleAlpha = Module.db.idleBars or 1
		local idle = idleAlpha < 1
			and not inCombat
			and not UnitExists("target")
			and not GetCursorInfo()
			and not bottom.frame:IsMouseOver()
		if idle == barsIdle then
			return
		end
		barsIdle = idle
		for _, name in ipairs(BOTTOM_BARS) do
			local holder = holders[_G[name] or false]
			if holder then
				T:FadeTo(holder, idle and idleAlpha or 1, idle and 0.6 or 0.15)
			end
		end
	end)

	T:On("DISPLAY_SIZE_CHANGED", QueueLayout)
	T:On("UI_SCALE_CHANGED", QueueLayout)

	-- Les tiroirs restent tels quels en combat : seuls leur fond (rouge
	-- leger) et leur opacite changent. Une animation en cours est terminee
	-- d'un coup, le verrouillage de combat n'etant pas encore actif ici.
	local function SetCombat(state)
		inCombat = state
		for _, drawer in pairs(drawers) do
			if state then
				drawer.progress = drawer.target
			end
			Place(drawer)
		end
		AnimateCombat(state and 1 or 0)
		UpdateBreath()
	end
	T:On("PLAYER_REGEN_DISABLED", function()
		SetCombat(true)
	end)
	T:On("PLAYER_REGEN_ENABLED", function()
		SetCombat(false)
	end)
	-- Mana faible : le liseré glisse du rouge au violet et respire.
	-- (T:On passe le nom de l'evenement en premier argument.)
	local function CheckMana(_, unit)
		if unit and unit ~= "player" then
			return
		end
		local low = IsLowMana()
		if low ~= lowMana then
			lowMana = low
			AnimateMana(low and 1 or 0)
			UpdateBreath()
		end
	end
	T:OnUnit("UNIT_POWER_UPDATE", CheckMana, "player")
	T:OnUnit("UNIT_MAXPOWER", CheckMana, "player")
	T:OnUnit("UNIT_DISPLAYPOWER", CheckMana, "player")
	T:On("PLAYER_ENTERING_WORLD", CheckMana)
	CheckMana()
	-- Changement de theme : on repeint le fond avec la nouvelle couleur.
	hooksecurefunc(T, "RefreshTheme", function()
		for _, drawer in pairs(drawers) do
			PaintBackground(drawer)
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
	LiveRange("width", "Largeur", 12, 35, 1, 1, true),
	{ type = "toggle", key = "bags", label = "Contenu des sacs dans le tiroir" },
	{ type = "toggle", key = "tooltip", label = "Décaler l'infobulle quand le tiroir est ouvert" },
	{ type = "toggle", key = "hideStatusBars", label = "Masquer les barres d'expérience et de réputation du jeu" },

	{ type = "header", label = "Tiroir du bas" },
	Nested("bottom", "use", "Utiliser le tiroir du bas"),
	{ type = "toggle", key = "chat", label = "Chat rangé dans le tiroir (à gauche des barres)" },

	{ type = "header", label = "Apparence" },
	LiveRange("alpha", "Opacité par défaut", 20, 100, 5, 100),
	LiveRange("combatAlpha", "Opacité en combat", 20, 100, 5, 100),
	LiveRange("idleBars", "Barres 1 à 4 au repos (100 = toujours pleines)", 20, 100, 5, 100),
	{
		type = "range",
		key = "lowMana",
		label = "Mana faible : liseré violet en combat sous (0 = jamais)",
		min = 0,
		max = 60,
		step = 5,
		suffix = "%",
	},
	LiveRange("barScale", "Échelle des barres 1 à 4 (tiroir du bas)", 50, 100, 5, 100, true),
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
