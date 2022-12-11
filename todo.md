# mario_game:
* bad guys
* jumping tile movement
* tile destruction
* mushrooms and daisies
* scripted sections
* Hud
* animation
* Camera movement

# General / engine
* merge zig-gl and zig-elevator into one repo
    - I want to try developing all my graphical projects and games from one repo so I don't have to worry about version control as much
* fully develop api for GraphicsContext
    - Ensure all batch types work.
    - Allow for manual creation of batches to move away from immediate mode rendering when possible
    - Better shader and translation support
    - increase effeciency with instanced rendering

* Improve styling and layout of gui
* add more functions to gui
* cleanup all the code
* write a serialization format for json that encodes a schema or something

# Ecs
* Write a system helper function that returns a type containing all the components of specified system / component mask

# Engine todo
* Integrate the collision world somehow

# Mario Todo:
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

