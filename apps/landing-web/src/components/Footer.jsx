import { footerColumns } from '../data/footer';

const Footer = () => (
  <footer className="footer">
    <div className="container footer-grid">
      <div>
        <div className="logo">
          <img src="/assets/liive-logo.svg" alt="Liive" />
        </div>
        <p>Real-time ordering for modern restaurant teams.</p>
      </div>
      <div className="footer-columns">
        {footerColumns.map((column) => (
          <div key={column.title}>
            <h4>{column.title}</h4>
            <ul>
              {column.links.map((link) => (
                <li key={link}>
                  <button type="button">{link}</button>
                </li>
              ))}
            </ul>
          </div>
        ))}
      </div>
    </div>
    <div className="footer-bottom">
      <span>© 2026 Liive</span>
      <div className="footer-socials">
        <button type="button">LinkedIn</button>
        <button type="button">X</button>
        <button type="button">YouTube</button>
      </div>
    </div>
  </footer>
);

export default Footer;
