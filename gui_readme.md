## The instant-mode GUI

### Todo
* proper textbox implementation
* scaling, laying out a gui using pixels makes sense when using bitmaps to style. Scaling is a must and can be done by manually having a scale variable (current TestWindow approach) or just transforming everything with a single Mat4 passed to draw shaders. If scaling on the gpu, we need to manually scale all mouse coordinates passed into Context.
* Double clicking
* Using mouse buttons other than mouse1
* Right click popup menu
* Disable a button

### Widgets to add
* Enum selector that has a drop down and a textbox that can be used to enter the enum value 
* Mac OS 9 style dropdown. No scroll, just a long popup of all the possiblities

### Possible core features
* Multiple windows? This would require some primitive window management aswell as some thought about draw ordering and proper input distribution
* Utf8 support
* Opt-in caching, the widgetGeneric functions would be a good place to start

### Misc
* Try writing a backend using nanovg or cairo

How did old software rendered GUIs do the drawing?
A simple double buffer?

### Rethinking the drawing architecture
Instead of having different named drawcommand buffers for different layers, default, popup, tooltip, have an array of drawcommand buffers. Each of these represents a depth

Ideally caching can be done transparently.
For example. We have a sigle drawcommand buffer.
because our gui can only ever draw inside of the area from getArea, if we can associate sets of draw commands with the layout they are in, we know which drawcommands can be cached, and which can be changed.

A simple way to implement it would be to have each layout in the layout stack cache store a list of drawcommands.
When the layout cache invalidates or a diff is found, insert the draw command

