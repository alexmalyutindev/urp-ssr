using SSR.InternalBridge;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace SSR.Runtime
{
    public class SpecularReflectivityPass : ScriptableRenderPass
    {
        private const string BufferName = "_SpecularReflectivityBuffer";
        private const string SpecularReflectivityPassName = "SpecularReflectivity";
        private RTHandle _specularBuffer;
        private UniversalRenderer _renderer;
        private FilteringSettings _filteringSettings;
        private ShaderTagId _shaderTagId;

        public SpecularReflectivityPass()
        {
            profilingSampler = new ProfilingSampler(nameof(SpecularReflectivityPass));
            ConfigureInput(ScriptableRenderPassInput.Depth | ScriptableRenderPassInput.Normal);

            _filteringSettings = FilteringSettings.defaultValue;
            _filteringSettings.renderQueueRange = RenderQueueRange.opaque;

            _shaderTagId = new ShaderTagId(SpecularReflectivityPassName);
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            _renderer = renderingData.cameraData.renderer as UniversalRenderer;
        }

        public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
        {
            var desc = new RenderTextureDescriptor(
                cameraTextureDescriptor.width,
                cameraTextureDescriptor.height,
                RenderTextureFormat.ARGB32
            );

            RenderingUtils.ReAllocateIfNeeded(ref _specularBuffer, desc, name: BufferName);

            ConfigureTarget(_specularBuffer, _renderer.GetDepthTexture());
            ConfigureClear(ClearFlag.Color, Color.clear);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            var cmd = CommandBufferPool.Get();

            using (new ProfilingScope(cmd, profilingSampler))
            {
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();

                var drawingSettings = CreateDrawingSettings(
                    _shaderTagId,
                    ref renderingData,
                    SortingCriteria.CommonOpaque
                );

                context.DrawRenderers(renderingData.cullResults, ref drawingSettings, ref _filteringSettings);
            }

            cmd.SetGlobalTexture(BufferName, _specularBuffer);
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();

            CommandBufferPool.Release(cmd);
        }

        public override void OnCameraCleanup(CommandBuffer cmd) { }
    }
}