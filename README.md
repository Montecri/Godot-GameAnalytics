# Godot-GameAnalytics

Apr 23, 2018

Native GDScript for GameAnalytics in Godot

When first started learning Godot I notice the limitation when it comes to capture game analytics. The vast majority of options are incomplete in the sense that supports only one platform, missing functions etc, besides the regular need to recompile the engine, rebuild export templates, etc.

In search of a native, cross platform solution, identified that https://gameanalytics.com/ had a REST API sample in Python

Worked to convert it to GDScript (hardest part was implementing HMAC-SHA256).

The result is here.

Yes, the code is crude, poluted, redundant, etc, but it works. Don't complain, go fix it and share the result.
