Shader "Custom/WaterSSR_URP"
{
    Properties
    {
        _MainTex ("Main Texture", 2D) = "white" {}
        _NormalMap ("Normal Map", 2D) = "bump" {}
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
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"

            // Properties
            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            TEXTURE2D(_NormalMap);

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

            RayMarchResult RayMarchSSR(float3 rayStartWS, float3 rayDirWS)
            {
                RayMarchResult result;
                result.hit = false;
                result.stepIndex = 0.0;
                result.hitUV = float2(0, 0);
                result.confidence = 0.0;

                // Calculate ray end in world space
                float3 rayEndWS = rayStartWS + rayDirWS * _SSRTraceLength;
                float3 rayDeltaWS = rayEndWS - rayStartWS;

                // Ray marching
                const float DEPTH_THRESHOLD = 3.1875f;
                const float stepSizes[8] = {0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875, 1.0};

                [unroll(8)]
                for (int i = 1; i < 8; i++)
                {
                    float3 currentRayPosWS = rayStartWS + rayDeltaWS * stepSizes[i];
                    float4 currentRayPosCS = TransformWorldToHClip(currentRayPosWS);
                    if (any(abs(currentRayPosCS.xy) > currentRayPosCS.w))
                    {
                        break;
                    }

                    float2 sampleUV = mad(currentRayPosCS.xy / currentRayPosCS.w, float2(0.5, -0.5), float2(0.5, 0.5));
                    float expectedDepthRaw = currentRayPosCS.z / currentRayPosCS.w;
                    float sceneDepthRaw = SampleSceneDepth(sampleUV);
                    float depthDiff = abs(expectedDepthRaw - sceneDepthRaw) * _ProjectionParams.z;


                    #ifdef UNITY_REVERSED_Z
                    bool depthCheck = expectedDepthRaw < sceneDepthRaw;
                    #else
                    bool depthCheck = expectedDepthRaw > sceneDepthRaw;
                    #endif

                    // Check for intersection - ray is behind geometry
                    if (depthDiff < DEPTH_THRESHOLD && depthCheck)
                    {
                        result.hit = true;
                        result.stepIndex = (float)(i + 1);
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
                // Refraction
                float2 normalizedScreenUV = GetNormalizedScreenSpaceUV(input.positionCS.xy);
                float2 surfaceUV = input.positionWS.xz * 0.25 + _Time.x;
                half3 normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalMap, sampler_LinearRepeat, surfaceUV), 0.1);
                half3 refractionColor = SampleSceneColor(normalizedScreenUV + normalTS.xy);
                refractionColor *= half3(0.94h, 0.96h, 1.0h);

                float3 normalWS = normalize(input.normalWS);
                float NdotV = dot(normalWS, normalize(input.viewDirWS));
                float fresnel = saturate(1.0h - NdotV);
                fresnel = fresnel * fresnel * 0.98h + 0.02h;

                float3 reflectionDirWS = reflect(-input.viewDirWS, normalWS);

                float4 farHitCS = TransformWorldToHClip(input.positionWS + reflectionDirWS * 10);
                float2 farHitUV = mad(farHitCS.xy / farHitCS.w, float2(0.5, -0.5), float2(0.5, 0.5));

                half3 reflectionColor;
                half reflectionAlpha;

                // reflectionDirWS *= InterleavedGradientNoise(input.positionCS.xy, _TimeParameters.x * 120) * 0.25 + 0.75;
                RayMarchResult rayResult = RayMarchSSR(input.positionWS, reflectionDirWS);
                if (rayResult.hit)
                {
                    reflectionColor = SampleSceneColor(rayResult.hitUV + normalTS.xy);
                    float reflectionEdgeFade = CalculateScreenEdgeFade(rayResult.hitUV);
                    reflectionAlpha = reflectionEdgeFade;
                }
                else
                {
                    farHitUV += normalTS.xy;
                    reflectionColor = SampleSceneColor(farHitUV);
                    float reflectionEdgeFade = CalculateScreenEdgeFade(farHitUV);
                    float sceneDepth = LinearEyeDepth(SampleSceneDepth(farHitUV), _ZBufferParams);
                    reflectionAlpha = reflectionEdgeFade * (sceneDepth > _ProjectionParams.z * 0.5h);
                }

                // Blend EnvCube
                half4 encodedIrradiance = half4(
                    SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, normalize(reflectionDirWS), 0)
                );
                half3 envReflection = DecodeHDREnvironment(encodedIrradiance, unity_SpecCube0_HDR);
                reflectionColor = lerp(envReflection, reflectionColor, reflectionAlpha);

                return half4(lerp(refractionColor, reflectionColor, fresnel), 1.0h);
            }
            ENDHLSL
        }
    }

    // Fallback for older hardware
    Fallback "Universal Render Pipeline/Lit"
}