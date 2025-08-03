Shader "Custom/WaterSSR_URP"
{
    Properties
    {
        _MainTex ("Main Texture", 2D) = "white" {}
        _SSRTraceLength ("SSR Trace Length", Float) = 50.0
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Transparent"
            "RenderPipeline" = "UniversalPipeline"
            "Queue" = "Transparent-10"
        }

        Pass
        {
            Name "WaterSSRPass"
            Tags
            {
                "LightMode" = "UniversalForward"
            }

            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite On
            Cull Back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment ReflectionFragment
            #pragma target 3.0

            // URP includes
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"

            // Properties
            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);

            TEXTURE2D(_HalfResTransRTForWaterTextures);
            SAMPLER(sampler_HalfResTransRTForWaterTextures);

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float _SSRTraceLength;
            CBUFFER_END

            // Vertex input
            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
            };

            // Vertex to fragment
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float4 screenPos : TEXCOORD2;
                float2 uv : TEXCOORD3;
                float3 viewDirWS : TEXCOORD4;
            };

            // Helper functions
            float3 ReconstructWorldPosFromDepth(float2 screenUV, float depth)
            {
                float3 worldPos = ComputeWorldSpacePosition(screenUV, depth, UNITY_MATRIX_I_VP);
                return worldPos;
            }

            float CalculateScreenEdgeFade(float2 screenUV)
            {
                float2 edge = min(screenUV, 1.0 - screenUV);
                return saturate(min(edge.x, edge.y) * 6.666f);
            }

            float GetLinearDepth(float2 screenUV)
            {
                float rawDepth = SampleSceneDepth(screenUV);
                return LinearEyeDepth(rawDepth, _ZBufferParams);
            }

            // Ray marching result
            struct RayMarchResult
            {
                bool hit;
                float stepIndex;
                float2 hitUV;
                float confidence;
            };

            RayMarchResult RayMarchSSR(float3 rayStartWS, float3 rayDirWS, float4 currentScreenPos, int maxSteps)
            {
                RayMarchResult result;
                result.hit = false;
                result.stepIndex = 0.0;
                result.hitUV = float2(0, 0);
                result.confidence = 0.0;

                // Step size in world space
                float stepSize = _SSRTraceLength / (float)maxSteps;

                // Calculate ray end in world space
                float3 rayEndWS = rayStartWS + rayDirWS * _SSRTraceLength;

                // Convert to screen space
                float4 rayStartCS = TransformWorldToHClip(rayStartWS);
                float4 rayEndCS = TransformWorldToHClip(rayEndWS);

                // Convert to screen UV space
                float2 rayStartUV = mad(rayStartCS.xy / rayStartCS.w, float2(0.5, -0.5), float2(0.5, 0.5));
                float2 rayEndUV = mad(rayEndCS.xy / rayEndCS.w, float2(0.5, -0.5), float2(0.5, 0.5));

                float2 rayDeltaUV = rayEndUV - rayStartUV;
                float rayStartDepth = LinearEyeDepth(rayStartCS.z / rayStartCS.w, _ZBufferParams);
                float rayEndDepth = LinearEyeDepth(rayEndCS.z / rayEndCS.w, _ZBufferParams);
                float rayDeltaDepth = rayEndDepth - rayStartDepth;

                // Ray marching
                const float DEPTH_THRESHOLD = 3.18;

                [unroll(8)]
                for (int i = 1; i <= maxSteps; i++)
                {
                    float3 currentRayPosWS = rayStartWS + rayDirWS * (stepSize * (float)i);
                    float4 currentRayPosCS = TransformWorldToHClip(currentRayPosWS);
                    float2 sampleUV = mad(currentRayPosCS.xy / currentRayPosCS.w, float2(0.5, -0.5), float2(0.5, 0.5));

                    // Check bounds
                    // if (any(sampleUV < 0.0) || any(sampleUV > 1.0)) break;

                    // Get expected depth at this point
                    float expectedDepth = LinearEyeDepth(currentRayPosCS.z / currentRayPosCS.w, _ZBufferParams);

                    // Sample scene depth
                    float sceneDepth = GetLinearDepth(sampleUV);
                    float depthDiff = abs(expectedDepth - sceneDepth);

                    // Check for intersection
                    if (depthDiff < DEPTH_THRESHOLD && expectedDepth > sceneDepth)
                    {
                        result.hit = true;
                        result.stepIndex = (float)i;
                        result.hitUV = sampleUV;
                        result.confidence = 1.0 - (depthDiff / DEPTH_THRESHOLD);
                        break;
                    }
                }

                return result;
            }

            // Vertex shader
            Varyings vert(Attributes input)
            {
                Varyings output;

                VertexPositionInputs positionInputs = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs normalInputs = GetVertexNormalInputs(input.normalOS);

                output.positionCS = positionInputs.positionCS;
                output.positionWS = positionInputs.positionWS;
                output.normalWS = normalInputs.normalWS;
                output.screenPos = ComputeScreenPos(output.positionCS);
                output.uv = TRANSFORM_TEX(input.uv, _MainTex);
                output.viewDirWS = GetWorldSpaceViewDir(output.positionWS);

                return output;
            }

            // Fragment shader
            float4 ReflectionFragment(Varyings input) : SV_Target
            {
                float3 normalWS = normalize(input.normalWS);
                float3 viewDirWS = normalize(input.viewDirWS);
                float3 reflectionDirWS = reflect(-viewDirWS, normalWS);

                RayMarchResult rayResult = RayMarchSSR(input.positionWS, reflectionDirWS, input.screenPos, 8);
                if (rayResult.hit)
                {
                    float3 reflectionColor = SampleSceneColor(rayResult.hitUV);
                    float reflectionEdgeFade = CalculateScreenEdgeFade(rayResult.hitUV);
                    float alpha = reflectionEdgeFade * rayResult.confidence;
                    return half4(reflectionColor, alpha);
                }

                float4 farHitCS = TransformWorldToHClip(viewDirWS + reflectionDirWS * 50);
                float2 farHitUV = mad(farHitCS.xy / farHitCS.w, float2(0.5, -0.5), float2(0.5, 0.5));
                float depth01 = LinearEyeDepth(SampleSceneDepth(farHitUV), _ZBufferParams);

                float reflectionEdgeFade = CalculateScreenEdgeFade(farHitUV);
                return half4(SampleSceneColor(farHitUV), reflectionEdgeFade * (depth01 > 50));
            }
            ENDHLSL
        }
    }

    // Fallback for older hardware
    Fallback "Universal Render Pipeline/Lit"
}