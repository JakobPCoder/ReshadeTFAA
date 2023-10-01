


/** 
 * - Temporal Filter Anti Aliasing | TFAA
 * - First published 2022 - Copyright, Jakob Wapenhensch
 * - https://creativecommons.org/licenses/by-nc/4.0/
 * - https://creativecommons.org/licenses/by-nc/4.0/legalcode
 */

 
/*
	# Human-readable summary of the License and not a substitute for https://creativecommons.org/licenses/by-nc/4.0/legalcode:

	You are free to:
	- Share — copy and redistribute the material in any medium or format
	- Adapt — remix, transform, and build upon the material
	- The licensor cannot revoke these freedoms as long as you follow the license terms.

	Under the following terms:
	- Attribution — You must give appropriate credit, provide a link to the license, and indicate if changes were made. You may do so in any reasonable manner, but not in any way that suggests the licensor endorses you or your use.
	- NonCommercial — You may not use the material for commercial purposes.
	- No additional restrictions — You may not apply legal terms or technological measures that legally restrict others from doing anything the license permits.

	Notices:
	- You do not have to comply with the license for elements of the material in the public domain or where your use is permitted by an applicable exception or limitation.
	- No warranties are given. The license may not give you all of the permissions necessary for your intended use. For example, other rights such as publicity, privacy, or moral rights may limit how you use the material.
*/


/*=============================================================================
	Includes
=============================================================================*/

#include "ReShadeUI.fxh"
#include "ReShade.fxh"


/*=============================================================================
	Preprocessor settings
=============================================================================*/

#ifndef USE_LAUNCHPAD
 #define USE_LAUNCHPAD 	0		// 0 -> Use my own motion estimation shader   1 - > use martys Launchpad shader
#endif

#ifndef UI_USE_CUBIC_HISTORY
 #define UI_USE_CUBIC_HISTORY 	1		// 0 -> Use Bilinear Sampling - Blury -   1 -> Use Cubic History Sampling - Sharper -  (Default)
#endif


// Uniform variables to store frame time and frame count
uniform float frametime < source = "frametime"; >;
uniform int framecount < source = "framecount"; >;

// Constant to compute FPS; 48 frames are expected per 1000 milliseconds
static const float fpsConst = (1000.0 / 48.0);

/*=============================================================================
	UI Uniforms
=============================================================================*/

uniform float  UI_TEMPORAL_FILTER_STRENGTH <
	ui_type = "slider";
	ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
	ui_label = "Temporal Filter Strength";
	ui_category = "Temporal Filter";
	ui_tooltip = "";
> = 0.5;




/*=============================================================================
	Textures & Samplers
=============================================================================*/

// Textures and their corresponding samplers
texture texDepthIn : DEPTH;
sampler smpDepthIn { Texture = texDepthIn; };

// Texture and sampler for the current frame's color
texture texInCur : COLOR;
sampler smpInCur { Texture = texInCur; AddressU = Clamp; AddressV = Clamp; MipFilter = Linear; MinFilter = Linear; MagFilter = Linear; };

