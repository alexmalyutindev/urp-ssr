using SSR.InternalBridge;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace SSR.Runtime
{
    public class ScreenSpaceReflectionPass : ScriptableRenderPass
    {
        private const string BufferName = "_SpecularReflectivityBuffer";
        private RTHandle _specularBuffer;
        private UniversalRenderer _renderer;
        private FilteringSettings _filteringSettings;
        private ShaderTagId _shaderTagId;

        public ScreenSpaceReflectionPass()
        {
            ConfigureInput(ScriptableRenderPassInput.Depth);

            _filteringSettings = FilteringSettings.defaultValue;
            _filteringSettings.renderQueueRange = RenderQueueRange.opaque;

            _shaderTagId = new ShaderTagId("SpecularReflectivityPass");
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            _renderer = renderingData.cameraData.renderer as UniversalRenderer;
        }

        public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
        {
            var desc = new RenderTextureDescriptor()
            {
                width = cameraTextureDescriptor.width,
                height = cameraTextureDescriptor.height,
                colorFormat = RenderTextureFormat.ARGB32
            };

            RenderingUtils.ReAllocateIfNeeded(ref _specularBuffer, desc, name: BufferName);

            ConfigureTarget(_specularBuffer, _renderer.GetDepthTexture());
            ConfigureClear(ClearFlag.Color, Color.clear);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            var cmd = CommandBufferPool.Get();

            using (new ProfilingScope(cmd, profilingSampler))
            {
                var drawingSettings = CreateDrawingSettings(
                    _shaderTagId,
                    ref renderingData,
                    SortingCriteria.CommonOpaque
                );

                context.DrawRenderers(renderingData.cullResults, ref drawingSettings, ref _filteringSettings);

                cmd.SetGlobalTexture(BufferName, _specularBuffer);
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();
            }


            CommandBufferPool.Release(cmd);
        }

        public override void OnCameraCleanup(CommandBuffer cmd) { }
    }
}