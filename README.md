# CobraFX
My shaders for ReShade are saved here.

Please read this first: All my compute shaders (currently computeGravity.fx and Colorsort.fx) only work inside the current ReShade Beta you can build yourself as described here: https://github.com/crosire/reshade#building
Also compute shaders do not work with DirectX 10 or lower and some older OpenGL versions.


Gravity.fx is a shader which lets Pixels gravitate towards the bottom of the screen inside the games 3D environment. This shader consumes an insane amount of resources on high resolutions (4k+), so keep this in mind as a warning.
Don't forget to include the texture inside the Textures folder!
About the texture: You can replace it with your own texture, if you want. It has to be 1920x1080 and greyscale. The brighter the pixel inside the texture, the more intense the effect will be at this location ingame.

computeGravity.fx is the compute shader version of Gravity.fx. It has a better color selection, and inverse gravity option.
It runs slower on normal solution, but a lot faster than Gravity.fx on high resolution, so you can downsample/hotsample without issues.
Don't forget to include the texture inside the Textures folder!


Colorsort.fx is a compute shader, which sorts colors from brightest to darkest.


LongExposure.fx is a shader, which enables you to capture changes over time, like in long-exposure photography. If you filter by brightness, it will have the most similar effect to real world photography, but try Freeze on a static scene with brightness turned off and not moving the camera to recieve the most interesting results. Make sure to also check out Trails.fx by BlueSkyDefender for similar brightness results with improved smoothness and depth effects: https://github.com/BlueSkyDefender/Depth3D/blob/master/Shaders/Others/Trails.fx .
