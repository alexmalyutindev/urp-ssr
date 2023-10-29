using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace SSR.Runtime
{
    public class ScreenSpaceReflectionPass : ScriptableRenderPass
    {
        private readonly Material _tracingMaterial;
        private readonly PostProcessData _postProcessData;
        private int ditheringIndex = 0;

        public ScreenSpaceReflectionPass(Material tracingMaterial, PostProcessData postProcessData)
        {
            _tracingMaterial = tracingMaterial;
            _postProcessData = postProcessData;
            profilingSampler = new ProfilingSampler(nameof(ScreenSpaceReflectionPass));
            ConfigureInput(ScriptableRenderPassInput.Depth | ScriptableRenderPassInput.Normal);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            var cmd = CommandBufferPool.Get();

            var camera = renderingData.cameraData.camera;
            ditheringIndex = PostProcessUtils.ConfigureDithering(
                _postProcessData,
                ditheringIndex,
                camera.pixelWidth,
                camera.pixelHeight,
                _tracingMaterial
            );
            
            using (new ProfilingScope(cmd, profilingSampler))
            {
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();
                
                var transform = camera.transform;
                Matrix4x4 quad = Matrix4x4.TRS(
                    transform.position + transform.forward,
                    transform.rotation,
                    Vector3.one * 2
                );
                cmd.DrawMesh(RenderingUtils.fullscreenMesh, quad, _tracingMaterial);
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();
                // Blitter.BlitTexture(
                //     cmd,
                //     colorAttachmentHandle.nameID,
                //     renderingData.cameraData.renderer.cameraColorTargetHandle.nameID,
                //     _tracingMaterial,
                //     0
                // );
            }

            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();

            CommandBufferPool.Release(cmd);
        }
    }
}