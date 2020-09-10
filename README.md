# CobraFX
My shaders for ReShade are saved here.

Gravity.fx is a shader which lets Pixels gravitate towards the bottom of the screen.
Don't forget to include the texture inside the Textures folder!

Colorsort.fx is a compute shader, which sorts colors from brightest to darkest.
It does only work inside the current ReShade Beta you can build yourself as described here: https://github.com/crosire/reshade#building
Also it will only work with DirectX 11 or newer.

LongExposure.fx is a shader, which enables you to capture changes over time, like in long-exposure photography. If you filter by brightness, it will have the most similar effect to real world photography, but try Freeze on a static scene with brightness turned off and not moving the camera to recieve the most interesting results. Make sure to also check out Trails.fx by BlueSkyDefender for similar brightness results with improved smoothness and depth effects: https://github.com/BlueSkyDefender/Depth3D/blob/master/Shaders/Others/Trails.fx .
