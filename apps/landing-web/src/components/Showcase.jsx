import { showcaseCards } from '../data/showcase';

const Showcase = () => (
  <section className="showcase">
    <div className="container showcase-layout">
      <div className="showcase-copy reveal">
        <span className="eyebrow">What Liive delivers</span>
        <h2>Ordering feels live at every location.</h2>
        <p>
          Designed for clarity, Liive keeps the focus on outcomes: faster
          service, higher accuracy, and consistent experiences across every
          store.
        </p>
        <button className="btn ghost" type="button">
          Explore the platform
        </button>
      </div>
      <div className="showcase-cards">
        {showcaseCards.map((card) => (
          <article className={`showcase-card ${card.tone}`} key={card.title}>
            <span className="showcase-tag">{card.tag}</span>
            <h3>{card.title}</h3>
            <p>{card.description}</p>
          </article>
        ))}
      </div>
    </div>
  </section>
);

export default Showcase;
