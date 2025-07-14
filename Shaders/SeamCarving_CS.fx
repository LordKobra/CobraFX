////////////////////////////////////////////////////////////////////////////////////////////////////////
// Seam Carving (SeamCarving_CS.fx) by SirCobra
// Version 0.1.0
// You can find info and all my shaders here: https://github.com/LordKobra/CobraFX
//
// --------Description---------
// Content Aware Scaling / Liquid Rescale
// ----------Credits-----------
// Thanks to Radegast (Warp-FX) for motivation!
// ----------License-----------
// Basically MIT License - If you want to use the shader or improve upon it, go for it!
// I put some ideas at the bottom.
////////////////////////////////////////////////////////////////////////////////////////////////////////

#include "Reshade.fxh"

// Shader Start

// Namespace Everything!

namespace COBRA_XSCR
{
    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                            Defines & UI
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    // Defines

    #define COBRA_XSCR_VERSION "0.1.0"

    #define COBRA_UTL_MODE 0
    #include ".\CobraUtility.fxh"

    #if (COBRA_UTL_VERSION_NUMBER < 1030)
        #error "CobraUtility.fxh outdated! Please update CobraFX!"
    #endif

    #define COBRA_XSCR_THREADS 16
    #define COBRA_XSCR_THREAD_WIDTH 16
    #define COBRA_XSCR_DISPATCHES ROUNDUP(BUFFER_HEIGHT, COBRA_XSCR_THREADS)

    # define COBRA_XSCR_WIDTH 1024

   // We need Compute Shader Support
    #if (((__RENDERER__ >= 0xb000 && __RENDERER__ < 0x10000) || (__RENDERER__ >= 0x14300)) && __RESHADE__ >= 40800)
        #define COBRA_XSCR_COMPUTE 1
    #else
        #define COBRA_XSCR_COMPUTE 0
        #warning "SeamCarving_CS.fx does only work with ReShade 4.8 or newer, DirectX 11 or newer, OpenGL 4.3 or newer and Vulkan."
    #endif

    #if COBRA_XSCR_COMPUTE != 0

    // UI

    uniform bool UI_StartSeamCarving <
        ui_label     = " Start Seam Carving";
        ui_tooltip   = "Click to start processing the image @TODO.";
        ui_category  = COBRA_UTL_UI_GENERAL;
    >                = false;

    uniform float UI_Percentage <
        ui_label     = " Keep Percentage";
        ui_type      = "slider";
        ui_min       = 0.0;
        ui_max       = 1.0;
        ui_step      = 0.001;
        ui_units     = "%";
        ui_tooltip   = "The percentage of the image you'd like to keep! @TODO.";
        ui_category  = COBRA_UTL_UI_GENERAL;
    >                = 1.0;

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                         Textures & Samplers
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    // Texture

    texture2D TEX_Options // reset before activation
    {
        Width  = 1;
        Height = 1;
        Format = RGBA32U;
    };

    texture TEX_Source // copied before activation
    {
        Width  = BUFFER_WIDTH;
        Height = BUFFER_HEIGHT;
        Format = RGBA8; // @TODO adaptable format - currently no HDR support
    };

    texture TEX_FilteredIndex // generated each turn
    {
        Width  = BUFFER_WIDTH;
        Height = BUFFER_HEIGHT;
        Format = R32U;
    };

    texture TEX_Filtered //generated each turn
    {
        Width  = BUFFER_WIDTH;
        Height = BUFFER_HEIGHT;
        Format = RGBA8; // @TODO adaptable format
    };

    texture TEX_Edge // generated each turn
    {
        Width  = BUFFER_WIDTH;
        Height = BUFFER_HEIGHT;
        Format = R16F;
    };

    texture TEX_Path // generated each turn
    {
        Width  = BUFFER_WIDTH;
        Height = BUFFER_HEIGHT;
        Format = R8;
    };

    texture TEX_Index // reset before activation
    {
        Width  = BUFFER_WIDTH;
        Height = BUFFER_HEIGHT;
        Format = R32U;
    };

    // Sampler

    sampler<uint4> SAM_Options
    {
        Texture   = TEX_Options;
    };

