-- Warn and require confirmation when an AUR package maintainer changes.
--
-- The known maintainer for each package is stored in a plain text cache file
-- inside the yay cache directory (build_dir). On the first upgrade for a
-- package the current maintainer is recorded without any warning. On
-- subsequent upgrades:
--   * different maintainer → notify the user and prompt for confirmation
--
-- The cache is updated whenever a new package is seen or for existing packages,
-- when the package has successfully been upgraded.
--
-- Cache file location: <cache_dir>/maintainer_cache
-- Format: one "pkgname=maintainer" entry per line.

local cache_file = yay.opt.build_dir .. "/maintainer_cache"

local changed = {}

local function load_cache()
	local cache = {}
	local f = io.open(cache_file, "r")
	if not f then
		return cache
	end

	for line in f:lines() do
		local name, maintainer = line:match("^([^=]+)=(.*)$")
		if name then
			cache[name] = maintainer
		end
	end

	f:close()
	return cache
end

local function write_cache(cache)
	local f = assert(io.open(cache_file, "w"))

	for name, maintainer in pairs(cache) do
		f:write(name .. "=" .. maintainer .. "\n")
	end

	f:close()
end

local function save_cache(entries)
	local cache = load_cache()
	local dirty = false

	for name, item in pairs(entries) do
		if item.confirmed then
			cache[name] = item.new
			dirty = true
		elseif item.old ~= nil then
			cache[name] = item.old
		end
	end

	if dirty then
		write_cache(cache)
	end
end

local function ask_yes_no(prompt)
	io.write(prompt .. " [y/N] ")
	local answer = io.read()

	if not answer then
		return false
	end

	answer = answer:lower()
	return answer == "y" or answer == "yes"
end

yay.create_autocmd("UpgradeSelect", {
	desc = "confirm AUR maintainer changes",
	callback = function(event)
		local cache = load_cache()
		local changed_maintainers = {}

		changed = {}

		for _, pkg in ipairs(event.data.upgrades) do
			if pkg.repository == "aur" and pkg.maintainer ~= "" then
				local cached = cache[pkg.name]

				if cached == nil then
					-- First time seeing this package: seed cache immediately.
					changed[pkg.name] = {
						old = nil,
						new = pkg.maintainer,
						confirmed = true,
					}
				elseif cached ~= pkg.maintainer then
					-- Maintainer changed: prompt now, but only update cache after install succeeds.
					changed[pkg.name] = {
						old = cached,
						new = pkg.maintainer,
						confirmed = false,
					}

					table.insert(changed_maintainers, {
						name = pkg.name,
						old = cached,
						new = pkg.maintainer,
					})
				end
			end
		end

		save_cache(changed)

		if #changed_maintainers > 0 then
			yay.log.error("AUR package maintainer change detected:")

			for _, item in ipairs(changed_maintainers) do
				yay.log.error("  " .. item.name .. " (was: " .. item.old .. ", now: " .. item.new .. ")")
			end

			if not ask_yes_no("Continue with upgrade anyway?") then
				yay.abort("aborted because an AUR package maintainer changed")
			end
		end

		return { exclude = {}, skip_menu = false }
	end,
})

yay.create_autocmd("PostInstall", {
	desc = "confirm installed AUR maintainer changes",
	callback = function(event)
		for _, pkg in ipairs(event.data.packages) do
			if pkg.source == "aur" and changed[pkg.name] ~= nil then
				changed[pkg.name].confirmed = true
			end
		end

		save_cache(changed)
	end,
})
