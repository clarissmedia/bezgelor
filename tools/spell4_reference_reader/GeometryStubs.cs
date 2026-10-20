// IO adapters only. The original Telegraph.InsideTelegraph and maths are linked
// unmodified. Map search is intentionally unavailable: this tool emits point
// reference vectors, never live targets. No NLog or other package is installed.
using System.Numerics;

namespace NLog
{
    public interface ILogger { void Warn(string message); }
    public static class LogManager
    {
        private sealed class Logger : ILogger { public void Warn(string message) { } }
        public static ILogger GetCurrentClassLogger() => new Logger();
    }
}
namespace NexusForever.Game.Abstract.Entity
{
    public interface IUnitEntity { float HitRadius { get; } ReferenceMap Map { get; } }
    public interface IPlayer : IUnitEntity { }
    public sealed class ReferenceMap
    {
        public IEnumerable<IUnitEntity> Search(Vector3 p, float r, object check)
            => throw new NotSupportedException("Map search is not a reference-vector operation");
    }
    public sealed class ReferenceCaster : IPlayer
    {
        public float HitRadius => 0;
        public ReferenceMap Map => throw new NotSupportedException();
    }
}
namespace NexusForever.Game.Abstract.Spell { public interface ITelegraph { } }
namespace NexusForever.Game.Map.Search
{
    public sealed class SearchCheckTelegraph
    {
        public SearchCheckTelegraph(object telegraph, object caster) { }
    }
}
