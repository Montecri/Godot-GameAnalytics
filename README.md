# Godot-GameAnalytics

Apr 23, 2018 - Cristiano Reis Monteiro <cristianomonteiro@gmail.com>

Native GDScript for GameAnalytics in Godot

When I first started learning Godot I notice the limitation when it comes to capture game analytics. The vast majority of options are incomplete in the sense that supports only one platform, missing functions etc, besides the regular need to recompile the engine, rebuild export templates, etc.

In search of a native, cross platform solution, identified that https://gameanalytics.com/ had a REST API sample in Python

Worked to convert it to GDScript (hardest part was implementing HMAC-SHA256).

The result is here.

Yes, the code is crude, poluted, redundant, etc, but it works. Don't complain, go fix it and share the result.

PLEASE NOTE: This GDScript makes use of https://github.com/xsellier/godot-uuid, so, download uuid.gd and place in the same folder as GameAnalytics.gd

USAGE INSTRUCTIONS:

. Add GameAnalytics.gd and uuid.gd to your root resources folder

. Add that to your main .gd:

```gdscript
extends Node

var GameAnalytics = preload("res://GameAnalytics.gd")
var GA = GameAnalytics.new()

func _ready():
	# Uncomment the following lines to use production keys instead of sandbox keys
	# GA.game_key = <your_game_key_supplied_by_GameAnalytics>
	# GA.secret_key = <your_secret_key_supplied_by_GameAnalytics>
	# GA.base_url = "http://api.gameanalytics.com"

	# Run once per session
	var init_response = GA.request_init()

	# Add events to queue
	GA.add_to_event_queue(GA.get_test_design_event("player:new_level", 1))
	GA.add_to_event_queue(GA.get_test_design_event("player:new_level", 2))

	# Submit events and flush queue - return code will indicate success (200) or failure (400, 401, 404)
	var returned = GA.submit_events()
```

The following GameAnalytics calls are also available:

```gdscript
add_to_event_queue(get_test_design_event(<string>, <value>))
add_to_event_queue(get_test_user_event())
add_to_event_queue(get_test_business_event_dict())
add_to_event_queue(get_test_session_end_event(200))
```

Study GameAnalytics.gd (commented examples there) and GameAnalytics REST API page to understand what else can be submitted.

TODO

. Correctly calculate client_ts offset

. Enable GZip compression (partially done / commented out)

. Better error treatment

. Fix comments and clean up code
