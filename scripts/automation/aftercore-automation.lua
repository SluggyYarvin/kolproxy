function get_combat_macro_ids()
	local macros = {}
	local pt = get_page("/account_combatmacros.php")
	for x in pt:gmatch("<option.-</option>") do
		local macroid = tonumber(x:match([[value="([0-9]+)"]]))
		local macroname = x:match(">(.-)</option>")
		if macroid and macroname then
			macros[macroname] = macroid
		end
	end
	return macros
end

local function autoattack_macro_id()
	local tbl = ascension["__script.aftercore script options"]
	if tbl and tbl.macroid then
		return "99" .. tbl.macroid
	end
end

function spend_aftercore_turns()
	local priorities = {
		["automate-nemesis"] = 10,
		["automate-a-quest-lol"] = 50,
		["automate-nemesis-island"] = 100,
		["automate-felonia"] = 1000,
		["automate-suburbandis"] = 1500,
		["automate-spaaace"] = 2000,
	}
	if advs() < 150 then
		priorities["automate-nemesis"] = nil
	end
	local available_scripts = {}
	local details = {}
	local fs = {}
	for x, y in pairs(list_automation_scripts()) do
		if y.category == "Quests" and y.link and priorities[x] then
			table.insert(available_scripts, x)
			details[x] = y.details
			fs[x] = y.f
		end
	end
	table.sort(available_scripts, function(a, b) return priorities[a] < priorities[b] end)

	if #available_scripts >= 1 then
		local x = available_scripts[1]
		print("DOING", x)
		local script = get_automation_scripts()
		script.want_familiar("Slimeling")
		script.wear {}
		script.ensure_buffs {}
		async_get_page("/familiar.php", { action = "hatseat", famid = get_familiarid("BRICKO chick"), pwd = session.pwd })
		--print("DETAILS", tostring(details[x]))
		if details[x].macro or x == "automate-suburbandis" then -- HACK: for old suburbandis style script, TODO: FIX!
			print("  autoattack off")
			disable_autoattack()
		else
			print("  setting autoattack")
			set_autoattack_id(autoattack_macro_id())
		end
		text, url = fs[x]()
		if not locked() and not list_automation_scripts()[x].link then
			print("SUCCESS!", x)
			return spend_aftercore_turns()
		end
	end

	disable_autoattack()

	return text, url, available_scripts
end

