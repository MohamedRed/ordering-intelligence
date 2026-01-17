import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import App from './App';
import './styles/fonts.css';
import './styles/reset.css';
import './styles/variables.css';
import './styles/base.css';
import './styles/layout.css';
import './styles/hero.css';
import './styles/work.css';
import './styles/gallery.css';
import './styles/contact.css';
import './styles/footer.css';

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <App />
  </StrictMode>
);
