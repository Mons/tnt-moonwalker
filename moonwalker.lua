--[[

moonwalker
	
	Iterate over one space with the following logic
	
	Collect stage:
	1. create an iterator and iterate over space for not more than `pause` items
	2. put items for update into temporary lua table
	3. yield fiber, then reposition iterator to GT(`last selected tuple`)
	4. if collected enough (`take`) tuples, switch to update phase

	Update stage:

	1. iterate over temporary table
	2. for each element call `actor`
	3. reposition iterator to GT(`last selected tuple`), switch to collect phase

	+ Parameters
		+ examine: (optional, function:boolean) - called during collect phase. **must not yield**. 
		+ actor: (function, altname: updater) - called during update phase for every examined tuple
		+ pause: `1000` (number) - make fiber.yield after stepping over this count of items.
		+ take: `500` (number) - how many items should be collected before calling updates
		+ dryrun: `false` (boolean) - don't call actor, only print stats
		+ limit: `` (optional, number) - process not more than limit items (useful for testing)
		+ progress: `2%` (optional, string or number) - print progress message every N records or percent

]]

local fiber = require 'fiber'
local log = require 'log'
local ffi = require 'ffi'
local clock = require 'clock'

local M = {}

local function create_keyfields(index)
	local f = {}
	for k,v in pairs(index.parts) do
		table.insert(f, "t[".. v.fieldno .."]")
	end
	return loadstring('return function(t) return '..table.concat(f,",")..' end')()
end

local function iiterator(index, itype, key)
	local f, ctx, state = index:pairs(key, { iterator = itype })
	local tuple
	return function ()
		state, tuple = f(ctx,state)
		if not state then return nil end
		return tuple
	end
end

local function moonwalker(opts)
	local o = {}
	assert(opts.space, "Required option .space")
	local space = opts.space
	local waitevery = opts.pause or 1000
	local takeby = opts.take or 500
	local examine = opts.examine
	local updater = opts.actor or opts.updater
	assert(type(updater) == 'function', "Need .actor function")
	local dryrun = opts.dryrun or false
	local limit = opts.limit or 2^63
	local printevery = opts.progress or '2%'

	local index      = opts.index or space.index[0]
	local keyfields  = create_keyfields(index)
	if index.type ~= "TREE"then
		error("Index "..index.name.." in space "..space.name.." is non-iteratable",2)
	end

	local size  = space:len()
	local start = clock.time()
	local prev  = start

	if type(printevery) == 'string' then
		if printevery:match('%%$') then
			local num = math.floor(size * tonumber(printevery:match('^(%d+)')) / 100)
			if num > size or num < 0 then error("Bad value for progress",2) end
			-- print("use num ",num)
			printevery = num
		else
			printevery = tonumber(printevery)
		end
	end
	if printevery > size then
		printevery = math.floor(size/4)
	end

	log.info("Processing %d items in %s mode; wait: 1/%d; take: %d", size, dryrun and "dryrun" or "real", waitevery, takeby)
	-- if true then return end

	local working = true
	local function batch_update(toupdate)
		if not dryrun then		
			for _,v in ipairs(toupdate) do
				local r,e = pcall(updater, v)
				if not r then
					local t = tostring(v)
					if #t > 1000 then t = string.sub(t,1,995)..'...' end
					error(3,string.format("failed to update %s: %s",t,e))
					working = false
					break
				end
			end
		end
	end

	local it = iiterator( index, box.index.ALL )
	local v
	local toupdate = {}
	local c = 0
	local u = 0
	local csw   = 0
	local clock_sum = 0
	local clock1 = clock.proc()

	while working do c = c + 1
		if c % waitevery == 0 then
			clock_sum = clock_sum + ( clock.proc() - clock1 )
			csw = csw + 1
			-- print("yield on ",c)
			fiber.sleep( 0 )
			clock1 = clock.proc()
			it = iiterator( index, box.index.GT, keyfields(v) )
		end
		v = it()
		-- print(v)

		if not v or c > limit then
			batch_update(toupdate)
			break
		end
		
		if not examine or examine(v) then
			u = u + 1
			table.insert(toupdate, v)
		end
		
		if #toupdate >= takeby then
			clock_sum = clock_sum + ( clock.proc() - clock1 )
			csw = csw + 1
			batch_update(toupdate)
			clock1 = clock.proc()
			toupdate = {}
			it = iiterator(index, box.index.GT, keyfields(v))
		end
		
		if c % printevery == 0 then
			local now = clock.time()
			local r,e = pcall(function()
				local run = now - start
				local run1 = now - prev
				local rps = c/run
				local rps1 = printevery/run1
				collectgarbage("collect")
				local mem = collectgarbage("count")
				log.info("Processed %d (%d) (%0.1f%%) in %0.3fs (rps: %.0f tot; %.0f/%.1fs; %.2fms/c) ETA:+%ds (or %ds) Mem: %dK",
					c, u,
					100*c/size,
					run,
					c/run, rps1, run1,
					1000*clock_sum/csw,
					
					(size - c)/rps1,
					(size - c)/rps,
					
					mem
				)
			end)
			if not r then print(e) end
			prev = now
		end
	end
	return { processed = c-1; updated = u; yields = csw }
end

return moonwalker
