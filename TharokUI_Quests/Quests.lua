-- Tharok UI - Quetes
-- Suivi des objectifs epure : les bandeaux decores des en-tetes sont
-- remplaces par un simple trait a la couleur d'accent. Le contenu (quetes,
-- objectifs, boutons d'objets) n'est pas modifie. Position et hauteur se
-- reglent dans le mode Edition du jeu.

local T = TharokUI

local Module = T:RegisterModule("Quests", {
	title = "Quetes",
})

local skinned = {}

local function SkinHeader(header)
	if not header or skinned[header] then
		return
	end
	skinned[header] = true

	T:Fade(header.Background)

	T:CreateAccentLine(header, "BOTTOM", 2)

	T:StyleFont(header.Text, nil, "OUTLINE")
end

local function SkinTracker()
	local tracker = ObjectiveTrackerFrame
	SkinHeader(tracker.Header)
	if type(tracker.modules) == "table" then
		for _, module in ipairs(tracker.modules) do
			SkinHeader(module.Header)
		end
	end
end

function Module:OnEnable()
	if not ObjectiveTrackerFrame then
		return
	end
	SkinTracker()
	-- Des modules (scenario, metiers...) peuvent s'ajouter en cours de jeu.
	if ObjectiveTrackerFrame.AddModule then
		hooksecurefunc(ObjectiveTrackerFrame, "AddModule", SkinTracker)
	end
end
