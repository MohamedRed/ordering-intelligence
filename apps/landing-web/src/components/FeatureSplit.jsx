const FeatureSplit = ({ eyebrow, title, description, bullets, image, reversed }) => (
  <div className={`feature ${reversed ? 'reverse' : ''}`}>
    <div className="container feature-grid">
      <div className="feature-copy">
        <span className="eyebrow">{eyebrow}</span>
        <h3>{title}</h3>
        <p>{description}</p>
        <ul className="feature-list">
          {bullets.map((item) => (
            <li key={item}>{item}</li>
          ))}
        </ul>
      </div>
      <div className="feature-media">
        <img src={image} alt="" loading="lazy" />
      </div>
    </div>
  </div>
);

export default FeatureSplit;