// Backup texture for the current frame's color
texture texInCurBackup < pooled = true; > { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
sampler smpInCurBackup { Texture = texInCurBackup; AddressU = Clamp; AddressV = Clamp; MipFilter = Linear; MinFilter = Linear; MagFilter = Linear; };

// Textures to store Exponential frame Buffer
texture texExpColor < pooled = true; > { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
texture texExpColorBackup < pooled = true; > { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
sampler smpExpColor { Texture = texExpColor; AddressU = Clamp; AddressV = Clamp; MipFilter = Linear; MinFilter = Linear; MagFilter = Linear; };
sampler smpExpColorBackup { Texture = texExpColorBackup; AddressU = Clamp; AddressV = Clamp; MipFilter = Linear; MinFilter = Linear; MagFilter = Linear; };

// Backup texture to store depth information
texture texDepthBackup < pooled = true; > { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16f; };
sampler smpDepthBackup { Texture = texDepthBackup; AddressU = Clamp; AddressV = Clamp; MipFilter = Point; MinFilter = Point; MagFilter = Point; };

// Motion Vectors Selection
#if USE_LAUNCHPAD == 0

	// Texture to store motion vectors
	texture texMotionVectors < pooled = false; > { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RG16F; };
	sampler SamplerMotionVectors { Texture = texMotionVectors; AddressU = Clamp; AddressV = Clamp; MipFilter = Point; MinFilter = Point; MagFilter = Point; };

	/**
	 * Function to sample motion vectors.
	 * 
	 * @param texcoord The texture coordinates.
	 * @return The RG components representing motion vectors.
	 */
	float2 sampleMotion(float2 texcoord)
	{
		return tex2D(SamplerMotionVectors, texcoord).rg;
	}

#else

	namespace Deferred 
	{
		texture MotionVectorsTex        { Width = BUFFER_WIDTH;   Height = BUFFER_HEIGHT;   Format = RG16F;     };
	}
	sampler SamplerMartysMotionVectors { Texture = Deferred::MotionVectorsTex; AddressU = Clamp; AddressV = Clamp; MipFilter = Point; MinFilter = Point; MagFilter = Point; };

	/**
	 * Function to sample Marty's motion vectors.
	 * 
	 * @param texcoord The texture coordinates.
	 * @return The RG components representing motion vectors.
	 */
	float2 sampleMotion(float2 texcoord)
	{
		return tex2D(SamplerMartysMotionVectors, texcoord).rg;
	}
	
#endif



/*=============================================================================
	Functions
=============================================================================*/

//YCbCr
//with permissions from https://github.com/BlueSkyDefender/AstrayFX
float3 cvtRgb2YCbCr(float3 rgb)
{
 	float y = 0.299 * rgb.r + 0.587 * rgb.g + 0.114 * rgb.b;
    float cb = (rgb.b - y) * 0.565;
    float cr = (rgb.r - y) * 0.713;

    return float3(y, cb, cr);
}

float3 cvtYCbCr2Rgb(float3 YCbCr)
{
    return float3(
        YCbCr.x + 1.403 * YCbCr.z,
        YCbCr.x - 0.344 * YCbCr.y - 0.714 * YCbCr.z,
        YCbCr.x + 1.770 * YCbCr.y
    );
}

/**
 * Color Conversion Wrapper for RGB to "whatever" color space.
 * This wrapper is employed because the YCbCr color space (as an example) produces sharper, better clamping results than RGB.
 */

float3 cvtRgb2whatever(float3 rgb)
{
	return cvtRgb2YCbCr(rgb);
}

float3 cvtWhatever2Rgb(float3 whatever)
{
	return cvtYCbCr2Rgb(whatever);
}



// History resampling, could not track down who wrote this code comes from, but thanks to who ever did it first
float4 sampleBicubic(sampler2D source, float2 texcoord)
{
	// Calculate the size of the source texture
    float2 texSize = tex2Dsize(source);

    // Calculate the position to sample in the source texture
    float2 samplePos = texcoord * texSize;

    // Calculate the integer and fractional parts of the sample position
    float2 texPos1 = floor(samplePos - 0.5f) + 0.5f;
    float2 f = samplePos - texPos1;

    // Calculate the interpolation weights for the four cubic spline basis functions
    float2 w0 = f * (-0.5f + f * (1.0f - 0.5f * f));
    float2 w1 = 1.0f + f * f * (-2.5f + 1.5f * f);
    float2 w2 = f * (0.5f + f * (2.0f - 1.5f * f));
    float2 w3 = f * f * (-0.5f + 0.5f * f);

    // Calculate weights for two intermediate values (used for more efficient sampling)
    float2 w12 = w1 + w2;
    float2 offset12 = w2 / (w1 + w2);

    // Calculate the positions to sample for the eight texels involved in bicubic interpolation
    float2 texPos0 = texPos1 - 1;
    float2 texPos3 = texPos1 + 2;
    float2 texPos12 = texPos1 + offset12;

    // Normalize the texel positions to the [0, 1] range
    texPos0 /= texSize;
    texPos3 /= texSize;
    texPos12 /= texSize;

    // Initialize the result color to zero
    float4 result = 0.0f;

    // Perform bicubic interpolation by sampling the source texture with the calculated weights
    result += tex2D(source, float2(texPos0.x, texPos0.y)) * w0.x * w0.y;
    result += tex2D(source, float2(texPos12.x, texPos0.y)) * w12.x * w0.y;
    result += tex2D(source, float2(texPos3.x, texPos0.y)) * w3.x * w0.y;

    result += tex2D(source, float2(texPos0.x, texPos12.y)) * w0.x * w12.y;
    result += tex2D(source, float2(texPos12.x, texPos12.y)) * w12.x * w12.y;
    result += tex2D(source, float2(texPos3.x, texPos12.y)) * w3.x * w12.y;

    result += tex2D(source, float2(texPos0.x, texPos3.y)) * w0.x * w3.y;
    result += tex2D(source, float2(texPos12.x, texPos3.y)) * w12.x * w3.y;
    result += tex2D(source, float2(texPos3.x, texPos3.y)) * w3.x * w3.y;

    return result;
}


//Sample Wrappers

/**
 * Sample from the history texture.
 *
 * @param historySampler The sampler2D object used to sample the history texture.
 * @param texcoord The texture coordinate.
 * @return The sampled color.
 */
float4 sampleHistory(sampler2D historySampler, float2 texcoord)
{
	#if UI_USE_CUBIC_HISTORY
		// Use bicubic sampling if UI_USE_CUBIC_HISTORY is defined
		return sampleBicubic(historySampler, texcoord);
	#else
		// Default to bilinear sampling
		return tex2D(historySampler, texcoord);
	#endif
}

/**
 * Retrieve depth information from a 2D texture coordinate.
 *
 * @param texcoord The texture coordinate.
 * @return Depth value at the given coordinate.
 */
float getDepth(float2 texcoord)
{
	// Sample depth from depth texture using Level of Detail (LOD) 0
	float depth = tex2Dlod(smpDepthIn, float4(texcoord, 0, 0)).x;

	#if RESHADE_DEPTH_INPUT_IS_REVERSED
		// Reverse depth value if RESHADE_DEPTH_INPUT_IS_REVERSED is defined
		depth = 1.0 - depth;
	#endif

	return depth;
}


//Passes

float4 SaveCurPS(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target0
{	
	//write current color and depth into one texture for easy use later;
	float depthOnly = getDepth(texcoord);
	return float4(tex2D(smpInCur, texcoord).rgb, depthOnly);
}


float4 TaaPass(float4 position : SV_Position, float2 texcoord : TEXCOORD ) : SV_Target
{
	//sample local pixel color and depth
	float4 sampleCur = tex2D(smpInCurBackup, texcoord);
	float depthCur = sampleCur.a;

	//local pixel from rgb to clamping format		
	float4 cvtColorCur = float4(cvtRgb2whatever(sampleCur.rgb), depthCur);

	//variables for storing min max values for clamping
	float4 nCrossMin = cvtColorCur;
	float4 nCrossMax = cvtColorCur;
	float4 nCornersMin = cvtColorCur;
	float4 nCornersMax = cvtColorCur;

	//neigborhood sample offsets
	static const float2 nOffsets[9] = { float2(0,  1), float2(0, -1), float2(1, 0), float2(-1, 0),
										float2(-1,-1), float2(1, -1), float2(1, 1), float2(-1, 1), float2(0, 0) };
	
	//variables for storing neigborhood and closest depth for dilated motion vectors
	float4 neigborhood[8];
	int closestDepthIndex = 8; //defualt to (0, 0)
	float closestDepth = 1.0;

	for (int i = 0; i < 8; i++)
	{
		float4 nSample = tex2D(smpInCurBackup, texcoord + (nOffsets[i] * ReShade::PixelSize));
		neigborhood[i] = nSample;

		//find pixel for dilated motion vectors
		if (nSample.a < closestDepth)
		{
			closestDepth = nSample.a;
			closestDepthIndex = i;
		}

		//get min and max of neighborhood for clamping
		float4 cvt = float4(cvtRgb2whatever(nSample.rgb), nSample.a);

		if (i < 4)
		{
			nCrossMin = min(cvt, nCrossMin);
			nCrossMax = max(cvt, nCrossMax);
		}
		else
		{
			nCornersMin = min(cvt, nCornersMin);
			nCornersMax = max(cvt, nCornersMax);
		}
	}

	//Rounded Box -> average of Box and Cross min max values -> close to properly weighted samples
	float4 boxMin =  min(nCrossMin, nCornersMin);
	float4 boxMax =  max(nCrossMax, nCornersMax);
	float4 finalMin = (nCrossMin + boxMin) * 0.5;
	float4 finalMax = (nCrossMax + boxMax) * 0.5;


	//sample Motion with closest Depth
	float2 sampledMotion = sampleMotion(texcoord + (nOffsets[closestDepthIndex] * ReShade::PixelSize));

	//reprojection -> sample where local pixel was last
	float2 lastSamplePos = texcoord + sampledMotion;
	float4 sampleLast = sampleHistory(smpExpColorBackup, lastSamplePos);


	//Blending weight calculation
	//weight from menu
	float weight = lerp(0.5, 0.99, UI_TEMPORAL_FILTER_STRENGTH);

	//weight normalized to 48 hz test scenario 
	float fpsFix = frametime / fpsConst;
	weight = weight / fpsFix;

	//use more of old frame when we are in a high contrast region
	weight *= 0.5 + (saturate(length(finalMin.rgb - finalMax.rgb) * 10.0) * 0.5);

	//when last and current sample are very similar, we just use the new one.
	weight *= saturate(length(sampleLast.rgb - sampleCur.rgb) * 10);

	//clamp weight in reasonable range
	weight = clamp(weight, 0.5, 0.99);



	//Gamma-corrected Interpolation: Better preserves perceived light intensity, 
	float3 blendedColor = sqrt(lerp(sampleCur.rgb * sampleCur.rgb, sampleLast.rgb * sampleLast.rgb, weight));

	//Color Clamping
	float3 rgb = cvtWhatever2Rgb(clamp(cvtRgb2whatever(blendedColor), finalMin.rgb, finalMax.rgb));
	
	//how much we clamped this time
	float clampDelta = length(blendedColor - rgb);

	//if neighborhood has a bigger range, we expect more clamping so we keep the delta low for the next frame
	float clampDeltaNormalized = clampDelta / (1.0 + (length(finalMin.rgb - finalMax.rgb) * 10));


	//return color and clamp amount
	return float4(rgb, clampDeltaNormalized);
}


void SaveResultsPS(float4 position : SV_Position, float2 texcoord : TEXCOORD, out float4 lastExpOut : SV_Target0, out float depthOnly : SV_Target1)
{
	//save current depth and state of the exponential history for use in the next frame frame
	lastExpOut = tex2D(smpExpColor, texcoord);
	depthOnly = getDepth(texcoord);
}

float4 OutPS(float4 position : SV_Position, float2 texcoord : TEXCOORD ) : SV_Target
{
	//show filtered image to screen
	return tex2D(smpExpColor, texcoord);
}

//Technique
technique TFAA
{
	pass SaveCurBuffersPass
	{
		VertexShader = PostProcessVS;
		PixelShader = SaveCurPS;
		RenderTarget0 = texInCurBackup;
	}
	pass TaaPass
	{
		VertexShader = PostProcessVS;
		PixelShader = TaaPass;
		RenderTarget = texExpColor;
	}
	pass SaveResultsPass
	{
		VertexShader = PostProcessVS;
		PixelShader = SaveResultsPS;
		RenderTarget0 = texExpColorBackup;
		RenderTarget1 = texDepthBackup;
	}
	pass OutPass
	{
		VertexShader = PostProcessVS;
		PixelShader = OutPS;
	}
}
