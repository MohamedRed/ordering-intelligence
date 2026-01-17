import { features } from '../data/features';
import FeatureSplit from './FeatureSplit';

const FeatureSeries = () => (
  <section className="feature-series">
    <div className="container section-title">
      <span className="eyebrow">Platform</span>
      <h2>Everything needed to keep orders live.</h2>
      <p>From menu ingestion to orchestration and QA in one stack.</p>
    </div>
    {features.map((feature) => (
      <FeatureSplit key={feature.title} {...feature} />
    ))}
  </section>
);

export default FeatureSeries;
