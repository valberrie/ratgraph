# What:
This is a big engine of different things written in zig

## Mario Game:
* Head Bangers
    * mystery boxes
        * hidden ones
        * Mushrooms
            - Spawning
            - Movement ai
                - Getting knocked by another head_banger
            - Collection ai
            - type, 1up vs level up
        * coins
            - How are they collected
            - Multi coin blocks
        * Stars
            - spawning
            - Movement ai
                - how they bounce
        * Flowers
            - Spawning
        * Animation, fading between colors
    * Breakable tiles
* Enemies
    * setting if they walk off ledges or not
    * Goomba
    * koopa
        - sleeping
            - shell pushing
        - Winged koopa
    * parina plants
    * All the stupid fish
    * bowser
    * turtles
    * hammer bros
    * cloudy fucker
    * flying fish
    * cannon shooters
* Levels
    * elevators
    * ladders
    * pipes
    * Pits of death
    * those spinny shits
* Non player controlled sequnces
    - Flagpole
    - Level and walks
    - Bowser end
* How the camera works
* hud 

## General / engine
* cleanup code and document usefull api
* fully develop api for GraphicsContext
    - Ensure all batch types work.
    - Allow for manual creation of batches to move away from immediate mode rendering when possible
    - Better shader and translation support
    - instanced rendering batch system

* Improve styling and layout of gui
* add more functions to gui
* cleanup code
* modify std/json.zig for custom deserialization, being able to specify what containers arrays get parsed into
* Integrate the collision world somehow
* Port stb_rect_pack to zig
* Spatial indexing
    - Either a bsp tree or grid system


## Sub projects
### Bsp tree or quadtree for spatial indexing
    # Bsp tree
    
### Ecs
    This first implementation will probably be inefficent and backwards.

    Actual api: see registry.zig

    Outline of the desired api usage:
        Creation:
            Create a entity registry with specified component types:
            conts reg_type=  Registry(&.{comp1, comp2, comp3});
            var r = reg_type.init();

        Adding/removing entities and components
            my_id = r.createEntity();
            my_id.attachComponents(&.{Coord{.x = 0,.y=0}, comp3{.data = 0}})

            r.removeComponent(my_id, .coord);// Should this fail if my_id doesn't have specified component?
            r.destroyEntity(my_id); //removes entity and all components.

        Creating a view:
            const v_type = r.genView(&.{.comp1 ,.com2});
            const ent = r.getEntity(v_type, my_id);
            ent.comp1.* = data //Components available as pointers

            How does an iterator work?
                A: iterate the smallest of the component dense arrays and lookup the other components with the reverse index;
                B: iterate the bitsets and return any lookup any with true & mask.

                An iterator holds a pointer to the parent registry.
                If the iterator allocs the memory used for the queue memory leaks will happen if it.deinit() is not called. This would warn me if appending changes were forgotten. Not a big deal because you will notice quickly if the queue doesn't get applied
                Might not even matter if using arena allocations

                var my_it = r.Iterator(r.genView(&.{.comp1, .comp2}));
                var item = my_it.next();
                while(item != null): (item = my_it.next()){
                    //do stuff with item
                    const pending_id = my_it.qCreateEntity();
                    my_it.qAttachComponent(pending_id, mycomp);
                }
                my_it.deinit();//All the q'd arrays are pushed to r registry


    Notes:
        During an iteration how are deletions and insertions handled?
        calling entityCreate, attachComponent, destroyEntity, removeComponent, during iteration can cause iterator or pointers to be invalidated.
        Possible solutions include: queing these operations and applying after the iteration, Easy to implement
        Page all memory involved in entity storage, Harder to implement. Do iterators iterate just inserted elements or wait until next update()

        Potential Optimizations:
            Empty components that act as flags.
            The entities bitset already provides information about the components attached to types, does std.ArrayList even allocate for zero sized types?


