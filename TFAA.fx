


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


// I (Jakob W.) reused the sharpening weight calculations from AMD CAS after i noticed they where basedon local min/max
// which i calcualte any way. 
// The following copyright notice therefore only a applies to a few lines of this software.
// =======
// Copyright (c) 2017-2019 Advanced Micro Devices, Inc. All rights reserved.
// -------
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy,
// modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following conditions:
// -------
// The above copyright notice and this permission notice shall be included in all copies or substantial portions of the
// Software.
// -------
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
// WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE AUTHORS OR
// COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
// ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE


#include "ReShadeUI.fxh"
#include "MotionVectors.fxh"
#include "TFAAUI.fxh"


uniform float frametime < source = "frametime"; >;
uniform int framecount < source = "framecount"; >;


// Shader
//Textures
texture texInCur : COLOR;
texture texInCurBackup < pooled = false; > { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };

texture texExpColor < pooled = false; > { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
texture texExpColorBackup < pooled = false; > { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };

//Samplers
sampler smpInCur { Texture = texInCur; AddressU = Clamp; AddressV = Clamp; MipFilter = Linear; MinFilter = Linear; MagFilter = Linear; };
sampler smpInCurBackup { Texture = texInCurBackup; AddressU = Clamp; AddressV = Clamp; MipFilter = Linear; MinFilter = Linear; MagFilter = Linear; };

sampler smpExpColor { Texture = texExpColor; AddressU = Clamp; AddressV = Clamp; MipFilter = Linear; MinFilter = Linear; MagFilter = Linear; };
sampler smpExpColorBackup { Texture = texExpColorBackup; AddressU = Clamp; AddressV = Clamp; MipFilter = Linear; MinFilter = Linear; MagFilter = Linear; };



//  Helper Functions
// Color Converstions
//YCgCo
float3 cvtRgb2YCgCo(float3 rgb)
{
	float3 RGB2Y =  float3(0.25, 0.5, -0.25);
	float3 RGB2Cg = float3(0.5,  0.0,  0.5);
	float3 RGB2Co = float3(0.25,-0.5, -0.25);
	return float3(dot(rgb, RGB2Y), dot(rgb, RGB2Cg), dot(rgb, RGB2Co));
}

float3 cvtYCgCo2Rgb(float3 ycc)
{
	float3 YCgCo2R = float3( 1.0, 1.0, 1.0);
	float3 YCgCo2G = float3(1.0, 0.0, -1.0);
	float3 YCgCo2B = float3(-1.0, 1.0, -1.0);
	return float3(dot(ycc, YCgCo2R), dot(ycc, YCgCo2G), dot(ycc, YCgCo2B));
}

//YCbCr
//from https://github.com/BlueSkyDefender/AstrayFX
float3 cvtRgb2YCbCr(float3 rgb)
{
	float3 RGB2Y =  float3( 0.299, 0.587, 0.114);
	float3 RGB2Cb = float3(-0.169,-0.331, 0.500);
	float3 RGB2Cr = float3( 0.500,-0.419,-0.081);
	return float3(dot(rgb, RGB2Y), dot(rgb, RGB2Cb), dot(rgb, RGB2Cr));
}

float3 cvtYCbCr2Rgb(float3 ycc)
{
	float3 YCbCr2R = float3( 1.000, 0.000, 1.400);
	float3 YCbCr2G = float3( 1.000,-0.343,-0.711);
	float3 YCbCr2B = float3( 1.000, 1.765, 0.000);
	return float3(dot(ycc, YCbCr2R), dot(ycc, YCbCr2G), dot(ycc, YCbCr2B));
}

//Color Conversion Wrapper
float3 cvtRgb2whatever(float3 rgb)
{
	switch(UI_COLOR_FORMAT)
	{
		case 1:
			return cvtRgb2YCgCo(rgb);
		case 2:
			return cvtRgb2YCbCr(rgb);
		default:
			return rgb;
	}
}

float3 cvtWhatever2Rgb(float3 whatever)
{
	switch(UI_COLOR_FORMAT)
	{
		case 1:
			return cvtYCgCo2Rgb(whatever);
		case 2:
			return cvtYCbCr2Rgb(whatever);
		default:
			return whatever;
	}
}

// History resampling
float4 SampleTextureCatmullRom(sampler2D source, float2 texcoord)
{
	float2 texSize = tex2Dsize(source);

    //We're going to sample a a 4x4 grid of texels surrounding the target texcoord. We'll do this by rounding
    //down the sample location to get the exact center of our "starting" texel. The starting texel will be at
    //location [1, 1] in the grid, where [0, 0] is the top left corner.
    float2 samplePos = texcoord * texSize;
    float2 texPos1 = floor(samplePos - 0.5f) + 0.5f;

    //Compute the fractional offset from our starting texel to our original sample location, which we'll
    //feed into the Catmull-Rom spline function to get our filter weights.
    float2 f = samplePos - texPos1;

    //Compute the Catmull-Rom weights using the fractional offset that we calculated earlier.
    //These equations are pre-expanded based on our knowledge of where the texels will be located,
    //which lets us avoid having to evaluate a piece-wise function.
    float2 w0 = f * (-0.5f + f * (1.0f - 0.5f * f));
    float2 w1 = 1.0f + f * f * (-2.5f + 1.5f * f);
    float2 w2 = f * (0.5f + f * (2.0f - 1.5f * f));
    float2 w3 = f * f * (-0.5f + 0.5f * f);

    //Work out weighting factors and sampling offsets that will let us use bilinear filtering to
    //simultaneously evaluate the middle 2 samples from the 4x4 grid.
    float2 w12 = w1 + w2;
    float2 offset12 = w2 / (w1 + w2);

    //Compute the final texcoords we'll use for sampling the texture
    float2 texPos0 = texPos1 - 1;
    float2 texPos3 = texPos1 + 2;
    float2 texPos12 = texPos1 + offset12;

    texPos0 /= texSize;
    texPos3 /= texSize;
    texPos12 /= texSize;

    float4 result = 0.0f;
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

//Wrapper
float4 sampleHistory(sampler2D historySampler, float2 texcoord)
{
	[branch] if (UI_USE_CUBIC_HISTORY)
		return SampleTextureCatmullRom(historySampler, texcoord);
	else
		return tex2D(historySampler, texcoord);
}



//Passes
float4 SaveCurPS(float4 position : SV_Position, float2 texcoord : TEXCOORD, out float4 last : SV_Target1, out float4 lastExpOut : SV_Target2) : SV_Target0
{	
	return float4(tex2D(smpInCur, texcoord).rgb, ReShade::GetLinearizedDepth(texcoord));
}

/*
uniform bool UI_VECTORS_AVAILABLE <
uniform float  UI_NEW_FRAME_WEIGHT <
uniform int UI_CLAMP_TYPE <
uniform int UI_CLAMP_PATTERN <
uniform int UI_COLOR_FORMAT <
uniform bool UI_USE_CLIPPING <
*/
float4 TaaPass(float4 position : SV_Position, float2 texcoord : TEXCOORD ) : SV_Target
{


	float4 sampleCur = tex2D(smpInCurBackup, texcoord);
	float3 colorCur = sampleCur.rgb;
	float depthCur = sampleCur.a;

	//size of neighborhood
	float2 sampleDist =  1.0 * ReShade::PixelSize; //lerp(0.33, 1.0, lerp(1.0, 0.0, UI_CLAMP_STRENGTH)) * ReShade::PixelSize;
	//rgb to clamping format		
	float4 cvtColorCur = float4(cvtRgb2whatever(colorCur), depthCur);
	
	//get min and max of neighborhood
	float4 finalMin = 1.0;
	float4 finalMax = 0.0;
	float2 sampledMotion = float2(0, 0);

	float4 nCrossMin = cvtColorCur;
	float4 nCrossMax = cvtColorCur;
	static const float2 nOffsets[8] = { float2(0,1), float2(0,-1), float2(1,0), float2(-1,0),
										float2(-1,-1), float2(1,-1), float2(1,1), float2(-1,1) };
	float4 neigborhood[8];
	int closestDepthIndex = -1;
	float closestDepth = 1.0;
	[unroll] for (int i = 0; i < 4; i++)
	{
		float4 nSample = tex2D(smpInCurBackup, texcoord + (nOffsets[i] * sampleDist));
		neigborhood[i] = nSample;

		if (nSample.a < closestDepth)
		{
			closestDepth = nSample.a;
			closestDepthIndex = i;
		}

		float4 cvt = float4(cvtRgb2whatever(nSample.rgb), nSample.a);
		nCrossMin = min(cvt, nCrossMin);
		nCrossMax = max(cvt, nCrossMax);
	}

	[branch] if (UI_CLAMP_PATTERN != 0)	
	{
		float4 nCornersMin = cvtColorCur;
		float4 nCornersMax = cvtColorCur;
		[unroll] for (int i = 4; i < 8; i++)
		{
			float4 nSample = tex2D(smpInCurBackup, texcoord + (nOffsets[i] * sampleDist));
			neigborhood[i] = nSample;

			if (nSample.a < closestDepth)
			{
				closestDepth = nSample.a;
				closestDepthIndex = i;
			}
			
			float4 cvt = float4(cvtRgb2whatever(nSample.rgb), nSample.a);
			nCornersMin = min(cvt, nCornersMin);
			nCornersMax = max(cvt, nCornersMax);
		}

		//box min max from cross and corner min max
		float4 boxMin = min(nCrossMin, nCornersMin);
		float4 boxMax = max(nCrossMax, nCornersMax);

		//Rounded Box -> average of Box and Cross min max values -> close to properly weighted samples
		finalMin = (nCrossMin + boxMin) * 0.5;
		finalMax = (nCrossMax + boxMax) * 0.5;

		//sample Motion with closest Depth
		sampledMotion = sampleMotion(texcoord + (neigborhood[closestDepthIndex] * sampleDist));

	}
	//Cross
	else
	{
		//only cross min max
		finalMin = nCrossMin;
		finalMax = nCrossMax;
		//sample Motion with closest Depth

	}

	if(closestDepthIndex != -1)
		sampledMotion = sampleMotion(texcoord + (neigborhood[closestDepthIndex] * sampleDist));

	//get fps factor
	float fpsFix = frametime / (1000.0 / 48.0);

	//reprojection
	float4 sampleLast = sampleHistory(smpExpColorBackup, texcoord + sampledMotion);
	float3 colorLast = sampleLast.rgb;

	//reduce history impact when we clamped a lot last time, do less clamping when feedback is low due to menu setting
	float previousClamping = sampleLast.a;



	//sharp current pixel before blending with past and before clamping so artifacts are supressed
	//float preSharpFactor = clamp(UI_PRESHARP * pow(UI_TEMPORAL_FILTER_STRENGTH, 3) * (1 * 20), 0, 3);
	float sharpAmount = clamp(UI_PRESHARP * lerp(0.1, 1.0, UI_TEMPORAL_FILTER_STRENGTH) * previousClamping * 3, 0, 1);


	// Smooth minimum distance to signal limit divided by smooth max.
	float3 rcpMRGB = rcp(finalMax);
	float3 ampRGB = saturate(min(finalMin, 2.0 - finalMax) * rcpMRGB);	
	
	// Shaping amount of sharpening.
	ampRGB = rsqrt(ampRGB);
	
	float contrast = 0.5;
	float peak = -3.0 * contrast + 8.0;
	float3 wRGB = -rcp(ampRGB * peak);

	float3 rcpWeightRGB = rcp(4.0 * wRGB + 1.0);

	//						  0 w 0
	//  Filter shape:		   w 1 w
	//						  0 w 0  
	float3 window = (neigborhood[0] + neigborhood[1]) + (neigborhood[2] + neigborhood[3]);
	float3 outColor = saturate((window * wRGB + colorCur) * rcpWeightRGB);
	float3 sharpened = lerp(colorCur, outColor, sharpAmount);



	//weight from menu
	float weight = lerp(0.4, 0.025, UI_TEMPORAL_FILTER_STRENGTH);

	//weight normalized to 48 hz test scenario 
	weight = weight * fpsFix;

	//maximum reduction of history = 25% 1 / (3 + 1)
    float reduceOldData = clamp(previousClamping * UI_CLAMP_STRENGTH * UI_TEMPORAL_FILTER_STRENGTH * 5, 0.0, 3.0);

	//weigt clamped in a reasonable range	//less old info when od info was wrong last time
	weight = clamp(weight * (1.0 + reduceOldData), 0.025, 0.5);

	//blending
	float3 blendedColor = lerp(colorLast, sharpened, weight);

	//clamp to local min and max
	float3 clamped = clamp(cvtRgb2whatever(blendedColor.rgb), finalMin.rgb, finalMax.rgb);

	//check how much got clamped
	
	float delta = length(clamped - colorLast);

	//suspress history next time when we clamp a lot now 
	float nextClamp = ((delta + previousClamping) * 0.5);

	//convert back to rgb
	float3 rgb = cvtWhatever2Rgb(clamped);

	//return color and clamp amount
	return float4(rgb, nextClamp);
}


void SaveThisPS(float4 position : SV_Position, float2 texcoord : TEXCOORD, out float4 lastExpOut : SV_Target0)
{
	lastExpOut = tex2D(smpExpColor, texcoord);
}

float4 OutPS(float4 position : SV_Position, float2 texcoord : TEXCOORD ) : SV_Target
{
	float4 color = tex2D(smpExpColor, texcoord);
	int2 pos = int2(texcoord / ReShade::PixelSize);

	if (pos.y < 4)
	{
		if (pos.x < 4)
		{
			if (framecount % uint(8) == 0)
				color = float3(0, 1, 0);
			else
				color = float3(1, 0, 1);
		}
	}

	return color;
}

//Technique
technique TFAA
{
	pass SaveLastColorPass
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
	pass SaveThisPass
	{
		VertexShader = PostProcessVS;
		PixelShader = SaveThisPS;
		RenderTarget0 = texExpColorBackup;
	}
	pass OutPass
	{
		VertexShader = PostProcessVS;
		PixelShader = OutPS;
	}
}
