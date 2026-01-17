const Hero = () => (
  <section className="hero">
    <div className="container hero-top">
      <div className="hero-kicker">We are Liive</div>
      <div className="hero-subtitle">The live ordering company</div>
    </div>
    <div className="hero-center">
      <div className="hero-blob">
        <span className="hero-blob-core" />
      </div>
    </div>
    <div className="container hero-bottom">
      <div className="hero-copy">
        <h1>Ordering feels live at every location.</h1>
        <p>
          Liive orchestrates voice, drive-thru, web, and kiosk ordering with
          real-time menu intelligence and live ops oversight.
        </p>
      </div>
      <div className="hero-actions">
        <button className="btn" type="button">
          See the platform
        </button>
        <button className="btn ghost" type="button">
          Download overview
        </button>
      </div>
    </div>
  </section>
);

export default Hero;
