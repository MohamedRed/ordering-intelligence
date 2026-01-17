import { processSteps } from '../data/process';

const Process = () => (
  <section className="process">
    <div className="container">
      <div className="section-title">
        <span className="eyebrow">How it works</span>
        <h2>Launch a live ordering layer in four steps.</h2>
        <p>Designed for enterprise teams managing multiple locations.</p>
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
          <div className="process-orbit" />
          <div className="process-card">
            <p>Live rollout map</p>
            <strong>All locations synced</strong>
            <span>Ops, menus, and routing in one console.</span>
          </div>
        </div>
      </div>
    </div>
  </section>
);

export default Process;
