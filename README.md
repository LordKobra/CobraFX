# CobraFX


CobraFX comprises SirCobra's contribution of shaders for [ReShade](https://github.com/crosire/reshade). The shaders are designed for in-game photography.

### Requirements

>**Note**
>Important! All compute shaders (filename has "_CS"-Suffix) only work with ReShade 4.8 or newer, DirectX 11 or newer, OpenGL 4.3 or newer and Vulkan!


>**Note**
>Gravity, Color Sort and Cobra Mask require depth-buffer access to unlock all features.

## Gravity & Gravity CS

**Gravity.fx** lets pixels gravitate towards the bottom of the screen inside the game's 3D environment. You can filter the affected pixels by depth and by color. 

It uses a custom seed (currently the Mandelbrot set) to determine the intensity of each pixel. Make sure to also test out the texture-RNG variant with the picture `gravityrng.png` provided in the Textures folder. You can replace the texture with your own texture, as long as it is 1920x1080, RGBA8 and has the same name. Only the red-intensity is taken. So either use red images or greyscale images. The brighter the pixel inside the texture, the more intense the effect will be at this location ingame.

This shader consumes a high amount of resources on high resolutions (4k+), so on large resolutions, lower the `Gravity Intensity` or check out Gravity_CS.fx instead.

**Gravity_CS.fx** is the compute shader version of Gravity.fx. It has a better color selection, and an inverse gravity option.
It runs slower on normal resolutions, but a lot faster than Gravity.fx on higher resolutions, and you can downsample / hotsample without issues.

To increase performance, you can lower the `Gravity Intensity` slider or change the `GRAVITY_HEIGHT` preprocessor parameter. This parameter controls the resolution of the effect along the gravitational axis. At lower resolutions, you gain performance at the cost of visual fidelity.

<p align="center"><img src="https://cdn.discordapp.com/attachments/995429348637167646/1169987517987164260/Mirrors_Edge_Screenshot_2023.11.03_-_14.04.41.07.png?ex=655766c9&is=6544f1c9&hm=6448f13ca90256be88af0f009616fb7904403bd617c82636b52dc55ec8d55221&">
<i>Gravity in action</i></p>

## Color Sort

**Colorsort_CS.fx** is a compute shader, which sorts colors from brightest to darkest along a user-specified axis. You can filter the selection by depth and color. Place your own shaders between `Color Sort: Masking` and `Color Sort: Main` to only affect the sorted area.

The shader consumes a lot of resources. To balance between quality and performance,
adjust the preprocessor parameter `COLOR_HEIGHT`. `COLOR_HEIGHT` (default value: 10) multiplied by 64 defines the resolution of the effect along the sorting axis. The value needs to be integer. Smaller values give performance at cost of visual fidelity. 8: Performance, 10: Default, 12: Good, 14: High
<p align="center"><img src="https://cdn.discordapp.com/attachments/549986930071175169/1168953753622294558/The_Witcher_3_Screenshot_2023.10.31_-_17.33.41.22.png?ex=6553a404&is=65412f04&hm=fafe5566b5f2a34f9d79dc65fcee61d4a06a4427d9458d283c2ff1734813f9d4&">
<i>Color Sort in action</i></p>

## Realistic Long-Exposure

**RealLongExposure.fx** enables you to capture changes over time, like in long-exposure photography. It will record the game's output for a user-defined amount of seconds to create the final image, just as a camera would do in real life. A `Gamma` slider allows to regulate the highlight persistence.

If you want a continuous effect, make sure to also check out the old [LongExposure.fx](/Shaders/outdated/LongExposure.fx) which fakes the effect or [Trails.fx by BlueSkyDefender](https://github.com/BlueSkyDefender/AstrayFX/blob/master/Shaders/Trails.fx) for similar brightness results with improved smoothness and depth effects.

Tip: Right-click the `Start Exposure` button to bind this functionality to a hotkey for convenient usage.

<p align="center"><img src="https://cdn.discordapp.com/attachments/995429348637167646/1171151680616800276/The_Witcher_3_Screenshot_2023.11.06_-_19.17.50.63.png?ex=655ba2ff&is=65492dff&hm=6891ab57df21487f5132b96f928a287fdabbe14d37d866159b76ab9abeda81c0&">
<i>Realistic Long-Exposure in action</i></p>

## Droste Effect

**Droste.fx** warps the image-space to recursively appear within itself. It features a circular and rectangular shape and can be applied as continuous spiral.

<p align="center"><img src="https://cdn.discordapp.com/attachments/995429348637167646/1169995170717122701/Mirrors_Edge_Screenshot_2023.11.03_-_14.42.37.79.png?ex=65576dea&is=6544f8ea&hm=9a681c8760111a87c96ea34aa03ee8d6a7ebd2c4c9138662119e18255b4b98db&">
<i>Droste Effect in action</i></p>

## Cobra Mask

**CobraMask.fx** allows to apply ReShade shaders exclusively to a selected part of the screen. The mask can be defined through color and scene-depth parameters. The parameters are specifically designed to work in accordance with the color and depth selection of other CobraFX shaders. 

This shader works the following way: In the effect window, you put "Cobra Mask: Start" above, and "Cobra Mask: Finish" below the shaders you want to be affected by the mask. When you turn it on, the effects in between will only affect the part of the screen with the correct color and depth. This effect adapts to the current scene. If you need to cover a fixed area of the screen, like the game UI, check out [UI Mask](https://github.com/crosire/reshade-shaders/blob/slim/Shaders/UIMask.fx).


<p align="center"><img src="https://cdn.discordapp.com/attachments/995429348637167646/1171579925749309570/MirrorsEdge_2023-11-07_23-34-53.png?ex=655d31d5&is=654abcd5&hm=3bdb05db0259f3ccc63ff1bab8a28c007d5a4d63679617b566c126091556adb2&">
<i> Cobra Mask applying the <a href="https://github.com/Daodan317081/reshade-shaders">Comic.fx</a> debug layer to the foreground</i>
</p>

## Installation

### Using the Installer

CobraFX is registered in the [latest installer](https://reshade.me/#download) of ReShade. Make sure you tick this repository when selecting the shader packages during the installation.

### Manual Installation

1. [Download](https://github.com/LordKobra/CobraFX/archive/master.zip) this repository
2. Extract the downloaded archive file somewhere
3. Start your game, open the ReShade in-game menu and switch to the "Settings" tab
4. Add the path to the extracted [Shaders](/Shaders) folder to "Effect Search Paths"
5. Add the path to the extracted [Textures](/Textures) folder to "Texture Search Paths"
6. Switch back to the "Home" tab and click on "Reload" to load the shaders

## Contributing

Check out [the language reference document](REFERENCE.md) to get started on how to write your own shader!

And make sure to join the ReShade forum or discord if you want to share your ideas or need help :
 - https://reshade.me/forum
 - https://discordapp.com/invite/GEb23bD

If you want to report a bug, you can open an [issue on GitHub](https://github.com/LordKobra/CobraFX/issues) or report it in the ReShade discord.
