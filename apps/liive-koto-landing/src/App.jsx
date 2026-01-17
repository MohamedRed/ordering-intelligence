import Nav from './components/Nav';
import Hero from './components/Hero';
import WorkShowcase from './components/WorkShowcase';
import Gallery from './components/Gallery';
import Contact from './components/Contact';
import Footer from './components/Footer';

const App = () => (
  <div className="page">
    <Nav />
    <main>
      <Hero />
      <WorkShowcase />
      <Gallery />
      <Contact />
    </main>
    <Footer />
  </div>
);

export default App;