aftercore_automation_href = add_automation_script("aftercore-automation", function()
	script = get_automation_scripts()

	automate_aftercore_pulls()
	automate_aftercore_pulls()
	automate_aftercore_pulls()
	pull_storage_items { "antique accordion" }
	pull_storage_items { "milk of magnesium" }
	pull_storage_items { "turtle totem" }
	pull_storage_items { "saucepan" }
	pull_storage_items { "borrowed time" }
	use_item("borrowed time")

	local function remaining_spleen()
		return estimate_max_spleen() - spleen()
	end
	local function remaining_fullness()
		return estimate_max_fullness() - fullness()
	end
	local function remaining_drunkenness()
		return estimate_max_safe_drunkenness() - drunkenness()
	end
	while remaining_spleen() > 0 do
		if remaining_spleen() >= 4 then
			maybe_pull_item("agua de vida", 1)
			use_item("agua de vida")
		elseif remaining_spleen() == 3 then
			maybe_pull_item("mojo filter", 1)
			use_item("mojo filter")
			assert(remaining_spleen() == 4)
		elseif remaining_spleen() <= 2 then
			maybe_pull_item("twinkly wad", remaining_spleen())
			use_item("twinkly wad")
			use_item("twinkly wad")
		else
			break
		end
	end
	while remaining_fullness() >= 5 do
		local f = remaining_fullness()
		script.ensure_buffs { "Got Milk" }
		script.ensure_buff_turns("Got Milk", remaining_fullness())
		local himeins = { "hot hi mein", "cold hi mein", "stinky hi mein", "spooky hi mein", "sleazy hi mein" }
		pull_storage_items(himeins)
		for _, x in ipairs(himeins) do eat_item(x) end
		if f == remaining_fullness() then break end
	end
	local eq = equipment()
	while remaining_drunkenness() > 0 do
		script.ensure_buffs { "Ode to Booze" }
		script.ensure_buff_turns("Ode to Booze", remaining_drunkenness())
		if remaining_drunkenness() >= 4 then
			maybe_pull_item("tuxedo shirt", 1)
			equip_item("tuxedo shirt")
			if not have_equipped_item("tuxedo shirt") then
				critical "Couldn't wear tuxedo shirt"
			end
			maybe_pull_item("soft green echo eyedrop antidote martini", 1)
			drink_item("soft green echo eyedrop antidote martini")
		elseif remaining_drunkenness() >= 2 then
			maybe_pull_item("Feliz Navidad", 1)
			drink_item("Feliz Navidad")
		elseif remaining_drunkenness() >= 1 then
			maybe_pull_item("pumpkin beer", 1)
			drink_item("pumpkin beer")
		end
	end
	set_equipment(eq)
	text, url = get_page("/main.php")
	text = add_message_to_page(text, "Done.", "Automation results:")
	text, url, available_scripts = spend_aftercore_turns()
	if not locked() then
		automate_pvp_fights(pvpfights(), 2, "lootwhatever")
		for _, x in ipairs { "Boris's key", "Jarlsberg's key", "Sneaky Pete's key", "digital key", "Richard's star key" } do
			if have_item(x) then
				if not have_item("lime") then
					pull_storage_items { "lime" }
				end
				cook_items(x, "lime")()
			end
		end
	end
	if not locked() and not available_scripts[1] then
		if advs() > 0 then
			set_autoattack_id(autoattack_macro_id())
			text, url = run_castle_turns(advs(), familiarid())
		end
	end
	return text, url
end)

setup_aftercore_automation_href = add_automation_script("setup-aftercore-automation", function()
	if params.confirm == "yes" and params.macroid then
		ascension["__script.aftercore script options"] = { macroid = tonumber(params.macroid) }
		character["__script.aftercore script option defaults"] = { macroid = tonumber(params.macroid) }
		return get_page("/main.php")
	end
	local macrolist = {}
	for a, b in pairs(get_combat_macro_ids()) do
		table.insert(macrolist, { name = a, id = b })
	end
	table.sort(macrolist, function(x, y) return x.name < y.name end)
	local optionlist = {}
	local defaultid = (character["__script.aftercore script option defaults"] or {}).macroid
	for _, x in ipairs(macrolist) do
		if x.id == defaultid then
			table.insert(optionlist, string.format([[<option value="%d" selected="selected">%s</option>]], x.id, x.name))
		else
			table.insert(optionlist, string.format([[<option value="%d">%s</option>]], x.id, x.name))
		end
	end
	return [[
<form action="/kolproxy-automation-script" method="get">
<input type="hidden" name="pwd" value="]]..session.pwd..[[">
<input type="hidden" name="confirm" value="yes">
<input type="hidden" name="automation-script" value="setup-aftercore-automation">
Pick macro to use for automation scripts:<br>
<select name="macroid">
]] .. table.concat(optionlist, "\n") .. [[
</select><br>
<input type="submit">
</form>
]]
end)

add_printer("/main.php", function()
	if tonumber(status().freedralph) == 0 then return end
	if not setting_enabled("enable turnplaying automation") then return end

	local rows = {}

	if autoattack_macro_id() then
		local alink = [[<a href="]]..aftercore_automation_href { pwd = session.pwd }..[[" style="color: green">{ Make aftercore go away }</a>]]
		table.insert(rows, [[<tr><td><center>]] .. alink .. [[</center></td></tr>]])
	else
		local alink = [[<a href="]]..setup_aftercore_automation_href { pwd = session.pwd }..[[" style="color: green">{ Setup aftercore automation }</a>]]
		table.insert(rows, [[<tr><td><center>]] .. alink .. [[</center></td></tr>]])
	end

	text = text:gsub([[title="Bottom Edge".-</table>]], [[%0<table>]] .. table.concat(rows) .. [[</table>]])
end)
