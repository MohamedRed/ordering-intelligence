import { processSteps } from '../data/process';

const Process = () => (
  <section className="process">
    <div className="container">
      <div className="section-title">
        <span className="eyebrow">How it works</span>
        <h2>Launch a production-ready agent in four steps.</h2>
        <p>Designed for enterprise teams with multiple locations.</p>
      </div>
      <div className="process-grid">
        <div className="process-steps">
          {processSteps.map((step, index) => (
            <div className="process-step" key={step.title}>
              <span>0{index + 1}</span>
              <div>
                <h3>{step.title}</h3>
                <p>{step.description}</p>
              </div>
            </div>
          ))}
        </div>
        <div className="process-visual">
          <img src="/placeholders/process.svg" alt="" loading="lazy" />
        </div>
      </div>
    </div>
  </section>
);

export default Process;
