-- Tharok UI - commandes /tharok

local T = TharokUI

local function FindModule(text)
	text = strlower(text)
	for _, name in ipairs(T.moduleOrder) do
		if strlower(name) == text then
			return T.modules[name]
		end
	end
end

local ParseBool, State = T.ParseBool, T.StateText

local function ShowStatus()
	T:Print("version", T.version)
	if #T.moduleOrder == 0 then
		print("  Aucun module installe.")
	end
	for _, name in ipairs(T.moduleOrder) do
		local module = T.modules[name]
		print(format("  |cffffd100%s|r : %s", name, State(module.db.enabled)))
		for key, value in pairs(module.db) do
			if key ~= "enabled" and type(value) == "boolean" then
				print(format("      %s : %s", key, State(value)))
			end
		end
	end
	print("  /tharok config  (menu des parametres)")
	print("  /tharok theme   (accent, fonds, bordures, police)")
	print("  /tharok scale   (mise a l'echelle selon la resolution)")
	print("  /tharok <module> on|off")
	print("  /tharok <module> <option> on|off")
	print("  Les changements s'appliquent apres /reload.")
end

-------------------------------------------------------------------------------
-- /tharok theme
-------------------------------------------------------------------------------

local function ParseHex(text)
	if not text or not strmatch(text, "^%x%x%x%x%x%x$") then
		return nil
	end
	return {
		tonumber(strsub(text, 1, 2), 16) / 255,
		tonumber(strsub(text, 3, 4), 16) / 255,
		tonumber(strsub(text, 5, 6), 16) / 255,
	}
end

local function ToHex(color)
	return format("%02x%02x%02x", color[1] * 255 + 0.5, color[2] * 255 + 0.5, color[3] * 255 + 0.5)
end

local function ShowTheme()
	local theme = T.db.theme
	T:Print("theme")
	print("  accent : " .. (theme.accent and ToHex(theme.accent) or "couleur de classe"))
	print(format("  bg     : %d%%", theme.bgAlpha * 100 + 0.5))
	print("  border : " .. ToHex(theme.border))
	print(format("  shade  : %d%%", theme.shade * 100 + 0.5))
	print("  font   : " .. State(theme.font))
	print("  /tharok theme accent class|RRGGBB   (apres /reload)")
	print("  /tharok theme bg <0-100>            (immediat)")
	print("  /tharok theme border RRGGBB         (immediat)")
	print("  /tharok theme shade <0-100>         (degrade des barres, immediat)")
	print("  /tharok theme font on|off           (apres /reload)")
end

local function ThemeCommand(args)
	local theme = T.db.theme
	local key = args[2] and strlower(args[2])
	local value = args[3] and strlower(args[3])

	if key == "accent" then
		if value == "class" then
			theme.accent = nil
			T:Print("accent = couleur de classe - tape /reload pour appliquer.")
			return
		end
		local color = ParseHex(value)
		if color then
			theme.accent = color
			T:Print("accent =", value, "- tape /reload pour appliquer.")
			return
		end
	elseif key == "bg" then
		local percent = T.ParseNumber(value, 0, 100)
		if percent then
			theme.bgAlpha = percent / 100
			T.colors.bg[4] = theme.bgAlpha
			T:RefreshTheme()
			T:Print("opacite des fonds =", percent .. "%")
			return
		end
	elseif key == "border" then
		local color = ParseHex(value)
		if color then
			theme.border = color
			T.colors.border = { color[1], color[2], color[3], 1 }
			T:RefreshTheme()
			T:Print("bordures =", value)
			return
		end
	elseif key == "shade" then
		local percent = T.ParseNumber(value, 0, 100)
		if percent then
			theme.shade = percent / 100
			T:RefreshTheme()
			T:Print("degrade des barres =", percent .. "%")
			return
		end
	elseif key == "font" then
		local enabled = ParseBool(value)
		if enabled ~= nil then
			theme.font = enabled
			T:Print("police unique =", State(enabled), "- tape /reload pour appliquer.")
			return
		end
	end
	ShowTheme()
end

SLASH_THAROKUI1 = "/tharok"
SLASH_THAROKUI2 = "/tk"

SlashCmdList.THAROKUI = function(message)
	local args = {}
	for word in gmatch(message or "", "%S+") do
		args[#args + 1] = word
	end

	if #args == 0 then
		ShowStatus()
		return
	end

	local first = strlower(args[1])
	if first == "config" or first == "menu" or first == "options" then
		T:ToggleOptions()
		return
	end

	if strlower(args[1]) == "theme" then
		ThemeCommand(args)
		return
	end

	if strlower(args[1]) == "scale" then
		T:ScaleCommand(args)
		return
	end

	local module = FindModule(args[1])
	if not module then
		T:Print("module inconnu :", args[1])
		return
	end

	-- Un module peut traiter lui-meme ses arguments (ex. /tharok fade ...).
	if module.OnCommand and module.db then
		local moduleArgs = {}
		for i = 2, #args do
			moduleArgs[#moduleArgs + 1] = args[i]
		end
		local ok, handled = T.SafeCall(module.OnCommand, module, moduleArgs)
		if ok and handled then
			return
		end
	end

	local key, value
	if #args == 2 then
		key, value = "enabled", ParseBool(args[2])
	else
		key, value = args[2], ParseBool(args[3])
		-- retrouve la casse exacte de l'option
		for optionName in pairs(module.db) do
			if strlower(optionName) == strlower(key) then
				key = optionName
				break
			end
		end
	end

	if value == nil or type(module.db[key]) ~= "boolean" then
		T:Print("usage : /tharok", module.name, "[option] on|off")
		return
	end

	module.db[key] = value
	T:Print(module.name, key, "=", State(value), "- tape /reload pour appliquer.")
end
