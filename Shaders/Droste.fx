////////////////////////////////////////////////////////////////////////////////////////////////////////
// Droste.fx by SirCobra
// Version 0.1
// You can find info and my repository here: https://github.com/LordKobra/CobraFX
// This effect warps space inside a spiral.
////////////////////////////////////////////////////////////////////////////////////////////////////////


////////////////////////////////////////////////////////////////////////////////////////////////////////
//***************************************                  *******************************************//
//***************************************   UI & Defines   *******************************************//
//***************************************                  *******************************************//
////////////////////////////////////////////////////////////////////////////////////////////////////////

// Shader Start
#include "Reshade.fxh"

// Namespace everything
namespace Droste
{

//defines
#define MASKING_M   "General Options\n"

#ifndef M_PI
	#define M_PI 3.1415927
#endif

	//ui
	uniform int Buffer1 <
		ui_type = "radio"; ui_label = " ";
	>;	
	uniform float InnerRing <
		ui_type = "slider";
		ui_min = 0.00; ui_max = 1;
		ui_step = 0.01;
		ui_tooltip = "The inner ring defines the texture border towards the center of the screen.";
		ui_category = MASKING_M;
	> = 0.5;
    uniform float OuterRing <
		ui_type = "slider";
		ui_min = 0.0; ui_max = 1;
		ui_step = 0.01;
		ui_tooltip = "The outer ring defines the texture border towards the edge of the screen.";
		ui_category = MASKING_M;
	> = 1.0;
	uniform float Scale <
		ui_type = "slider";
		ui_min = 0.1; ui_max = 10;
		ui_step = 0.01;
		ui_tooltip = "Scale the output.";
		ui_category = MASKING_M;
	> = 1.0;
	uniform int Buffer4 <
		ui_type = "radio"; ui_label = " ";
	>;

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //***************************************                  *******************************************//
    //*************************************** Helper Functions *******************************************//
    //***************************************                  *******************************************//
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

	//vector mod and normal fmod
	float mod(float x, float y) 
	{
		return x - y * floor(x / y);
	}
    float atan2_approx(float y, float x)
    {
        return acos(x*rsqrt(y*y+x*x))*(y<0 ? -1:1);
    }
    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //***************************************                  *******************************************//
    //***************************************      Spiral      *******************************************//
    //***************************************                  *******************************************//
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

	void droste(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 fragment : SV_Target)
	{
        //transform coordinate system
        float ar = float(BUFFER_WIDTH) / BUFFER_HEIGHT;
        float new_x = (texcoord.x-0.5)*ar;
        float new_y = (texcoord.y-0.5);
		//calculate and normalize angle
		float val = atan2_approx(new_x,new_y)+M_PI;
        val /= 2*M_PI;
		//calculate distance from center
        val += log(sqrt(new_x*new_x+new_y*new_y)*Scale);
        val = mod(val, 1);
		//calculate relative position towards outer and inner ring and interpolate
        float current_scale = sqrt(new_x*new_x+new_y*new_y);
        float lower_scale = InnerRing*0.5/current_scale;
        float upper_scale = OuterRing*0.5/current_scale;
        float real_scale = (1-val)*lower_scale+val*upper_scale;
        float adjusted_x = new_x/ar*real_scale+0.5;
        float adjusted_y = new_y*real_scale+0.5;
        fragment = tex2D(ReShade::BackBuffer, float2(adjusted_x, adjusted_y));

	}


	////////////////////////////////////////////////////////////////////////////////////////////////////////
	//***************************************                  *******************************************//
	//***************************************     Pipeline     *******************************************//
	//***************************************                  *******************************************//
	////////////////////////////////////////////////////////////////////////////////////////////////////////

	technique Droste < ui_tooltip = "Warp space inside a spiral."; >
	{
		pass spiral_step { VertexShader = PostProcessVS; PixelShader = droste; }
	}

} // Namespace End
