import { showcaseCards } from '../data/showcase';

const Showcase = () => (
  <section className="showcase">
    <div className="container">
      <div className="section-title">
        <span className="eyebrow">Platform</span>
        <h2>Everything you need to launch voice ordering.</h2>
        <p>Unified tools for onboarding, orchestration, and continuous QA.</p>
      </div>
      <div className="showcase-grid">
        {showcaseCards.map((card) => (
          <article className="showcase-card" key={card.title}>
            <img src={card.image} alt="" loading="lazy" />
            <div>
              <h3>{card.title}</h3>
              <p>{card.description}</p>
            </div>
          </article>
        ))}
      </div>
    </div>
  </section>
);

export default Showcase;
