import { workCards, workList } from '../data/work';

const WorkShowcase = () => (
  <section className="work">
    <div className="container work-grid">
      <div className="work-left">
        <div className="work-title">Our work</div>
        <div className="work-subtitle">Live ordering deployments</div>
        <p className="work-description">
          Liive is built for enterprise rollouts, with consistent experiences
          across every channel and every store.
        </p>
        <div className="work-list">
          {workList.map((item) => (
            <div className="work-item" key={item.title}>
              <div>
                <h3>{item.title}</h3>
                <p>{item.description}</p>
              </div>
              <span>{item.meta}</span>
            </div>
          ))}
        </div>
      </div>
      <div className="work-right">
        {workCards.map((card) => (
          <article className={`work-card ${card.tone}`} key={card.title}>
            <div className="work-card-top">
              <span>{card.tag}</span>
              <span>{card.year}</span>
            </div>
            <h3>{card.title}</h3>
            <p>{card.description}</p>
            <div className="work-card-media">
              <div className="media-label">{card.media}</div>
            </div>
          </article>
        ))}
      </div>
    </div>
  </section>
);

export default WorkShowcase;
