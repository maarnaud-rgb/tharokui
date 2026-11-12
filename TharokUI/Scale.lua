-- Tharok UI - mise a l'echelle selon la resolution
--
-- L'interface est composee sur un ecran de reference (ex. 4K). On memorise la
-- taille du "canevas" de UIParent sur cet ecran ; sur un autre ecran, on
-- regle l'echelle de UIParent pour retrouver ce meme canevas. Ce facteur
-- s'applique par-dessus toutes les echelles reglees par le joueur (mode
-- Edition, modules...) : tout retrecit ou grandit d'un bloc, sans
-- chevauchement. Voir /tharok scale.

local T = TharokUI

local naturalScale -- echelle de UIParent decidee par le jeu, sans nous
local appliedScale -- echelle que nous avons posee (nil = aucune)

local function Near(a, b)
	return math.abs(a - b) < 0.0005
end

-- Taille de l'ecran en unites d'echelle 1 (768 de haut par convention).
local function ScreenSize()
	local width, height = GetPhysicalScreenSize()
	if not width or not height or height == 0 then
		return nil
	end
	return 768 * width / height, 768, width, height
end

-- Memorise l'ecran courant comme reference.
local function CaptureReference()
	local width, height, physicalWidth, physicalHeight = ScreenSize()
	if not width or not naturalScale or naturalScale == 0 then
		return false
	end
	local db = T.db.scale
	db.width = width / naturalScale
	db.height = height / naturalScale
	db.resolution = format("%dx%d", physicalWidth, physicalHeight)
	return true
end

-- Echelle a donner a UIParent pour que le canevas de reference tienne en
-- entier a l'ecran (si le format d'ecran differe, il reste de la marge sur
-- un axe plutot qu'un debordement sur l'autre).
local function TargetScale()
	local db = T.db.scale
	if not db.enabled or not db.width or not db.height then
		return naturalScale
	end
	local width, height = ScreenSize()
	if not width then
		return naturalScale
	end
	local scale = math.min(width / db.width, height / db.height)
	if Near(scale, naturalScale) then
		return naturalScale
	end
	return scale
end

local function Apply()
	if not naturalScale then
		return
	end
	local target = TargetScale()
	if not target or target <= 0 then
		return
	end
	if not Near(UIParent:GetScale(), target) then
		UIParent:SetScale(target)
	end
	appliedScale = target
	if T.RelayoutBorders then
		T.RelayoutBorders()
	end
end

-- UIParent est protege : hors combat uniquement.
local pending = false

local function QueueApply()
	if pending then
		return
	end
	pending = true
	T:AfterCombat(function()
		pending = false
		Apply()
	end)
end

-- Appele par le socle a PLAYER_LOGIN, avant le demarrage des modules.
function T:InitScale()
	if type(T.db.scale) ~= "table" then
		T.db.scale = {}
	end
	local db = T.db.scale
	if db.enabled == nil then
		db.enabled = true
	end

	naturalScale = UIParent:GetScale()

	if not db.width or not db.height then
		if CaptureReference() then
			T:Print(
				"mise a l'echelle : ecran de reference =",
				db.resolution,
				"(/tharok scale ref pour le redefinir sur un autre ecran)."
			)
		end
	end
	QueueApply()
end

-- Le jeu recalcule l'echelle de UIParent quand la resolution ou le reglage
-- d'echelle change : on releve sa nouvelle valeur, puis on repose la notre.
local function OnScaleEvent()
	if not naturalScale then
		return
	end
	local current = UIParent:GetScale()
	if not appliedScale or not Near(current, appliedScale) then
		naturalScale = current
	end
	QueueApply()
end

T:On("UI_SCALE_CHANGED", OnScaleEvent)
T:On("DISPLAY_SIZE_CHANGED", OnScaleEvent)

-------------------------------------------------------------------------------
-- /tharok scale
-------------------------------------------------------------------------------

local State = T.StateText

function T:ScaleCommand(args)
	local db = T.db.scale
	local key = args[2] and strlower(args[2])

	local enabled = T.ParseBool(key)

	if enabled ~= nil then
		db.enabled = enabled
		QueueApply()
		T:Print("mise a l'echelle =", State(db.enabled))
		return
	elseif key == "ref" then
		if InCombatLockdown() then
			T:Print("impossible en combat.")
		elseif CaptureReference() then
			QueueApply()
			T:Print("ecran de reference =", db.resolution)
		end
		return
	end

	local _, _, physicalWidth, physicalHeight = ScreenSize()
	T:Print("mise a l'echelle", State(db.enabled))
	print("  reference : " .. (db.resolution or "aucune"))
	if physicalWidth then
		print(format("  ecran     : %dx%d", physicalWidth, physicalHeight))
	end
	if naturalScale and naturalScale > 0 then
		print(format("  facteur   : x%.2f", UIParent:GetScale() / naturalScale))
	end
	print("  /tharok scale on|off   (immediat)")
	print("  /tharok scale ref      (l'ecran actuel devient la reference)")
end
