#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

float4x4 _InverseViewMatrix;
float4x4 _InverseProjectionMatrix;
float4x4 _ScreenSpaceProjectionMatrix;

struct Ray
{
    float3 origin;
    float3 direction;
};

struct Segment
{
    float3 start;
    float3 end;

    float3 direction;
};

struct Result
{
    bool isHit;

    float2 uv;
    float3 position;

    int iterationCount;
};

float4 ProjectToScreenSpace(float3 position)
{
    return float4(
        _ScreenSpaceProjectionMatrix[0][0] * position.x + _ScreenSpaceProjectionMatrix[0][2] * position.z,
        _ScreenSpaceProjectionMatrix[1][1] * position.y + _ScreenSpaceProjectionMatrix[1][2] * position.z,
        _ScreenSpaceProjectionMatrix[2][2] * position.z + _ScreenSpaceProjectionMatrix[2][3],
        _ScreenSpaceProjectionMatrix[3][2] * position.z
    );
}

// Heavily adapted from McGuire and Mara's original implementation
// http://casual-effects.blogspot.com/2014/08/screen-space-ray-tracing.html
Result March(Ray ray, Varyings input)
{
    Result result;

    result.isHit = false;

    result.uv = 0.0;
    result.position = 0.0;

    result.iterationCount = 0;

    Segment segment;

    segment.start = ray.origin;

    float end = ray.origin.z + ray.direction.z * _MaximumMarchDistance;
    float magnitude = _MaximumMarchDistance;

    if (end > -_ProjectionParams.y)
        magnitude = (-_ProjectionParams.y - ray.origin.z) / ray.direction.z;

    segment.end = ray.origin + ray.direction * magnitude;

    float4 r = ProjectToScreenSpace(segment.start);
    float4 q = ProjectToScreenSpace(segment.end);

    const float2 homogenizers = rcp(float2(r.w, q.w));

    segment.start *= homogenizers.x;
    segment.end *= homogenizers.y;

    float4 endPoints = float4(r.xy, q.xy) * homogenizers.xxyy;
    endPoints.zw += step(GetSquaredDistance(endPoints.xy, endPoints.zw), 0.0001) * max(
        _Test_TexelSize.x, _Test_TexelSize.y);

    float2 displacement = endPoints.zw - endPoints.xy;

    bool isPermuted = false;

    if (abs(displacement.x) < abs(displacement.y))
    {
        isPermuted = true;

        displacement = displacement.yx;
        endPoints.xyzw = endPoints.yxwz;
    }

    float direction = sign(displacement.x);
    float normalizer = direction / displacement.x;

    segment.direction = (segment.end - segment.start) * normalizer;
    float4 derivatives = float4(float2(direction, displacement.y * normalizer),
                                (homogenizers.y - homogenizers.x) * normalizer, segment.direction.z);

    float stride = 1.0 - min(1.0, -ray.origin.z * 0.01);

    float2 uv = input.uv * _NoiseTiling;
    uv.y *= _AspectRatio;

    float jitter = _Noise.SampleLevel(sampler_Noise, uv + _WorldSpaceCameraPos.xz, 0).r;
    stride *= _Bandwidth;

    derivatives *= stride;
    segment.direction *= stride;

    float2 z = 0.0;
    float4 tracker = float4(endPoints.xy, homogenizers.x, segment.start.z) + derivatives * jitter;

    for (int i = 0; i < _MaximumIterationCount; ++i)
    {
        if (any(result.uv < 0.0) || any(result.uv > 1.0))
        {
            result.isHit = false;
            return result;
        }

        tracker += derivatives;

        z.x = z.y;
        z.y = tracker.w + derivatives.w * 0.5;
        z.y /= tracker.z + derivatives.z * 0.5;

        #if SSR_KILL_FIREFLIES
        UNITY_FLATTEN
        if (z.y < -_MaximumMarchDistance)
        {
            result.isHit = false;
            return result;
        }
        #endif

        UNITY_FLATTEN
        if (z.y > z.x)
        {
            float k = z.x;
            z.x = z.y;
            z.y = k;
        }

        uv = tracker.xy;

        UNITY_FLATTEN
        if (isPermuted)
            uv = uv.yx;

        uv *= _Test_TexelSize.xy;

        float d = SampleSceneDepthLod0(uv);
        float depth = -LinearEyeDepth(d, _ZBufferParams);

        UNITY_FLATTEN
        if (z.y < depth)
        {
            UNITY_FLATTEN
            if (depth - z.y > _Bandwidth)
            {
                result.isHit = false;
                return result;
            }
            result.uv = uv;
            result.isHit = true;
            result.iterationCount = i + 1;
            return result;
        }
    }

    return result;
}
