import { navItems } from '../data/nav';

const Nav = () => (
  <header className="nav">
    <div className="container nav-inner">
      <div className="brand">
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
        <button className="nav-link" type="button">
          Log in
        </button>
        <button className="btn" type="button">
          Book a demo
        </button>
      </div>
    </div>
  </header>
);

export default Nav;
