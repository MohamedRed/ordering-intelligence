import { features } from '../data/features';
import FeatureSplit from './FeatureSplit';

const FeatureSeries = () => (
  <div className="feature-series">
    {features.map((feature) => (
      <FeatureSplit key={feature.title} {...feature} />
    ))}
  </div>
);

export default FeatureSeries;
