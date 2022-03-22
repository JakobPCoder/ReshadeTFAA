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

// UI
//User UI

uniform float  UI_TEMPORAL_FILTER_STRENGTH <
	ui_type = "slider";
	ui_min = 0.0; ui_max = 1.0; ui_step = 0.1;
	ui_label = "Temporal Anti Aliasing Strength";
	ui_category = "Temporal Filter";
	ui_tooltip = "";
> = 0.7;

uniform float  UI_PRESHARP <
	ui_type = "slider";
	ui_min = 0.0; ui_max = 1.0; ui_step = 0.1;
	ui_label = "Pre Filter Sharpening";
	ui_category = "Temporal Filter";
	ui_tooltip = "";
> = 0.5;

uniform bool UI_USE_CUBIC_HISTORY <
	ui_label = "Cubic History Sampling";
	ui_category = "Temporal Filter";
	ui_tooltip = "";
> = true;


uniform float  UI_CLAMP_STRENGTH <
	ui_type = "slider";
	ui_min = 0.0; ui_max = 1.0; ui_step = 0.1;
	ui_label = "Clamping Strength";
	ui_category = "Anti Ghosting";
	ui_tooltip = "";
> = 0.5;

uniform int UI_CLAMP_TYPE <
	ui_type = "combo";
	ui_items = "Min/Max Clamping\0Variance Clamping\0None (Debug)\0";
	ui_label = "Camping Type";
	ui_category = "Anti Ghosting";
	ui_tooltip = "";
> = 0;

uniform int UI_CLAMP_PATTERN <
	ui_type = "combo";
	ui_items = "Cross (4 Taps)\0Rounded Box (8taps)\0";
	ui_label = "Clamp Pattern";
	ui_category = "Anti Ghosting";
	ui_tooltip = "";
> = 1;

uniform int UI_COLOR_FORMAT <
	ui_type = "combo";
	ui_items = "RGB\0YCgCo\0YCbCr\0";
	ui_label = "Clamping Color Space ";
	ui_category = "Anti Ghosting";
	ui_tooltip = "Anti Ghosting";
> = 2;

/*uniform bool UI_VECTORS_AVAILABLE <
    ui_label = "Motion Vectors Available";
    ui_category = "Temporal Filter";
	ui_tooltip = "Enables Rerojection of the previous Data to aproximate a better Representation of the Image. ";
> = true;*/







/*uniform bool UI_USE_CLIPPING <
    ui_label = "Use Clipping";
    ui_tooltip = "If disabled, it limits the Search Results of each Layer to its own Range. No Upscaling of lower Level Features";
    ui_category = "Anti Ghosting";
> = false;*/



