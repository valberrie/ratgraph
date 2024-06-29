## Gui design discussion

### Identifying widgets
Text inputs need to stay focused between frames
Popups need to know if they are the active popup
Sliders need to know if active to grab mouse cursor

All of these require a way of uniqely identifying elements. We know if the layouts change using the layout cache system.

Ideally a widget could receive a single integer and compare it to a global. (myid == active_popup_id)
