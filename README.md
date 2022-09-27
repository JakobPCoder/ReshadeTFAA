# Reshade TFAA
- This is a work in progress Reshade shader, which acts as an addon to other, non temporal, anti aliasing methods.
- It requires my [Dense Reshade Motion Estimation Shader (DRME)](https://github.com/JakobPCoder/ReshadeMotionEstimation). You can also use Marty McFly's [motion estiamtion](https://gist.github.com/martymcmodding/69c775f844124ec2c71c37541801c053to) instead.

# Copyright Notice
 - Temporal Filter Anti Aliasing | TFAA
 - First published 2022 - Copyright, Jakob Wapenhensch
 - License File [HERE](LICENSE)
 - https://creativecommons.org/licenses/by-nc/4.0/
 - https://creativecommons.org/licenses/by-nc/4.0/legalcode
  
# Updates
- 0.1 
  - Initial release, a lot of stuff broken or not working at all
- 0.2 
  - Variance Clamping was implemented
  - Finished implementig features present in the UI but did nothing at all in 0.1
  - Fixed a lot of bugs.
  - Optimized some stuff.

# Installation
- Install current Reshade build
- Drag everything into your Shaders folder
- Do the same for https://github.com/JakobPCoder/ReshadeMotionEstimation
- Order in reshade should be (FXAA or! SMAA or! CMAA2) -> DRME -> TFAA -> EVERYTHING ELSE    

