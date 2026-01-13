const FeatureSplit = ({ eyebrow, title, description, bullets, image, reversed }) => (
  <section className={`feature ${reversed ? 'reverse' : ''}`}>
    <div className="container feature-grid">
      <div className="feature-copy">
        <span className="eyebrow">{eyebrow}</span>
        <h2>{title}</h2>
        <p>{description}</p>
        <ul>
          {bullets.map((item) => (
            <li key={item}>{item}</li>
          ))}
        </ul>
      </div>
      <div className="feature-media">
        <img src={image} alt="" loading="lazy" />
      </div>
    </div>
  </section>
);

export default FeatureSplit;
