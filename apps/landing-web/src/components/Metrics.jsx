const Metrics = () => (
  <section className="metrics">
    <div className="container metrics-grid">
      <div>
        <span className="eyebrow">Outcomes</span>
        <h2>Start in days, not months.</h2>
        <p>
          Launch quickly with curated templates, automated menu ingestion, and
          real-time QA.
        </p>
        <button className="btn primary" type="button">
          See launch plan
        </button>
      </div>
      <div className="metrics-cards">
        <article>
          <strong>45%</strong>
          <span>average call containment</span>
        </article>
        <article>
          <strong>3.4x</strong>
          <span>faster onboarding</span>
        </article>
        <article>
          <strong>15%</strong>
          <span>higher ticket sizes</span>
        </article>
      </div>
    </div>
  </section>
);

export default Metrics;
