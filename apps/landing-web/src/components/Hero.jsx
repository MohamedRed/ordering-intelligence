const Hero = () => (
  <section className="hero">
    <div className="container hero-grid">
      <div className="hero-content reveal">
        <span className="eyebrow">Conversational Agents</span>
        <h1>The conversational agents platform.</h1>
        <p>
          Build voice agents that sound human, resolve orders instantly, and
          scale across every location.
        </p>
        <div className="hero-actions">
          <button className="btn primary" type="button">
            Book a demo
          </button>
          <button className="btn secondary" type="button">
            Watch overview
          </button>
        </div>
        <div className="hero-meta">
          <div>
            <strong>99.9%</strong>
            <span>uptime SLA</span>
          </div>
          <div>
            <strong>2 weeks</strong>
            <span>avg launch</span>
          </div>
          <div>
            <strong>24/7</strong>
            <span>coverage</span>
          </div>
        </div>
      </div>
      <div className="hero-visual reveal delay-1">
        <div className="hero-glow" />
        <img
          src="/placeholders/hero.svg"
          alt="Hero product preview"
          loading="lazy"
        />
      </div>
    </div>
  </section>
);

export default Hero;
