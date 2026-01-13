import { logos } from '../data/logos';

const LogoRow = () => (
  <section className="logos">
    <div className="container">
      <p className="logos-title">Trusted by modern restaurant teams</p>
      <div className="logos-row">
        {logos.map((logo) => (
          <span className="logo-pill" key={logo}>
            {logo}
          </span>
        ))}
      </div>
    </div>
  </section>
);

export default LogoRow;
