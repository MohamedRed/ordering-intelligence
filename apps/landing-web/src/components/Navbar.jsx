import { navItems } from '../data/nav';

const Navbar = () => (
  <header className="nav">
    <div className="container nav-inner">
      <div className="logo">
        <img src="/assets/liive-logo.svg" alt="Liive" />
      </div>
      <nav className="nav-links">
        {navItems.map((item) => (
          <button className="nav-link" key={item} type="button">
            {item}
          </button>
        ))}
      </nav>
      <div className="nav-actions">
        <button className="btn ghost" type="button">
          Sign in
        </button>
        <button className="btn primary" type="button">
          Request demo
        </button>
      </div>
    </div>
  </header>
);

export default Navbar;
