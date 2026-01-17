import { galleryItems } from '../data/gallery';

const Gallery = () => (
  <section className="gallery">
    <div className="container">
      <div className="gallery-header">
        <h2>Live operations in every channel.</h2>
        <p>
          A unified platform to launch, monitor, and improve ordering experiences
          at scale.
        </p>
      </div>
      <div className="gallery-grid">
        {galleryItems.map((item) => (
          <article className="gallery-card" key={item.title}>
            <div className={`gallery-media ${item.tone}`}>
              <span>{item.media}</span>
            </div>
            <div className="gallery-body">
              <h3>{item.title}</h3>
              <p>{item.description}</p>
              <button type="button">View detail</button>
            </div>
          </article>
        ))}
      </div>
    </div>
  </section>
);

export default Gallery;
