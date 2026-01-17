const LiveOps = () => (
  <section className="live-ops">
    <div className="container live-ops-grid">
      <div className="live-ops-copy reveal">
        <span className="eyebrow">Live control center</span>
        <h2>Keep every location on script, even at peak volume.</h2>
        <p>
          Supervisors can watch live order streams, step in instantly, and keep
          every store aligned with policy.
        </p>
        <div className="pill-row">
          <span>Live takeover</span>
          <span>QA review</span>
          <span>Store alerts</span>
          <span>Performance benchmarks</span>
        </div>
      </div>
      <div className="live-ops-panel reveal delay-1">
        <div className="live-ops-card">
          <h3>Active locations</h3>
          <p>Orders, exceptions, and handoffs across all stores.</p>
          <div className="live-ops-metrics">
            <div>
              <strong>Contained orders</strong>
              <span>AI handles most demand</span>
            </div>
            <div>
              <strong>Faster pickup</strong>
              <span>Reduced queue friction</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  </section>
);

export default LiveOps;
