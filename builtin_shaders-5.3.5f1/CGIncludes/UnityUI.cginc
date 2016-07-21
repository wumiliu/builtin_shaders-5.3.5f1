#ifndef UNITY_UI_INCLUDED
#define UNITY_UI_INCLUDED

//裁剪
inline float UnityGet2DClipping (in float2 position, in float4 clipRect)
{
	//step return x>=a?1:0  step(a,x)
 	float2 inside = step(clipRect.xy, position.xy) * step(position.xy, clipRect.zw);
 	return inside.x * inside.y;
}
#endif