    sampler2D SAM_Source
    {
        Texture   = TEX_Source;
    };    
    
    sampler2D SAM_Filtered
    {
        Texture   = TEX_Filtered;
    };

    sampler2D<uint> SAM_FilteredIndex
    {
        Texture   = TEX_FilteredIndex;
        MagFilter = POINT;
        MinFilter = POINT;
        MipFilter = POINT;
    };

    sampler2D SAM_Edge
    {
        Texture   = TEX_Edge;
        MagFilter = POINT;
        MinFilter = POINT;
        MipFilter = POINT;
    };

    sampler2D SAM_Path
    {
        Texture   = TEX_Path;
        MagFilter = POINT;
        MinFilter = POINT;
        MipFilter = POINT;
    };

   sampler2D<uint> SAM_Index
    {
        Texture   = TEX_Index;
    };

    // Storage
    storage<uint4> STOR_Options { Texture = TEX_Options; };
    storage STOR_Filtered { Texture = TEX_Filtered; };
    storage<uint> STOR_FilteredIndex { Texture = TEX_FilteredIndex; };
    storage STOR_Path { Texture = TEX_Path; };
    storage2D<uint> STOR_Index { Texture = TEX_Index; };

    // Groupshared Memory
    groupshared float energy[2 * BUFFER_WIDTH];
    groupshared uint min_energy;
    groupshared uint min_idx;
    groupshared uint texture_width;

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                           Helper Functions
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    #define COBRA_UTL_MODE 2
    #include ".\CobraUtility.fxh"

