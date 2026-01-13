import Navbar from './components/Navbar';
import Hero from './components/Hero';
import LogoRow from './components/LogoRow';
import Showcase from './components/Showcase';
import VoiceAgents from './components/VoiceAgents';
import FeatureSeries from './components/FeatureSeries';
import Metrics from './components/Metrics';
import Process from './components/Process';
import Faq from './components/Faq';
import CTA from './components/CTA';
import Footer from './components/Footer';

const App = () => (
  <div className="page">
    <Navbar />
    <main>
      <Hero />
      <LogoRow />
      <Showcase />
      <VoiceAgents />
      <FeatureSeries />
      <Metrics />
      <Process />
      <Faq />
      <CTA />
    </main>
    <Footer />
  </div>
);

export default App;
