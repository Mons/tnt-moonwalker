<a href="http://tarantool.org">
	<img src="https://avatars2.githubusercontent.com/u/2344919?v=2&s=250" align="right">
</a>

# Per-space updater for Tarantool 1.6+

A Lua module for [Tarantool 1.6+](http://github.com/tarantool) that allows
iterating over one space with the following logic:

1. Phase #1 (сollect):
  1. Create an iterator and iterate over the space for not more than `pause` items.
  2. Put items-to-update into a temporary Lua table.
  3. Yield the fiber, then reposition the iterator to GT(`last selected tuple`).
  4. If collected enough (`take`) tuples, switch to phase #2 (update).

2. Phase #2 (update):

  1. Iterate over the temporary table.
  2. For each element, call the `actor` function.
  3. Reposition the iterator to GT(`last selected tuple`) and switch back to
     phase #1 (collect).

## Table of contents

* [Parameters](#parameters)
* [Examples](#examples)

## Parameters

* `space` - the space to process.
* `index` (optional) - the index to iterate by. If not defined, use the primary
  index.
* `examine`: (optional, function:boolean) - called during phase #1 (collect).
  **Must not yield**. 
* `actor`: (function, altname: updater) - called during phase #2 (update) for
  every examined tuple.
* `pause`: `1000` (number) - make `fiber.yield` after stepping over this number
  of items.
* `take`: `500` (number) - how many items should be collected before switching to
  phase #2 (update).
* `dryrun`: `false` (boolean) - don't call the actor, only print the statistics.
* `limit`: `2^63` (optional, number) - process not more than this number of items.
  Useful for testing.
* `progress`: `2%` (optional, string or number) - print a progress message every
  N records or percent.


## Examples

```lua
local moonwalker = require 'moonwalker'

-- update the whole database (the simplest example)
moonwalker {
	space = box.space.users;
	actor = function(t)
		box.space.users:update({t[1]},{
			{'=', 2, os.time()}
		})
	end;
}

-- update the database, add missed fields (example with 'examine')
moonwalker {
	space = box.space.users;
	examine = function(t)
		return #t < 4; -- user tuple has only 3 fields
	end;
	actor = function(t)
		box.space.users:update({t[1]},{
			{'=', 4, "newfield"}
		})
	end;
}

-- iterate by a specific index
moonwalker {
	space = box.space.users;
	index = box.space.users.index.name; -- iterate over index 'name'
	pause = 100; -- be very polite, but slow: pause after every 100 records
	take  = 100; -- collect 100 items for update
	limit = 1000; -- stop after examining the first 1000 tuples
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





















