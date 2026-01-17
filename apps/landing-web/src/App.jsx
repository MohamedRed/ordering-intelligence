import Navbar from './components/Navbar';
import Hero from './components/Hero';
import ChannelRow from './components/ChannelRow';
import Showcase from './components/Showcase';
import LiveOps from './components/LiveOps';
import FeatureSeries from './components/FeatureSeries';
import Metrics from './components/Metrics';
import Process from './components/Process';
import CTA from './components/CTA';
import Footer from './components/Footer';

const App = () => (
  <div className="page">
    <Navbar />
    <main>
      <Hero />
      <ChannelRow />
      <Showcase />
      <LiveOps />
      <FeatureSeries />
      <Metrics />
      <Process />
      <CTA />
    </main>
    <Footer />
  </div>
);

export default App;
