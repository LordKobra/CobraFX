/////////////////////////////////////////////////////////
// MirrorScreen.fx by SirCobra
// Version 0.1
// Did this shader exist already? We will never know
/////////////////////////////////////////////////////////

#include "ReShade.fxh"
uniform bool FlipAxis <
    ui_tooltip = "Flip the mirror axis.";
> = false;
void mirror_screen(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 fragment : SV_Target)
{
	float tex_x_new = !FlipAxis ? 0.5 - abs(texcoord.x - 0.5) : texcoord.x;
	float tex_y_new = FlipAxis ? 0.5 - abs(texcoord.y - 0.5) : texcoord.y;
	float2 p = float2(tex_x_new, tex_y_new);
	fragment = tex2D(ReShade::BackBuffer, p);
}

technique MirrorScreen
{
	pass mirrorScreen { VertexShader = PostProcessVS; PixelShader = mirror_screen; }
}
