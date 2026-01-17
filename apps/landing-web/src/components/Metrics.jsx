const Metrics = () => (
  <section className="metrics">
    <div className="container metrics-grid">
      <div>
        <span className="eyebrow">Outcomes</span>
        <h2>Launch without disrupting operations.</h2>
        <p>
          Liive rolls out fast with guided onboarding, store-level routing, and
          real-time quality checks.
        </p>
        <button className="btn primary" type="button">
          View deployment plan
        </button>
      </div>
      <div className="metrics-cards">
        <article>
          <strong>Multi-channel</strong>
          <span>One order stream for every surface</span>
        </article>
        <article>
          <strong>Location-aware</strong>
          <span>Routing rules per store and daypart</span>
        </article>
        <article>
          <strong>Enterprise-ready</strong>
          <span>Security and governance built in</span>
        </article>
      </div>
    </div>
  </section>
);

export default Metrics;
