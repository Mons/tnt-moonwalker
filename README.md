# Iterate over one space with the following logic

- Collect stage:
	1. create an iterator and iterate over space for not note than `pause` items
	2. put items for update into temporary lua table
	3. yield fiber, then reposition iterator to GT(`last selected tuple`)
	4. if collected enough (`take`) tuples, switch to update phase

- Update stage:

	1. iterate over temporary table
	2. for each element call `actor`
	3. reposition iterator to GT(`last selected tuple`), switch to collect phase

## Parameters

+ examine: (optional, function:boolean) - called during collect phase. **must not yield**. 
+ actor: (function, altname: updater) - called during update phase for every examined tuple
+ pause: `1000` (number) - make fiber.yield after stepping over this count of items.
+ take: `500` (number) - how many items should be collected before calling updates
+ dryrun: `false` (boolean) - don't call actor, only print stats
+ limit: `` (optional, number) - process not more than limit items (useful for testing)
+ progress: `2%` (optional, string or number) - print progress message every N records or percent


## Example

```lua
local moonwalker = require 'moonwalker'

-- update the whole database, (the most simple example)
moonwalker {
	space = box.space.users;
	actor = function(t)
		box.space.users:update({t[1]},{
			{'=', 2, os.time()}
		})
	end;
}

-- update database, add missed fields (example with examine)
moonwalker {
	space = box.space.users;
	examine = function(t)
		return #t < 4; -- user tuple have only 3 fields
	end;
	actor = function(t)
		box.space.users:update({t[1]},{
			{'=', 4, "newfield"}
		})
	end;
}

moonwalker {
	space = box.space.users;
	index = box.space.users.index.name; -- iterate over index 'name'
	pause = 100; -- be very polite, pause after every 100 records (but slow)
	take  = 100; -- collect 100 items for update
	limit = 1000; -- stop after examining only first 1000 tuples
	examine = function(t)
		return #t < 4;
	end;
	actor = function(t)
		box.space.users:update({t[1]},{
			{'=',4,"newfield"}
		})
	end;
}
```





















