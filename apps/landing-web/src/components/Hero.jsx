const Hero = () => (
  <section className="hero">
    <div className="container hero-grid">
      <div className="hero-content reveal">
        <span className="eyebrow">Real-time ordering</span>
        <h1>Liive turns ordering into a live, location-aware experience.</h1>
        <p>
          Capture every order across phone, drive-thru, web, and kiosk with AI
          that understands menus, modifiers, and store-level operations.
        </p>
        <div className="hero-actions">
          <button className="btn primary" type="button">
            Request demo
          </button>
          <button className="btn secondary" type="button">
            See live flow
          </button>
        </div>
        <div className="hero-meta">
          <div>
            <strong>Live ops</strong>
            <span>Monitor and intervene instantly</span>
          </div>
          <div>
            <strong>Menu intelligence</strong>
            <span>Structured logic for every item</span>
          </div>
          <div>
            <strong>Multi-location</strong>
            <span>Built for enterprise rollout</span>
          </div>
        </div>
      </div>
      <div className="hero-visual reveal delay-1">
        <div className="hero-orbit" />
        <div className="hero-rings">
          <span />
          <span />
          <span />
        </div>
        <div className="hero-pin">
          <span />
        </div>
        <div className="hero-chip">Live order stream</div>
      </div>
    </div>
  </section>
);

export default Hero;
