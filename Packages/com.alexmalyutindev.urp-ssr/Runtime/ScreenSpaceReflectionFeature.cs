using UnityEngine.Rendering.Universal;

namespace SSR.Runtime
{
    public class ScreenSpaceReflectionFeature : ScriptableRendererFeature
    {
        ScreenSpaceReflectionPass _pass;

        /// <inheritdoc/>
        public override void Create()
        {
            _pass = new ScreenSpaceReflectionPass
            {
                renderPassEvent = RenderPassEvent.AfterRenderingOpaques
            };
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            renderer.EnqueuePass(_pass);
        }
    }
}