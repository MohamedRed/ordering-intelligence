import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import App from './App';
import './styles/fonts.css';
import './styles/reset.css';
import './styles/variables.css';
import './styles/base.css';
import './styles/layout.css';
import './styles/hero.css';
import './styles/sections.css';
import './styles/feature.css';
import './styles/metrics.css';
import './styles/process.css';
import './styles/cta.css';
import './styles/footer.css';

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <App />
  </StrictMode>
);