    float4 show_progress(float2 texcoord, float4 fragment, float progress)
    {
        // @TODO HDR support (check RLE rework)
        const float2 POS  = float2(0.5, 0.07);
        const float RANGE = 0.05;
        const float2 AR   = float2(BUFFER_ASPECT_RATIO, 1.0);
        float2 tx         = (texcoord - POS) * AR;
        float angle       = (atan2_approx(tx.x, tx.y) + M_PI) / (2 * M_PI);
        float intensity   = (sqrt(dot(abs(tx), abs(tx))) - RANGE) * 100;
        intensity         = progress > 1.0 ? (1 - saturate(intensity)) * 0 : (1 - abs(intensity)) * UI_StartSeamCarving;
        if (intensity > 0.0 && intensity <= 1.0 && progress < 1.0)
        {
            fragment = lerp(fragment, float4(0.0, 0.0, 0.0, 1.0), 0.65 * saturate(intensity * 4));
        }

        intensity = intensity * 0.7;
        if (intensity > 0.0 && intensity <= 1.0 && progress > angle)
        {
            fragment = lerp(fragment, float4(0.3, 0.7, 0.3, 1.0), saturate(intensity * 4));
        }

        return fragment;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                              Shaders
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    vs2ps VS_Stage0(uint id : SV_VertexID)
    {
        vs2ps o = vs_basic(id, float2(0.0, 0.0));
        if (UI_StartSeamCarving)
            o.vpos.xy = 0.0;
        return o;
    }

    vs2ps VS_Stage1(uint id : SV_VertexID)
    {
        vs2ps o = vs_basic(id, float2(0.0, 0.0));
        uint4 options = tex2Dfetch(SAM_Options, int2(0, 0));
        uint current_iter = options.x;
        uint current_idx  = options.y;
        if (!UI_StartSeamCarving || current_iter > BUFFER_WIDTH)
            o.vpos.xy = 0.0;
        return o;
    }

    vs2ps VS_Stage12(uint id : SV_VertexID)
    {
        vs2ps o = vs_basic(id, float2(0.0, 0.0));
        if (!UI_StartSeamCarving)
            o.vpos.xy = 0.0;
        return o;
    }

    void PS_ResetOptions(vs2ps o, out uint4 fragment : SV_Target)
    {
        fragment = uint4(0, 0, 0, 0);
    }

    void PS_ResetIndex(vs2ps o, out uint fragment : SV_Target)
    {
        fragment = 0;
    }

    void PS_Source(vs2ps o, out float4 fragment : SV_Target)
    {
        fragment = tex2D(ReShade::BackBuffer, o.uv.xy);
    }

    void CS_Filter(uint3 id : SV_DispatchThreadID, uint3 tid : SV_GroupThreadID)
    {
        uint4 options = tex2Dfetch(SAM_Options, int2(0, 0));
        uint current_iter = options.x;
        uint current_idx  = options.y;
    
        if (!UI_StartSeamCarving || current_iter > BUFFER_WIDTH)
            return;

        uint filtered_row = 0;
        uint max_row = 0;
        for(uint row = 0; row < BUFFER_WIDTH; row++)
        {
            uint curr_index = tex2Dfetch(SAM_Index, int2(row, id.y)).r;
            if(curr_index == 0) // only 0 is untouched
            {
                tex2Dstore(STOR_FilteredIndex, float2(filtered_row, id.y), row);
                filtered_row++;
                max_row = row;
            }
        }
        for(uint row = filtered_row; row < BUFFER_WIDTH; row++)
            tex2Dstore(STOR_FilteredIndex, float2(row, id.y), max_row);
    }

    void PS_FilterColor(vs2ps o, out float4 fragment : SV_Target)
    {
        uint index = tex2Dfetch(SAM_FilteredIndex, floor(o.vpos.xy)).r;
        fragment = tex2Dfetch(SAM_Source, int2(index, floor(o.vpos.y)));

    }

    void CS_FilterDisplay(uint3 id : SV_DispatchThreadID, uint3 tid : SV_GroupThreadID)
    {
        uint4 options = tex2Dfetch(SAM_Options, int2(0, 0));
        uint current_iter = options.x;
        uint current_idx  = options.y;
    
        if (!UI_StartSeamCarving)
            return;

        uint max_filter = (1.0 - UI_Percentage) * BUFFER_WIDTH;
        uint filtered_row = 0;
        for(uint row = 0; row < BUFFER_WIDTH; row++)
        {
            uint curr_index = tex2Dfetch(SAM_Index, int2(row, id.y)).r;
            if(curr_index == 0 || curr_index > max_filter) // only 0 is untouched
            {
                tex2Dstore(STOR_FilteredIndex, float2(filtered_row, id.y), row);
                filtered_row++;
            }
        }
    }

    void PS_Edge(vs2ps o, out float fragment : SV_Target)
    {
        float4 pxoffset = ReShade::PixelSize.xyxy * float4(0.5, 0.5, -0.5, -0.5);
        // @TODO perhaps perceptual luminance? factor in color?
        // @TODO scaled filtered borders eventually not correctly clamping?
        float3 lb = csp_to_oklab(enc_to_lin(tex2D(SAM_Filtered, o.uv.xy + pxoffset.zy).xyz));
        float3 lt = csp_to_oklab(enc_to_lin(tex2D(SAM_Filtered, o.uv.xy + pxoffset.zw).xyz));
        float3 rt = csp_to_oklab(enc_to_lin(tex2D(SAM_Filtered, o.uv.xy + pxoffset.xw).xyz));
        float3 rb = csp_to_oklab(enc_to_lin(tex2D(SAM_Filtered, o.uv.xy + pxoffset.xy).xyz));
        float3 xdir = ((lt + lb) - (rt + rb));
        float3 ydir = ((lt + rt) - (lb + rb));
        fragment = dot(sqrt(xdir * xdir + ydir * ydir), 1.0);
    }

    void CS_EnergyMap(uint3 id : SV_DispatchThreadID, uint3 tid : SV_GroupThreadID)
    {
        /*    For Lines:
        I. Sample current pixel edge
        II. Check values below(shared memory)
        Write Result to texture and shared memory */
        uint current_iter = 0;
        if(id.x == 0)
        {    
            uint4 options = tex2Dfetch(STOR_Options, int2(0, 0));
            current_iter = options.x + 1;
            texture_width = BUFFER_WIDTH + 1 - current_iter;
        }
        barrier();        
        if((texture_width > BUFFER_WIDTH) || (texture_width == 0) || !UI_StartSeamCarving)
            return;
        barrier();
        for(uint stack = 0; stack < texture_width; stack += COBRA_XSCR_WIDTH)
        {
            uint idx = id.x + stack;
            if(idx < texture_width)
            {
                energy[idx] = 0.0;
                energy[idx + texture_width] = 0.0;
            }        
        }
        barrier();
        for(int line = BUFFER_HEIGHT - 1; line >= 0; line--)
        {
            for(uint stack = 0; stack < texture_width; stack += COBRA_XSCR_WIDTH)
            {
                barrier();
                uint idx = id.x + stack; // @TODO check bound passes
                if(idx < texture_width)
                {
                    uint uline = uint(line);
                    uint curr_pos =  idx + texture_width * ((uline + 1) % 2);
                    uint below_pos = idx + texture_width * (uline % 2);
                    float current = tex2Dfetch(SAM_Edge, int2(idx, line)).r;
                    float below = energy[below_pos];
                    float path_val = 0.0;
                    for(int n = max(0, idx - 1); n < min(texture_width, idx + 2); n++)
                    {
                        int path_id = n - (idx - 1);
                        float curr_energy = energy[n + texture_width * (uline % 2)];
                        below = min(below, curr_energy);
                        if(below == curr_energy)
                            path_val = 0.5*path_id;
                    }
                    float result = below + current;
                    energy[curr_pos] = result;
                    tex2Dstore(STOR_Path, float2(idx, line), path_val);
                }
            }
        }
        if (id.x == 0)
        {
            min_energy = 16777216;
            min_idx = 0;
        }
        barrier();
        /* find the topmost spot */
        /*first internally compare then globally*/
        uint idx_final = id.x;
        int thread_energy_final = 16777216;
        for(uint stack = 0; stack < texture_width; stack += COBRA_XSCR_WIDTH)
        {
            uint idx = id.x + stack; // @TODO
            if(idx < texture_width)
            {
                int thread_energy = int(energy[idx + texture_width * ((0 + 1) % 2)] * 768.0);
                if(thread_energy < thread_energy_final && idx < texture_width)
                {
                    thread_energy_final = thread_energy;
                    idx_final = idx;
                }
            }
        }
        atomicMin(min_energy, thread_energy_final);
        barrier();
        if(min_energy == thread_energy_final)
        {
            atomicExchange(min_idx, idx_final);
        }
        barrier();
        /* Update Options
            x = Iteration (+1 for continuous increase)
            y = min_idx 
        */
        if (id.x == 0)
        {
            tex2Dstore(STOR_Options, float2(0.0, 0.0), uint4(current_iter, min_idx, 0, 1));
        }
    }

    void CS_FindSeam(uint3 id : SV_DispatchThreadID, uint3 tid : SV_GroupThreadID)
    {
        uint4 options = tex2Dfetch(SAM_Options, int2(0, 0));
        uint current_iter = options.x;
        uint current_idx  = options.y;
        if((current_iter >= BUFFER_WIDTH) || !UI_StartSeamCarving)
            return;
        for(int line = 0; line < BUFFER_HEIGHT; line++)
        {
            uint current_source_idx = tex2Dfetch(SAM_FilteredIndex, int2(current_idx, line));         
            tex2Dstore(STOR_Index, float2(current_source_idx, line), current_iter);
            current_idx += int(tex2Dfetch(SAM_Path, int2(current_idx, line)).r * 2.0 - 1.0);
        }
    }

    void PS_Display(vs2ps o, out float4 fragment : SV_Target)
    {
        uint4 options = tex2Dfetch(SAM_Options, int2(0, 0));
        uint current_iter = options.x + 1;
        uint current_idx  = options.y;
        int percentage = max(UI_Percentage * (BUFFER_WIDTH - 1), BUFFER_WIDTH - int(current_iter));
        uint start_pos = (BUFFER_WIDTH - 1) / 2.0 - percentage * 0.5;
        int2 aligned_pos = floor(o.vpos.xy) - int2(start_pos, 0);
        fragment = tex2Dfetch(SAM_Filtered, aligned_pos);
        fragment.rgb = enc_to_lin(fragment.rgb);
        if (aligned_pos.x < 0 || aligned_pos.x > percentage) fragment.rgb = 0.1842; // @BlendOp
        fragment.a = 1.0;
        float progress = float(current_iter) / float(BUFFER_WIDTH);
        progress = progress > (1.0 - UI_Percentage) ? 1.1 : progress;
        fragment.rgb = show_progress(o.uv.xy, fragment, progress).rgb; // @BlendOp
        fragment.rgb = lin_to_enc(fragment.rgb);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                             Techniques
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    technique TECH_SeamCarve <
        ui_label     = "Seam Carving";
        ui_tooltip   = "------About-------\n"
                       "Seam Carving is also known as Content Aware Scaling / Liquid Rescale.\n\n"
                       "Version:    " COBRA_XSCR_VERSION "\nAuthor:     SirCobra\nCollection: CobraFX\n"
                       "            https://github.com/LordKobra/CobraFX";
    >
    {
        pass ResetOptions                       // 0
        {
            VertexShader = VS_Stage0;
            PixelShader  = PS_ResetOptions;
            RenderTarget = TEX_Options;
        }

        pass ResetIndex                         // 0
        {
            VertexShader = VS_Stage0;
            PixelShader  = PS_ResetIndex;
            RenderTarget = TEX_Index;
        }

        pass CopySource                         // 0
        {
            VertexShader = VS_Stage0;
            PixelShader  = PS_Source;
            RenderTarget = TEX_Source;
        }

#define COBRA_XSCR_FILTER_PASS \
        pass Filter \
        { \
            ComputeShader = CS_Filter<COBRA_XSCR_THREAD_WIDTH, COBRA_XSCR_THREADS>; \
            DispatchSizeX = 1; \
            DispatchSizeY = COBRA_XSCR_DISPATCHES;   \
        } \
 \
        pass FilterColor \
        { \
            VertexShader = VS_Stage1; \
            PixelShader  = PS_FilterColor; \
            RenderTarget = TEX_Filtered; \
        }    \
  \
        pass FindEdges \
        { \
            VertexShader = VS_Stage1; \
            PixelShader  = PS_Edge; \
            RenderTarget = TEX_Edge; \
        } \
 \
        pass MapEnergy \
        { \
            ComputeShader = CS_EnergyMap<COBRA_XSCR_WIDTH, 1>; \
            DispatchSizeX = 1; \
            DispatchSizeY = 1;   \
        } \
 \
        pass FindSeam \
        { \
            ComputeShader = CS_FindSeam<1, 1>; \
            DispatchSizeX = 1; \
            DispatchSizeY = 1;   \
        }

        COBRA_XSCR_FILTER_PASS
        COBRA_XSCR_FILTER_PASS
        COBRA_XSCR_FILTER_PASS

        pass FilterDisplay                      // 1 - 2
        {
            ComputeShader = CS_FilterDisplay<COBRA_XSCR_THREAD_WIDTH, COBRA_XSCR_THREADS>;
            DispatchSizeX = 1;
            DispatchSizeY = COBRA_XSCR_DISPATCHES;  
        }

        pass FilterColorDisplay                 // 1 - 2
        {
            VertexShader = VS_Stage12;
            PixelShader  = PS_FilterColor;
            RenderTarget = TEX_Filtered;
        }
        
        pass Display                            // 1 - 2
        {
            VertexShader = VS_Stage12;
            PixelShader  = PS_Display;            
        }

        /* pass FindEdges 
        { 
            VertexShader = VS_Stage12;
            PixelShader  = PS_Edge;
        } */
    }

#endif // Shader End

} // Namespace End

/*-------------.
| :: Footer :: |
'--------------/
 1. Assign Pixel Importance (Sobel) -> EdgeTex
 2. Create Energy Map
    For Lines:
        I. Sample current pixel edge
        II. Check values below(shared memory)
        Write Result to texture and shared memory
        Optimization done: Write only path to predecessor into map but
        only preserve current row in energy map. Once at the top, we already know
        the starting-point and only need the path texture, no energy map
 3. paint path in original image with key
 4. produce new shifted image + positions
... filter output by key

TODO: make faster
TODO: artistic energymap?
TODO: check for correct counter increase/usage/ordering
Improvement Ideas to avoid artifacts:
    - implement masking good energy function
    - alternate Horizontal / Vertical Seams
    - do not delete but merge/blend seams
    - increase angle to allow more than 45° orientation of seam (only works with merging/blending)
*/